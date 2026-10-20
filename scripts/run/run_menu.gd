extends CanvasLayer
## Run-wide pause menu. Progress currently lives only in memory.

const BATTLE_CHROME := preload("res://scripts/run/battle_chrome.gd")
signal restart_battle_requested

var _was_paused := false
var _owns_pause := false
var _previous_focus: Control
var _destination := ""
var _battle_button_layout := false
var _button_offsets: Vector4
@onready var _original_panel_style: StyleBox = $Overlay/Center/Panel.get_theme_stylebox("panel")
@onready var _overlay: Control = $Overlay
@onready var _title: Label = $Overlay/Center/Panel/Column/Title
@onready var _message: Label = $Overlay/Center/Panel/Column/Message
@onready var _resume: Button = $Overlay/Center/Panel/Column/Resume
@onready var _restart: Button = $Overlay/Center/Panel/Column/Restart
@onready var _main: Button = $Overlay/Center/Panel/Column/MainMenu
@onready var _quit: Button = $Overlay/Center/Panel/Column/Quit
@onready var _confirm: Button = $Overlay/Center/Panel/Column/Confirm
@onready var _cancel: Button = $Overlay/Center/Panel/Column/Cancel


func _ready() -> void:
	var button := $MenuButton as Button
	_button_offsets = Vector4(button.offset_left, button.offset_top, button.offset_right, button.offset_bottom)
	$MenuButton.pressed.connect(open_menu)
	_resume.pressed.connect(close_menu)
	_restart.pressed.connect(_ask_leave.bind("restart"))
	_main.pressed.connect(_ask_leave.bind("menu"))
	_quit.pressed.connect(_ask_leave.bind("quit"))
	_confirm.pressed.connect(_confirm_leave)
	_cancel.pressed.connect(_show_options)
	_resume.icon = BattleAssets.texture("battle_log_pause") # The PLAY picture.
	_restart.icon = BattleAssets.texture("battle_log_restart")
	_quit.icon = BattleAssets.texture("battle_log_exit")
	for control in [_resume, _restart, _quit]:
		control.expand_icon = true
		control.add_theme_constant_override("icon_max_width", 48)
		control.mouse_entered.connect(_paint_icon.bind(control))
		control.mouse_exited.connect(_paint_icon.bind(control))
		control.focus_entered.connect(_paint_icon.bind(control))
		control.focus_exited.connect(_paint_icon.bind(control))
	$MenuButton.focus_mode = Control.FOCUS_ALL
	$MenuButton/Art.texture = BattleAssets.texture("battle_log_continue")
	_resume.tooltip_text = "继续游戏（Esc）"
	_restart.tooltip_text = "恢复本场开战时的生命、卡牌和随机数状态"
	_quit.tooltip_text = "退出游戏，需再次确认"
	call_deferred("_apply_theme")
	call_deferred("_sync_button_layout")


func _process(_delta: float) -> void:
	_sync_button_layout()


func _sync_button_layout() -> void:
	var battle := get_parent().get_node_or_null("Battle") as RunBattle
	var button := $MenuButton as Button
	if battle != null and battle.is_visible_in_tree():
		var bar := battle.get_node("Board/Margin/Column/TopBar") as Control
		var bounds := bar.get_global_rect()
		var side := minf(80.0, maxf(0.0, bounds.size.y - 16.0))
		button.size = Vector2(side, side)
		button.global_position = Vector2(bounds.end.x - side - 12.0, bounds.get_center().y - side / 2.0)
		_battle_button_layout = true
	elif _battle_button_layout:
		button.offset_left = _button_offsets.x
		button.offset_top = _button_offsets.y
		button.offset_right = _button_offsets.z
		button.offset_bottom = _button_offsets.w
		_battle_button_layout = false


func _apply_theme() -> void:
	# Reuse the tower's fonts and button styling on every run screen.
	var ui: Theme = get_parent().get_node("Layout").theme
	$MenuButton.theme = ui
	_overlay.theme = ui


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if _overlay.visible:
		if _destination != "":
			_show_options()
		else:
			close_menu()
	else:
		var inventory := get_parent().get_node("Inventory") as RunInventory
		if inventory.blocks_input():
			return # The first Escape closes the bag.
		open_menu()
	get_viewport().set_input_as_handled()


func open_menu() -> void:
	if _overlay.visible:
		return
	_previous_focus = get_viewport().gui_get_focus_owner()
	_was_paused = get_tree().paused
	_owns_pause = true
	get_tree().paused = true
	_apply_context_chrome()
	_overlay.show()
	_show_options()


func close_menu() -> void:
	_overlay.hide()
	_restore_pause()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()


func _show_options() -> void:
	_destination = ""
	_title.text = "游戏已暂停"
	_message.text = "当前版本暂不支持存档。\n返回主菜单或退出游戏会丢失本局进度。"
	_resume.show()
	_restart.visible = get_parent().has_method("can_restart_battle") and get_parent().can_restart_battle()
	_main.show()
	_quit.show()
	_confirm.hide()
	_cancel.hide()
	_resume.grab_focus()


func _ask_leave(destination: String) -> void:
	if destination == "restart" and not get_parent().can_restart_battle():
		return
	_destination = destination
	_title.text = "返回主菜单？" if destination == "menu" else "退出游戏？"
	_message.text = "本局进度不会保存，离开后无法继续。"
	if destination == "restart":
		_title.text = "重开本场战斗？"
		_message.text = "恢复本场开战时的生命、卡牌和随机数状态。"
	_resume.hide()
	_restart.hide()
	_main.hide()
	_quit.hide()
	_confirm.text = "确认返回主菜单" if destination == "menu" else "确认退出游戏"
	if destination == "restart":
		_confirm.text = "确认重开本场"
	_confirm.show()
	_cancel.show()
	_cancel.grab_focus()


func _confirm_leave() -> void:
	if _destination == "restart":
		if not get_parent().can_restart_battle():
			_show_options()
			return
		close_menu()
		restart_battle_requested.emit()
	elif _destination == "quit":
		get_tree().quit()
	elif _destination == "menu":
		var error := get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
		if error != OK:
			_message.text = "无法返回主菜单，请取消后重试。"


func _restore_pause() -> void:
	if _owns_pause:
		get_tree().paused = _was_paused
		_owns_pause = false


func _exit_tree() -> void:
	_restore_pause()


func _apply_context_chrome() -> void:
	var battle := get_parent().get_node_or_null("Battle") as RunBattle
	var active := battle != null and battle.visible
	_overlay.theme = BATTLE_CHROME.make_theme(28) if active else get_parent().get_node("Layout").theme
	var panel := $Overlay/Center/Panel as PanelContainer
	if active:
		panel.add_theme_stylebox_override("panel", BATTLE_CHROME.paper(Color.WHITE, 40.0))
		BATTLE_CHROME.ink_labels(panel)
	else:
		panel.remove_theme_stylebox_override("panel")
		panel.add_theme_stylebox_override("panel", _original_panel_style)
		_title.add_theme_color_override("font_color", Color(0.93, 0.86, 0.68))
		_message.remove_theme_color_override("font_color")


func _paint_icon(button: Button) -> void:
	button.self_modulate = Color(1.1, 1.1, 1.15) if button.is_hovered() or button.has_focus() else Color.WHITE
