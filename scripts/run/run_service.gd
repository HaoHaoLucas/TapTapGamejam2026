class_name RunService
extends RefCounted
## Owns one run: new game, room resolution, and the reward pause after victory.


static func new_run(run_seed: String) -> Dictionary:
	if not GameData.ensure_loaded():
		return {"ok": false, "error": "配置表无法开局", "errors": GameData.errors.duplicate()}
	if run_seed.is_empty():
		return {"ok": false, "error": "缺少本局种子"}
	var run := RunState.new()
	run.init_new(run_seed)
	TowerDeck.create_starter_deck(run)
	var generated := MapService.make_offers(run)
	if not generated.get("ok", false):
		return generated
	return {"ok": true, "run": run}


static func restore_run(data: Dictionary) -> Dictionary:
	if not GameData.ensure_loaded():
		return {"ok": false, "error": "配置表无法开局", "errors": GameData.errors.duplicate()}
	if str(data.get("config_version", "")) != RunState.CONFIG_VERSION or str(data.get("engine_version", "")) != RunState.ENGINE_VERSION:
		return {"ok": false, "error": "存档版本不兼容"}
	if str(data.get("ruleset_id", "")) != RunState.RULESET_ID:
		return {"ok": false, "error": "存档规则不兼容"}
	return {"ok": true, "run": RunState.from_dict(data)}


static func finish_room(run: RunState, outcome: String) -> Dictionary:
	var room := run.current_room
	if room.is_empty() or str(room.get("status", "")) != "ENTERED":
		return {"ok": false, "error": "没有进行中的房间"}
	if outcome == "defeat":
		room.status = "RESOLVED"
		run.current_room = room
		RewardService.fail_open_quests(run)
		run.phase = "DEAD"
		run.outcome = "defeat"
		return {"ok": true, "ended": true}
	var rewards: Array = []
	if outcome == "victory" and str(room.get("scene_key", "")) == "battle":
		rewards = RewardService.open_combat_rewards(run, room)
	room.status = "RESOLVED"
	run.current_room = room
	if str(room.get("room_kind", "")) == "BOSS":
		RewardService.mark_pizza_ready(run)
	if _reward_pending(run, str(room.get("room_uid", ""))):
		run.phase = "REWARD"
		return {"ok": true, "rewards": rewards, "reward": true}
	if str(room.get("room_kind", "")) == "BOSS":
		run.phase = "FLOOR_CLEAR"
		return {"ok": true, "rewards": rewards, "floor_clear": true}
	run.current_room = {}
	run.current_offers = []
	var generated := MapService.make_offers(run)
	if not generated.get("ok", false):
		return generated
	return {"ok": true, "rewards": rewards, "next": generated}


static func continue_after_rewards(run: RunState) -> Dictionary:
	if run.phase != "REWARD":
		return {"ok": false, "error": "现在不是领奖"}
	var room := run.current_room
	var room_uid := str(room.get("room_uid", ""))
	if not _rewards_closed(run, room_uid):
		return {"ok": false, "error": "还有奖励没处理"}
	if str(room.get("room_kind", "")) == "BOSS":
		run.phase = "FLOOR_CLEAR"
		return {"ok": true, "floor_clear": true}
	run.current_room = {}
	run.current_offers = []
	run.phase = "MAP"
	var generated := MapService.make_offers(run)
	if not generated.get("ok", false):
		return generated
	return {"ok": true, "next": generated}


static func _reward_pending(run: RunState, room_uid: String) -> bool:
	for session in run.reward_sessions:
		if str(session.get("source_uid", "")) != room_uid:
			continue
		if str(session.get("status", "")) == "OPEN":
			return true
	return false


static func _rewards_closed(run: RunState, room_uid: String) -> bool:
	for session in run.reward_sessions:
		if str(session.get("source_uid", "")) != room_uid:
			continue
		var status := str(session.get("status", ""))
		if status != "COMMITTED" and status != "SKIPPED":
			return false
	return true


static func finish_floor(run: RunState, continue_run: bool) -> Dictionary:
	if run.phase != "FLOOR_CLEAR":
		return {"ok": false, "error": "这一层还没有打完"}
	if not continue_run:
		RewardService.fail_open_quests(run)
		run.phase = "ENDED"
		run.outcome = "retire"
		return {"ok": true, "ended": true}
	run.depth += 1
	run.slot_index = 0
	run.pending_slot = 0
	run.normal_used = 0
	run.event_used = 0
	run.visited_content_ids = []
	run.current_room = {}
	run.current_offers = []
	run.phase = "MAP"
	return MapService.make_offers(run)
