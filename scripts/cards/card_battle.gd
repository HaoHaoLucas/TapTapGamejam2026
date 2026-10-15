class_name CardBattle
extends RefCounted
## Thin combat clock around the card services: 10s turns, combo clicks, one fixed intent.

var battle_uid: String = ""
var phase: String = "IDLE"
var paused: bool = false
var turn_index: int = 0
var turn_remaining: float = 0.0
var clock: float = 0.0
var player_hp: int = 100
var player_max_hp: int = 100
var enemy_hp: int = 0
var enemy_max_hp: int = 0
var intent_damage: int = 0
var combo_streak: int = 0
var combo_pending: bool = false
var combo_used_this_turn: bool = false
var combo_window: float = 0.0
var combo_remaining: float = 0.0
var combo_snapshots: Array = []
var add_snapshots: Array = []
var last_click_clock: float = -1.0
var _run: WeakRef
var _seq: int = 0


func _init(ctx: RunContext) -> void:
	_run = weakref(ctx)


func start(enemy_hp_value: int, intent: int, auto_deal: bool, player_hp_value: int) -> void:
	var ctx := _ctx()
	_seq += 1
	battle_uid = "%s_b%d" % [ctx.run_id, _seq]
	phase = "PLAYER_ACTIVE"
	paused = false
	clock = 0.0
	last_click_clock = -1.0
	combo_streak = 0
	combo_pending = false
	combo_used_this_turn = false
	combo_window = 0.0
	combo_remaining = 0.0
	combo_snapshots = []
	add_snapshots = []
	enemy_max_hp = enemy_hp_value
	enemy_hp = enemy_hp_value
	intent_damage = intent
	player_max_hp = int(ctx.catalog.rule().max_hp)
	player_hp = player_max_hp if player_hp_value < 0 else player_hp_value
	for card in ctx.library.all_cards():
		card.locked_until_turn = -1
		card.drawn_turn = -1
	turn_index = 1
	ctx.library.turn_index = 1
	turn_remaining = float(ctx.catalog.rule().turn_seconds)
	if auto_deal:
		ctx.draw_service.opening_deal(battle_uid)


func end_battle() -> void:
	var ctx := _ctx()
	for card in ctx.library.all_cards():
		if card.zone in [CardInstance.DRAW, CardInstance.HAND, CardInstance.DISCARD, CardInstance.RESOLVING]:
			ctx.library.move(card, CardInstance.RUN_DECK, "BATTLE_END", battle_uid, ctx)
		card.drawn_turn = -1
		card.locked_until_turn = -1
	phase = "IDLE"
	turn_index = 0
	ctx.library.turn_index = 0
	combo_pending = false


func end_player_turn() -> void:
	if phase != "PLAYER_ACTIVE":
		return
	if enemy_hp <= 0:
		phase = "VICTORY"
		combo_pending = false
		return
	if combo_pending:
		phase = "COMBO"
		combo_remaining = combo_window
		return
	resolve_enemy_turn()


func advance(dt: float) -> void:
	if paused or dt <= 0.0:
		return
	if phase != "PLAYER_ACTIVE" and phase != "COMBO":
		return
	clock += dt
	if phase == "PLAYER_ACTIVE":
		turn_remaining = maxf(0.0, turn_remaining - dt)
		if turn_remaining <= 0.0:
			end_player_turn()
	elif phase == "COMBO":
		combo_remaining = maxf(0.0, combo_remaining - dt)
		if combo_remaining <= 0.0:
			resolve_enemy_turn()


func combo_click() -> Dictionary:
	var ctx := _ctx()
	if phase != "COMBO":
		return {"ok": false, "reason_code": "PHASE", "damage": 0}
	var interval := 1.0 / float(ctx.catalog.rule().combo_click_rate_cap)
	if last_click_clock >= 0.0 and clock - last_click_clock < interval:
		return {"ok": false, "reason_code": "RATE", "damage": 0}
	last_click_clock = clock
	var damage := int(ctx.catalog.rule().combo_click_damage)
	apply_damage(damage)
	if enemy_hp <= 0:
		phase = "VICTORY"
		combo_pending = false
	return {"ok": true, "reason_code": "OK", "damage": damage}


func resolve_enemy_turn() -> void:
	var ctx := _ctx()
	phase = "ENEMY"
	combo_pending = false
	player_hp = maxi(0, player_hp - intent_damage)
	if player_hp <= 0:
		phase = "DEFEAT"
		return
	var hand: Array = ctx.library.pile(CardInstance.HAND)
	for card_uid in hand:
		var card := ctx.library.get_card(str(card_uid))
		if card.is_frozen(turn_index):
			continue
		ctx.library.move(card, CardInstance.DISCARD, "END_TURN", battle_uid, ctx)
	turn_index += 1
	ctx.library.turn_index = turn_index
	combo_streak = 0
	combo_used_this_turn = false
	combo_window = 0.0
	combo_remaining = 0.0
	combo_snapshots = []
	add_snapshots = []
	last_click_clock = -1.0
	ctx.draw_service.refill(battle_uid, "TURN_START", battle_uid)
	if ctx.library.is_fighting_exhausted():
		phase = "DECK_EXHAUSTED"
		return
	phase = "PLAYER_ACTIVE"
	turn_remaining = float(ctx.catalog.rule().turn_seconds)


func apply_damage(amount: int) -> void:
	if amount <= 0:
		return
	enemy_hp = maxi(0, enemy_hp - amount)


func _ctx() -> RunContext:
	return _run.get_ref() as RunContext
