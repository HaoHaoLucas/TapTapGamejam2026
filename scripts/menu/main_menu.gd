extends Control
## 主菜单。舞台尺寸与每个按钮的矩形都写在场景里，这里只管缩放适配与开关层。

const RUN_SCENE := "res://scenes/run/run_shell.tscn"

@onready var _stage: Control = $Stage
@onready var _start_button: ArtButton = $Stage/StartButton
@onready var _new_layer: Control = $Stage/NewGameLayer
@onready var _settings_layer: Control = $Stage/SettingsLayer
@onready var _menu_buttons: Array[ArtButton] = [
	$Stage/StartButton as ArtButton,
	$Stage/NewButton as ArtButton,
	$Stage/OptionsButton as ArtButton,
	$Stage/QuitButton as ArtButton,
]


func _ready() -> void:
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
	var fit := minf(view.x / _stage.size.x, view.y / _stage.size.y)
	_stage.scale = Vector2(fit, fit)
	_stage.position = (view - _stage.size * fit) * 0.5


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
