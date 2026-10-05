extends SceneTree

var _failures: int = 0
var _timeouts: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var demo = load("res://scenes/cards/card_demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	var hud: BattleHUD = demo.hud
	hud.time_expired.connect(func() -> void: _timeouts += 1)
	_check(hud.get_time_remaining() > 29.0, "Demo must start a 30 second countdown")
	hud.set_health(200, 100)
	_check(hud._hp_label.text == "HP 100/100" and hud._hp_bar.value == 100, "External HP must update and clamp")
	hud.set_health(-1, 100)
	_check(hud._hp_bar.value == 0, "Negative HP must display zero")
	hud.set_health(70, 100)
	var card: CardData = demo.card_panel.get_hand_cards()[0]
	demo.card_panel.burn_card(card.instance_id)
	hud.start_countdown(0.05)
	await create_timer(0.15).timeout
	_check(_timeouts == 1 and not demo.card_panel.is_turn_active(), "Timeout must end and lock turn exactly once")
	_check(hud.get_time_remaining() == 0.0 and demo._health == 100, "Timeout must settle pending heal")
	demo._finish_turn()
	_check(demo._health == 100 and _timeouts == 1, "Repeated manual finish must not repeat settlement")
	demo._start_turn()
	_check(demo.card_panel.is_turn_active() and hud.get_time_remaining() > 29.0, "Next turn resets countdown")
	hud.start_countdown(0.1)
	demo._finish_turn()
	await create_timer(0.15).timeout
	_check(_timeouts == 1, "Manual finish must stop countdown and prevent delayed timeout")
	demo._start_turn()
	hud.start_countdown(0.05)
	hud.set_time_remaining(12.0)
	await create_timer(0.1).timeout
	_check(hud.get_time_remaining() == 12.0 and _timeouts == 1, "External clock must disable local countdown")
	hud.set_time_remaining(0.0)
	_check(_timeouts == 1 and demo.card_panel.is_turn_active(), "External zero is display-only; Battle owns settlement")
	if _failures == 0:
		print("PASS: HP display, timeout settlement, single settlement, countdown reset and external clock takeover")
	quit(1 if _failures else 0)
