class_name BattleCard
extends RefCounted
## One physical mixed-deck card. IDs match the HTML demo: n0…n10, p0/p1, m0/m1.

var id: String = ""
var type: String = ""
var value: int = 0
var elem: String = ""
var op: String = ""

func is_number() -> bool:
	return type == "number"


func is_operator() -> bool:
	return type == "operator"


func to_dict() -> Dictionary:
	if type == "operator":
		return {"id": id, "type": type, "op": op}
	return {"id": id, "type": type, "value": value, "elem": elem}
