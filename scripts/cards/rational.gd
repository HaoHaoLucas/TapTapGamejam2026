class_name Rational
extends RefCounted
## Exact rational value. Operators reduce the fraction before any float conversion.

var numerator: int = 0
var denominator: int = 1

static func from_int(value: int) -> Rational:
	return from_parts(value, 1)

static func from_parts(part_numerator: int, part_denominator: int) -> Rational:
	var rational := Rational.new()
	rational.numerator = part_numerator
	rational.denominator = part_denominator
	rational._reduce()
	return rational

func is_zero() -> bool:
	return numerator == 0

func is_int(value: int) -> bool:
	return denominator == 1 and numerator == value

func equals(part_numerator: int, part_denominator: int) -> bool:
	var other := from_parts(part_numerator, part_denominator)
	return numerator == other.numerator and denominator == other.denominator

func add(other: Rational) -> Rational:
	return from_parts(
		numerator * other.denominator + other.numerator * denominator,
		denominator * other.denominator
	)

func subtract(other: Rational) -> Rational:
	return add(from_parts(-other.numerator, other.denominator))

func multiply(other: Rational) -> Rational:
	var left_numerator := numerator
	var left_denominator := denominator
	var right_numerator := other.numerator
	var right_denominator := other.denominator
	var shared_left := _gcd(absi(left_numerator), right_denominator)
	var shared_right := _gcd(absi(right_numerator), left_denominator)
	left_numerator = _quot(left_numerator, shared_left)
	right_denominator = _quot(right_denominator, shared_left)
	right_numerator = _quot(right_numerator, shared_right)
	left_denominator = _quot(left_denominator, shared_right)
	return from_parts(left_numerator * right_numerator, left_denominator * right_denominator)

func divide(other: Rational) -> Rational:
	return multiply(from_parts(other.denominator, other.numerator))

func to_float() -> float:
	return float(numerator) / float(denominator)

func display_text() -> String:
	if denominator == 1:
		return str(numerator)
	var negative := numerator < 0
	var whole := _quot(absi(numerator), denominator)
	var remainder := absi(numerator) % denominator
	var digits := ""
	var seen: Dictionary = {}
	var repeating := false
	while remainder != 0 and digits.length() < 6:
		if seen.has(remainder):
			repeating = true
			break
		seen[remainder] = true
		remainder *= 10
		digits += str(_quot(remainder, denominator))
		remainder %= denominator
	if repeating:
		while digits.length() < 3 and remainder != 0:
			remainder *= 10
			digits += str(_quot(remainder, denominator))
			remainder %= denominator
	var text := "%d.%s" % [whole, digits]
	if repeating:
		text += "…"
	if negative:
		text = "-" + text
	return text

func _reduce() -> void:
	if denominator < 0:
		numerator = -numerator
		denominator = -denominator
	if numerator == 0:
		denominator = 1
		return
	var divisor := _gcd(absi(numerator), denominator)
	numerator = _quot(numerator, divisor)
	denominator = _quot(denominator, divisor)

static func _quot(value: int, divisor: int) -> int:
	if divisor == 0:
		return 0
	var negative := (value < 0) != (divisor < 0)
	var left := absi(value)
	var right := absi(divisor)
	if left < right:
		return 0
	var quotient := 0
	var place := 1
	var factor := right
	while factor <= left >> 1:
		factor <<= 1
		place <<= 1
	while place > 0:
		if left >= factor:
			left -= factor
			quotient += place
		factor >>= 1
		place >>= 1
	return -quotient if negative else quotient

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var next := a % b
		a = b
		b = next
	return a
