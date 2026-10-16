class_name CardLibrary
extends RefCounted
## Instances for one run. Shared config rows are never written.

var catalog: ConfigCatalog
var run_id: String = ""
var turn_index: int = 0
var _seq: int = 0
var _cards: Dictionary = {}
var _order: Array[String] = []
var _piles: Dictionary = {}


func _init(p_catalog: ConfigCatalog, p_run_id: String) -> void:
	catalog = p_catalog
	run_id = p_run_id
	for zone in CardInstance.ZONES:
		_piles[zone] = []


func create_starter(starter_id: String = "STARTER_JAM") -> Array:
	var created: Array = []
	for entry in catalog.starter_rows(starter_id):
		var count := int(entry.starter_count)
		for _i in count:
			var card := create_instance(str(entry.def_id), [], 1, "")
			if card != null:
				created.append(card)
	return created


func create_instance(def_id: String, enhancement_ids: Array, depth: int, source_uid: String) -> CardInstance:
	if catalog.card(def_id).is_empty():
		push_error("未知卡牌模板 %s" % def_id)
		return null
	if not _marks_valid(def_id, enhancement_ids):
		push_error("印记与 %s 不兼容" % def_id)
		return null
	_seq += 1
	var card := CardInstance.new()
	card.card_uid = "%s_%d" % [run_id, _seq]
	card.def_id = def_id
	card.zone = CardInstance.RUN_DECK
	card.acquired_depth = depth
	card.source_uid = source_uid
	for raw in enhancement_ids:
		card.enhancement_ids.append(str(raw))
	card.refresh_opening_priority()
	_cards[card.card_uid] = card
	_order.append(card.card_uid)
	_piles[CardInstance.RUN_DECK].append(card.card_uid)
	return card


func get_card(card_uid: String) -> CardInstance:
	return _cards.get(card_uid, null)


func all_cards() -> Array:
	var out: Array = []
	for card_uid in _order:
		out.append(_cards[card_uid])
	return out


func card_count() -> int:
	return _cards.size()


func pile(zone: String) -> Array:
	return (_piles.get(zone, []) as Array).duplicate()


func move(card: CardInstance, to_zone: String, reason: String, txn_id: String, bus: RunContext) -> void:
	if card == null or not CardInstance.ZONES.has(to_zone):
		return
	var from := card.zone
	if from == to_zone:
		return
	(_piles[from] as Array).erase(card.card_uid)
	card.zone = to_zone
	(_piles[to_zone] as Array).append(card.card_uid)
	if bus != null:
		bus.card_zone_changed.emit(card.card_uid, from, to_zone, reason, txn_id)


func swap_cards(a: CardInstance, b: CardInstance, reason: String, txn_id: String, bus: RunContext) -> void:
	if a == null or b == null or a == b:
		return
	var a_zone := a.zone
	var b_zone := b.zone
	if a_zone == b_zone or not _piles.has(a_zone) or not _piles.has(b_zone):
		return
	var a_pile: Array = _piles[a_zone]
	var b_pile: Array = _piles[b_zone]
	var a_index := a_pile.find(a.card_uid)
	var b_index := b_pile.find(b.card_uid)
	if a_index < 0 or b_index < 0:
		return
	a_pile[a_index] = b.card_uid
	b_pile[b_index] = a.card_uid
	a.zone = b_zone
	b.zone = a_zone
	if bus != null:
		bus.card_zone_changed.emit(a.card_uid, a_zone, b_zone, reason, txn_id)
		bus.card_zone_changed.emit(b.card_uid, b_zone, a_zone, reason, txn_id)


func normal_hand_count() -> int:
	var count := 0
	for card_uid in _piles[CardInstance.HAND]:
		var card: CardInstance = _cards[card_uid]
		if card.hand_slot_cost(catalog) > 0:
			count += 1
	return count


func is_fighting_exhausted() -> bool:
	var numbers := 0
	var operators := 0
	# STOLEN is withheld and does not count. RUN_DECK is outside the fight.
	for zone in [CardInstance.HAND, CardInstance.DRAW, CardInstance.DISCARD, CardInstance.RESOLVING]:
		for card_uid in _piles[zone]:
			var card: CardInstance = _cards[card_uid]
			var def := catalog.card(card.def_id)
			if str(def.get("card_kind", "")) == "NUM":
				numbers += 1
			elif str(def.get("operator_code", "")) == "ADD" or str(def.get("operator_code", "")) == "MUL":
				operators += 1
	return numbers < 2 or operators < 1


func collect_opening() -> Dictionary:
	var vanguards: Array = []
	var rest: Array = []
	for card_uid in _order:
		var card: CardInstance = _cards[card_uid]
		if card.zone == CardInstance.REMOVED or card.zone == CardInstance.COLLECTION or card.zone == CardInstance.STOLEN:
			continue
		if card.has_mark("EN_VANGUARD"):
			vanguards.append(card)
		else:
			rest.append(card)
	return {"vanguards": vanguards, "rest": rest}


func _marks_valid(def_id: String, marks: Array) -> bool:
	var kind := str(catalog.card(def_id).get("card_kind", ""))
	var max_marks := int(catalog.rule().get("max_marks_per_card", 2))
	if marks.size() > max_marks:
		return false
	var families := {}
	for raw in marks:
		var enh_id := str(raw)
		if enh_id == "EN_ALCHEMY":
			return false
		var entry := catalog.enh(enh_id)
		if entry.is_empty() or not EnhancementRegistry.has_id(enh_id):
			return false
		var kinds: Array = entry.get("valid_card_kinds", [])
		if not kinds.has(kind):
			return false
		var family := str(entry.get("family_id", ""))
		if families.has(family):
			return false
		families[family] = true
	return true
