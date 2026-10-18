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
	await _test_menu_enters_room_choice()
	await _test_battle_choice_opens_combat()
	await _test_battle_losses()
	_test_sacrifice_result_is_readable()
	if _failures == 0:
		print("PASS: a battle room opens the jam fight and writes zones back")
	quit(1 if _failures else 0)


func _test_menu_enters_room_choice() -> void:
	var changed := change_scene_to_file("res://scenes/menu/main_menu.tscn")
	_check(changed == OK, "The main menu must load")
	await process_frame
	await process_frame
	var menu := current_scene
	_check(menu != null and menu.name == "MainMenu", "Play starts on the main menu")
	if menu == null:
		return
	var start := menu.get_node_or_null("Stage/StartButton") as ArtButton
	_check(start != null, "开始游戏 is on the main menu")
	if start == null:
		return
	start.pressed.emit()
	await process_frame
	await process_frame
	var shell := current_scene
	_check(shell != null and shell.name == "RunShell", "开始游戏 enters the tower")
	if shell == null or shell.run == null:
		_check(shell != null and shell.run != null, "The tower run did not start from the menu")
		return
	_check_first_choice(shell)
	shell.queue_free()
	await process_frame


func _check_first_choice(shell) -> void:
	_check(str(shell.run.current_room.get("status", "")) != "ENTERED", "The first day opens on a room choice")
	_check(shell.run.current_offers.size() == 3, "The first day offers three rooms")
	_check(shell._battle == null or not shell._battle.visible, "The fight stays hidden until a room is chosen")
	var choices := 0
	for child in shell._body.get_children():
		if child is Button and (str(child.text) == "战斗" or str(child.text) == "奇遇"):
			choices += 1
	_check(choices == 3, "The room list shows three choices, got %s" % choices)


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
	_check_first_choice(shell)
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
	_check(shell._battle != null and shell._battle.visible and shell._battle is RunBattle, "The jam battle view must be shown")
	_check(shell._session != null and shell._session.ctx != null and shell._session.ctx.battle.phase == "PLAYER_ACTIVE", "Combat must be in the player turn")
	if shell._session == null or shell._session.ctx == null:
		shell.queue_free()
		await process_frame
		return
	_check(_hand_views(shell) == 5, "The battle hand must show five cards")
	_check(shell._header.visible == false, "The room list must step aside for the battle")
	var uids: Array = shell._session.projected_uids.duplicate()
	var burned := _burn_hand_number(shell)
	_check(burned != "", "A hand number can be burned")
	shell._session.ctx.battle.phase = "VICTORY"
	shell._on_return_to_tower("VICTORY")
	_check(shell.run.phase == "REWARD", "VICTORY returns to the tower as a win, got %s" % shell.run.phase)
	for card_uid in uids:
		var inst = shell.run.find_card(str(card_uid))
		if str(card_uid) == burned:
			_check(inst != null and inst.zone == "REMOVED", "A burned card stays removed")
		else:
			_check(inst != null and inst.zone == "RUN_DECK", "Write-back restores the other cards to the run deck")
	shell.queue_free()
	await process_frame


func _test_battle_losses() -> void:
	var defeat = await _open_battle()
	if defeat == null:
		return
	defeat._session.ctx.battle.phase = "DEFEAT"
	defeat._on_return_to_tower("DEFEAT")
	_check(defeat.run.phase == "DEAD" and defeat.run.outcome == "defeat", "DEFEAT is a loss")
	defeat.queue_free()
	await process_frame
	var exhausted = await _open_battle()
	if exhausted == null:
		return
	exhausted._session.ctx.battle.phase = "DECK_EXHAUSTED"
	exhausted._on_return_to_tower("DECK_EXHAUSTED")
	_check(exhausted.run.phase == "DEAD" and exhausted.run.outcome == "defeat", "DECK_EXHAUSTED is a loss")
	exhausted.queue_free()
	await process_frame


func _open_battle():
	var shell = load("res://scenes/run/run_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	if shell.run == null or not _reach_choice(shell):
		_check(false, "Could not open a battle from the tower")
		shell.queue_free()
		await process_frame
		return null
	shell._show()
	await process_frame
	var battle_button: Button = null
	for child in shell._body.get_children():
		if child is Button and str(child.text) == "战斗":
			battle_button = child
			break
	if battle_button == null:
		_check(false, "A battle choice must be on screen")
		shell.queue_free()
		await process_frame
		return null
	battle_button.pressed.emit()
	await process_frame
	await process_frame
	if shell._session == null or shell._session.ctx == null:
		_check(false, "The battle session did not open")
		shell.queue_free()
		await process_frame
		return null
	return shell


func _hand_views(shell) -> int:
	var count := 0
	if shell._battle == null or shell._battle._hand_box == null:
		return 0
	for child in shell._battle._hand_box.get_children():
		if child is CardView:
			count += 1
	return count


func _burn_hand_number(shell) -> String:
	var ctx = shell._session.ctx
	ctx.battle.player_hp = 40
	for card_uid in ctx.library.pile(CardInstance.HAND):
		var card = ctx.library.get_card(str(card_uid))
		if card == null:
			continue
		var kind := str(ctx.catalog.card(card.def_id).get("card_kind", ""))
		if kind != "NUM" or card.printed_value(ctx.catalog) == 0:
			continue
		var result = ctx.card_service.burn(card.card_uid, "shell-burn")
		if result.get("ok", false) and result.get("removed", false):
			return card.card_uid
	return ""


func _test_sacrifice_result_is_readable() -> void:
	var created := RunService.new_run("sac-result")
	_check(created.get("ok", false), "Could not start a run for the sacrifice result")
	if not created.get("ok", false):
		return
	var run: RunState = created.run
	var room := GameData.room("RM_SAC")
	run.current_room = {
		"room_uid": run.uid("R"),
		"room_id": "RM_SAC",
		"content_id": "EV_SAC",
		"room_kind": str(room.get("room_kind", "EVENT")),
		"display_key": str(room.get("display_key", "ROOM_EVENT")),
		"scene_key": "event",
		"status": "ENTERED",
	}
	run.phase = "ROOM"
	var room_uid := str(run.current_room.get("room_uid", ""))
	var offered := str(TowerDeck.deck_cards(run)[0].card_uid)
	var result := EventService.commit(run, room_uid, {"sacrifice_uids": [offered]}, "sac-result")
	_check(result.get("ok", false), "A one-card sacrifice should succeed: %s" % result.get("error", ""))
	if not result.get("ok", false):
		return
	var shell = load("res://scripts/run/run_shell.gd").new()
	shell.run = run
	var lines: PackedStringArray = shell._event_result_lines(result)
	var text := "\n".join(lines)
	_check(text.contains("交出了这些牌"), "Sacrifice result must name the cards that were given")
	_check(text.contains("给剩下的牌加上了"), "Sacrifice result must name the marks that were granted")
	_check(text.contains("加上 "), "Each granted mark must be written out, got %s" % text)
	shell.free()


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
