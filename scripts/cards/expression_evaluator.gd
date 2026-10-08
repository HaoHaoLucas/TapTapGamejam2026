class_name ExpressionEvaluator
extends RefCounted
## × and ÷ bind tighter than + and −. Each level evaluates left to right.
## A trailing operator with no following number is ignored.
## Division keeps an exact fraction. Any executed ÷ 0 makes the result 0.

class Outcome extends RefCounted:
	var result: Rational
	var valid: bool = false
	var divided_by_zero: bool = false
	var complete: bool = false

	func _init() -> void:
		result = Rational.from_int(0)

static func is_valid(cards: Array[CardData]) -> bool:
	for index in range(cards.size()):
		var expected := CardData.Kind.NUMBER if index % 2 == 0 else CardData.Kind.OPERATOR
		if cards[index].kind != expected:
			return false
	return true

static func evaluate(cards: Array[CardData]) -> float:
	return inspect_cards(cards).result.to_float()

static func inspect_cards(cards: Array[CardData]) -> Outcome:
	var outcome := Outcome.new()
	if not is_valid(cards):
		return outcome
	outcome.valid = true
	outcome.complete = true
	if cards.is_empty():
		return outcome
	var numbers: Array[int] = []
	var operators: Array[String] = []
	var limit := cards.size()
	if cards[limit - 1].kind == CardData.Kind.OPERATOR:
		limit -= 1
	for index in range(0, limit, 2):
		numbers.append(cards[index].number)
		if index + 1 < limit:
			operators.append(cards[index + 1].operator)
	return _apply(outcome, numbers, operators)

static func inspect_slots(slots: Array[FormulaSlot]) -> Outcome:
	var outcome := Outcome.new()
	if not FormulaSlot.is_valid_template(slots):
		return outcome
	outcome.valid = true
	var numbers: Array[int] = []
	var operators: Array[String] = []
	for index in range(slots.size()):
		var slot := slots[index]
		if index % 2 == 0:
			if slot.locked:
				numbers.append(slot.number)
			elif slot.card != null:
				numbers.append(int(slot.card.number))
			else:
				return outcome
		else:
			var symbol := ""
			if slot.locked:
				symbol = slot.operator
			elif slot.card != null:
				symbol = slot.card.operator
			if symbol == "":
				return outcome
			operators.append(symbol)
	outcome.complete = true
	return _apply(outcome, numbers, operators)

static func _apply(outcome: Outcome, numbers: Array[int], operators: Array[String]) -> Outcome:
	var reduced := _reduce(numbers, operators)
	outcome.divided_by_zero = reduced["divided_by_zero"]
	outcome.result = reduced["result"]
	return outcome

static func _reduce(numbers: Array[int], operators: Array[String]) -> Dictionary:
	var term := Rational.from_int(numbers[0])
	var terms: Array[Rational] = []
	var additives: Array[String] = []
	for index in range(operators.size()):
		var op := operators[index]
		var rhs := Rational.from_int(numbers[index + 1])
		if op == "×":
			term = term.multiply(rhs)
		elif op == "÷":
			if rhs.is_zero():
				return {"result": Rational.from_int(0), "divided_by_zero": true}
			term = term.divide(rhs)
		elif op == "+" or op == "-":
			terms.append(term)
			additives.append(op)
			term = rhs
		else:
			return {"result": Rational.from_int(0), "divided_by_zero": false}
	terms.append(term)
	var result := terms[0]
	for index in range(additives.size()):
		if additives[index] == "+":
			result = result.add(terms[index + 1])
		else:
			result = result.subtract(terms[index + 1])
	return {"result": result, "divided_by_zero": false}
