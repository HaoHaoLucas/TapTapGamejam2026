class_name RngStream
extends RefCounted
## Five gameplay streams. Seed is the first 8 hex chars of SHA-256(run_seed + stream name).


static func derive_seed(run_seed: String, stream_name: String) -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((run_seed + stream_name).to_utf8_buffer())
	var hex := ctx.finish().hex_encode()
	return int(hex.substr(0, 8).hex_to_int())


static func make(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func pick_index(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0
	for weight in weights:
		total += int(weight)
	if total <= 0:
		return -1
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for i in weights.size():
		acc += int(weights[i])
		if roll < acc:
			return i
	return weights.size() - 1
