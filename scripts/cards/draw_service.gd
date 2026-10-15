class_name DrawService
extends RefCounted
## Hand refill, magnet, ghost weight, freeze-on-draw, and vanguard opening.

var _run: WeakRef


func _init(ctx: RunContext) -> void:
	_run = weakref(ctx)


func refill(battle_uid: String, draw_reason: String, txn_id: String = "") -> Dictionary:
	var ctx := _ctx()
	var txn := txn_id if txn_id != "" else battle_uid
	var events: Array = []
	var drawn := {}
	var target := int(ctx.catalog.rule().hand_target)
	var guard := 0
	var limit := ctx.library.card_count() + 2
	while ctx.library.normal_hand_count() < target and guard < limit:
		guard += 1
		var card_uid := _pull(true, drawn, txn)
		if card_uid == "":
			break
		var card := ctx.library.get_card(card_uid)
		_enter(card, "NORMAL_DRAW", txn, drawn, events)
		if card.has_mark("EN_MAGNET"):
			var extras := int(ctx.catalog.enh("EN_MAGNET").params.extra_draw)
			for _extra in extras:
				var partner_uid := _pick_magnet(drawn)
				if partner_uid == "":
					break
				_enter(ctx.library.get_card(partner_uid), "MAGNET", txn, drawn, events)
	return {
		"ok": true,
		"battle_uid": battle_uid,
		"draw_reason": draw_reason,
		"events": events,
	}


func opening_deal(battle_uid: String) -> Dictionary:
	var ctx := _ctx()
	var split: Dictionary = ctx.library.collect_opening()
	var vanguards: Array = split.vanguards
	vanguards.sort_custom(func(a, b) -> bool:
		if int(a.opening_priority) != int(b.opening_priority):
			return int(a.opening_priority) > int(b.opening_priority)
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
	var filled := refill(battle_uid, "BATTLE_START", battle_uid)
	return {"opening": opening, "refill": filled.events}


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


func _ctx() -> RunContext:
	return _run.get_ref() as RunContext
