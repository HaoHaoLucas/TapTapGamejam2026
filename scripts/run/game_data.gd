class_name GameData
extends RefCounted
## Loads jam_1.2.0 JSON tables and refuses to start when keys or enums are wrong.

const CONFIG_VERSION := "jam_1.2.0"
const HANDLERS: PackedStringArray = [
	"COPY_CARD", "SACRIFICE_MARK", "SPECIAL_OFFER", "MARK_OFFER",
	"ACCEPT_PIZZA", "TRANSFORM_CARD", "BASIC_CACHE",
]
const CONDITIONS: PackedStringArray = [
	"CAN_COPY", "CAN_SACRIFICE", "ALWAYS", "HAS_MARK_TARGET", "NO_PIZZA", "CAN_TRANSFORM",
]
const INPUT_MODES: PackedStringArray = ["CARD_ONE", "CARD_MULTI", "OFFER_ONE", "ACCEPT_OR_SKIP", "NONE"]
const LEGACY_NOS: Array = [1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 16]

static var loaded := false
static var ok := false
static var errors: Array = []
static var config_version := CONFIG_VERSION
static var tables: Dictionary = {}
static var index: Dictionary = {}


static func ensure_loaded() -> bool:
	if loaded:
		return ok
	loaded = true
	ok = false
	errors = []
	tables = {}
	index = {}
	_load_table("res://data/run/floor_rule.json", "floor_rule")
	_load_table("res://data/run/floor_config.json", "floor_config")
	_load_table("res://data/run/monster_config.json", "monster_config")
	_load_table("res://data/run/room_def.json", "room_def")
	_load_table("res://data/run/room_pool_entry.json", "room_pool_entry")
	_load_table("res://data/run/event_def.json", "event_def")
	_load_table("res://data/cards/card_def.json", "card_def")
	_load_table("res://data/cards/starter_deck.json", "starter_deck")
	_load_table("res://data/cards/enhancement_def.json", "enhancement_def")
	_load_table("res://data/cards/collection_def.json", "collection_def")
	_load_table("res://data/reward/reward_plan.json", "reward_plan")
	_load_table("res://data/reward/reward_bundle.json", "reward_bundle")
	_load_table("res://data/reward/quality_curve.json", "quality_curve")
	_load_table("res://data/reward/card_base_pool.json", "card_base_pool")
	_load_table("res://data/reward/enhancement_pool.json", "enhancement_pool")
	_load_table("res://data/reward/variant_profile.json", "variant_profile")
	_load_table("res://data/reward/special_card.json", "special_card")
	if errors.is_empty():
		_index_all()
		_validate()
	ok = errors.is_empty()
	if not ok:
		for err in errors:
			push_error(str(err))
	return ok


static func rows(table: String) -> Array:
	return tables.get(table, [])


static func row(table: String, id) -> Dictionary:
	var bucket: Dictionary = index.get(table, {})
	var found = bucket.get(str(id), null)
	return found if found is Dictionary else {}


static func floor_rule() -> Dictionary:
	return row("floor_rule", "FL_STANDARD")


static func floor_config(floor: int) -> Dictionary:
	return row("floor_config", floor)


static func monster(monster_id: String) -> Dictionary:
	return row("monster_config", monster_id)


static func monster_for_encounter(encounter_id: String) -> Dictionary:
	var bucket: Dictionary = index.get("encounter_monster", {})
	var found = bucket.get(str(encounter_id), null)
	return found if found is Dictionary else {}


static func mark_pool_rows(pool_id: String, depth: int) -> Array:
	var found: Array = []
	for item in rows("enhancement_pool"):
		if str(item.get("pool_id", "")) != pool_id:
			continue
		if float(item.get("weight", 0)) <= 0.0:
			continue
		var min_depth := int(item.get("min_depth", 1))
		var max_depth := int(item.get("max_depth", 0))
		if depth >= min_depth and (max_depth == 0 or depth <= max_depth):
			found.append(item)
	return found


static func room(room_id: String) -> Dictionary:
	return row("room_def", room_id)


static func event(event_id: String) -> Dictionary:
	return row("event_def", event_id)


static func card(def_id: String) -> Dictionary:
	return row("card_def", def_id)


static func enh(enh_id: String) -> Dictionary:
	return row("enhancement_def", enh_id)


static func reward(reward_id: String) -> Dictionary:
	return row("reward_plan", reward_id)


static func card_pool(pool_id: String) -> Dictionary:
	return row("card_base_pool", pool_id)


static func _load_table(path: String, expected: String) -> void:
	if not FileAccess.file_exists(path):
		errors.append("缺少配置表 %s" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("配置表为空 %s" % path)
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("配置表不是对象 %s" % path)
		return
	if int(parsed.get("schema_version", -1)) != 1:
		errors.append("%s schema_version 必须为 1" % expected)
	if str(parsed.get("config_version", "")) != CONFIG_VERSION:
		errors.append("%s config_version 必须为 %s" % [expected, CONFIG_VERSION])
	if str(parsed.get("table", "")) != expected:
		errors.append("%s 表名不匹配" % path)
	var table_rows = parsed.get("rows", null)
	if typeof(table_rows) != TYPE_ARRAY or table_rows.is_empty():
		errors.append("%s 缺少 rows" % expected)
		return
	for item in table_rows:
		if typeof(item) != TYPE_DICTIONARY:
			errors.append("%s 存在非对象行" % expected)
			return
	tables[expected] = table_rows


static func _index_all() -> void:
	_index("floor_rule", "rule_id")
	_index("monster_config", "monster_id")
	_index("room_def", "room_id")
	_index("room_pool_entry", "entry_id")
	_index("event_def", "event_id")
	_index("card_def", "def_id")
	_index("enhancement_def", "enh_id")
	_index("collection_def", "collection_id")
	_index("reward_plan", "reward_id")
	_index("reward_bundle", "bundle_id")
	_index("card_base_pool", "pool_id")
	_index("enhancement_pool", "entry_id")
	_index("variant_profile", "entry_id")
	_index("special_card", "special_id")
	var starter := {}
	for item in rows("starter_deck"):
		var key := "%s|%s" % [item.get("starter_id", ""), item.get("def_id", "")]
		if starter.has(key):
			errors.append("starter_deck 主键重复 %s" % key)
		starter[key] = item
	index["starter_deck"] = starter
	var depths := {}
	for item in rows("quality_curve"):
		var key := str(int(item.get("depth", -1)))
		if depths.has(key):
			errors.append("quality_curve 深度重复 %s" % key)
		depths[key] = item
	index["quality_curve"] = depths
	var floors := {}
	for item in rows("floor_config"):
		var key := str(int(item.get("floor", -1)))
		if floors.has(key):
			errors.append("floor_config 层数重复 %s" % key)
		floors[key] = item
	index["floor_config"] = floors
	var encounters := {}
	for item in rows("monster_config"):
		var key := str(item.get("encounter_id", ""))
		if key.is_empty():
			errors.append("怪物缺少 encounter_id %s" % item.get("monster_id", ""))
			continue
		if encounters.has(key):
			errors.append("遭遇重复映射 %s" % key)
		encounters[key] = item
	index["encounter_monster"] = encounters


static func _index(table: String, pk: String) -> void:
	var bucket := {}
	for item in rows(table):
		var key := str(item.get(pk, ""))
		if key.is_empty():
			errors.append("%s 缺少主键 %s" % [table, pk])
			continue
		if bucket.has(key):
			errors.append("%s 主键重复 %s" % [table, key])
		bucket[key] = item
	index[table] = bucket


static func _validate() -> void:
	_validate_floor()
	_validate_floors()
	_validate_monsters()
	_validate_rooms()
	_validate_events()
	_validate_cards()
	_validate_enhancements()
	_validate_rewards()
	_validate_pools_cover_depth()


static func _validate_floor() -> void:
	var rule := floor_rule()
	if rule.is_empty():
		errors.append("缺少 FL_STANDARD")
		return
	_expect_int(rule, "rooms_per_floor", 5, "floor_rule")
	_expect_int(rule, "normal_quota", 2, "floor_rule")
	_expect_int(rule, "event_quota", 2, "floor_rule")
	_expect_int(rule, "boss_slot", 5, "floor_rule")
	_expect_int(rule, "offer_count", 3, "floor_rule")
	if str(rule.get("first_policy", "")) != "QUOTA_WEIGHTED":
		errors.append("first_policy 必须为 QUOTA_WEIGHTED")
	if not (rule.get("choice_slots", []) is Array) or rule.choice_slots != [2, 3, 4]:
		# JSON numbers are floats; compare numerically.
		var slots: Array = rule.get("choice_slots", [])
		var ok_slots := slots.size() == 3
		if ok_slots:
			for i in 3:
				ok_slots = ok_slots and int(slots[i]) == [2, 3, 4][i]
		if not ok_slots:
			errors.append("choice_slots 必须为 [2,3,4]")
	for pool_id in ["normal_pool_id", "event_pool_id", "boss_pool_id"]:
		if str(rule.get(pool_id, "")).is_empty():
			errors.append("floor_rule 缺少 %s" % pool_id)


static func _validate_rooms() -> void:
	var display := {"NORMAL": "ROOM_NORMAL", "EVENT": "ROOM_EVENT", "BOSS": "ROOM_BOSS"}
	var scene := {"NORMAL": "battle", "EVENT": "event", "BOSS": "battle"}
	for item in rows("room_def"):
		var kind := str(item.get("room_kind", ""))
		if kind not in ["NORMAL", "EVENT", "BOSS"]:
			errors.append("房间类型未知 %s" % item.get("room_id", ""))
			continue
		var content_kind := str(item.get("content_kind", ""))
		if content_kind not in ["ENCOUNTER", "EVENT"]:
			errors.append("content_kind 未知 %s" % item.get("room_id", ""))
		var content_id := str(item.get("content_id", ""))
		if content_id.is_empty():
			errors.append("房间缺少 content_id %s" % item.get("room_id", ""))
		elif content_kind == "EVENT" and event(content_id).is_empty():
			errors.append("事件外键缺失 %s -> %s" % [item.get("room_id", ""), content_id])
		elif content_kind == "ENCOUNTER" and not content_id.begins_with("ENC_"):
			errors.append("遭遇 ID 必须以 ENC_ 开头 %s" % content_id)
		if content_kind == "ENCOUNTER":
			var monster_id := str(item.get("monster_id", ""))
			var mon := monster(monster_id)
			if mon.is_empty():
				errors.append("遭遇缺少怪物 %s -> %s" % [item.get("room_id", ""), content_id])
			elif str(mon.get("encounter_id", "")) != content_id:
				errors.append("遭遇与怪物不一致 %s" % content_id)
		elif str(item.get("monster_id", "")) != "":
			errors.append("非遭遇房不能绑定怪物 %s" % item.get("room_id", ""))
		if str(item.get("display_key", "")) != str(display[kind]):
			errors.append("display_key 与房型不一致 %s" % item.get("room_id", ""))
		if str(item.get("scene_key", "")) != str(scene[kind]):
			errors.append("scene_key 与房型不一致 %s" % item.get("room_id", ""))
		if not item.has("reward_bundle_id"):
			errors.append("房间缺少 reward_bundle_id %s" % item.get("room_id", ""))
		else:
			var bundle_id := str(item.get("reward_bundle_id", ""))
			if bundle_id != "" and row("reward_bundle", bundle_id).is_empty():
				errors.append("奖励包外键缺失 %s -> %s" % [item.get("room_id", ""), bundle_id])
	if room("RM_CACHE").is_empty():
		errors.append("缺少容错房 RM_CACHE")
	for item in rows("room_pool_entry"):
		var weight = item.get("weight", 0)
		if not _whole(weight) or int(weight) <= 0:
			errors.append("房间池权重必须为正整数 %s" % item.get("entry_id", ""))
		if room(str(item.get("room_id", ""))).is_empty():
			errors.append("房间池外键缺失 %s" % item.get("entry_id", ""))
		var pool_id := str(item.get("pool_id", ""))
		if pool_id not in ["POOL_NORMAL", "POOL_EVENT", "POOL_BOSS"]:
			errors.append("未知房间池 %s" % pool_id)
		if not _whole(item.get("min_depth", 1)) or not _whole(item.get("max_depth", 0)):
			errors.append("房间池深度不是整数 %s" % item.get("entry_id", ""))
		var linked := room(str(item.get("room_id", "")))
		if pool_id == "POOL_NORMAL" and str(linked.get("room_kind", "")) != "NORMAL":
			errors.append("普通池混入非战斗房 %s" % item.get("entry_id", ""))
		if pool_id == "POOL_EVENT" and str(linked.get("room_kind", "")) != "EVENT":
			errors.append("奇遇池混入非奇遇房 %s" % item.get("entry_id", ""))
		if pool_id == "POOL_BOSS" and str(linked.get("room_kind", "")) != "BOSS":
			errors.append("Boss 池混入非 Boss 房 %s" % item.get("entry_id", ""))
		if str(item.get("room_id", "")) == "RM_CACHE":
			errors.append("RM_CACHE 不能进入权重池")


static func _validate_events() -> void:
	var seen := {}
	for item in rows("event_def"):
		var handler := str(item.get("handler_id", ""))
		if handler not in HANDLERS:
			errors.append("事件处理器未注册 %s" % handler)
		seen[handler] = true
		if str(item.get("condition_id", "")) not in CONDITIONS:
			errors.append("事件条件未知 %s" % item.get("event_id", ""))
		if str(item.get("input_mode", "")) not in INPUT_MODES:
			errors.append("input_mode 未知 %s" % item.get("event_id", ""))
		if str(item.get("failure_policy", "")) != "ROLLBACK":
			errors.append("failure_policy 必须为 ROLLBACK %s" % item.get("event_id", ""))
		if typeof(item.get("params", null)) != TYPE_DICTIONARY:
			errors.append("事件 params 必须是对象 %s" % item.get("event_id", ""))
			continue
		_validate_event_params(item)
		if str(item.get("name", "")).is_empty():
			errors.append("事件缺少名称 %s" % item.get("event_id", ""))
		var display_names := {
			"EV_COPY": "终极复制机",
			"EV_SAC": "无言的祭祀",
			"EV_MAGE": "大魔导师",
			"EV_SMITH": "铁匠",
			"EV_PIZZA": "披萨饼师傅",
			"EV_TRANS": "无机转化",
		}
		var event_id := str(item.get("event_id", ""))
		if display_names.has(event_id) and str(item.get("name", "")) != str(display_names[event_id]):
			errors.append("事件显示名不正确 %s" % event_id)
	for handler in HANDLERS:
		if not seen.has(handler):
			errors.append("首包缺少处理器 %s" % handler)


static func _validate_event_params(item: Dictionary) -> void:
	var params: Dictionary = item.params
	var event_id := str(item.event_id)
	match str(item.handler_id):
		"COPY_CARD":
			if int(params.get("copies", 0)) != 1 or not bool(params.get("copy_flags", false)):
				errors.append("复制参数不符合首包 %s" % event_id)
		"SACRIFICE_MARK":
			var min_n := int(params.get("min", 0))
			var max_n := int(params.get("max", 0))
			if min_n < 1 or max_n > 3 or max_n < min_n or not bool(params.get("distinct_targets", false)):
				errors.append("献祭参数不符合首包 %s" % event_id)
		"SPECIAL_OFFER", "MARK_OFFER":
			if int(params.get("offers", 0)) != 3 or int(params.get("choose", 0)) != 1:
				errors.append("三选一参数必须 offers=3 choose=1 %s" % event_id)
			var pool_id := str(params.get("pool_id", ""))
			if str(item.handler_id) == "SPECIAL_OFFER" and _specials(pool_id).is_empty():
				errors.append("特殊牌池缺失 %s" % pool_id)
			if str(item.handler_id) == "MARK_OFFER" and _pool_entries(pool_id).is_empty():
				errors.append("印记池缺失 %s" % pool_id)
		"ACCEPT_PIZZA":
			var offsets: Array = params.get("offsets", [])
			var weights: Array = params.get("weights", [])
			if offsets.size() != weights.size() or offsets.is_empty():
				errors.append("披萨 offsets/weights 长度不一致")
			for offset in offsets:
				if int(offset) != 1 and int(offset) != 2:
					errors.append("披萨 offset 只允许 1 或 2")
			for weight in weights:
				if not _whole(weight) or int(weight) <= 0:
					errors.append("披萨权重必须为正整数")
			if reward(str(params.get("reward_id", ""))).is_empty():
				errors.append("披萨 reward_id 缺失")
		"TRANSFORM_CARD":
			if not bool(params.get("same_kind", false)) or not bool(params.get("keep_marks", false)) or not bool(params.get("exclude_original", false)):
				errors.append("转化参数不符合首包 %s" % event_id)
		"BASIC_CACHE":
			if not bool(params.get("repair_if_invalid", false)) or reward(str(params.get("reward_id", ""))).is_empty():
				errors.append("应急物资参数不符合首包 %s" % event_id)


static func _validate_cards() -> void:
	if rows("card_def").size() != 13:
		errors.append("卡牌模板必须为 13 张")
	var total := 0
	var seen_defs := {}
	for item in rows("starter_deck"):
		if str(item.get("starter_id", "")) != "STARTER_JAM":
			errors.append("起始牌组必须使用 STARTER_JAM")
		var def_id := str(item.get("def_id", ""))
		if seen_defs.has(def_id):
			errors.append("起始牌组 def 重复 %s" % def_id)
		seen_defs[def_id] = true
		var def := card(def_id)
		if def.is_empty():
			errors.append("起始牌外键缺失 %s" % def_id)
			continue
		var count := int(item.get("starter_count", 0))
		if count <= 0:
			errors.append("起始牌数量必须为正 %s" % def_id)
		total += count
		if str(def.get("operator_code", "")) in ["SUB", "DIV"]:
			errors.append("起始牌不能使用未启用运算符")
	if total != 15:
		errors.append("起始牌组总数必须为 15，当前 %s" % total)
	for item in rows("card_def"):
		var kind := str(item.get("card_kind", ""))
		var value := int(item.get("base_value", 99))
		var op := str(item.get("operator_code", ""))
		if kind == "NUM":
			if value < -5 or value > 5 or op != "NONE":
				errors.append("数字牌数值或运算符不合法 %s" % item.get("def_id", ""))
		elif kind == "OP":
			if value != 0 or op not in ["ADD", "MUL"]:
				errors.append("符号牌不合法 %s" % item.get("def_id", ""))
		else:
			errors.append("卡牌种类未知 %s" % item.get("def_id", ""))
		if str(item.get("name", "")).is_empty() or str(item.get("motif_id", "")).is_empty():
			errors.append("卡牌缺少名称或花纹 %s" % item.get("def_id", ""))


static func _validate_enhancements() -> void:
	if rows("enhancement_def").size() != 16:
		errors.append("强化定义必须为 16 条")
	var legacies := {}
	var value_ids: Array = []
	for item in rows("enhancement_def"):
		var enh_id := str(item.get("enh_id", ""))
		var legacy := int(item.get("legacy_no", 0))
		legacies[legacy] = true
		if str(item.get("handler_id", "")) != enh_id:
			errors.append("强化 handler 必须与 ID 相同 %s" % enh_id)
		if int(item.get("max_stacks", 0)) != 1:
			errors.append("强化叠加上限必须为 1 %s" % enh_id)
		if str(item.get("description_key", "")) != "DESC_%s" % enh_id:
			errors.append("description_key 不符合约定 %s" % enh_id)
		if str(item.get("family_id", "")) == "VALUE":
			value_ids.append(enh_id)
		var kinds: Array = item.get("valid_card_kinds", [])
		if kinds.is_empty():
			errors.append("强化缺少适用卡种 %s" % enh_id)
		if enh_id == "EN_ALCHEMY":
			if int(item.get("slot_cost", 1)) != 0 or str(item.get("risk_kind", "")) != "CONVERT":
				errors.append("点金手必须是 0 位转化")
			if row("collection_def", str(item.get("params", {}).get("collection_id", ""))).is_empty():
				errors.append("点金手收藏品外键缺失")
		elif int(item.get("slot_cost", 0)) != 1:
			errors.append("普通强化必须占用 1 个强化位 %s" % enh_id)
		if typeof(item.get("params", null)) != TYPE_DICTIONARY or typeof(item.get("hooks", null)) != TYPE_ARRAY:
			errors.append("强化 params/hooks 类型错误 %s" % enh_id)
	value_ids.sort()
	if value_ids != ["EN_NUM1", "EN_NUM2", "EN_NUM3"]:
		errors.append("VALUE 家族必须且只能是数值增长三档")
	for legacy in LEGACY_NOS:
		if not legacies.has(legacy):
			errors.append("缺少 legacy 类型 %s" % legacy)
	if legacies.size() != LEGACY_NOS.size():
		errors.append("legacy 类型数量不是 14")


static func _validate_rewards() -> void:
	for item in rows("reward_plan"):
		var reward_id := str(item.get("reward_id", ""))
		if str(item.get("payload_kind", "")) not in ["CARD", "MARK"]:
			errors.append("奖励类型未知 %s" % reward_id)
		if str(item.get("ui_mode", "")) not in ["PICK", "TAKE_ALL"]:
			errors.append("奖励界面未知 %s" % reward_id)
		if str(item.get("quality_profile", "")) not in ["NORMAL", "BOSS", "PIZZA", "FIXED_0", "NONE"]:
			errors.append("品质曲线未知 %s" % reward_id)
		var base_pool := str(item.get("base_pool_id", ""))
		if base_pool != "" and card_pool(base_pool).is_empty():
			errors.append("基础牌池外键缺失 %s" % base_pool)
		var mark_pool := str(item.get("mark_pool_id", ""))
		if mark_pool != "" and _pool_entries(mark_pool).is_empty():
			errors.append("印记池外键缺失 %s" % mark_pool)
		var fallback := str(item.get("fallback_reward_id", ""))
		if fallback != "" and reward(fallback).is_empty():
			errors.append("回退奖励外键缺失 %s" % fallback)
		var values: Array = item.get("grant_count_values", [])
		var weights: Array = item.get("grant_count_weights", [])
		if values.size() != weights.size():
			errors.append("奖励数量与权重长度不一致 %s" % reward_id)
		for weight in weights:
			if not _whole(weight) or int(weight) <= 0:
				errors.append("奖励数量权重必须为正 %s" % reward_id)
	for item in rows("reward_bundle"):
		for reward_id in item.get("ordered_reward_ids", []):
			if reward(str(reward_id)).is_empty():
				errors.append("奖励包外键缺失 %s" % reward_id)
	if rows("quality_curve").size() != 10:
		errors.append("品质曲线必须覆盖第 1—10 层")
	var previous_p0 := 2.0
	var previous_p2 := -1.0
	for depth in range(1, 11):
		var curve := row("quality_curve", depth)
		if curve.is_empty():
			errors.append("缺少深度 %s 的品质曲线" % depth)
			continue
		var p0 := float(curve.get("p0", -1))
		var p1 := float(curve.get("p1", -1))
		var p2 := float(curve.get("p2", -1))
		if p0 < 0.0 or p1 < 0.0 or p2 < 0.0 or p0 > 1.0 or p1 > 1.0 or p2 > 1.0:
			errors.append("品质概率超出 [0,1] 深度 %s" % depth)
		if absf(p0 + p1 + p2 - 1.0) > 0.000001:
			errors.append("品质概率之和不是 1 深度 %s" % depth)
		if p0 > previous_p0 or p2 < previous_p2:
			errors.append("品质曲线单调性不符合深度 %s" % depth)
		previous_p0 = p0
		previous_p2 = p2
		if int(curve.get("tail_start_depth", 0)) != 11:
			errors.append("tail_start_depth 必须为 11")
	_validate_card_pools()
	_validate_mark_pools()
	_validate_variants()
	_validate_specials()


static func _validate_card_pools() -> void:
	for item in rows("card_base_pool"):
		var weights: Dictionary = item.get("kind_weights", {})
		var total := 0
		for key in ["NUM", "ADD", "MUL"]:
			if not weights.has(key) or int(weights[key]) < 0:
				errors.append("牌池种类权重不完整 %s" % item.get("pool_id", ""))
			else:
				total += int(weights[key])
		if total <= 0:
			errors.append("牌池种类权重之和必须大于 0 %s" % item.get("pool_id", ""))
		var values: Array = item.get("abs_values", [])
		var abs_weights: Array = item.get("abs_weights", [])
		if values.size() != abs_weights.size():
			errors.append("绝对值与权重长度不一致 %s" % item.get("pool_id", ""))
		var fixed: Array = item.get("fixed_def_ids", [])
		for def_id in fixed:
			if card(str(def_id)).is_empty():
				errors.append("固定候选外键缺失 %s" % def_id)
		if fixed.is_empty() and values.is_empty():
			errors.append("非固定牌池必须有绝对值分布 %s" % item.get("pool_id", ""))


static func _validate_mark_pools() -> void:
	var families := {}
	for item in rows("enhancement_def"):
		families[str(item.get("family_id", ""))] = true
	var by_pool := {"EP_SAFE": [], "EP_SMITH": []}
	for item in rows("enhancement_pool"):
		var pool_id := str(item.get("pool_id", ""))
		var family := str(item.get("family_id", ""))
		var enh_id := str(item.get("enh_id", ""))
		var entry_id := str(item.get("entry_id", ""))
		if not by_pool.has(pool_id):
			errors.append("未知印记池 %s" % pool_id)
			continue
		if not families.has(family):
			errors.append("印记家族外键缺失 %s" % family)
		if family == "FROZEN" or enh_id == "EN_FROZEN":
			errors.append("冻结只出现在特殊牌，不进入印记池")
		if pool_id == "EP_SAFE" and (family == "ALCHEMY" or enh_id == "EN_ALCHEMY"):
			errors.append("普通印记池不能包含点金手或冻结")
		var enh_row := enh(enh_id)
		if enh_row.is_empty():
			errors.append("印记池强化外键缺失 %s" % entry_id)
		elif str(enh_row.get("family_id", "")) != family:
			errors.append("印记池家族与强化不一致 %s" % entry_id)
		if not _number(item.get("weight", null)) or float(item.get("weight", -1)) < 0.0:
			errors.append("印记池权重不能为负 %s" % entry_id)
		if str(item.get("variant_profile_id", "")) == "VAR_DEPTH":
			errors.append("数值增长必须直接抽取，不能再走 VAR_DEPTH %s" % entry_id)
		by_pool[pool_id].append(item)
	for pool_id in by_pool.keys():
		_expect_mark_pool_shape(pool_id, by_pool[pool_id])


static func _expect_mark_pool_shape(pool_id: String, entries: Array) -> void:
	var bands: Array = [
		{"min": 1, "max": 2, "EN_NUM1": 21.0, "EN_NUM2": 7.5, "EN_NUM3": 1.5},
		{"min": 3, "max": 5, "EN_NUM1": 15.0, "EN_NUM2": 10.5, "EN_NUM3": 4.5},
		{"min": 6, "max": 0, "EN_NUM1": 9.0, "EN_NUM2": 12.0, "EN_NUM3": 9.0},
	]
	var expected := {}
	for enh_id in ["EN_NUM1", "EN_NUM2", "EN_NUM3"]:
		expected[enh_id] = []
		for band in bands:
			expected[enh_id].append({"min": int(band["min"]), "max": int(band["max"]), "weight": float(band[enh_id])})
	var flat := {
		"EN_ECHO": 8.0,
		"EN_RETURN": 8.0,
		"EN_FRAGILE": 6.0,
		"EN_MAGNET": 8.0,
		"EN_YINYANG": 8.0,
		"EN_FLAMMABLE": 6.0,
		"EN_SMOLDER": 5.0,
		"EN_COMBO": 6.0,
		"EN_PRICE": 4.0,
		"EN_GHOST": 0.0,
		"EN_VANGUARD": 5.0,
	}
	if pool_id == "EP_SMITH":
		flat["EN_ALCHEMY"] = 5.0
	for enh_id in flat.keys():
		expected[enh_id] = [{"min": 1, "max": 0, "weight": float(flat[enh_id])}]
	var seen := {}
	for item in entries:
		var enh_id := str(item.get("enh_id", ""))
		if not expected.has(enh_id):
			errors.append("印记池出现未登记强化 %s %s" % [pool_id, enh_id])
			continue
		if not seen.has(enh_id):
			seen[enh_id] = []
		seen[enh_id].append(item)
	for enh_id in expected.keys():
		var want: Array = expected[enh_id]
		var got: Array = seen.get(enh_id, [])
		if got.size() != want.size():
			errors.append("%s 的 %s 行数应为 %s" % [pool_id, enh_id, want.size()])
			continue
		var used := {}
		for spec in want:
			var matched := false
			for i in got.size():
				if used.has(i):
					continue
				var entry: Dictionary = got[i]
				var same_depth := int(entry.get("min_depth", -1)) == int(spec["min"]) and int(entry.get("max_depth", -2)) == int(spec["max"])
				var same_weight := is_equal_approx(float(entry.get("weight", -1)), float(spec.weight))
				if same_depth and same_weight:
					used[i] = true
					matched = true
					break
			if not matched:
				errors.append("%s 的 %s 缺少权重 %s（%s-%s 层）" % [pool_id, enh_id, spec.weight, spec.min, spec.max])
	for depth in [1, 3, 6]:
		var total := 0.0
		for item in entries:
			var min_depth := int(item.get("min_depth", 1))
			var max_depth := int(item.get("max_depth", 0))
			if depth >= min_depth and (max_depth == 0 or depth <= max_depth):
				total += float(item.get("weight", 0))
		var want_total := 99.0 if pool_id == "EP_SMITH" else 94.0
		if not is_equal_approx(total, want_total):
			errors.append("%s 在第 %s 层的权重合计应为 %s，幽灵空出的 6 点不摊回" % [pool_id, depth, want_total])


static func _validate_variants() -> void:
	var saw_pizza := false
	for item in rows("variant_profile"):
		var ids: Array = item.get("enh_ids", [])
		var weights: Array = item.get("weights", [])
		if ids.size() != weights.size() or ids.is_empty():
			errors.append("变体权重长度不一致 %s" % item.get("entry_id", ""))
			continue
		for enh_id in ids:
			var enh_row := enh(str(enh_id))
			if enh_row.is_empty() or str(enh_row.get("family_id", "")) != "VALUE":
				errors.append("变体强化必须属于 VALUE %s" % enh_id)
		for weight in weights:
			if not _whole(weight) or int(weight) <= 0:
				errors.append("变体权重必须为正 %s" % item.get("entry_id", ""))
		if str(item.get("profile_id", "")) == "VAR_PIZZA":
			saw_pizza = true
			var want := [10, 25, 65]
			var same := weights.size() == want.size()
			if same:
				for i in want.size():
					same = same and int(weights[i]) == int(want[i])
			if not same:
				errors.append("披萨数值偏向必须为 10/25/65")
	if not saw_pizza:
		errors.append("缺少披萨数值偏向 VAR_PIZZA")


static func _validate_specials() -> void:
	var expected_weights := {
		"SP_BURST": 15.0,
		"SP_MEMORY": 20.0,
		"SP_REACTOR": 15.0,
		"SP_FIST": 0.0,
		"SP_TWIN": 15.0,
		"SP_LINK": 15.0,
	}
	var total := 0.0
	for item in rows("special_card"):
		var special_id := str(item.get("special_id", ""))
		var weight = item.get("weight", null)
		if not expected_weights.has(special_id):
			errors.append("未知特殊牌 %s" % special_id)
		elif not _number(weight) or float(weight) < 0.0 or not is_equal_approx(float(weight), float(expected_weights[special_id])):
			errors.append("特殊牌权重不符合停投表 %s" % special_id)
		else:
			total += float(weight)
		if special_id == "SP_FIST":
			var fist_marks: Array = item.get("enhancement_ids", [])
			var fist_ok := str(item.get("def_id", "")) == "CARD_ADD" and fist_marks.size() == 2
			fist_ok = fist_ok and str(fist_marks[0]) == "EN_COMBO" and str(fist_marks[1]) == "EN_GHOST"
			if not fist_ok:
				errors.append("SP_FIST 必须保留 CARD_ADD + EN_COMBO + EN_GHOST")
		var def := card(str(item.get("def_id", "")))
		if def.is_empty():
			errors.append("特殊牌基础牌缺失 %s" % item.get("special_id", ""))
			continue
		var marks: Array = item.get("enhancement_ids", [])
		if marks.size() < 1 or marks.size() > 2:
			errors.append("特殊牌印记数量必须为 1—2 %s" % item.get("special_id", ""))
			continue
		var families := {}
		var slots := 0
		for enh_id in marks:
			var enh_row := enh(str(enh_id))
			if enh_row.is_empty():
				errors.append("特殊牌印记外键缺失 %s" % enh_id)
				continue
			if not (enh_row.get("valid_card_kinds", []) as Array).has(str(def.get("card_kind", ""))):
				errors.append("特殊牌印记与卡种不兼容 %s" % item.get("special_id", ""))
			var family := str(enh_row.get("family_id", ""))
			if families.has(family):
				errors.append("特殊牌同族印记重复 %s" % item.get("special_id", ""))
			families[family] = true
			slots += int(enh_row.get("slot_cost", 1))
		if slots > 2:
			errors.append("特殊牌强化位超过 2 %s" % item.get("special_id", ""))
	if not is_equal_approx(total, 80.0):
		errors.append("特殊牌总权重必须为 80，SP_FIST 停投后不把 20 点摊回")


static func _validate_pools_cover_depth() -> void:
	for depth in range(1, 11):
		for pool_id in ["POOL_NORMAL", "POOL_EVENT", "POOL_BOSS"]:
			var covered := false
			for item in rows("room_pool_entry"):
				if str(item.get("pool_id", "")) != pool_id:
					continue
				var min_depth := int(item.get("min_depth", 1))
				var max_depth := int(item.get("max_depth", 0))
				if depth >= min_depth and (max_depth == 0 or depth <= max_depth):
					covered = true
					break
			if not covered:
				errors.append("%s 不能覆盖深度 %s" % [pool_id, depth])
	if mark_pool_rows("EP_SAFE", 1).is_empty() or mark_pool_rows("EP_SMITH", 1).is_empty():
		errors.append("印记池不能为空")
	if _rollable_specials("SP_MAGE").size() < 3:
		errors.append("魔导师特殊牌不足以三选一")


static func _validate_floors() -> void:
	var expected: Array = [
		[1, 1.0, 1.0, 24, 1],
		[2, 1.215, 1.085, 32, 3],
		[3, 1.5, 1.19, 38, 7],
		[4, 1.855, 1.315, 42, 13],
		[5, 2.28, 1.46, 44, 20],
		[6, 2.775, 1.625, 44, 28],
		[7, 3.34, 1.81, 42, 36],
		[8, 3.975, 2.015, 40, 43],
		[9, 4.68, 2.24, 37, 50],
		[10, 5.455, 2.485, 35, 55],
	]
	if rows("floor_config").size() != expected.size():
		errors.append("floor_config 必须覆盖第 1—10 层")
	for spec in expected:
		var floor_no := int(spec[0])
		var floor_row := floor_config(floor_no)
		if floor_row.is_empty():
			errors.append("缺少层数倍率 %s" % floor_no)
			continue
		if not is_equal_approx(float(floor_row.get("hp_mul", -1)), float(spec[1])):
			errors.append("floor_config.%s hp_mul 不正确" % floor_no)
		if not is_equal_approx(float(floor_row.get("atk_mul", -1)), float(spec[2])):
			errors.append("floor_config.%s atk_mul 不正确" % floor_no)
		if not _whole(floor_row.get("p1", null)) or not _whole(floor_row.get("p2", null)):
			errors.append("floor_config.%s 的 p1/p2 必须是百分数" % floor_no)
			continue
		var p1 := int(floor_row.get("p1", -1))
		var p2 := int(floor_row.get("p2", -1))
		if p1 != int(spec[3]) or p2 != int(spec[4]) or p1 < 0 or p2 < 0 or p1 + p2 > 100:
			errors.append("floor_config.%s 的 p1/p2 不正确" % floor_no)
			continue
		var curve := row("quality_curve", floor_no)
		if curve.is_empty():
			errors.append("品质曲线缺少深度 %s" % floor_no)
			continue
		var p0 := (100.0 - float(p1) - float(p2)) / 100.0
		if absf(p0 - float(curve.get("p0", -1))) > 0.000001:
			errors.append("floor_config 与 quality_curve 的 p0 不一致 层 %s" % floor_no)
		if absf(float(p1) / 100.0 - float(curve.get("p1", -1))) > 0.000001:
			errors.append("floor_config 与 quality_curve 的 p1 不一致 层 %s" % floor_no)
		if absf(float(p2) / 100.0 - float(curve.get("p2", -1))) > 0.000001:
			errors.append("floor_config 与 quality_curve 的 p2 不一致 层 %s" % floor_no)


static func _validate_monsters() -> void:
	var expected: Array = [
		{"monster_id": "MON_RUST", "encounter_id": "ENC_RUST", "name": "锈刃哥布林", "kind": "NORMAL", "base_hp": 60, "base_atk": 10, "min_floor": 1, "weight": 40},
		{"monster_id": "MON_PARITY", "encounter_id": "ENC_PARITY", "name": "单目哥布林", "kind": "NORMAL", "base_hp": 70, "base_atk": 11, "min_floor": 1, "weight": 30},
		{"monster_id": "MON_INK", "encounter_id": "ENC_INK", "name": "墨罐哥布林", "kind": "NORMAL", "base_hp": 66, "base_atk": 10, "min_floor": 1, "weight": 30},
		{"monster_id": "MON_PRIEST", "encounter_id": "ENC_PRIEST", "name": "深渊牧师", "kind": "NORMAL", "base_hp": 86, "base_atk": 10, "min_floor": 2, "weight": 20},
		{"monster_id": "MON_THIEF", "encounter_id": "ENC_THIEF", "name": "拾荒盗贼", "kind": "NORMAL", "base_hp": 78, "base_atk": 12, "min_floor": 3, "weight": 15},
		{"monster_id": "MON_SWORD", "encounter_id": "ENC_SWORD", "name": "守门剑士", "kind": "BOSS", "base_hp": 160, "base_atk": 16, "min_floor": 1, "weight": 100},
	]
	if rows("monster_config").size() != expected.size():
		errors.append("怪物表必须是 6 行")
	for spec in expected:
		var monster_id := str(spec["monster_id"])
		var mon := monster(monster_id)
		if mon.is_empty():
			errors.append("缺少怪物 %s" % monster_id)
			continue
		if str(mon.get("kind", "")) not in ["NORMAL", "BOSS"]:
			errors.append("怪物种类必须是 NORMAL 或 BOSS %s" % monster_id)
		for key in ["encounter_id", "name", "kind"]:
			if str(mon.get(key, "")) != str(spec[key]):
				errors.append("怪物 %s 的 %s 不正确" % [monster_id, key])
		for key in ["base_hp", "base_atk", "min_floor", "weight"]:
			if not _whole(mon.get(key, null)) or int(mon.get(key, -1)) != int(spec[key]):
				errors.append("怪物 %s 的 %s 不正确" % [monster_id, key])
		var linked_pool := {}
		for entry in rows("room_pool_entry"):
			var linked := room(str(entry.get("room_id", "")))
			if str(linked.get("monster_id", "")) == monster_id:
				linked_pool = entry
				break
		if linked_pool.is_empty():
			errors.append("怪物没有对应房间池 %s" % monster_id)
		elif int(linked_pool.get("weight", -1)) != int(spec["weight"]) or int(linked_pool.get("min_depth", -1)) != int(spec["min_floor"]):
			errors.append("怪物权重或解锁层与房间池不一致 %s" % monster_id)


static func _pool_entries(pool_id: String) -> Array:
	var found: Array = []
	for item in rows("enhancement_pool"):
		if str(item.get("pool_id", "")) == pool_id:
			found.append(item)
	return found


static func _specials(pool_id: String) -> Array:
	var found: Array = []
	for item in rows("special_card"):
		if str(item.get("pool_id", "")) == pool_id:
			found.append(item)
	return found


static func _rollable_specials(pool_id: String) -> Array:
	var found: Array = []
	for item in _specials(pool_id):
		if float(item.get("weight", 0)) > 0.0:
			found.append(item)
	return found


static func _expect_int(row_data: Dictionary, key: String, expected: int, label: String) -> void:
	if not _whole(row_data.get(key, null)) or int(row_data.get(key, 0)) != expected:
		errors.append("%s.%s 必须为 %s" % [label, key, expected])


static func _whole(value) -> bool:
	return (value is int) or (value is float and is_finite(float(value)) and float(value) == floor(float(value)))


static func _number(value) -> bool:
	return (value is int) or (value is float and is_finite(float(value)))
