class_name CardRng
extends RefCounted
## One named run stream. Seed is the first 8 hex chars of SHA-256(str(run_seed)+stream).

var stream_name: String = ""
var seed_value: int = 0
var _rng := RandomNumberGenerator.new()


func _init(run_seed, p_stream_name: String) -> void:
	stream_name = p_stream_name
	seed_value = derive_seed(run_seed, p_stream_name)
	_rng.seed = seed_value


static func derive_seed(run_seed, p_stream_name: String) -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((str(run_seed) + p_stream_name).to_utf8_buffer())
	var hex := ctx.finish().hex_encode()
	return hex.substr(0, 8).hex_to_int()


func randf() -> float:
	return _rng.randf()


func randi_range(low: int, high: int) -> int:
	return _rng.randi_range(low, high)


func state() -> int:
	return _rng.state


func snapshot() -> Dictionary:
	return {"seed": str(seed_value), "state": str(_rng.state)}


func shuffle(items: Array) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
