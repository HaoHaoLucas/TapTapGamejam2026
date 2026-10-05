extends Node2D

const Player = preload("res://scripts/player.gd")
const START := Vector2(120, 324)
const OBSTACLES: Array[Rect2] = [
	Rect2(300, 180, 48, 288), Rect2(530, 90, 48, 210),
	Rect2(530, 420, 48, 138), Rect2(770, 250, 48, 210)
]
const PICKUPS: Array[Vector2] = [
	Vector2(220, 150), Vector2(430, 510), Vector2(660, 170),
	Vector2(680, 500), Vector2(960, 324)
]
var player: CharacterBody2D
var collected: Array[Vector2] = []
var hud: Label
var status: Label
var elapsed: float = 0.0
var finished: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	for rect in OBSTACLES:
		_add_wall(rect)
	for rect in [Rect2(40, 80, 1072, 16), Rect2(40, 552, 1072, 16), Rect2(40, 80, 16, 488), Rect2(1096, 80, 16, 488)]:
		_add_wall(rect)
	player = Player.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.position = START
	add_child(player)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(48, 22)
	hud.add_theme_font_size_override("font_size", 24)
	canvas.add_child(hud)
	status = Label.new()
	status.position = Vector2(48, 592)
	status.add_theme_font_size_override("font_size", 18)
	canvas.add_child(status)
	_update_hud()

func _setup_input() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"pause": [KEY_ESCAPE], "restart": [KEY_R]
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _add_wall(rect: Rect2) -> void:
	var wall := StaticBody2D.new()
	wall.position = rect.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().paused = false
		get_tree().reload_current_scene()
	elif event.is_action_pressed("pause") and not finished:
		get_tree().paused = not get_tree().paused
		_update_hud()

func _process(delta: float) -> void:
	if get_tree().paused or finished:
		return
	elapsed += delta
	for point in PICKUPS:
		if point not in collected and player.position.distance_to(point) < 28.0:
			collected.append(point)
			queue_redraw()
	if collected.size() == PICKUPS.size():
		finished = true
		player.set_physics_process(false)
	_update_hud()

func _update_hud() -> void:
	hud.text = "EMERGENCE     /     ENERGY %d / %d     /     %.1fs" % [collected.size(), PICKUPS.size(), elapsed]
	if finished:
		status.text = "All energy collected!   /   R to restart"
	elif get_tree().paused:
		status.text = "PAUSED   /   Esc to continue   /   R to restart"
	else:
		status.text = "WASD / Arrows: Move     Esc: Pause     R: Restart     Collect all glowing energy."

func _draw() -> void:
	for x in range(40, 1113, 32):
		draw_line(Vector2(x, 80), Vector2(x, 568), Color(0.12, 0.2, 0.27, 0.4))
	for y in range(80, 569, 32):
		draw_line(Vector2(40, y), Vector2(1112, y), Color(0.12, 0.2, 0.27, 0.4))
	draw_rect(Rect2(40, 80, 1072, 488), Color("355067"), false, 2.0)
	for rect in OBSTACLES:
		draw_rect(rect, Color("21354a"))
		draw_rect(rect, Color("54758d"), false, 2.0)
	for point in PICKUPS:
		if point not in collected:
			draw_circle(point, 22.0, Color(1.0, 0.77, 0.35, 0.1))
			draw_circle(point, 9.0, Color("ffc65c"))
			draw_arc(point, 15.0, 0.0, TAU, 32, Color("ffc65c"), 1.0)
