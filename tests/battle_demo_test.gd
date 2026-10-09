extends SceneTree
## Instantiates the battle demo and checks UI stays in sync with CombatEngine.

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _ids(cards: Array) -> Array:
	var out: Array = []
	for card in cards:
		out.append(null if card == null else card.id)
	return out


func _make_demo() -> BattleDemo:
	var demo: BattleDemo = load("res://scenes/cards/card_demo.tscn").instantiate()
	demo.auto_advance = false
	demo.sound_on = false
	demo.record_path = "user://emergence_v03_test.cfg"
	root.add_child(demo)
	return demo


func _await_ui() -> void:
	await process_frame
	await process_frame
	await process_frame


func _run() -> void:
	root.size = Vector2i(1440, 900)
	await _test_intro_and_start()
	await _test_select_fire_and_ui()
	await _test_burn_end_turn_and_timeout()
	await process_frame
	if _failures == 0:
		print("PASS: battle demo intro, hand fire, burn, end turn, countdown, UI/engine sync")
	quit(1 if _failures else 0)


func _test_intro_and_start() -> void:
	var demo := _make_demo()
	await _await_ui()
	_check(demo.engine.s.phase == "intro", "Demo must start on the intro phase")
	_check(demo.overlay.visible and demo.current_overlay() == "intro", "Intro overlay must be visible")
	_check(demo.hp_label.text.contains("80") and demo.enemy_hp_label.text.contains("120"), "Intro HP labels must show 80 and 120")
	_check(demo.timer_label.text.contains("10"), "Intro timer must show the 10s turn")
	_check(demo.start_button != null, "Start button must exist on the intro modal")
	demo.start_button.pressed.emit()
	await _await_ui()
	_check(demo.engine.s.phase == "player" and demo.engine.active(), "Start must enter the player turn")
	_check(not demo.overlay.visible and demo.current_overlay() == "", "Intro overlay must close after start")
	_check(_ids(demo.engine.s.hand) == ["n3", "n5", "n0", "m1", "n6"], "Seed 20261009 must deal n3, n5, n0, m1, n6")
	_check(demo.hp_label.text == "80 / 100", "Player HP label must match engine HP")
	_check(demo.enemy_hp_label.text == "120 / 120", "Enemy HP label must match engine HP")
	_check(demo.intent_label.text.contains("8"), "Round 1 intent must show 8")
	_check(demo.round_label.text.contains("第 1 回合"), "Round caption must show round 1")
	_check(demo.engine.invariant(), "Invariant must hold after start")
	demo.queue_free()
	await process_frame


func _test_select_fire_and_ui() -> void:
	var demo := _make_demo()
	await _await_ui()
	demo.act("start")
	await _await_ui()
	demo.click_hand(2)
	demo.click_hand(0)
	demo.hand_buttons[3].pressed.emit()
	await _await_ui()
	_check(demo.engine.s.selected == ["n0", "n3"] and str(demo.engine.s.operatorId) == "m1", "Clicking hand slots must select −5, −2 and ×")
	_check(demo.eq_slot_a.get_node("Label").text.contains("5"), "Equation slot A must show the first number")
	_check(demo.eq_slot_op.get_node("Label").text == "×", "Equation operator slot must show ×")
	_check(not demo.fire_button.disabled, "Fire must enable once two numbers and an operator are packed")
	_check(demo.eq_result.text == "—", "Default mode must hide the result until fire")
	demo.fire_button.pressed.emit()
	await _await_ui()
	_check(demo.engine.s.enemies[0].hp == 110 and demo.engine.s.enemies[0].burn == 4, "−5 × −2 must deal 10 and apply 4 burn")
	_check(demo.enemy_hp_label.text == "110 / 120", "Enemy HP label must follow the engine after fire")
	_check(demo.eq_reaction.text.contains("余烬叠燃") or demo.eq_reaction.text.contains("(−5) × (−2) = 10"), "Equation line must reveal the last shot")
	_check(demo.formula_reveal_main.text.contains("×"), "Formula reveal must show the fired equation")
	_check(_ids(demo.engine.s.hand) == [null, "n5", null, null, "n6"], "Fired slots must stay empty")
	_check(demo.hand_buttons[0].disabled and demo.hand_buttons[2].disabled, "Empty hand slots must be disabled")
	_check(demo.hand_mode_label.text.contains("凑不出算式") or demo.hand_mode_label.text.contains("烧掉"), "Hand caption must notice the incomplete hand")
	_check(demo.race_equations_label.text == "01", "Race strip must count the completed equation")
	_check(demo.engine.invariant(), "Invariant must hold after firing from the UI")
	demo.queue_free()
	await process_frame


func _test_burn_end_turn_and_timeout() -> void:
	var demo := _make_demo()
	await _await_ui()
	demo.act("start")
	await _await_ui()
	demo.click_hand(2)
	demo.click_hand(0)
	demo.click_hand(3)
	demo.act("fire")
	await _await_ui()
	demo.burn_button.pressed.emit()
	await _await_ui()
	_check(demo.engine.s.burnMode, "Burn button must enter burn mode")
	_check(demo.hand_mode_label.text.contains("烧掉"), "Hand caption must show burn mode")
	demo.click_hand(4)
	await _await_ui()
	_check(demo.engine.s.hp == 90 and demo.engine.s.stats.healing == 10, "Burning +1 must heal 10")
	_check(demo.hp_label.text == "90 / 100", "HP label must match the healed engine value")
	_check(demo.engine.s.hand[4] == null, "Burned slot must stay empty")
	_check(demo.burn_count_label.text.contains("1"), "Burn counter must show one exiled card")
	demo.handle_key(KEY_E)
	await _await_ui()
	_check(demo.engine.s.phase == "enemy", "E must end the turn and hand control to the enemy")
	_check(demo.timer_label.text == "敌方", "Timer must show 敌方 during the enemy phase")
	_check(demo.end_turn_button.text.contains("敌方行动"), "End-turn button must show the enemy phase")
	_check(not demo.engine.active() and demo.fire_button.disabled, "Player actions must lock during the enemy windup")
	demo.queue_free()
	await process_frame

	var timeout := _make_demo()
	await _await_ui()
	timeout.act("start")
	await _await_ui()
	timeout.engine.advance(10.0)
	await _await_ui()
	_check(timeout.engine.s.phase == "enemy" and timeout.engine.s.enemyStage == "windup", "Advancing 10s must expire the player turn")
	_check(timeout.engine.s.stats.skips == 1, "A timeout with no equation must count as a skip")
	_check(timeout.timer_label.text == "敌方", "Expired countdown UI must match the enemy phase")
	_check(timeout.round_label.text.contains("敌方行动"), "Round caption must say 敌方行动 after timeout")
	_check(timeout.hp_label.text == "80 / 100", "Timeout itself must not apply the enemy hit")
	_check(timeout.engine.invariant(), "Invariant must hold after countdown expiry")
	timeout.handle_key(KEY_P)
	await _await_ui()
	_check(timeout.current_overlay() == "pause" and timeout.engine.s.paused, "P must open the pause overlay and stop the clock")
	_check(not timeout.engine.s.ranked, "Pausing during play must unrank the run")
	var pause_panel := timeout.overlay_host.get_node_or_null("ModalPanel") as Control
	_check(pause_panel != null and pause_panel.custom_minimum_size.x <= 560, "Pause dialog must be a compact card, not a full-board sheet")
	var pause_scroll := timeout.overlay_host.get_node_or_null("ModalPanel/Margin/Scroll") as Control
	_check(pause_scroll != null and pause_scroll.custom_minimum_size.y < 200, "Pause dialog must size to its buttons, not a 620px empty scroller")
	timeout.adjust_zoom(0.3)
	_check(is_equal_approx(timeout.ui_zoom, 1.3), "Zoom in must raise the UI scale")
	timeout.adjust_zoom(-2.0)
	_check(timeout.ui_zoom >= BattleDemo.ZOOM_MIN, "Zoom must clamp at the minimum")
	timeout.ui_zoom = 1.0
	timeout._apply_zoom()
	timeout.act("close")
	await _await_ui()
	_check(timeout.current_overlay() == "" and not timeout.engine.s.paused, "Closing pause must resume the battle overlay")
	timeout.queue_free()
	await process_frame
