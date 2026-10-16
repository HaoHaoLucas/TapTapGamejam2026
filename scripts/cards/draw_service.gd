class_name DrawService
extends RefCounted
## Fixed-count draws, one magnet partner, freeze-on-draw, and vanguard opening.
## After a draw, swap with DRAW so the hand has one operator and two numbers when it can.

const MIN_OPERATORS := 1
const MIN_NUMBERS := 2

var _run: WeakRef
var _opening_vanguards: Dictionary = {}


func _init(ctx: RunContext) -> void:
	_run = weakref(ctx)


func draw_count(count: int, battle_uid: String, draw_reason: String, txn_id: String = "") -> Dictionary:
	var ctx := _ctx()
	var txn := txn_id if txn_id != "" else battle_uid
	var events: Array = []
	var drawn := {}
	var limit := int(ctx.catalog.rule().get("hand_limit", 0))
	var wanted := maxi(0, count)
	var base_drawn := 0
	var normal_uids: Array = []
	while base_drawn < wanted:
		if limit > 0 and ctx.library.pile(CardInstance.HAND).size() >= limit:
			break
		var card_uid := _pull(true, drawn, txn)
		if card_uid == "":
			break
		var card := ctx.library.get_card(card_uid)
		_enter(card, "NORMAL_DRAW", txn, drawn, events)
		normal_uids.append(card.card_uid)
		base_drawn += 1
		if card.has_mark("EN_MAGNET"):
			_attach_magnet(drawn, txn, events, limit)
	if base_drawn > 0:
		_repair_hand_composition(txn, normal_uids)
	return {
		"ok": true,
		"battle_uid": battle_uid,
		"draw_reason": draw_reason,
		"events": events,
	}


func opening_deal(battle_uid: String) -> Dictionary:
	var ctx := _ctx()
	_opening_vanguards = {}
	var split: Dictionary = ctx.library.collect_opening()
	var vanguards: Array = split.vanguards
	vanguards.sort_custom(func(a, b) -> bool:
		return str(a.card_uid) < str(b.card_uid)
	)
	var rest_uids: Array = []
	for card in split.rest:
		rest_uids.append(card.card_uid)
	var shuffled: Array = ctx.rng_of("COMBAT").shuffle(rest_uids)
	for card_uid in shuffled:
		ctx.library.move(ctx.library.get_card(str(card_uid)), CardInstance.DRAW, "BATTLE_SHUFFLE", battle_uid, ctx)
	var opening: Array = []
	var drawn := {}
	for card in vanguards:
		_enter(card, "VANGUARD", battle_uid, drawn, opening)
		_opening_vanguards[card.card_uid] = true
	var start_draw := int(ctx.catalog.rule().get("turn_start_draw", 5))
	var filled := draw_count(maxi(0, start_draw - vanguards.size()), battle_uid, "BATTLE_START", battle_uid)
	if (filled.events as Array).is_empty():
		_repair_hand_composition(battle_uid, [])
	return {"opening": opening, "draws": filled.events}


func _pull(allow_reshuffle: bool, drawn: Dictionary, txn_id: String) -> String:
	var ctx := _ctx()
	if ctx.library.pile(CardInstance.DRAW).is_empty() and allow_reshuffle:
		_reshuffle_discard(drawn, txn_id)
	for card_uid in ctx.library.pile(CardInstance.DRAW):
		if not drawn.has(card_uid):
			return str(card_uid)
	return ""


func _reshuffle_discard(drawn: Dictionary, txn_id: String) -> void:
	var ctx := _ctx()
	var pending: Array = []
	for card_uid in ctx.library.pile(CardInstance.DISCARD):
		if not drawn.has(card_uid):
			pending.append(card_uid)
	if pending.is_empty():
		return
	var shuffled: Array = ctx.rng_of("COMBAT").shuffle(pending)
	for card_uid in shuffled:
		ctx.library.move(ctx.library.get_card(str(card_uid)), CardInstance.DRAW, "SHUFFLE", txn_id, ctx)


func _attach_magnet(drawn: Dictionary, txn_id: String, events: Array, hand_limit: int) -> void:
	var ctx := _ctx()
	if hand_limit > 0 and ctx.library.pile(CardInstance.HAND).size() >= hand_limit:
		return
	var partner_uid := _pick_magnet(drawn)
	if partner_uid == "":
		return
	_enter(ctx.library.get_card(partner_uid), "MAGNET", txn_id, drawn, events)


func _pick_magnet(drawn: Dictionary) -> String:
	var ctx := _ctx()
	var candidates: Array = []
	for card_uid in ctx.library.pile(CardInstance.DRAW):
		if drawn.has(card_uid):
			continue
		var card := ctx.library.get_card(str(card_uid))
		if card != null and card.has_mark("EN_MAGNET"):
			candidates.append(str(card_uid))
	if candidates.is_empty():
		return ""
	var index := ctx.rng_of("COMBAT").randi_range(0, candidates.size() - 1)
	return str(candidates[index])


func _enter(card: CardInstance, reason: String, txn_id: String, drawn: Dictionary, events: Array) -> void:
	var ctx := _ctx()
	ctx.library.move(card, CardInstance.HAND, reason, txn_id, ctx)
	drawn[card.card_uid] = true
	card.drawn_turn = ctx.library.turn_index
	if card.has_mark("EN_FROZEN"):
		var locks := int(ctx.catalog.enh("EN_FROZEN").params.lock_turns)
		card.locked_until_turn = ctx.library.turn_index + locks
	events.append({"card_uid": card.card_uid, "draw_reason": reason})


## One operator and two numbers, using cards still in DRAW. Discard is not reshuffled for this.
## The swap is not a draw: it does not spend the base count, chain magnet, or freeze.
func _repair_hand_composition(txn_id: String, normal_uids: Array) -> void:
	var ctx := _ctx()
	var guard := 0
	var limit := maxi(1, ctx.library.pile(CardInstance.HAND).size())
	while guard < limit:
		guard += 1
		var counts := _hand_roles()
		var operators := int(counts.operators)
		var numbers := int(counts.numbers)
		if operators >= MIN_OPERATORS and numbers >= MIN_NUMBERS:
			return
		var want := "operator" if operators < MIN_OPERATORS else "number"
		var donor := _find_draw_donor(want)
		if donor == null:
			return
		var spare := "number" if want == "operator" else "operator"
		var spare_count := numbers if spare == "number" else operators
		var spare_floor := MIN_NUMBERS if spare == "number" else MIN_OPERATORS
		if spare_count <= spare_floor:
			return
		var evict := _pick_spare(spare, normal_uids)
		if evict == null:
			return
		ctx.library.swap_cards(evict, donor, "COMPOSITION", txn_id, ctx)


func _find_draw_donor(want: String) -> CardInstance:
	var ctx := _ctx()
	for card_uid in ctx.library.pile(CardInstance.DRAW):
		var card := ctx.library.get_card(str(card_uid))
		if card != null and _role(card) == want:
			return card
	return null


func _pick_spare(spare: String, normal_uids: Array) -> CardInstance:
	for i in range(normal_uids.size() - 1, -1, -1):
		var drawn := _ctx().library.get_card(str(normal_uids[i]))
		if _is_spare(drawn, spare):
			return drawn
	var hand: Array = _ctx().library.pile(CardInstance.HAND)
	var vanguard: CardInstance = null
	for i in range(hand.size() - 1, -1, -1):
		var card := _ctx().library.get_card(str(hand[i]))
		if not _is_spare(card, spare):
			continue
		if _opening_vanguards.has(card.card_uid):
			if vanguard == null:
				vanguard = card
			continue
		return card
	return vanguard


func _is_spare(card: CardInstance, spare: String) -> bool:
	return card != null and card.zone == CardInstance.HAND and _role(card) == spare


func _hand_roles() -> Dictionary:
	var operators := 0
	var numbers := 0
	var ctx := _ctx()
	for card_uid in ctx.library.pile(CardInstance.HAND):
		match _role(ctx.library.get_card(str(card_uid))):
			"operator":
				operators += 1
			"number":
				numbers += 1
	return {"operators": operators, "numbers": numbers}


func _role(card: CardInstance) -> String:
	if card == null:
		return ""
	var def := _ctx().catalog.card(card.def_id)
	if str(def.get("card_kind", "")) == "NUM":
		return "number"
	if str(def.get("operator_code", "")) == "ADD" or str(def.get("operator_code", "")) == "MUL":
		return "operator"
	return ""


func _ctx() -> RunContext:
	return _run.get_ref() as RunContext
