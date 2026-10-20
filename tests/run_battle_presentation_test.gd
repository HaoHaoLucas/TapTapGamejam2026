extends SceneTree

const VIEW := preload("res://scenes/run/run_battle.tscn")
const MONSTERS := preload("res://scripts/run/monster_presenter.gd")
const CHROME := preload("res://scripts/run/battle_chrome.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func session_for(monster: String = "ENC_INK") -> CombatSession:
	var run: RunState = RunService.new_run("battle-presentation").run
	run.current_room = {"room_uid": "PRESENTATION", "content_id": monster, "room_kind": "NORMAL", "scene_key": "battle", "status": "ENTERED"}
	var session := CombatSession.new()
	session.start(run)
	return session


func _run() -> void:
	var view: RunBattle = VIEW.instantiate()
	root.add_child(view)
	var session := session_for()
	view.adopt(session)
	view.set_process(false) # Explicit deltas make boundary assertions deterministic.
	var battle := session.ctx.battle
	var time := battle.turn_remaining
	var hand := session.ctx.library.pile(CardInstance.HAND).duplicate()
	var selected := str(hand[0])
	view._on_card_pressed(selected)
	view.selected_uid = selected # Even a stale selection cannot burn during preparation.
	view._burn()
	view._commit()
	view._clear_selection()
	view._end_turn()
	view._combo_click()
	check(view.formula.is_empty() and battle.turn_index == 1, "Preparation blocks every action entry")
	check(session.ctx.library.pile(CardInstance.HAND) == hand, "Preparation cannot move cards")
	view._process(2.0)
	check(is_equal_approx(battle.turn_remaining, time) and not battle.delayed_draw_done, "Preparation consumes no battle time or delayed draw")
	battle.paused = true
	view._process(10.0)
	check(is_equal_approx(view.presentation_remaining, 3.0), "Bag pause freezes preparation")
	battle.paused = false
	view.set_external_input_blocked(true)
	view._process(10.0)
	check(is_equal_approx(view.presentation_remaining, 3.0), "External input lock freezes preparation")
	view.set_external_input_blocked(false)
	view.hide()
	view._process(10.0)
	check(is_equal_approx(view.presentation_remaining, 3.0), "Hidden preparation sleeps")
	view.show()
	view.set_process(false)
	paused = true
	view._process(10.0)
	check(is_equal_approx(view.presentation_remaining, 3.0), "Menu pause freezes preparation")
	paused = false
	view._process(4.0)
	check(view.presentation == RunBattle.Presentation.ACTIVE and is_equal_approx(battle.turn_remaining, time), "Preparation ends without spilling time into turn one")
	view._process(0.25)
	check(is_equal_approx(battle.turn_remaining, time - 0.25), "Active clock starts on next frame")
	var sequence := view._action_seq
	view._commit()
	check(view._action_seq == sequence and view._log.text == "", "Empty keyboard submission is silent")
	view._on_card_pressed(selected)
	check(not view.formula.is_empty(), "Cards work after preparation")
	view._commit()
	view._update_action_states()
	check(view.formula == [selected] and view._action_seq == sequence, "Incomplete submission preserves selected cards without committing")
	check(view.get_node("Board/Margin/Column/Controls/FireButton").disabled, "Incomplete formula cannot fire")
	check(view._preview.text.contains("数字") and not view._log.text.contains("没有提交"), "Equation area explains how to complete the selection")
	var heard: Array[String] = []
	view.returned_to_tower.connect(func(outcome: String) -> void: heard.append(outcome))
	battle.enemy_hp = 0
	battle.declare_victory()
	view._note_phase()
	check(view._victory.visible and not view._combo_layer.visible and heard.is_empty(), "Victory is visible before returning")
	view._burn()
	view._end_turn()
	view._combo_click()
	view._process(1.0)
	check(heard.is_empty() and battle.turn_index == 1, "Victory locks actions and waits two seconds")
	battle.paused = true
	view._process(5.0)
	check(heard.is_empty() and is_equal_approx(view.presentation_remaining, 1.0), "Bag freezes victory countdown")
	battle.paused = false
	paused = true
	view._process(5.0)
	check(heard.is_empty(), "Menu freezes victory countdown")
	paused = false
	view._process(1.0)
	view._process(5.0)
	view._note_phase()
	check(heard == ["VICTORY"], "Victory reports exactly once after two seconds")
	view.adopt(session_for("ENC_RUST"))
	check(view.presentation == RunBattle.Presentation.PREPARING and not view._victory.visible and view._enemy_art.modulate.a == 1.0 and view.formula.is_empty(), "New battle clears every presentation artifact")
	view._process(5.0)
	var combo_battle := view.session.ctx.battle
	combo_battle.phase = "COMBO"
	combo_battle.enemy_hp = 1
	combo_battle.combo_remaining = 2.0
	view._combo_click()
	check(view.presentation == RunBattle.Presentation.VICTORY_PRESENTATION and view._victory.visible and heard.size() == 1, "Combo kill also waits for victory presentation")
	view.adopt(session_for())
	view._process(2.0)
	check(heard.size() == 1, "Replacing a victory cancels its old report")
	view.session.ctx.battle.phase = "DECK_EXHAUSTED"
	view._note_phase()
	check(heard == ["VICTORY", "DECK_EXHAUSTED"], "Loss keeps the original outcome path")
	_test_monsters()
	view.free()
	await _test_hosted_flow()
	if failures == 0:
		print("PASS: preparation, victory, input guards, monster descriptions and hosted reward handoff")
	quit(1 if failures else 0)


func _test_monsters() -> void:
	for encounter in MonsterRules.ENCOUNTER_MONSTER:
		# Keep the context alive: CardBattle intentionally stores only a weak reference.
		var session := session_for(encounter)
		var battle := session.ctx.battle
		var description := MONSTERS.describe(battle)
		check(description.summary != "" and description.detail != "", "Every monster has a description: " + encounter)
		if encounter == "ENC_INK":
			battle.ink_tax_used = true
			check(MONSTERS.describe(battle).state.contains("已消耗"), "Ink state reflects consumption")
		if encounter == "ENC_PRIEST":
			battle.priest_heal_cancelled = true
			check(MONSTERS.describe(battle).state.contains("已阻止"), "Priest state reflects cancelled healing")
		if encounter == "ENC_SWORD":
			battle.turn_index = 3
			battle.sword_positive_add = true
			battle.sword_positive_mul = true
			check(MONSTERS.describe(battle).state.contains("已打断"), "Sword state reflects interrupt")
		if encounter == "ENC_THIEF":
			battle.declare_victory()
			check(MONSTERS.describe(battle).state.contains("无扣押"), "Thief state reflects released card")


func _test_hosted_flow() -> void:
	var shell = load("res://scenes/run/run_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	shell.run.current_room = {"room_uid": "HOSTED", "room_id": "RM_RUST", "content_id": "ENC_RUST", "room_kind": "NORMAL", "scene_key": "battle", "status": "ENTERED"}
	shell.run.phase = "ROOM"
	shell._show_battle()
	var view: RunBattle = shell._battle
	view.set_process(false)
	var bag: RunInventory = shell.get_node("Inventory")
	check(bag._panel.get_theme_stylebox("panel") is StyleBoxTexture, "Battle bag uses paper chrome")
	bag.request_open()
	view._process(10.0)
	check(view.presentation_remaining == 5.0, "Real bag opening freezes preparation")
	bag._stop_slide()
	bag._sliding = false
	bag._target_open = false
	bag._open_ratio = 0.0
	bag._release_pause()
	bag._apply_input_lock()
	var menu = shell.get_node("RunMenu")
	menu.open_menu()
	check(menu.get_node("Overlay/Center/Panel").get_theme_stylebox("panel") is StyleBoxTexture, "Battle pause menu uses paper chrome")
	view._process(10.0)
	check(view.presentation_remaining == 5.0, "Real pause menu freezes preparation")
	menu.close_menu()
	view._process(5.0)
	view.session.ctx.battle.declare_victory()
	view._note_phase()
	check(shell._session != null and shell.run.phase != "REWARD", "Host does not generate reward before victory display")
	view._process(2.0)
	check(shell._session == null and shell.run.phase == "REWARD", "Host writes back and generates reward after victory display")
	check(not (bag._panel.get_theme_stylebox("panel") is StyleBoxTexture), "Bag restores roam chrome after battle")
	menu.open_menu()
	check(not (menu.get_node("Overlay/Center/Panel").get_theme_stylebox("panel") is StyleBoxTexture), "Pause menu restores roam chrome after battle")
	menu.close_menu()
	shell.free()
