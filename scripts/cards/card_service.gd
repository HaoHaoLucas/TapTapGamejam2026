class_name CardService
extends RefCounted
## Doc 02 card operations for RunContext. The tower uses TowerDeck instead.

var _ctx: RunContext
var _done: Dictionary = {}


func _init(ctx: RunContext) -> void:
	_ctx = ctx


static func printed_value_of(card) -> int:
	return TowerDeck.printed_value_of(card)


func can_apply_mark(card_uid: String, enh_id: String) -> Dictionary:
	var card := _ctx.library.get_card(card_uid)
	if card == null:
		return _no("ZONE")
	var enh := _ctx.catalog.enh(enh_id)
	if enh.is_empty():
		return _no("UNKNOWN_MARK")
	var def := _ctx.catalog.card(card.def_id)
	var kinds: Array = enh.get("valid_card_kinds", [])
	if not kinds.has(str(def.get("card_kind", ""))):
		return _no("KIND")
	if enh_id == "EN_ALCHEMY":
		return {"ok": true, "reason_code": ""}
	if _family_present(card, str(enh.get("family_id", ""))):
		return _no("FAMILY")
	if card.enhancement_ids.size() + int(enh.get("slot_cost", 1)) > int(_ctx.catalog.rule().get("max_marks_per_card", 2)):
		return _no("SLOTS")
	return {"ok": true, "reason_code": ""}


func apply_mark(card_uid: String, enh_id: String, txn_id: String, source: String = "") -> Dictionary:
	if _done.has(txn_id):
		return (_done[txn_id] as Dictionary).duplicate(true)
	var check := can_apply_mark(card_uid, enh_id)
	if not check.ok:
		return check
	var card := _ctx.library.get_card(card_uid)
	var result := {"ok": true, "reason_code": "", "card_uid": card_uid, "enh_id": enh_id}
	if enh_id == "EN_ALCHEMY":
		var score := _value_score(card)
		var params: Dictionary = _ctx.catalog.enh(enh_id).get("params", {})
		card.collection_snapshot = {
			"collection_id": str(params.get("collection_id", "COL_SAMPLE")),
			"source_def_id": card.def_id,
			"value_score": score,
			"enhancement_ids": card.enhancement_ids.duplicate(),
		}
		_ctx.library.move(card, CardInstance.COLLECTION, "ALCHEMY", txn_id, _ctx)
		result.value_score = score
	else:
		card.enhancement_ids.append(enh_id)
		card.refresh_opening_priority()
		_ctx.mark_applied.emit(card_uid, enh_id, source, txn_id)
	_done[txn_id] = result.duplicate(true)
	return result


func burn(card_uid: String, action_uid: String) -> Dictionary:
	if _done.has(action_uid):
		return (_done[action_uid] as Dictionary).duplicate(true)
	var card := _ctx.library.get_card(card_uid)
	if card == null:
		return _no("ZONE")
	if _ctx.battle == null or _ctx.battle.phase != "PLAYER_ACTIVE":
		return _no("PHASE")
	var def := _ctx.catalog.card(card.def_id)
	var printed := card.printed_value(_ctx.catalog)
	var magnitude: int = 0 if str(def.get("card_kind", "")) == "OP" else absi(printed)
	var heal_per := int(_ctx.catalog.rule().get("burn_heal_per_abs", 10))
	var missing := int(_ctx.battle.player_max_hp) - int(_ctx.battle.player_hp)
	var heal := mini(missing, magnitude * heal_per)
	_ctx.battle.player_hp += heal
	var smolder := card.has_mark("EN_SMOLDER") and not card.smolder_used_run
	var result := {
		"ok": true,
		"reason_code": "",
		"heal_delta": heal,
		"removed": not smolder,
		"smolder_flag": smolder,
	}
	if smolder:
		card.smolder_used_run = true
	else:
		_ctx.library.move(card, CardInstance.REMOVED, "BURN", action_uid, _ctx)
		_ctx.card_removed.emit(card_uid, "BURN")
	_done[action_uid] = result.duplicate(true)
	return result


func sacrifice(card_uid: String, txn_id: String) -> Dictionary:
	if _done.has(txn_id):
		return (_done[txn_id] as Dictionary).duplicate(true)
	var card := _ctx.library.get_card(card_uid)
	if card == null or card.zone == CardInstance.REMOVED or card.zone == CardInstance.COLLECTION:
		return _no("ZONE")
	_ctx.library.move(card, CardInstance.REMOVED, "SACRIFICE", txn_id, _ctx)
	_ctx.card_removed.emit(card_uid, "SACRIFICE")
	var result := {"ok": true, "reason_code": "", "heal_delta": 0, "card_uid": card_uid}
	_done[txn_id] = result.duplicate(true)
	return result


func copy_card(card_uid: String, txn_id: String) -> Dictionary:
	if _done.has(txn_id):
		return (_done[txn_id] as Dictionary).duplicate(true)
	var source := _ctx.library.get_card(card_uid)
	if source == null or source.zone == CardInstance.REMOVED or source.zone == CardInstance.COLLECTION:
		return _no("ZONE")
	var created := _ctx.library.create_instance(source.def_id, source.enhancement_ids, _ctx.depth, source.card_uid)
	if created == null:
		return _no("COPY")
	created.return_used_run = source.return_used_run
	created.smolder_used_run = source.smolder_used_run
	created.locked_until_turn = -1
	created.drawn_turn = -1
	created.refresh_opening_priority()
	var result := {"ok": true, "reason_code": "", "card_uid": created.card_uid}
	_done[txn_id] = result.duplicate(true)
	return result


func transform_card(card_uid: String, def_id: String, txn_id: String) -> Dictionary:
	if _done.has(txn_id):
		return (_done[txn_id] as Dictionary).duplicate(true)
	var card := _ctx.library.get_card(card_uid)
	if card == null:
		return _no("ZONE")
	if def_id == card.def_id:
		return _no("SAME_DEF")
	var current := _ctx.catalog.card(card.def_id)
	var nxt := _ctx.catalog.card(def_id)
	if nxt.is_empty() or str(nxt.get("card_kind", "")) != str(current.get("card_kind", "")):
		return _no("KIND")
	if str(nxt.get("card_kind", "")) == "OP" and str(nxt.get("operator_code", "")) not in ["ADD", "MUL"]:
		return _no("KIND")
	card.def_id = def_id
	card.refresh_opening_priority()
	var result := {"ok": true, "reason_code": "", "card_uid": card_uid, "def_id": def_id}
	_done[txn_id] = result.duplicate(true)
	return result


func _value_score(card: CardInstance) -> int:
	var def := _ctx.catalog.card(card.def_id)
	var abs_part: int = 0 if str(def.get("card_kind", "")) == "OP" else absi(card.printed_value(_ctx.catalog))
	var score := 10 + 5 * abs_part + 15 * card.enhancement_ids.size()
	if card.has_mark("EN_PRICE"):
		score *= 2
	return score


func _family_present(card: CardInstance, family: String) -> bool:
	for enh_id in card.enhancement_ids:
		if str(_ctx.catalog.enh(str(enh_id)).get("family_id", "")) == family:
			return true
	return false


func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason_code": reason}
