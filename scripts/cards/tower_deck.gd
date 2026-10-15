class_name TowerDeck
extends RefCounted
## Card instances, mark legality, and the conservative two-number one-operator check.


static func create_starter_deck(run: RunState) -> void:
	var specs: Array = []
	for row in GameData.rows("starter_deck"):
		if str(row.get("starter_id", "")) != "STARTER_JAM":
			continue
		for _i in int(row.get("starter_count", 0)):
			specs.append(str(row.get("def_id", "")))
	specs.sort()
	for def_id in specs:
		create_card(run, def_id, [], 1, "")


static func create_card(run: RunState, def_id: String, marks: Array, depth: int, source_uid: String) -> CardInstance:
	var card := CardInstance.new()
	card.card_uid = run.uid("C")
	card.def_id = def_id
	card.enhancement_ids = []
	for enh_id in marks:
		card.enhancement_ids.append(str(enh_id))
	card.zone = "RUN_DECK"
	card.acquired_depth = depth
	card.source_uid = source_uid
	card.return_used_run = false
	card.smolder_used_run = false
	card.drawn_turn = -1
	card.locked_until_turn = -1
	_refresh_priority(card)
	run.card_instances.append(card)
	return card


static func copy_card(run: RunState, source: CardInstance) -> CardInstance:
	var card := CardInstance.new()
	card.card_uid = run.uid("C")
	card.def_id = source.def_id
	card.enhancement_ids = source.enhancement_ids.duplicate()
	card.zone = "RUN_DECK"
	card.acquired_depth = run.depth
	card.source_uid = source.card_uid
	card.return_used_run = source.return_used_run
	card.smolder_used_run = source.smolder_used_run
	card.drawn_turn = -1
	card.locked_until_turn = -1
	_refresh_priority(card)
	run.card_instances.append(card)
	return card


static func deck_cards(run: RunState) -> Array:
	var found: Array = []
	for card in run.card_instances:
		if card.zone == "RUN_DECK":
			found.append(card)
	return found


static func is_deck_valid(run: RunState) -> bool:
	return is_valid_cards(snapshot_deck(run))


static func condition_met(run: RunState, condition_id: String) -> bool:
	match condition_id:
		"CAN_COPY":
			return not deck_cards(run).is_empty()
		"CAN_SACRIFICE":
			return can_sacrifice(run)
		"ALWAYS":
			return true
		"HAS_MARK_TARGET":
			return has_mark_target(run, "EP_SMITH")
		"NO_PIZZA":
			return not has_open_pizza(run)
		"CAN_TRANSFORM":
			return can_transform(run)
		_:
			push_error("未知事件条件 %s" % condition_id)
			return false


static func has_open_pizza(run: RunState) -> bool:
	for quest in run.quest_states:
		if str(quest.get("quest_type", "")) == "PIZZA" and str(quest.get("status", "")) in ["ACTIVE", "READY"]:
			return true
	return false


static func has_mark_target(run: RunState, pool_id: String) -> bool:
	for card in deck_cards(run):
		if not _marks_for_card(run, card, pool_id).is_empty():
			return true
	return false


static func can_sacrifice(run: RunState) -> bool:
	var cards := deck_cards(run)
	for size in [1, 2, 3]:
		if _sacrifice_exists(run, cards, size, 0, []):
			return true
	return false


static func can_transform(run: RunState) -> bool:
	for card in deck_cards(run):
		if not legal_transform_defs(run, card.card_uid).is_empty():
			return true
	return false


static func legal_transform_defs(run: RunState, card_uid: String) -> Array:
	var snaps := snapshot_deck(run)
	var target: Dictionary = {}
	for snap in snaps:
		if str(snap.get("card_uid", "")) == card_uid:
			target = snap
			break
	if target.is_empty():
		return []
	var current := GameData.card(str(target.get("def_id", "")))
	var ids: Array = []
	for row in GameData.rows("card_def"):
		ids.append(str(row.get("def_id", "")))
	ids.sort()
	var result: Array = []
	for def_id in ids:
		if def_id == str(target.get("def_id", "")):
			continue
		var other := GameData.card(def_id)
		if str(other.get("card_kind", "")) != str(current.get("card_kind", "")):
			continue
		if str(other.get("card_kind", "")) == "OP" and str(other.get("operator_code", "")) not in ["ADD", "MUL"]:
			continue
		var trial := _clone_snaps(snaps)
		for snap in trial:
			if str(snap.get("card_uid", "")) != card_uid:
				continue
			snap["def_id"] = def_id
			snap["enhancement_ids"] = compatible_marks(snap.get("enhancement_ids", []), str(other.get("card_kind", "")))
			break
		if is_valid_cards(trial):
			result.append(def_id)
	return result


static func marks_for(run: RunState, card_uid: String, pool_id: String) -> Array:
	var card := run.find_card(card_uid)
	if card == null:
		return []
	return _marks_for_card(run, card, pool_id)


static func targets_for_mark(run: RunState, enh_id: String) -> Array:
	var ids: Array = []
	for card in deck_cards(run):
		if can_apply_mark(run, card.card_uid, enh_id).get("ok", false):
			ids.append(card.card_uid)
	ids.sort()
	return ids


static func can_apply_mark(run: RunState, card_uid: String, enh_id: String) -> Dictionary:
	var card := run.find_card(card_uid)
	if card == null or card.zone != "RUN_DECK":
		return {"ok": false, "reason": "ZONE"}
	return _can_apply_card(run, card, enh_id)


static func apply_mark(run: RunState, card_uid: String, enh_id: String) -> Dictionary:
	var check := can_apply_mark(run, card_uid, enh_id)
	if not check.get("ok", false):
		return check
	var card := run.find_card(card_uid)
	if enh_id == "EN_ALCHEMY":
		var enh := GameData.enh(enh_id)
		card.collection_snapshot = {
			"collection_id": str(enh.get("params", {}).get("collection_id", "COL_SAMPLE")),
			"source_def_id": card.def_id,
			"value_score": value_score(card),
			"enhancement_ids": card.enhancement_ids.duplicate(),
		}
		card.zone = "COLLECTION"
		return {"ok": true, "reason": "", "converted": true}
	card.enhancement_ids.append(enh_id)
	_refresh_priority(card)
	return {"ok": true, "reason": "", "converted": false}


static func value_score(card: CardInstance) -> int:
	var def := GameData.card(card.def_id)
	var abs_part: int = 0 if str(def.get("card_kind", "")) == "OP" else absi(printed_value_of(card))
	var score := 10 + 5 * abs_part + 15 * card.enhancement_ids.size()
	if card.enhancement_ids.has("EN_PRICE"):
		score *= 2
	return score


static func describe_card(card: CardInstance) -> String:
	return describe_parts(card.def_id, card.enhancement_ids, "")


static func mark_line(enh_id: String) -> String:
	return mark_line_from(GameData.enh(str(enh_id)), str(enh_id))


static func mark_line_from(enh: Dictionary, enh_id: String = "") -> String:
	var name := str(enh.get("name", enh_id))
	var text := str(enh.get("text", ""))
	if name == "":
		name = enh_id
	if text == "":
		return name
	return "%s：%s" % [name, text]


static func describe_parts(def_id: String, marks: Array, display_name: String) -> String:
	var def := GameData.card(def_id)
	var face := str(def.get("name", def_id))
	if str(def.get("card_kind", "")) == "NUM":
		face = _format_number(printed_value_of({"def_id": def_id, "enhancement_ids": marks}))
	var lines: Array = []
	if display_name != "":
		lines.append(display_name)
	lines.append(face)
	for enh_id in marks:
		var line := mark_line(str(enh_id))
		if line != "":
			lines.append(line)
	return _join(lines, "\n")


static func snapshot_deck(run: RunState) -> Array:
	var snaps: Array = []
	for card in deck_cards(run):
		snaps.append({
			"card_uid": card.card_uid,
			"def_id": card.def_id,
			"enhancement_ids": card.enhancement_ids.duplicate(),
		})
	return snaps


static func is_valid_cards(cards: Array) -> bool:
	var numbers: Array = []
	var operators: Array = []
	for card in cards:
		var def := GameData.card(_def_of(card))
		if str(def.get("card_kind", "")) == "NUM":
			numbers.append(card)
		elif str(def.get("operator_code", "")) in ["ADD", "MUL"]:
			operators.append(card)
	if numbers.size() < 2 or operators.is_empty():
		return false
	for i in numbers.size():
		for j in range(i + 1, numbers.size()):
			for op_card in operators:
				if _positive(numbers[i], numbers[j], op_card):
					return true
	return false


static func compatible_marks(marks: Array, kind: String) -> Array:
	var kept: Array = []
	var families := {}
	for enh_id in marks:
		var enh := GameData.enh(str(enh_id))
		if enh.is_empty():
			continue
		if not (enh.get("valid_card_kinds", []) as Array).has(kind):
			continue
		var family := str(enh.get("family_id", ""))
		if families.has(family):
			continue
		if kept.size() >= 2 and int(enh.get("slot_cost", 1)) > 0:
			continue
		kept.append(str(enh_id))
		families[family] = true
	return kept


static func printed_value_of(card) -> int:
	var def := GameData.card(_def_of(card))
	var value := int(def.get("base_value", 0))
	for enh_id in _marks_of(card):
		var enh := GameData.enh(str(enh_id))
		if str(enh.get("family_id", "")) == "VALUE" or str(enh_id) == "EN_FRAGILE":
			value += int(enh.get("params", {}).get("add", 0))
	return value


static func operand_value(card, primary: String) -> int:
	var value := printed_value_of(card)
	var marks := _marks_of(card)
	if marks.has("EN_FLAMMABLE"):
		var params: Dictionary = GameData.enh("EN_FLAMMABLE").get("params", {})
		if primary == "MUL":
			value += int(params.get("mul_add", 0))
		elif primary == "ADD":
			value += int(params.get("add_add", 0))
	if marks.has("EN_ECHO"):
		value += value
	return value


static func _positive(a, b, op_card) -> bool:
	var primary := str(GameData.card(_def_of(op_card)).get("operator_code", ""))
	var left := operand_value(a, primary)
	var right := operand_value(b, primary)
	var result: int = left + right if primary == "ADD" else left * right
	if result <= 0:
		return false
	var yinyang := 0
	for card in [a, b, op_card]:
		if _marks_of(card).has("EN_YINYANG"):
			yinyang += 1
	var damage := float(result) * 2.0
	if yinyang >= 2:
		damage *= 2.0
	return damage > 0.0


static func _sacrifice_exists(run: RunState, cards: Array, size: int, start: int, chosen: Array) -> bool:
	if chosen.size() == size:
		return _sacrifice_plan_ok(run, cards, chosen)
	for i in range(start, cards.size()):
		chosen.append(cards[i])
		if _sacrifice_exists(run, cards, size, i + 1, chosen):
			chosen.pop_back()
			return true
		chosen.pop_back()
	return false


static func _sacrifice_plan_ok(run: RunState, cards: Array, chosen: Array) -> bool:
	var sacrificed := {}
	for card in chosen:
		sacrificed[card.card_uid] = true
	var remaining: Array = []
	for card in cards:
		if not sacrificed.has(card.card_uid):
			remaining.append(_snap_instance(card))
	if not is_valid_cards(remaining):
		return false
	var slots := 0
	for card in cards:
		if sacrificed.has(card.card_uid):
			continue
		if not _marks_for_card(run, card, "EP_SAFE").is_empty():
			slots += 1
	return slots >= chosen.size()


static func _marks_for_card(run: RunState, card: CardInstance, pool_id: String) -> Array:
	var found: Array = []
	for entry in GameData.rows("enhancement_pool"):
		if str(entry.get("pool_id", "")) != pool_id or int(entry.get("weight", 0)) <= 0:
			continue
		var family := str(entry.get("family_id", ""))
		for enh_id in _family_enh_ids(family):
			if _can_apply_card(run, card, enh_id).get("ok", false) and not found.has(enh_id):
				found.append(enh_id)
	return found


static func _family_enh_ids(family: String) -> Array:
	var ids: Array = []
	for row in GameData.rows("enhancement_def"):
		if str(row.get("family_id", "")) == family:
			ids.append(str(row.get("enh_id", "")))
	ids.sort()
	return ids


static func _can_apply_card(run: RunState, card: CardInstance, enh_id: String) -> Dictionary:
	var enh := GameData.enh(enh_id)
	if enh.is_empty():
		return {"ok": false, "reason": "UNKNOWN_MARK"}
	var def := GameData.card(card.def_id)
	if not (enh.get("valid_card_kinds", []) as Array).has(str(def.get("card_kind", ""))):
		return {"ok": false, "reason": "KIND"}
	if enh_id == "EN_ALCHEMY":
		var kept: Array = []
		for other in deck_cards(run):
			if other.card_uid != card.card_uid:
				kept.append(_snap_instance(other))
		if not is_valid_cards(kept):
			return {"ok": false, "reason": "DECK"}
		return {"ok": true, "reason": ""}
	if _has_family(card.enhancement_ids, str(enh.get("family_id", ""))):
		return {"ok": false, "reason": "FAMILY"}
	if card.enhancement_ids.size() + int(enh.get("slot_cost", 1)) > 2:
		return {"ok": false, "reason": "SLOTS"}
	return {"ok": true, "reason": ""}


static func _has_family(marks: Array, family: String) -> bool:
	for enh_id in marks:
		if str(GameData.enh(str(enh_id)).get("family_id", "")) == family:
			return true
	return false


static func _refresh_priority(card: CardInstance) -> void:
	card.opening_priority = 100 if card.enhancement_ids.has("EN_VANGUARD") else 0


static func _snap_instance(card: CardInstance) -> Dictionary:
	return {
		"card_uid": card.card_uid,
		"def_id": card.def_id,
		"enhancement_ids": card.enhancement_ids.duplicate(),
	}


static func _clone_snaps(snaps: Array) -> Array:
	var copied: Array = []
	for snap in snaps:
		copied.append({
			"card_uid": str(snap.get("card_uid", "")),
			"def_id": str(snap.get("def_id", "")),
			"enhancement_ids": (snap.get("enhancement_ids", []) as Array).duplicate(),
		})
	return copied


static func _def_of(card) -> String:
	if card is CardInstance:
		return card.def_id
	return str(card.get("def_id", ""))


static func _marks_of(card) -> Array:
	if card is CardInstance:
		return card.enhancement_ids
	return card.get("enhancement_ids", [])


static func _format_number(value: int) -> String:
	return "−%s" % absi(value) if value < 0 else str(value)


static func _join(parts: Array, sep: String) -> String:
	var packed := PackedStringArray()
	for part in parts:
		packed.append(str(part))
	return sep.join(packed)
