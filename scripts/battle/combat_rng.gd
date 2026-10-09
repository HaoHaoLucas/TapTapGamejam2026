class_name CombatRng
extends RefCounted
## Mulberry32 + Fisher–Yates, matching the HTML v0.3 CombatEngine RNG.

const DEFAULT_SEED := 20261009
const UINT32 := 0xFFFFFFFF
const _INCREMENT := 0x6D2B79F5
const _ELEMENTS: PackedStringArray = ["fire", "ice", "spark"]

var _state: int = 0


func _init(p_seed: int = DEFAULT_SEED) -> void:
	_state = p_seed & UINT32


func next_float() -> float:
	_state = (_state + _INCREMENT) & UINT32
	var t := _state
	t = _imul32(t ^ (t >> 15), t | 1)
	var extra := _imul32(t ^ (t >> 7), t | 61)
	t = (t ^ ((t + extra) & UINT32)) & UINT32
	return float((t ^ (t >> 14)) & UINT32) / 4294967296.0


func shuffle(cards: Array) -> Array:
	var shuffled := cards.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := int(floor(next_float() * float(i + 1)))
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	return shuffled


static func create_deck() -> Array:
	var cards: Array = []
	for value in range(-5, 6):
		var number := BattleCard.new()
		number.id = "n%d" % (value + 5)
		number.type = "number"
		number.value = value
		number.elem = _ELEMENTS[(value + 5) % 3]
		cards.append(number)
	for op in ["+", "×"]:
		for i in range(2):
			var symbol := BattleCard.new()
			symbol.id = ("p" if op == "+" else "m") + str(i)
			symbol.type = "operator"
			symbol.op = op
			cards.append(symbol)
	return cards


static func _imul32(a: int, b: int) -> int:
	a &= UINT32
	b &= UINT32
	var a_low := a & 0xFFFF
	var a_high := a >> 16
	var b_low := b & 0xFFFF
	var b_high := b >> 16
	var low := a_low * b_low
	var cross := a_high * b_low + a_low * b_high
	return (low + ((cross & 0xFFFF) << 16)) & UINT32
