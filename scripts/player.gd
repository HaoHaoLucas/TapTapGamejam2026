extends CharacterBody2D

@export var speed: float = 280.0

func _ready() -> void:
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	collision.shape = shape
	add_child(collision)
	queue_redraw()

func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed
	move_and_slide()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 21.0, Color(0.25, 0.9, 0.8, 0.12))
	draw_circle(Vector2.ZERO, 14.0, Color("64efd0"))
	draw_circle(Vector2(4, -4), 4.0, Color("f1fffa"))
