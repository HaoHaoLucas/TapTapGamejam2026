extends SceneTree
## Clicking a room button must enter that room. The button is freed while it emits.


var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(1440, 900)
	await _test_battle_choice_opens_combat()
	if _failures == 0:
		print("PASS: clicking a battle room opens combat")
	quit(1 if _failures else 0)


func _test_battle_choice_opens_combat() -> void:
	var shell = load("res://scenes/run/run_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	_check(shell.run != null, "Run shell must start a run")
	if shell.run == null:
		shell.queue_free()
		await process_frame
		return
	var reached := _reach_choice(shell)
	_check(reached, "Could not reach a room choice")
	if not reached:
		shell.queue_free()
		await process_frame
		return
	shell._show()
	await process_frame
	var battle_button: Button = null
	for child in shell._body.get_children():
		if child is Button and str(child.text) == "战斗":
			battle_button = child
			break
	_check(battle_button != null, "A battle choice must be on screen")
	if battle_button == null:
		shell.queue_free()
		await process_frame
		return
	battle_button.pressed.emit()
	await process_frame
	await process_frame
	_check(str(shell.run.current_room.get("status", "")) == "ENTERED", "Choosing a room must enter it")
	_check(str(shell.run.current_room.get("scene_key", "")) == "battle", "The battle button must enter a battle")
	_check(shell._demo.visible, "The battle view must be shown")
	_check(shell._demo.engine != null and str(shell._demo.engine.s.phase) == "player", "Combat must be in the player turn")
	_check(shell._demo.hand_buttons.size() == 5, "The battle hand must be on screen")
	_check(shell._header.visible == false, "The room list must step aside for the battle")
	shell.queue_free()
	await process_frame


func _reach_choice(shell) -> bool:
	var run: RunState = shell.run
	for _i in 4:
		if str(run.current_room.get("status", "")) != "ENTERED" and not run.current_offers.is_empty():
			return true
		if str(run.current_room.get("status", "")) == "ENTERED":
			var outcome := "victory" if str(run.current_room.get("scene_key", "")) == "battle" else "clear"
			var finished := RunService.finish_room(run, outcome)
			if not finished.get("ok", false):
				return false
		if run.phase == "REWARD":
			var room_uid := str(run.current_room.get("room_uid", ""))
			for session in run.reward_sessions:
				if str(session.get("source_uid", "")) != room_uid or str(session.get("status", "")) != "OPEN":
					continue
				RewardService.skip_session(run, str(session.get("reward_session_uid", "")), run.uid("T"))
			var continued := RunService.continue_after_rewards(run)
			if not continued.get("ok", false):
				return false
	return str(run.current_room.get("status", "")) != "ENTERED" and not run.current_offers.is_empty()
