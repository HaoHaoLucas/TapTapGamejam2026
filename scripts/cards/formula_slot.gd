class_name FormulaSlot
extends RefCounted
## One cell in a formula template. Apply copies these so fills cannot mutate the blueprint.

enum Kind { NUMBER, OPERATOR }

var kind: Kind = Kind.NUMBER
var locked: bool = false
var number: int = 0
var operator: String = ""
var card = null

static func open_number() -> FormulaSlot:
	var slot := FormulaSlot.new()
	slot.kind = Kind.NUMBER
	return slot

static func open_operator() -> FormulaSlot:
	var slot := FormulaSlot.new()
	slot.kind = Kind.OPERATOR
	return slot

static func locked_number(value: int) -> FormulaSlot:
	var slot := FormulaSlot.new()
	slot.kind = Kind.NUMBER
	slot.locked = true
	slot.number = value
	return slot

static func locked_operator(symbol: String) -> FormulaSlot:
	assert(symbol in ["+", "-", "×", "÷"], "Supported operators: +, -, ×, ÷")
	var slot := FormulaSlot.new()
	slot.kind = Kind.OPERATOR
	slot.locked = true
	slot.operator = symbol
	return slot

static func is_valid_template(slots: Array[FormulaSlot]) -> bool:
	if slots.is_empty() or slots.size() % 2 == 0:
		return false
	for index in range(slots.size()):
		var slot := slots[index]
		if slot == null:
			return false
		var number_slot := index % 2 == 0
		if number_slot and slot.kind != Kind.NUMBER:
			return false
		if not number_slot and slot.kind != Kind.OPERATOR:
			return false
		if slot.locked and slot.kind == Kind.OPERATOR and not slot.operator in ["+", "-", "×", "÷"]:
			return false
	return true

static func clone_all(slots: Array[FormulaSlot]) -> Array[FormulaSlot]:
	var copy: Array[FormulaSlot] = []
	for slot in slots:
		copy.append(slot.clone())
	return copy

func clone() -> FormulaSlot:
	var copy := FormulaSlot.new()
	copy.kind = kind
	copy.locked = locked
	copy.number = number
	copy.operator = operator
	return copy

func display_text() -> String:
	if not locked and card == null:
		return "□"
	if card != null:
		return card.display_text()
	return str(number) if kind == Kind.NUMBER else operator
