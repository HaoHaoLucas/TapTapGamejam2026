class_name CardInstance
extends RefCounted
## One physical card. Zone constants are shared with the card-rules library.

const RUN_DECK := "RUN_DECK"
const DRAW := "DRAW"
const HAND := "HAND"
const RESOLVING := "RESOLVING"
const DISCARD := "DISCARD"
const STOLEN := "STOLEN"
const COLLECTION := "COLLECTION"
const REMOVED := "REMOVED"
const ZONES: Array[String] = [RUN_DECK, DRAW, HAND, RESOLVING, DISCARD, STOLEN, COLLECTION, REMOVED]
const FIGHTING_ZONES: Array[String] = [DRAW, HAND, RESOLVING, DISCARD, STOLEN]

var card_uid: String = ""
var def_id: String = ""
var enhancement_ids: Array = []
var zone: String = RUN_DECK
var acquired_depth: int = 1
var source_uid: String = ""
var return_used_run: bool = false
var smolder_used_run: bool = false
var drawn_turn: int = -1
var locked_until_turn: int = -1
var opening_priority: int = 0
var collection_snapshot: Dictionary = {}


func has_mark(enh_id: String) -> bool:
	return enhancement_ids.has(enh_id)


func refresh_opening_priority() -> void:
	opening_priority = 100 if has_mark("EN_VANGUARD") else 0


func is_frozen(turn_index: int) -> bool:
	return locked_until_turn > turn_index


func hand_slot_cost(_catalog) -> int:
	return 0 if has_mark("EN_GHOST") else 1


func printed_value(catalog) -> int:
	var value := int(catalog.card(def_id).get("base_value", 0))
	for enh_id in enhancement_ids:
		var enh: Dictionary = catalog.enh(str(enh_id))
		if str(enh.get("family_id", "")) == "VALUE" or str(enh_id) == "EN_FRAGILE":
			value += int(enh.get("params", {}).get("add", 0))
	return value


func collection_value() -> int:
	return int(collection_snapshot.get("value_score", 0))


func to_dict() -> Dictionary:
	return {
		"card_uid": card_uid,
		"def_id": def_id,
		"enhancement_ids": enhancement_ids.duplicate(),
		"zone": zone,
		"acquired_depth": acquired_depth,
		"source_uid": source_uid,
		"return_used_run": return_used_run,
		"smolder_used_run": smolder_used_run,
		"drawn_turn": drawn_turn,
		"locked_until_turn": locked_until_turn,
		"opening_priority": opening_priority,
		"collection_snapshot": _copy_value(collection_snapshot),
	}


static func from_dict(data: Dictionary) -> CardInstance:
	var card := CardInstance.new()
	card.card_uid = str(data.get("card_uid", ""))
	card.def_id = str(data.get("def_id", ""))
	card.enhancement_ids = []
	for enh_id in data.get("enhancement_ids", []):
		card.enhancement_ids.append(str(enh_id))
	card.zone = str(data.get("zone", "RUN_DECK"))
	card.acquired_depth = int(data.get("acquired_depth", 1))
	card.source_uid = str(data.get("source_uid", ""))
	card.return_used_run = bool(data.get("return_used_run", false))
	card.smolder_used_run = bool(data.get("smolder_used_run", false))
	card.drawn_turn = int(data.get("drawn_turn", -1))
	card.locked_until_turn = int(data.get("locked_until_turn", -1))
	card.opening_priority = int(data.get("opening_priority", 0))
	var snap = data.get("collection_snapshot", {})
	card.collection_snapshot = _copy_value(snap) if snap is Dictionary else {}
	return card


static func _copy_value(value):
	if value is Array:
		var copied := []
		for item in value:
			copied.append(_copy_value(item))
		return copied
	if value is Dictionary:
		var copied := {}
		for key in value.keys():
			copied[key] = _copy_value(value[key])
		return copied
	return value
