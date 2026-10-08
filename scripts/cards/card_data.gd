class_name CardData
extends Resource
## One physical card. Equal values still receive different instance IDs.

enum Kind { NUMBER, OPERATOR, SPECIAL }

static var _next_id: int = 1

var instance_id: int
var kind: Kind
var number: int = 0
var operator: String = ""
var slots: Array[FormulaSlot] = []

func _init() -> void:
	instance_id = _next_id
	_next_id += 1

static func number_card(value: int) -> CardData:
	var card := CardData.new()
	card.kind = Kind.NUMBER
	card.number = value
	return card

static func operator_card(symbol: String) -> CardData:
	assert(symbol in ["+", "-", "×", "÷"], "Supported operators: +, -, ×, ÷")
	var card := CardData.new()
	card.kind = Kind.OPERATOR
	card.operator = symbol
	return card

static func special_card(formula: Array[FormulaSlot]) -> CardData:
	var card := CardData.new()
	card.kind = Kind.SPECIAL
	card.slots = FormulaSlot.clone_all(formula)
	return card

func display_text() -> String:
	if kind == Kind.SPECIAL:
		return "定式"
	return str(number) if kind == Kind.NUMBER else operator
