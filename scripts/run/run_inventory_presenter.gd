class_name RunInventoryPresenter
extends RefCounted
## Read-only snapshots of the cards a run is carrying.
## Filtering and sorting copy these dictionaries; they never move a card or draw a random number.

const RUN_RECORD_NOTE := "本局记录，尚未永久保存"

const KIND_ALL := "ALL"
const KIND_NUM := "NUM"
const KIND_OP := "OP"
const MARKS_ALL := "ALL"
const MARKS_PRESENT := "MARKED"
const MARKS_PLAIN := "PLAIN"
const SORT_ACQUIRED := "ACQUIRED"
const SORT_VALUE := "VALUE"


static func present(run: RunState, library: CardLibrary = null) -> Dictionary:
	if run == null:
		return _empty()
	var turn_index := 0 if library == null else library.turn_index
	var known := {}
	var entries: Array = []
	for index in run.card_instances.size():
		var card: CardInstance = run.card_instances[index]
		if card == null:
			continue
		var source := card
		if library != null and card.card_uid != "":
			var live := library.get_card(card.card_uid)
			if live != null:
				source = live
		known[card.card_uid] = true
		entries.append({"card": source, "acquired_index": index})
	if library != null:
		var extra := run.card_instances.size()
		for card in library.all_cards():
			if card == null or known.has(card.card_uid):
				continue
			entries.append({"card": card, "acquired_index": extra})
			extra += 1
	var cards: Array = []
	var collections: Array = []
	for entry in entries:
		var card: CardInstance = entry.card
		if card == null or card.zone == CardInstance.REMOVED:
			continue
		if card.zone == CardInstance.COLLECTION:
			collections.append(_collection_snapshot(card, library))
			continue
		cards.append(_card_snapshot(card, int(entry.acquired_index), library, turn_index))
	return {
		"cards": cards,
		"collections": collections,
		"counts": _counts(cards),
	}


static func filter_sort(cards: Array, kind: String, marks: String, sort_mode: String) -> Array:
	var filtered: Array = []
	for card in cards:
		if typeof(card) != TYPE_DICTIONARY:
			continue
		var card_kind := str(card.get("card_kind", ""))
		if kind == KIND_NUM and card_kind != "NUM":
			continue
		if kind == KIND_OP and card_kind != "OP":
			continue
		var enhanced := not (card.get("enhancement_ids", []) as Array).is_empty()
		if marks == MARKS_PRESENT and not enhanced:
			continue
		if marks == MARKS_PLAIN and enhanced:
			continue
		filtered.append(card)
	filtered.sort_custom(func(a, b): return _before(a, b, sort_mode))
	return filtered


static func zone_label(zone: String) -> String:
	match zone:
		"HAND":
			return "手牌"
		"DRAW":
			return "抽牌堆"
		"DISCARD":
			return "弃牌堆"
		"RESOLVING":
			return "结算中"
		"STOLEN":
			return "被偷走"
		"RUN_DECK":
			return "本局牌库"
		_:
			return zone


static func _before(a, b, sort_mode: String) -> bool:
	var left: Dictionary = a
	var right: Dictionary = b
	if sort_mode == SORT_VALUE:
		var left_value := int(left.get("printed_value", 0))
		var right_value := int(right.get("printed_value", 0))
		if left_value != right_value:
			return left_value < right_value
	var left_index := int(left.get("acquired_index", 0))
	var right_index := int(right.get("acquired_index", 0))
	if left_index != right_index:
		return left_index < right_index
	return str(left.get("card_uid", "")) < str(right.get("card_uid", ""))


static func _counts(cards: Array) -> Dictionary:
	var num := 0
	var op := 0
	var enhanced := 0
	for card in cards:
		if str(card.get("card_kind", "")) == "OP":
			op += 1
		else:
			num += 1
		if not (card.get("enhancement_ids", []) as Array).is_empty():
			enhanced += 1
	return {
		"total": cards.size(),
		"num": num,
		"op": op,
		"enhanced": enhanced,
		"plain": cards.size() - enhanced,
	}


static func _card_snapshot(card: CardInstance, acquired_index: int, library: CardLibrary, turn_index: int) -> Dictionary:
	var def := _def(library, card.def_id)
	var kind := str(def.get("card_kind", ""))
	var ids: Array = []
	var names: Array = []
	var lines: Array = []
	var name_lines := PackedStringArray()
	var tip_lines := PackedStringArray()
	for enh_id in card.enhancement_ids:
		var enh_key := str(enh_id)
		ids.append(enh_key)
		var enh := _enh(library, enh_key)
		var enh_name := str(enh.get("name", enh_key))
		var line := TowerDeck.mark_line_from(enh, enh_key)
		names.append(enh_name)
		lines.append(line)
		name_lines.append(enh_name)
		tip_lines.append(line)
	var printed := _printed_value(card, library)
	var value_text := str(def.get("name", card.def_id))
	if kind == "NUM":
		value_text = _format_number(printed)
	var ghost := ids.has("EN_GHOST")
	var frozen := card.is_frozen(turn_index)
	var flags := PackedStringArray()
	if ghost:
		flags.append("幽灵")
	if frozen:
		flags.append("冻结")
	var face := {
		"presentation": "card", "def_id": card.def_id, "card_kind": kind,
		"printed_value": printed, "operator_code": str(def.get("operator_code", "NONE")),
		"enhancement_ids": ids.duplicate(),
		"card_uid": card.card_uid,
		"value_text": value_text,
		"mark_text": "\n".join(name_lines),
		"state_text": " ".join(flags),
		"tooltip": "\n".join(tip_lines),
		"ghost": ghost,
		"frozen": frozen,
	}
	return {
		"card_uid": card.card_uid,
		"def_id": card.def_id,
		"name": str(def.get("name", card.def_id)),
		"card_kind": kind,
		"printed_value": printed,
		"value_text": value_text,
		"enhancement_ids": ids,
		"mark_names": names,
		"mark_lines": lines,
		"zone": card.zone,
		"zone_label": zone_label(card.zone),
		"acquired_depth": card.acquired_depth,
		"acquired_index": acquired_index,
		"return_used": card.return_used_run,
		"smolder_used": card.smolder_used_run,
		"has_return": ids.has("EN_RETURN"),
		"has_smolder": ids.has("EN_SMOLDER"),
		"ghost": ghost,
		"frozen": frozen,
		"face": face.duplicate(true),
	}


static func _collection_snapshot(card: CardInstance, library: CardLibrary) -> Dictionary:
	var snap: Dictionary = card.collection_snapshot
	var collection_id := str(snap.get("collection_id", ""))
	var row := _collection(library, collection_id)
	var source_def := str(snap.get("source_def_id", card.def_id))
	var source := _def(library, source_def)
	var name := str(row.get("name", ""))
	if name == "":
		name = collection_id if collection_id != "" else "收藏品"
	var source_name := str(source.get("name", source_def))
	return {
		"card_uid": card.card_uid,
		"collection_id": collection_id,
		"name": name,
		"source_def_id": source_def,
		"source_name": source_name,
		"value_score": int(snap.get("value_score", 0)),
		"note": RUN_RECORD_NOTE,
	}


static func _printed_value(card: CardInstance, library: CardLibrary) -> int:
	if library != null and library.catalog != null:
		return card.printed_value(library.catalog)
	var value := int(_def(null, card.def_id).get("base_value", 0))
	for enh_id in card.enhancement_ids:
		var enh := _enh(null, str(enh_id))
		if str(enh.get("family_id", "")) == "VALUE" or str(enh_id) == "EN_FRAGILE":
			value += int(enh.get("params", {}).get("add", 0))
	return value


static func _def(library: CardLibrary, def_id: String) -> Dictionary:
	if library != null and library.catalog != null:
		return library.catalog.card(def_id)
	return GameData.card(def_id)


static func _enh(library: CardLibrary, enh_id: String) -> Dictionary:
	if library != null and library.catalog != null:
		return library.catalog.enh(enh_id)
	return GameData.enh(enh_id)


static func _collection(library: CardLibrary, collection_id: String) -> Dictionary:
	if library != null and library.catalog != null:
		return library.catalog.collection(collection_id)
	return GameData.row("collection_def", collection_id)


static func _format_number(value: int) -> String:
	if value < 0:
		return "−%d" % absi(value)
	return str(value)


static func _empty() -> Dictionary:
	return {
		"cards": [],
		"collections": [],
		"counts": {"total": 0, "num": 0, "op": 0, "enhanced": 0, "plain": 0},
	}
