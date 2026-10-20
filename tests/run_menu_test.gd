extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func settle() -> void:
	for i in 4:
		await process_frame


func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)


func click(button: Control) -> void:
	var point := button.get_global_rect().get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
	await settle()


func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/menu-qa")
	root.get_texture().get_image().save_png("res://build/menu-qa/" + label + ".png")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/run/run_shell.tscn")
	await settle()
	var shell = current_scene
	var menu = shell.get_node("RunMenu")
	await capture("room-entry")
	await click(menu.get_node("MenuButton"))
	check(menu._overlay.visible and paused, "Visible menu button opens a paused overlay")
	await capture("pause")
	await click(menu._quit)
	check(menu._confirm.visible and menu._destination == "quit", "Quit requires confirmation")
	await capture("confirm")
	if OS.get_cmdline_user_args().has("--quit"):
		print("Checking confirmed exit; process must finish with code 0")
		await click(menu._confirm)
		push_error("Confirmed exit did not terminate the game")
		quit(1)
		return
	key(KEY_ESCAPE)
	check(menu._overlay.visible and not menu._confirm.visible, "Escape cancels leaving without resuming")
	key(KEY_ESCAPE)
	check(not menu._overlay.visible and not paused, "Escape resumes the run")

	var room := GameData.room("RM_RUST")
	shell.run.current_room = {"room_uid": shell.run.uid("R"), "room_id": "RM_RUST",
		"content_id": room.get("content_id", ""), "room_kind": room.get("room_kind", ""),
		"scene_key": "battle", "status": "ENTERED", "depth": 1, "slot_index": 1}
	shell._show_battle()
	await settle()
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle()
		var bar: Control = shell._battle.get_node("Board/Margin/Column/TopBar")
		check(bar.get_global_rect().encloses(menu.get_node("MenuButton").get_global_rect()), "Pause button stays inside the battle bar at " + str(resolution))
	await capture("battle-entry")
	await click(menu.get_node("MenuButton"))
	check(menu._overlay.visible and paused, "Battle pause icon opens the shared menu")
	await click(menu._resume)
	var battle: CardBattle = shell._session.ctx.battle
	shell._battle.formula.append("keep-selection")
	key(KEY_ESCAPE)
	check(menu._overlay.visible and paused, "Escape opens the menu during combat")
	var remaining := battle.turn_remaining
	await create_timer(0.15).timeout
	check(battle.turn_remaining == remaining, "Menu freezes the combat clock")
	key(KEY_P)
	key(KEY_E)
	check(not battle.paused, "Menu blocks combat shortcuts")
	check(shell._battle.formula == ["keep-selection"], "Opening the menu preserves the equation")
	await click(menu._resume)
	check(not paused and not menu._overlay.visible, "Continue works while the tree is paused")
	battle.paused = true
	key(KEY_ESCAPE)
	key(KEY_ESCAPE)
	check(battle.paused, "Menu preserves a manually paused battle")
	battle.paused = false
	shell._inventory.slide_seconds = 0.01
	shell._inventory.request_open()
	await create_timer(0.05).timeout
	key(KEY_ESCAPE)
	check(not menu._overlay.visible, "First Escape closes the bag without opening the menu")
	await create_timer(0.05).timeout
	check(not battle.paused, "Closing the bag restores combat")
	shell._inventory.request_open()
	await create_timer(0.05).timeout
	await click(menu.get_node("MenuButton"))
	check(menu._overlay.visible and battle.paused, "Menu is accessible over the open bag")
	await click(menu._resume)
	check(shell._inventory.blocks_input() and battle.paused, "Continue preserves the open bag pause")
	await click(menu.get_node("MenuButton"))
	await click(menu._main)
	check(menu._confirm.visible and paused, "Returning to menu requires confirmation")
	await click(menu._confirm)
	check(current_scene.name == "MainMenu" and not paused, "Return loads a working main menu and releases pause")
	if failures == 0:
		print("PASS: run menu input, confirmation, combat pause, bag interaction, and return")
	quit(0 if failures == 0 else 1)
