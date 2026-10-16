class_name CardBattle
extends RefCounted
## 10s player turns. At delayed_draw_at, draw once. Combo clicks, then one enemy action.
## monster_id == "" keeps the flat intent passed to start().

var battle_uid: String = ""
var phase: String = "IDLE"
var paused: bool = false
var turn_index: int = 0
var turn_remaining: float = 0.0
var clock: float = 0.0
var player_elapsed_s: float = 0.0
var delayed_draw_done: bool = false
var player_hp: int = 100
var player_max_hp: int = 100
var enemy_hp: int = 0
var enemy_max_hp: int = 0
var intent_damage: int = 0
var monster_id: String = ""
var monster_name: String = ""
var monster_kind: String = ""
var floor_no: int = 1
var base_atk: int = 0
var hp_mul: float = 1.0
var atk_mul: float = 1.0
var room_hp: float = 1.0
var room_atk: float = 1.0
var phase_mul: float = 1.0
## Announced action. A sword interrupt writes damage and action_mul only.
var intent: Dictionary = {}
var ink_tax_used: bool = false
var priest_heal_cancelled: bool = false
var sword_phase: int = 1
var sword_phase_pending: bool = false
var sword_positive_add: bool = false
var sword_positive_mul: bool = false
var stolen_card_uid: String = ""
var thief_progress: int = 0
var monster_armed_turn: int = 0
var combo_streak: int = 0
var combo_pending: bool = false
var combo_used_this_turn: bool = false
var combo_window: float = 0.0
var combo_remaining: float = 0.0
var combo_snapshots: Array = []
var add_snapshots: Array = []
var last_click_clock: float = -1.0
## Damage chosen but not yet applied. Blocks resource failure until it lands.
var pending_damage: int = 0
## Cards owed back to hand that are not in HAND, DRAW, DISCARD, or RESOLVING yet.
var pending_return_uids: Array = []
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
	pending_damage = 0
	pending_return_uids = []
	if monster_id == "":
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
	_reset_player_clock()
	if monster_id != "":
		MonsterRules.publish_intent(self)
	if auto_deal:
		ctx.draw_service.opening_deal(battle_uid)
	_reset_player_clock()


func end_battle() -> void:
	var ctx := _ctx()
	for card in ctx.library.all_cards():
		if card.zone in [CardInstance.DRAW, CardInstance.HAND, CardInstance.DISCARD, CardInstance.RESOLVING, CardInstance.STOLEN]:
			ctx.library.move(card, CardInstance.RUN_DECK, "BATTLE_END", battle_uid, ctx)
		card.drawn_turn = -1
		card.locked_until_turn = -1
	phase = "IDLE"
	turn_index = 0
	ctx.library.turn_index = 0
	combo_pending = false
	pending_damage = 0
	pending_return_uids = []
	player_elapsed_s = 0.0
	delayed_draw_done = false
	stolen_card_uid = ""
	thief_progress = 0
	monster_armed_turn = 0
	ink_tax_used = false
	priest_heal_cancelled = false
	sword_positive_add = false
	sword_positive_mul = false
	sword_phase = 1
	sword_phase_pending = false
	phase_mul = 1.0


func cancel_delayed_draw() -> void:
	delayed_draw_done = true


func declare_victory() -> void:
	cancel_delayed_draw()
	combo_pending = false
	phase = "VICTORY"
	_release_detained()


func end_player_turn() -> void:
	if phase != "PLAYER_ACTIVE":
		return
	if enemy_hp <= 0:
		declare_victory()
		return
	_close_delayed_draw()
	if combo_pending:
		phase = "COMBO"
		combo_remaining = combo_window
		return
	resolve_enemy_turn()


func advance(dt: float) -> void:
	if paused or dt <= 0.0:
		return
	if phase == "PLAYER_ACTIVE" and enemy_hp <= 0:
		declare_victory()
		return
	if phase != "PLAYER_ACTIVE" and phase != "COMBO":
		return
	clock += dt
	if phase == "COMBO":
		combo_remaining = maxf(0.0, combo_remaining - dt)
		if combo_remaining <= 0.0:
			resolve_enemy_turn()
		return
	player_elapsed_s += dt
	turn_remaining = maxf(0.0, turn_remaining - dt)
	if not delayed_draw_done and player_elapsed_s >= _delayed_draw_at():
		_perform_delayed_draw()
	if phase == "PLAYER_ACTIVE" and turn_remaining <= 0.0:
		end_player_turn()


func combo_click() -> Dictionary:
	var ctx := _ctx()
	if phase != "COMBO":
		return {"ok": false, "reason_code": "PHASE", "damage": 0}
	var interval := 1.0 / float(ctx.catalog.rule().combo_click_rate_cap)
	if last_click_clock >= 0.0 and clock - last_click_clock < interval:
		return {"ok": false, "reason_code": "RATE", "damage": 0}
	last_click_clock = clock
	var damage := int(ctx.catalog.rule().combo_click_damage)
	var hp_before := enemy_hp
	apply_damage(damage)
	if monster_id != "":
		MonsterRules.note_direct_hit(self, hp_before - enemy_hp)
	if enemy_hp <= 0:
		declare_victory()
	return {"ok": true, "reason_code": "OK", "damage": damage}


func resolve_enemy_turn() -> void:
	var ctx := _ctx()
	phase = "ENEMY"
	combo_pending = false
	MonsterRules.apply_enemy_action(self)
	if player_hp <= 0:
		phase = "DEFEAT"
		_release_detained()
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
	if monster_id != "":
		MonsterRules.publish_intent(self)
	var start_draw := int(ctx.catalog.rule().get("turn_start_draw", 5))
	ctx.draw_service.draw_count(start_draw, battle_uid, "TURN_START", battle_uid)
	_reset_player_clock()
	if fail_if_resources_exhausted():
		return
	phase = "PLAYER_ACTIVE"


func apply_damage(amount: int) -> void:
	if amount <= 0:
		return
	enemy_hp = maxi(0, enemy_hp - amount)


func has_pending_damage() -> bool:
	return pending_damage > 0


func has_pending_return() -> bool:
	if not pending_return_uids.is_empty():
		return true
	var ctx := _ctx()
	for card_uid in ctx.library.pile(CardInstance.RESOLVING):
		var card := ctx.library.get_card(str(card_uid))
		if card != null and card.has_mark("EN_RETURN") and not card.return_used_run:
			return true
	return false


func is_resource_failure() -> bool:
	if enemy_hp <= 0 or phase == "VICTORY":
		return false
	if has_pending_damage() or has_pending_return() or combo_pending:
		return false
	return _ctx().library.is_fighting_exhausted()


func fail_if_resources_exhausted() -> bool:
	if phase == "VICTORY" or phase == "DEFEAT":
		return false
	if not is_resource_failure():
		return false
	phase = "DECK_EXHAUSTED"
	_release_detained()
	return true


func _release_detained() -> void:
	var ctx := _ctx()
	if ctx == null:
		return
	for card in ctx.library.all_cards():
		if card.zone == CardInstance.STOLEN:
			ctx.library.move(card, CardInstance.RUN_DECK, "BATTLE_END", battle_uid, ctx)


func _close_delayed_draw() -> void:
	if delayed_draw_done:
		return
	if player_elapsed_s >= _delayed_draw_at():
		_perform_delayed_draw()
	else:
		cancel_delayed_draw()


func _perform_delayed_draw() -> void:
	if delayed_draw_done:
		return
	delayed_draw_done = true
	if enemy_hp <= 0 or phase != "PLAYER_ACTIVE":
		return
	var count := int(_ctx().catalog.rule().get("delayed_draw_count", 1))
	if count <= 0:
		return
	_ctx().draw_service.draw_count(count, battle_uid, "DELAYED", battle_uid)


func _reset_player_clock() -> void:
	player_elapsed_s = 0.0
	delayed_draw_done = false
	turn_remaining = float(_ctx().catalog.rule().turn_seconds)


func _delayed_draw_at() -> float:
	return float(_ctx().catalog.rule().get("delayed_draw_at", 7.5))


func _ctx() -> RunContext:
	return _run.get_ref() as RunContext
