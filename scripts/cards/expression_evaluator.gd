class_name ExpressionEvaluator
extends RefCounted
## Evaluates a number/operator alternating sequence from left to right.
## A trailing operator is pending and does not affect the result.

static func is_valid(cards: Array[CardData]) -> bool:
	for index in range(cards.size()):
		var expected := CardData.Kind.NUMBER if index % 2 == 0 else CardData.Kind.OPERATOR
		if cards[index].kind != expected:
			return false
	return true

static func evaluate(cards: Array[CardData]) -> int:
	if cards.is_empty() or not is_valid(cards):
		return 0
	var result := cards[0].number
	for index in range(1, cards.size() - 1, 2):
		var operand := cards[index + 1].number
		match cards[index].operator:
			"+": result += operand
			"-": result -= operand
			"×": result *= operand
	return result
