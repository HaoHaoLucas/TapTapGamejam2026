extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	assert(game.player.position == game.START, "Player must start at spawn")
	Input.action_press("move_right")
	for frame in range(30):
		await physics_frame
	Input.action_release("move_right")
	assert(game.player.position.x > game.START.x, "Movement must advance player")
	game.player.position = Vector2(280, 324)
	Input.action_press("move_right")
	for frame in range(30):
		await physics_frame
	Input.action_release("move_right")
	assert(game.player.position.x < 290, "Wall must stop player")
	for point in game.PICKUPS:
		game.player.position = point
		await process_frame
		await process_frame
	assert(game.finished, "Collecting all energy must finish level")
	assert(game.collected.size() == 5, "Each energy collected exactly once")
	print("PASS: spawn, movement, collision, collection, victory")
	quit()
