extends Control
## Main menu. A 2560x1440 stage scales uniformly into the window.

const STAGE_SIZE := Vector2(2560, 1440)
const BUTTON_SCALE := 0.42
const COLUMN_RIGHT := 2460.0
const BUTTON_GAP := 32.0
const RUN_SCENE := "res://scenes/run/run_shell.tscn"

const MENU_ITEMS: Array[Dictionary] = [
	{
		"name": "StartButton",
		"normal": preload("res://assets/ui/menu/btn_start_normal.png"),
		"hover": preload("res://assets/ui/menu/btn_start_hover.png"),
		"native": Vector2(1454, 681),
	},
	{
		"name": "NewButton",
		"normal": preload("res://assets/ui/menu/btn_new_normal.png"),
		"hover": preload("res://assets/ui/menu/btn_new_hover.png"),
		"native": Vector2(1466, 591),
	},
	{
		"name": "OptionsButton",
		"normal": preload("res://assets/ui/menu/btn_options_normal.png"),
		"hover": preload("res://assets/ui/menu/btn_options_hover.png"),
		"native": Vector2(1443, 672),
	},
	{
		"name": "QuitButton",
		"normal": preload("res://assets/ui/menu/btn_quit_normal.png"),
		"hover": preload("res://assets/ui/menu/btn_quit_hover.png"),
		"native": Vector2(1455, 610),
	},
]

var _stage: Control
var _menu_buttons: Array[ArtButton] = []
var _start_button: ArtButton
var _new_layer: Control
var _settings_layer: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.position = Vector2.ZERO
	_stage.size = STAGE_SIZE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_build_background()
	_build_menu_buttons()
	_build_new_game_layer()
	_build_settings_layer()
	resized.connect(_fit_stage)
	get_viewport().size_changed.connect(_fit_stage)
	_fit_stage()
	_focus_start_if_windowed()


func _unhandled_input(event: InputEvent) -> void:
	if _settings_layer == null or not _settings_layer.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_settings()
		get_viewport().set_input_as_handled()


func _fit_stage() -> void:
	var view := size
	if view.x < 2.0 or view.y < 2.0:
		view = get_viewport_rect().size
	if view.x < 2.0 or view.y < 2.0:
		return
	var fit := minf(view.x / STAGE_SIZE.x, view.y / STAGE_SIZE.y)
	_stage.scale = Vector2(fit, fit)
	_stage.position = (view - STAGE_SIZE * fit) * 0.5


func _build_background() -> void:
	var background := TextureRect.new()
	background.name = "Background"
	background.texture = preload("res://assets/ui/menu/bg_menu.jpg")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	_stage.add_child(background)
	_fill(background)


func _build_menu_buttons() -> void:
	var rects := _menu_rects()
	for index in MENU_ITEMS.size():
		var item: Dictionary = MENU_ITEMS[index]
		var button := ArtButton.new()
		button.name = str(item["name"])
		button.normal_texture = item["normal"]
		button.hover_texture = item["hover"]
		var rect: Rect2 = rects[index]
		button.position = rect.position
		button.size = rect.size
		_bind_menu_button(button)
		_stage.add_child(button)
		_menu_buttons.append(button)
		if button.name == "StartButton":
			_start_button = button
	_chain_vertical(_menu_buttons)


func _menu_rects() -> Array[Rect2]:
	var sizes: Array[Vector2] = []
	var total := 0.0
	for item in MENU_ITEMS:
		var native: Vector2 = item["native"]
		var scaled := native * BUTTON_SCALE
		sizes.append(scaled)
		total += scaled.y
	total += BUTTON_GAP * float(maxi(sizes.size() - 1, 0))
	var y := (STAGE_SIZE.y - total) * 0.5
	var rects: Array[Rect2] = []
	for scaled in sizes:
		rects.append(Rect2(COLUMN_RIGHT - scaled.x, y, scaled.x, scaled.y))
		y += scaled.y + BUTTON_GAP
	return rects


func _bind_menu_button(button: ArtButton) -> void:
	match button.name:
		"StartButton":
			button.pressed.connect(_start_run)
		"NewButton":
			button.pressed.connect(_open_new_game)
		"OptionsButton":
			button.pressed.connect(_open_settings)
		"QuitButton":
			button.pressed.connect(_quit_game)


func _chain_vertical(buttons: Array[ArtButton]) -> void:
	for index in buttons.size():
		var button := buttons[index]
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
		if index == 0:
			button.focus_neighbor_top = button.get_path_to(button)
		else:
			button.focus_neighbor_top = button.get_path_to(buttons[index - 1])
		if index + 1 == buttons.size():
			button.focus_neighbor_bottom = button.get_path_to(button)
		else:
			button.focus_neighbor_bottom = button.get_path_to(buttons[index + 1])


func _build_new_game_layer() -> void:
	_new_layer = Control.new()
	_new_layer.name = "NewGameLayer"
	_new_layer.position = Vector2.ZERO
	_new_layer.size = STAGE_SIZE
	_new_layer.visible = false
	_new_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_new_layer)
	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.color = Color(0, 0, 0, 0.45)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_new_layer.add_child(dimmer)
	_fill(dimmer)
	var dialog := TextureRect.new()
	dialog.name = "Dialog"
	dialog.texture = preload("res://assets/ui/menu/dlg_newgame.png")
	dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dialog.stretch_mode = TextureRect.STRETCH_SCALE
	_new_layer.add_child(dialog)
	_fill(dialog)
	var cancel := _full_stage_button(
		"CancelButton",
		preload("res://assets/ui/menu/btn_cancel_normal.png"),
		preload("res://assets/ui/menu/btn_cancel_hover.png")
	)
	cancel.pressed.connect(_close_new_game)
	_new_layer.add_child(cancel)
	var confirm := _full_stage_button(
		"ConfirmButton",
		preload("res://assets/ui/menu/btn_confirm_normal.png"),
		preload("res://assets/ui/menu/btn_confirm_hover.png")
	)
	confirm.pressed.connect(_start_run)
	_new_layer.add_child(confirm)
	_chain_horizontal([cancel, confirm])


func _build_settings_layer() -> void:
	_settings_layer = Control.new()
	_settings_layer.name = "SettingsLayer"
	_settings_layer.position = Vector2.ZERO
	_settings_layer.size = STAGE_SIZE
	_settings_layer.visible = false
	_settings_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_settings_layer)
	var background := TextureRect.new()
	background.name = "SettingsBackground"
	background.texture = preload("res://assets/ui/menu/bg_settings.png")
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	_settings_layer.add_child(background)
	_fill(background)
	_settings_layer.add_child(_make_back_button())


func _full_stage_button(node_name: String, normal: Texture2D, hover: Texture2D) -> ArtButton:
	var button := ArtButton.new()
	button.name = node_name
	button.normal_texture = normal
	button.hover_texture = hover
	button.position = Vector2.ZERO
	button.size = STAGE_SIZE
	return button


func _make_back_button() -> Button:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI",
	])
	var button := Button.new()
	button.name = "BackButton"
	button.text = "返回"
	# Bottom-left of the settings art is empty; the paper strips sit above and to the right.
	button.position = Vector2(48, 1320)
	button.size = Vector2(220, 84)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 42)
	button.pressed.connect(_close_settings)
	return button


func _fill(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _chain_horizontal(buttons: Array[ArtButton]) -> void:
	for index in buttons.size():
		var button := buttons[index]
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(button)
		if index == 0:
			button.focus_neighbor_left = button.get_path_to(button)
		else:
			button.focus_neighbor_left = button.get_path_to(buttons[index - 1])
		if index + 1 == buttons.size():
			button.focus_neighbor_right = button.get_path_to(button)
		else:
			button.focus_neighbor_right = button.get_path_to(buttons[index + 1])


func _open_new_game() -> void:
	_settings_layer.visible = false
	_new_layer.visible = true
	_set_menu_enabled(false)
	var cancel := _new_layer.get_node("CancelButton") as ArtButton
	cancel.grab_focus()


func _close_new_game() -> void:
	_new_layer.visible = false
	_set_menu_enabled(true)


func _open_settings() -> void:
	_new_layer.visible = false
	_settings_layer.visible = true
	_set_menu_enabled(false)
	var back := _settings_layer.get_node("BackButton") as Button
	back.grab_focus()


func _close_settings() -> void:
	_settings_layer.visible = false
	_set_menu_enabled(true)


func _set_menu_enabled(enabled: bool) -> void:
	for button in _menu_buttons:
		button.set_input_enabled(enabled)
	if enabled:
		_focus_start()


func _focus_start_if_windowed() -> void:
	# ui_accept still targets 开始游戏. Hover art follows the pointer, so this
	# grab must not paint the button. Headless skips it; the menu test focuses
	# explicitly when it checks that case.
	if DisplayServer.get_name() == "headless":
		return
	_focus_start()


func _focus_start() -> void:
	if _start_button == null:
		return
	if _new_layer.visible or _settings_layer.visible:
		return
	_start_button.grab_focus()


func _start_run() -> void:
	get_tree().change_scene_to_file(RUN_SCENE)


func _quit_game() -> void:
	get_tree().quit()
