class_name RunState
extends RefCounted
## Mutable state for one run. Static tables stay in GameData.

const STREAMS: PackedStringArray = ["MAP", "REWARD", "ENHANCE", "COMBAT", "QUEST"]
const ENGINE_VERSION := "4.7.2"
const CONFIG_VERSION := "jam_1.2.0"
const RULESET_ID := "RULE_JAM_10S"

var run_id: String = ""
var run_seed: String = ""
var instance_seq: int = 0
var ruleset_id: String = RULESET_ID
var config_version: String = CONFIG_VERSION
var engine_version: String = ENGINE_VERSION
var depth: int = 1
var slot_index: int = 0
var pending_slot: int = 0
var normal_used: int = 0
var event_used: int = 0
var visited_content_ids: Array = []
var current_room: Dictionary = {}
var current_offers: Array = []
var card_instances: Array = []
var quest_states: Array = []
var reward_sessions: Array = []
var rng_states: Dictionary = {}
var applied_txn_ids: Array = []
var txn_results: Dictionary = {}
var event_views: Dictionary = {}
var hp: int = 100
var max_hp: int = 100
var phase: String = "MAP"
var outcome: String = ""
var normal_plain_streak: int = 0
var logs: Array = []
var last_error: String = ""

var _rng: Dictionary = {}


func init_new(p_seed: String) -> void:
	run_seed = p_seed
	run_id = "RUN%d" % RngStream.derive_seed(p_seed, "RUN")
	instance_seq = 0
	ruleset_id = RULESET_ID
	config_version = GameData.config_version
	engine_version = ENGINE_VERSION
	depth = 1
	slot_index = 0
	pending_slot = 0
	normal_used = 0
	event_used = 0
	visited_content_ids = []
	current_room = {}
	current_offers = []
	card_instances = []
	quest_states = []
	reward_sessions = []
	applied_txn_ids = []
	txn_results = {}
	event_views = {}
	hp = 100
	max_hp = 100
	phase = "MAP"
	outcome = ""
	normal_plain_streak = 0
	logs = []
	last_error = ""
	_rng = {}
	rng_states = {}
	for stream in STREAMS:
		var rng := RngStream.make(RngStream.derive_seed(p_seed, stream))
		_rng[stream] = rng
		_remember(stream)


func next_seq() -> int:
	instance_seq += 1
	return instance_seq


func uid(prefix: String) -> String:
	return "%s_%s%d" % [run_id, prefix, next_seq()]


func find_card(card_uid: String) -> CardInstance:
	for card in card_instances:
		if card.card_uid == card_uid:
			return card
	return null


func find_session(session_uid: String) -> Dictionary:
	for session in reward_sessions:
		if str(session.get("reward_session_uid", "")) == session_uid:
			return session
	return {}


func find_quest(quest_uid: String) -> Dictionary:
	for quest in quest_states:
		if str(quest.get("quest_uid", "")) == quest_uid:
			return quest
	return {}


func randi_range_stream(stream: String, lo: int, hi: int) -> int:
	var rng: RandomNumberGenerator = _rng[stream]
	var value := rng.randi_range(lo, hi)
	_remember(stream)
	return value


func randi_stream(stream: String) -> int:
	var rng: RandomNumberGenerator = _rng[stream]
	var value := rng.randi()
	_remember(stream)
	return value


func randf_stream(stream: String) -> float:
	var rng: RandomNumberGenerator = _rng[stream]
	var value := rng.randf()
	_remember(stream)
	return value


func roll_weighted(stream: String, weights: Array) -> int:
	if RngStream.all_whole(weights):
		var total := 0
		for weight in weights:
			total += int(weight)
		if total <= 0:
			return -1
		var roll := randi_range_stream(stream, 0, total - 1)
		var acc := 0
		for i in weights.size():
			acc += int(weights[i])
			if roll < acc:
				return i
		return weights.size() - 1
	var float_total := 0.0
	for weight in weights:
		float_total += float(weight)
	if float_total <= 0.0:
		return -1
	var float_roll := randf_stream(stream) * float_total
	var float_acc := 0.0
	for i in weights.size():
		float_acc += float(weights[i])
		if float_roll < float_acc:
			return i
	return weights.size() - 1


func shuffle(stream: String, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := randi_range_stream(stream, 0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


func log_event(entry: Dictionary) -> void:
	var row: Dictionary = deep_copy(entry)
	row["run_id"] = run_id
	row["seed"] = run_seed
	logs.append(row)


func capture() -> Dictionary:
	return to_dict()


func rollback(snapshot: Dictionary) -> void:
	var revived := from_dict(snapshot)
	_adopt(revived)


func to_dict() -> Dictionary:
	for stream in STREAMS:
		_remember(stream)
	var cards: Array = []
	for card in card_instances:
		cards.append(card.to_dict())
	return {
		"run_id": run_id,
		"run_seed": run_seed,
		"instance_seq": instance_seq,
		"ruleset_id": ruleset_id,
		"config_version": config_version,
		"engine_version": engine_version,
		"depth": depth,
		"slot_index": slot_index,
		"pending_slot": pending_slot,
		"normal_used": normal_used,
		"event_used": event_used,
		"visited_content_ids": deep_copy(visited_content_ids),
		"current_room": deep_copy(current_room),
		"current_offers": deep_copy(current_offers),
		"card_instances": cards,
		"quest_states": deep_copy(quest_states),
		"reward_sessions": deep_copy(reward_sessions),
		"rng_states": deep_copy(rng_states),
		"applied_txn_ids": deep_copy(applied_txn_ids),
		"txn_results": deep_copy(txn_results),
		"event_views": deep_copy(event_views),
		"hp": hp,
		"max_hp": max_hp,
		"phase": phase,
		"outcome": outcome,
		"normal_plain_streak": normal_plain_streak,
		"logs": deep_copy(logs),
		"last_error": last_error,
	}


static func from_dict(data: Dictionary) -> RunState:
	var run := RunState.new()
	run.run_id = str(data.get("run_id", ""))
	run.run_seed = str(data.get("run_seed", ""))
	run.instance_seq = int(data.get("instance_seq", 0))
	run.ruleset_id = str(data.get("ruleset_id", RULESET_ID))
	run.config_version = str(data.get("config_version", CONFIG_VERSION))
	run.engine_version = str(data.get("engine_version", ENGINE_VERSION))
	run.depth = int(data.get("depth", 1))
	run.slot_index = int(data.get("slot_index", 0))
	run.pending_slot = int(data.get("pending_slot", 0))
	run.normal_used = int(data.get("normal_used", 0))
	run.event_used = int(data.get("event_used", 0))
	run.visited_content_ids = deep_copy(data.get("visited_content_ids", []))
	run.current_room = deep_copy(data.get("current_room", {}))
	run.current_offers = deep_copy(data.get("current_offers", []))
	run.card_instances = []
	for row in data.get("card_instances", []):
		run.card_instances.append(CardInstance.from_dict(row))
	run.quest_states = deep_copy(data.get("quest_states", []))
	run.reward_sessions = deep_copy(data.get("reward_sessions", []))
	run.rng_states = deep_copy(data.get("rng_states", {}))
	run.applied_txn_ids = deep_copy(data.get("applied_txn_ids", []))
	run.txn_results = deep_copy(data.get("txn_results", {}))
	run.event_views = deep_copy(data.get("event_views", {}))
	run.hp = int(data.get("hp", 100))
	run.max_hp = int(data.get("max_hp", 100))
	run.phase = str(data.get("phase", "MAP"))
	run.outcome = str(data.get("outcome", ""))
	run.normal_plain_streak = int(data.get("normal_plain_streak", 0))
	run.logs = deep_copy(data.get("logs", []))
	run.last_error = str(data.get("last_error", ""))
	run._rng = {}
	for stream in STREAMS:
		var entry = run.rng_states.get(stream, {})
		var rng := RandomNumberGenerator.new()
		rng.seed = int(str(entry.get("seed", "0")))
		rng.state = int(str(entry.get("state", "0")))
		run._rng[stream] = rng
	return run


func _adopt(other: RunState) -> void:
	run_id = other.run_id
	run_seed = other.run_seed
	instance_seq = other.instance_seq
	ruleset_id = other.ruleset_id
	config_version = other.config_version
	engine_version = other.engine_version
	depth = other.depth
	slot_index = other.slot_index
	pending_slot = other.pending_slot
	normal_used = other.normal_used
	event_used = other.event_used
	visited_content_ids = other.visited_content_ids
	current_room = other.current_room
	current_offers = other.current_offers
	card_instances = other.card_instances
	quest_states = other.quest_states
	reward_sessions = other.reward_sessions
	rng_states = other.rng_states
	applied_txn_ids = other.applied_txn_ids
	txn_results = other.txn_results
	event_views = other.event_views
	hp = other.hp
	max_hp = other.max_hp
	phase = other.phase
	outcome = other.outcome
	normal_plain_streak = other.normal_plain_streak
	logs = other.logs
	last_error = other.last_error
	_rng = other._rng


func _remember(stream: String) -> void:
	var rng: RandomNumberGenerator = _rng[stream]
	rng_states[stream] = {
		"seed": str(rng.seed),
		"state": str(rng.state),
	}


static func deep_copy(value):
	if value is Array:
		var copied: Array = []
		for item in value:
			copied.append(deep_copy(item))
		return copied
	if value is Dictionary:
		var copied := {}
		for key in value.keys():
			copied[key] = deep_copy(value[key])
		return copied
	return value
