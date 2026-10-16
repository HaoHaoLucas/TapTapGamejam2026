class_name MapService
extends RefCounted
## Fixed 5-room floors: three choices on rooms 1–4, boss in room 5.


static func make_offers(run: RunState) -> Dictionary:
	if run.phase in ["DEAD", "ENDED", "ERROR"]:
		return {"ok": false, "error": "本局已经停止"}
	if str(run.current_room.get("status", "")) == "ENTERED":
		return {"ok": true, "offers": run.current_offers, "entered": true}
	if not run.current_offers.is_empty() and str(run.current_room.get("status", "")) != "ENTERED":
		return {"ok": true, "offers": run.current_offers}
	var rule := GameData.floor_rule()
	var next_slot := run.slot_index + 1
	if next_slot > int(rule.get("rooms_per_floor", 5)):
		return {"ok": true, "offers": [], "floor_done": true}
	var remain := _remaining_normal(run) + _remaining_event(run)
	if next_slot == int(rule.get("boss_slot", 5)):
		if _remaining_normal(run) != 0 or _remaining_event(run) != 0:
			run.phase = "ERROR"
			run.last_error = "进入 Boss 前配额没有用完"
			push_error(run.last_error)
			return {"ok": false, "error": run.last_error}
	elif remain != 5 - next_slot:
		run.phase = "ERROR"
		run.last_error = "房间配额与序号不一致"
		push_error(run.last_error)
		return {"ok": false, "error": run.last_error}
	var cache := _condition_cache(run)
	if next_slot == int(rule.get("boss_slot", 5)):
		return _enter_generated(run, next_slot, "BOSS", cache)
	if _is_choice_slot(rule, next_slot):
		return _offer_choice(run, next_slot, cache)
	return _enter_first(run, next_slot, cache)


static func choose_room(run: RunState, offer_uid: String) -> Dictionary:
	if str(run.current_room.get("status", "")) == "ENTERED":
		if _chosen_uid(run) == offer_uid:
			return {"ok": true, "room_uid": str(run.current_room.get("room_uid", "")), "duplicate": true}
		return {"ok": false, "error": "已经进入房间"}
	var offer := {}
	for item in run.current_offers:
		if str(item.get("offer_uid", "")) == offer_uid:
			offer = item
			break
	if offer.is_empty():
		return {"ok": false, "error": "没有这个房间"}
	if bool(offer.get("chosen", false)):
		return {"ok": true, "room_uid": str(run.current_room.get("room_uid", "")), "duplicate": true}
	return _enter_offer(run, offer)


static func _is_choice_slot(rule: Dictionary, slot: int) -> bool:
	for item in rule.get("choice_slots", []):
		if int(item) == slot:
			return true
	return false


static func _enter_first(run: RunState, next_slot: int, cache: Dictionary) -> Dictionary:
	var types: Array = []
	var weights: Array = []
	if _remaining_normal(run) > 0:
		types.append("NORMAL")
		weights.append(_remaining_normal(run))
	if _remaining_event(run) > 0:
		types.append("EVENT")
		weights.append(_remaining_event(run))
	if types.is_empty():
		return _fail(run, "没有剩余房间配额")
	var kind: String = types[run.roll_weighted("MAP", weights)]
	return _enter_generated(run, next_slot, kind, cache)


static func _offer_choice(run: RunState, next_slot: int, cache: Dictionary) -> Dictionary:
	var legal: Array = []
	if _remaining_normal(run) > 0:
		legal.append("NORMAL")
	if _remaining_event(run) > 0:
		legal.append("EVENT")
	if legal.is_empty():
		return _fail(run, "没有剩余房间配额")
	var types: Array = []
	if legal.size() == 2:
		var third: String = ["NORMAL", "EVENT"][run.roll_weighted("MAP", [_remaining_normal(run), _remaining_event(run)])]
		types = ["NORMAL", "EVENT", third]
	else:
		types = [legal[0], legal[0], legal[0]]
	run.shuffle("MAP", types)
	var offers: Array = []
	var batch: Array = []
	for kind in types:
		var picked := _materialize(run, str(kind), batch, cache)
		if not picked.get("ok", false):
			return picked
		batch.append(str(picked.get("content_id", "")))
		offers.append(picked.offer)
	run.pending_slot = next_slot
	run.current_offers = offers
	run.current_room = {}
	run.phase = "MAP"
	run.log_event({
		"kind": "offers",
		"depth": run.depth,
		"slot_index": next_slot,
		"remaining_normal": _remaining_normal(run),
		"remaining_event": _remaining_event(run),
		"content_ids": batch,
	})
	return {"ok": true, "offers": offers}


static func _enter_generated(run: RunState, next_slot: int, kind: String, cache: Dictionary) -> Dictionary:
	var picked := _materialize(run, kind, [], cache)
	if not picked.get("ok", false):
		return picked
	run.pending_slot = next_slot
	run.current_offers = []
	return _enter_offer(run, picked.offer)


static func _enter_offer(run: RunState, offer: Dictionary) -> Dictionary:
	offer.chosen = true
	var room := {
		"room_uid": run.uid("R"),
		"room_id": str(offer.get("room_id", "")),
		"content_id": str(offer.get("content_id", "")),
		"room_kind": str(offer.get("room_kind", "")),
		"display_key": str(offer.get("display_key", "")),
		"scene_key": str(offer.get("scene_key", "")),
		"status": "ENTERED",
		"fallback_reason": str(offer.get("fallback_reason", "")),
		"offer_uid": str(offer.get("offer_uid", "")),
	}
	run.slot_index = run.pending_slot
	if room.room_kind == "NORMAL":
		run.normal_used += 1
	elif room.room_kind == "EVENT":
		run.event_used += 1
	if not run.visited_content_ids.has(room.content_id):
		run.visited_content_ids.append(room.content_id)
	run.current_room = room
	run.phase = "ROOM"
	run.log_event({
		"kind": "enter",
		"depth": run.depth,
		"slot_index": run.slot_index,
		"remaining_normal": _remaining_normal(run),
		"remaining_event": _remaining_event(run),
		"content_id": room.content_id,
		"offer_uid": room.offer_uid,
		"fallback_reason": room.fallback_reason,
		"room_uid": room.room_uid,
	})
	return {"ok": true, "room_uid": room.room_uid, "room": room}


static func _materialize(run: RunState, kind: String, batch: Array, cache: Dictionary) -> Dictionary:
	var picked: Dictionary = _pick_room(run, kind, batch, true, true, cache)
	var reason := ""
	if picked.is_empty():
		picked = _pick_room(run, kind, batch, false, true, cache)
		reason = "RELAX_FLOOR_DEDUP"
	if picked.is_empty():
		picked = _pick_room(run, kind, batch, false, false, cache)
		reason = "RELAX_BATCH_DEDUP"
	if picked.is_empty():
		if kind == "EVENT":
			picked = GameData.room("RM_CACHE")
			reason = "EVENT_POOL_EMPTY"
		elif kind == "BOSS":
			push_error("Boss 池为空，拒绝开局")
			return _fail(run, "Boss 池为空")
		else:
			push_error("普通战斗池为空")
			return _fail(run, "普通战斗池为空")
	if picked.is_empty():
		return _fail(run, "没有可用房间")
	return {
		"ok": true,
		"content_id": str(picked.get("content_id", "")),
		"offer": _make_offer(run, picked, reason),
	}


static func _pick_room(run: RunState, kind: String, batch: Array, use_floor: bool, use_batch: bool, cache: Dictionary) -> Dictionary:
	var pool_id := _pool_for(kind)
	var rooms: Array = []
	var weights: Array = []
	for entry in GameData.rows("room_pool_entry"):
		if str(entry.get("pool_id", "")) != pool_id:
			continue
		if not _depth_ok(entry, run.depth):
			continue
		var room := GameData.room(str(entry.get("room_id", "")))
		if str(room.get("room_kind", "")) != kind:
			continue
		if not _hard_ok(room, cache):
			continue
		var content_id := str(room.get("content_id", ""))
		if use_floor and run.visited_content_ids.has(content_id):
			continue
		if use_batch and batch.has(content_id):
			continue
		rooms.append(room)
		weights.append(int(entry.get("weight", 0)))
	if rooms.is_empty():
		return {}
	return rooms[run.roll_weighted("MAP", weights)]


static func _hard_ok(room: Dictionary, cache: Dictionary) -> bool:
	if str(room.get("content_kind", "")) != "EVENT":
		return true
	var event := GameData.event(str(room.get("content_id", "")))
	return bool(cache.get(str(event.get("condition_id", "")), false))


static func _condition_cache(run: RunState) -> Dictionary:
	var cache := {}
	for event in GameData.rows("event_def"):
		var condition_id := str(event.get("condition_id", ""))
		if not cache.has(condition_id):
			cache[condition_id] = TowerDeck.condition_met(run, condition_id)
	return cache


static func _make_offer(run: RunState, room: Dictionary, reason: String) -> Dictionary:
	return {
		"offer_uid": run.uid("O"),
		"room_id": str(room.get("room_id", "")),
		"content_id": str(room.get("content_id", "")),
		"room_kind": str(room.get("room_kind", "")),
		"display_key": str(room.get("display_key", "")),
		"scene_key": str(room.get("scene_key", "")),
		"chosen": false,
		"fallback_reason": reason,
	}


static func _pool_for(kind: String) -> String:
	match kind:
		"NORMAL":
			return str(GameData.floor_rule().get("normal_pool_id", "POOL_NORMAL"))
		"EVENT":
			return str(GameData.floor_rule().get("event_pool_id", "POOL_EVENT"))
		_:
			return str(GameData.floor_rule().get("boss_pool_id", "POOL_BOSS"))


static func _remaining_normal(run: RunState) -> int:
	return int(GameData.floor_rule().get("normal_quota", 2)) - run.normal_used


static func _remaining_event(run: RunState) -> int:
	return int(GameData.floor_rule().get("event_quota", 2)) - run.event_used


static func _depth_ok(entry: Dictionary, depth: int) -> bool:
	var min_depth := int(entry.get("min_depth", 1))
	var max_depth := int(entry.get("max_depth", 0))
	return depth >= min_depth and (max_depth == 0 or depth <= max_depth)


static func _chosen_uid(run: RunState) -> String:
	for offer in run.current_offers:
		if bool(offer.get("chosen", false)):
			return str(offer.get("offer_uid", ""))
	return str(run.current_room.get("offer_uid", ""))


static func _fail(run: RunState, message: String) -> Dictionary:
	run.phase = "ERROR"
	run.last_error = message
	return {"ok": false, "error": message}
