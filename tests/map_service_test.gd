extends SceneTree

var _failures: int = 0
var _paths: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	if not GameData.ensure_loaded():
		for err in GameData.errors:
			push_error(str(err))
		quit(1)
		return
	for seed in ["map-seed-a", "map-seed-b", "tower-seed"]:
		_paths = 0
		_test_paths(seed)
		_check(_paths == 81, "%s should have 81 legal room paths, got %s" % [seed, _paths])
	_test_event_quota("quota-seed")
	_test_roundtrip("round-seed")
	_test_rng_roundtrip()
	if _failures == 0:
		print("PASS: map quotas, room 4 normals, offer roundtrip")
	quit(1 if _failures else 0)


func _test_paths(seed: String) -> void:
	var created := RunService.new_run(seed)
	_check(created.get("ok", false), "New run failed for %s: %s" % [seed, created.get("error", "")])
	if not created.get("ok", false):
		return
	_walk(created.run, [])


func _walk(run: RunState, kinds: Array) -> void:
	if run.phase == "ERROR":
		_check(false, "Map entered an error: %s" % run.last_error)
		return
	if str(run.current_room.get("status", "")) == "ENTERED":
		var kind := str(run.current_room.get("room_kind", ""))
		kinds.append(kind)
		_check(run.normal_used <= 2 and run.event_used <= 2, "Quota exceeded")
		if int(run.slot_index) == 5:
			_check(kind == "BOSS", "Room 5 must be the boss")
			_check(run.normal_used == 2 and run.event_used == 2, "Boss requires both quotas to be spent")
			_check(_count(kinds, "NORMAL") == 2 and _count(kinds, "EVENT") == 2 and kinds.size() == 5, "Floor must be 2 fights, 2 events, 1 boss")
			_paths += 1
			return
		var finished := _finish_victory(run)
		_check(finished.get("ok", false), "Could not finish room: %s" % finished.get("error", ""))
		if finished.get("ok", false):
			_walk(run, kinds)
		return
	_check(run.current_offers.size() == 3, "Choice rooms offer exactly 3 candidates")
	if run.current_offers.size() != 3:
		return
	for offer in run.current_offers:
		var branch := RunState.from_dict(run.to_dict())
		var chosen := MapService.choose_room(branch, str(offer.get("offer_uid", "")))
		_check(chosen.get("ok", false), "Could not choose offer")
		if chosen.get("ok", false):
			_walk(branch, kinds.duplicate())


func _test_event_quota(seed: String) -> void:
	var created := RunService.new_run(seed)
	_check(created.get("ok", false), "Quota run failed to start")
	if not created.get("ok", false):
		return
	var run: RunState = created.run
	var guard := 0
	while guard < 12:
		guard += 1
		if str(run.current_room.get("status", "")) == "ENTERED":
			var finished := _finish_victory(run)
			_check(finished.get("ok", false), "Quota path could not finish a room")
			continue
		if int(run.pending_slot) == 4 and run.event_used >= 2:
			_check(run.current_offers.size() == 3, "Room 4 still offers three candidates")
			for offer in run.current_offers:
				_check(str(offer.get("room_kind", "")) == "NORMAL", "Room 4 must be all combat after events are spent")
			return
		var pick: Dictionary = {}
		for offer in run.current_offers:
			if str(offer.get("room_kind", "")) == "EVENT" and run.event_used < 2:
				pick = offer
				break
		if pick.is_empty() and not run.current_offers.is_empty():
			pick = run.current_offers[0]
		_check(not pick.is_empty(), "Missing a room offer while draining events")
		if pick.is_empty():
			return
		_check(MapService.choose_room(run, str(pick.get("offer_uid", ""))).get("ok", false), "Could not enter the preferred room")
	_check(false, "Did not reach room 4")


func _test_roundtrip(seed: String) -> void:
	var created := RunService.new_run(seed)
	var run: RunState = created.run
	_check(str(run.current_room.get("status", "")) != "ENTERED", "A new day waits on the room choice")
	_check(run.current_offers.size() == 3, "The first room is a three-way choice")
	var before: Array = []
	var contents: Array = []
	for offer in run.current_offers:
		before.append(str(offer.get("offer_uid", "")))
		contents.append(str(offer.get("content_id", "")))
	_check(before.size() == 3, "Roundtrip needs three offers")
	var restored := RunState.from_dict(run.to_dict())
	var after: Array = []
	for offer in restored.current_offers:
		after.append(str(offer.get("offer_uid", "")))
	_check(after == before, "Offer uids must survive a dictionary roundtrip")
	var again := MapService.make_offers(restored)
	var third: Array = []
	for offer in again.get("offers", []):
		third.append(str(offer.get("offer_uid", "")))
	_check(third == before, "Existing offers must be returned unchanged")
	var twin := RunService.new_run(seed)
	_check(twin.get("ok", false), "Twin run failed")
	if not twin.get("ok", false):
		return
	var twin_contents: Array = []
	for offer in twin.run.current_offers:
		twin_contents.append(str(offer.get("content_id", "")))
	_check(twin_contents == contents, "The same seed must rebuild the same hidden rooms")


func _test_rng_roundtrip() -> void:
	_check(RngStream.derive_seed("abc", "MAP") == RngStream.derive_seed("abc", "MAP"), "Derived seeds must be stable")
	_check(RngStream.derive_seed("abc", "MAP") != RngStream.derive_seed("abc", "REWARD"), "Streams must not share a seed")
	var run := RunState.new()
	run.init_new("abc")
	run.randi_stream("MAP")
	var snapshot := run.to_dict()
	var restored := RunState.from_dict(snapshot)
	_check(run.randi_stream("MAP") == restored.randi_stream("MAP"), "Restored RNG state must continue the same stream")
	_check(str(snapshot.rng_states.MAP.seed).is_valid_int() and str(snapshot.rng_states.MAP.state).is_valid_int(), "RNG seed and state are decimal strings")


func _finish_victory(run: RunState) -> Dictionary:
	var finished := RunService.finish_room(run, "victory")
	if not finished.get("ok", false) or run.phase != "REWARD":
		return finished
	var room_uid := str(run.current_room.get("room_uid", ""))
	for session in run.reward_sessions:
		if str(session.get("source_uid", "")) != room_uid:
			continue
		if str(session.get("status", "")) != "OPEN":
			continue
		RewardService.skip_session(run, str(session.get("reward_session_uid", "")), run.uid("T"))
	return RunService.continue_after_rewards(run)


func _count(items: Array, kind: String) -> int:
	var total := 0
	for item in items:
		if str(item) == kind:
			total += 1
	return total
