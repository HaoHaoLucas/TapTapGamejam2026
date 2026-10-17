class_name ConfigCatalog
extends RefCounted
## Read-only jam config. Rows are indexed by primary key and never hold run state.

const CONFIG_DIR := "res://data/config/jam_1.0.0"
const CONFIG_VERSION := "jam_1.2.0"
const FILES: PackedStringArray = [
	"battle_rule.json",
	"card_def.json",
	"starter_deck.json",
	"enhancement_def.json",
	"collection_def.json",
]
const NUMBER_IDS: PackedStringArray = [
	"CARD_NM5", "CARD_NM4", "CARD_NM3", "CARD_NM2", "CARD_NM1",
	"CARD_N0", "CARD_N1", "CARD_N2", "CARD_N3", "CARD_N4", "CARD_N5",
]
const PRIMARY_KEYS: Dictionary = {
	"battle_rule": ["ruleset_id"],
	"card_def": ["def_id"],
	"starter_deck": ["starter_id", "def_id"],
	"enhancement_def": ["enh_id"],
	"collection_def": ["collection_id"],
}

var config_version: String = ""
var errors: PackedStringArray = PackedStringArray()
var _tables: Dictionary = {}
var _index: Dictionary = {}


static func load_default() -> ConfigCatalog:
	return load_dir(CONFIG_DIR)


static func load_dir(path: String) -> ConfigCatalog:
	var catalog := ConfigCatalog.new()
	catalog.config_version = CONFIG_VERSION
	var loaded: Dictionary = {}
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				loaded[file_name] = true
				catalog._load_file(path.path_join(file_name))
			file_name = dir.get_next()
		dir.list_dir_end()
	for file_name in FILES:
		if not loaded.has(file_name):
			catalog._load_file(path.path_join(file_name))
	catalog._build_indexes()
	catalog.validate()
	return catalog


func ok() -> bool:
	return errors.is_empty()


func rule() -> Dictionary:
	return row("battle_rule", "RULE_JAM_10S")


func card(def_id: String) -> Dictionary:
	return row("card_def", def_id)


func enh(enh_id: String) -> Dictionary:
	return row("enhancement_def", enh_id)


func collection(collection_id: String) -> Dictionary:
	return row("collection_def", collection_id)


func row(table: String, key: String) -> Dictionary:
	var table_index: Dictionary = _index.get(table, {})
	var found = table_index.get(key, {})
	return found if found is Dictionary else {}


func rows(table: String) -> Array:
	var found = _tables.get(table, [])
	return found if found is Array else []


func starter_rows(starter_id: String = "STARTER_JAM") -> Array:
	var out: Array = []
	for entry in rows("starter_deck"):
		if str(entry.get("starter_id", "")) == starter_id:
			out.append(entry)
	return out


func enh_ids() -> Array:
	return _index.get("enhancement_def", {}).keys()


func validate() -> void:
	_require_tables()
	if not errors.is_empty() and _tables.is_empty():
		return
	_validate_battle_rule()
	_validate_cards()
	_validate_starter()
	_validate_enhancements()
	_validate_collection()


func _load_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		errors.append("缺少配置文件 %s" % path)
		return
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("JSON 顶层必须是对象 %s" % path)
		return
	var data: Dictionary = parsed
	if int(data.get("schema_version", -1)) != 1:
		errors.append("schema_version 必须为 1：%s" % path)
	if str(data.get("config_version", "")) != CONFIG_VERSION:
		errors.append("config_version 必须为 %s：%s" % [CONFIG_VERSION, path])
	var table := str(data.get("table", ""))
	if table == "":
		errors.append("缺少 table：%s" % path)
		return
	if data.get("rows") is not Array:
		errors.append("rows 必须是数组：%s" % path)
		return
	if _tables.has(table):
		errors.append("表名重复 %s" % table)
		return
	_tables[table] = data.rows


func _build_indexes() -> void:
	for table in _tables.keys():
		var index := {}
		for entry in _tables[table]:
			if entry is not Dictionary:
				errors.append("%s 出现非对象行" % table)
				continue
			var key := _primary_key(table, entry)
			if key == "":
				errors.append("%s 缺少主键" % table)
				continue
			if index.has(key):
				errors.append("%s 主键重复 %s" % [table, key])
				continue
			index[key] = entry
		_index[table] = index


func _primary_key(table: String, entry: Dictionary) -> String:
	var keys: Array = PRIMARY_KEYS.get(table, [])
	if keys.is_empty():
		if entry.has("id"):
			return str(entry.id)
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for key in keys:
		if not entry.has(key):
			return ""
		parts.append(str(entry[key]))
	return "|".join(parts)


func _require_tables() -> void:
	for table in PRIMARY_KEYS.keys():
		if not _tables.has(table):
			errors.append("缺少表 %s" % table)


func _validate_battle_rule() -> void:
	var rules := rows("battle_rule")
	if rules.size() != 1:
		errors.append("battle_rule 必须只有 RULE_JAM_10S 一行")
		return
	var row_data: Dictionary = rules[0]
	if str(row_data.get("ruleset_id", "")) != "RULE_JAM_10S":
		errors.append("ruleset_id 必须是 RULE_JAM_10S")
	_expect_number(row_data, "turn_seconds", "battle_rule")
	_expect_int(row_data, "turn_start_draw", "battle_rule", 1, 20)
	_expect_number(row_data, "delayed_draw_at", "battle_rule")
	_expect_int(row_data, "delayed_draw_count", "battle_rule", 1, 20)
	if not _is_int_number(row_data.get("hand_limit", null)) or int(row_data.get("hand_limit", -1)) != 0:
		errors.append("battle_rule.hand_limit 必须为 0")
	if not _is_int_number(row_data.get("discard_at_turn_end", null)) or int(row_data.get("discard_at_turn_end", -1)) != 0:
		errors.append("battle_rule.discard_at_turn_end 必须为 0")
	_expect_int(row_data, "initial_deck_size", "battle_rule", 1, 99)
	_expect_int(row_data, "max_hp", "battle_rule", 1, 999999)
	_expect_number(row_data, "damage_scale", "battle_rule")
	_expect_int(row_data, "burn_heal_per_abs", "battle_rule", 0, 9999)
	_expect_bool(row_data, "allow_operator_burn", "battle_rule")
	_expect_int(row_data, "max_marks_per_card", "battle_rule", 1, 9)
	_expect_int(row_data, "max_formula_tokens", "battle_rule", 3, 21)
	_expect_int(row_data, "max_equation_damage", "battle_rule", 1, 99999999)
	_expect_number(row_data, "combo_base_s", "battle_rule")
	_expect_number(row_data, "combo_cap_s", "battle_rule")
	_expect_int(row_data, "combo_click_damage", "battle_rule", 0, 99)
	_expect_int(row_data, "combo_click_rate_cap", "battle_rule", 1, 60)
	_expect_number(row_data, "normal_2_hp", "battle_rule")
	_expect_number(row_data, "normal_2_atk", "battle_rule")
	_expect_number(row_data, "boss_phase2_atk", "battle_rule")
	if int(row_data.get("max_marks_per_card", 0)) != 2:
		errors.append("本规则集每张牌最多 2 枚印记")
	if _is_number_value(row_data.get("turn_seconds", null)) and _is_number_value(row_data.get("delayed_draw_at", null)):
		var delayed_at := float(row_data.get("delayed_draw_at"))
		var turn_s := float(row_data.get("turn_seconds"))
		if delayed_at <= 0.0 or delayed_at >= turn_s:
			errors.append("delayed_draw_at 必须大于 0 且小于 turn_seconds")
	for key in ["normal_2_hp", "normal_2_atk", "boss_phase2_atk"]:
		var scale = row_data.get(key, null)
		if _is_number_value(scale) and float(scale) <= 0.0:
			errors.append("battle_rule.%s 必须大于 0" % key)


func _validate_cards() -> void:
	var seen_values := {}
	for def_id in NUMBER_IDS:
		if card(def_id).is_empty():
			errors.append("缺少数字模板 %s" % def_id)
	if card("CARD_ADD").is_empty() or card("CARD_MUL").is_empty():
		errors.append("缺少 ADD 或 MUL 模板")
	for entry in rows("card_def"):
		var def_id := str(entry.get("def_id", ""))
		var kind := str(entry.get("card_kind", ""))
		var op := str(entry.get("operator_code", ""))
		if kind != "NUM" and kind != "OP":
			errors.append("%s 的 card_kind 只能是 NUM 或 OP" % def_id)
		if op == "SUB" or op == "DIV":
			errors.append("本规则集不能出现 %s" % op)
		if str(entry.get("name", "")) == "" or str(entry.get("motif_id", "")) == "":
			errors.append("%s 缺少 name 或 motif_id" % def_id)
		if kind == "NUM":
			if op != "NONE":
				errors.append("%s 的 operator_code 必须是 NONE" % def_id)
			if not _is_int_number(entry.get("base_value", null)):
				errors.append("%s 的 base_value 必须是整数" % def_id)
			else:
				var base := int(entry.base_value)
				if base < -5 or base > 5:
					errors.append("%s 的 base_value 超出 −5 至 +5" % def_id)
				if seen_values.has(base):
					errors.append("数字牌面 %s 重复" % base)
				seen_values[base] = def_id
		elif kind == "OP":
			if int(entry.get("base_value", 1)) != 0:
				errors.append("%s 的 base_value 必须是 0" % def_id)
			if op != "ADD" and op != "MUL":
				errors.append("%s 的符号未启用" % def_id)
	if seen_values.size() != 11:
		errors.append("数字模板必须覆盖 −5 到 +5")


func _validate_starter() -> void:
	var total := 0
	var counts := {}
	for entry in rows("starter_deck"):
		var starter_id := str(entry.get("starter_id", ""))
		var def_id := str(entry.get("def_id", ""))
		if card(def_id).is_empty():
			errors.append("起始牌组引用了未知模板 %s" % def_id)
		if not _is_int_number(entry.get("starter_count", null)):
			errors.append("starter_count 必须是整数")
			continue
		var count := int(entry.starter_count)
		if count < 1:
			errors.append("%s 的 starter_count 必须为正" % def_id)
		if starter_id == "STARTER_JAM":
			total += count
			counts[def_id] = int(counts.get(def_id, 0)) + count
	var expected := int(rule().get("initial_deck_size", 15))
	if total != 15 or total != expected:
		errors.append("STARTER_JAM 必须正好 15 张，当前 %s" % total)
	for def_id in NUMBER_IDS:
		if int(counts.get(def_id, 0)) != 1:
			errors.append("STARTER_JAM 的 %s 必须是 1 张" % def_id)
	if int(counts.get("CARD_ADD", 0)) != 2 or int(counts.get("CARD_MUL", 0)) != 2:
		errors.append("STARTER_JAM 必须是 2 张 ADD 与 2 张 MUL")


func _validate_enhancements() -> void:
	var table_rows := rows("enhancement_def")
	if table_rows.size() != EnhancementRegistry.SPECS.size():
		errors.append("enhancement_def 必须是 16 行")
	var legacy_seen := {}
	var value_ids: Array = []
	for enh_id in EnhancementRegistry.SPECS.keys():
		var spec: Dictionary = EnhancementRegistry.SPECS[enh_id]
		var entry := enh(enh_id)
		if entry.is_empty():
			errors.append("缺少强化 %s" % enh_id)
			continue
		if str(entry.get("handler_id", "")) != enh_id:
			errors.append("%s 的 handler_id 必须与 enh_id 相同" % enh_id)
		if not EnhancementRegistry.has_id(str(entry.get("handler_id", ""))):
			errors.append("%s 指向了白名单之外的处理器" % enh_id)
		if int(entry.get("legacy_no", -1)) != int(spec.legacy_no):
			errors.append("%s 的 legacy_no 与原稿编号不一致" % enh_id)
		legacy_seen[int(entry.legacy_no)] = true
		if str(entry.get("family_id", "")) != str(spec.family_id):
			errors.append("%s 的 family_id 不正确" % enh_id)
		if str(entry.family_id) == "VALUE":
			value_ids.append(enh_id)
		if not _same_strings(entry.get("valid_card_kinds", []), spec.valid_card_kinds):
			errors.append("%s 的适用卡种不正确" % enh_id)
		if not _same_strings(entry.get("hooks", []), spec.hooks):
			errors.append("%s 的 hooks 不正确" % enh_id)
		if int(entry.get("slot_cost", -1)) != int(spec.slot_cost):
			errors.append("%s 的 slot_cost 与卡种规则不一致" % enh_id)
		if str(entry.get("risk_kind", "")) != str(spec.risk_kind):
			errors.append("%s 的 risk_kind 不正确" % enh_id)
		if int(entry.get("max_stacks", 0)) != 1:
			errors.append("%s 的 max_stacks 必须是 1" % enh_id)
		if str(entry.get("description_key", "")) != "DESC_%s" % enh_id:
			errors.append("%s 的 description_key 必须是 DESC_%s" % [enh_id, enh_id])
		if str(entry.get("name", "")) == "":
			errors.append("%s 缺少名称" % enh_id)
		if not _is_int_number(entry.get("power_score", null)):
			errors.append("%s 的 power_score 必须是整数" % enh_id)
		_validate_params(enh_id, entry.get("params", null), spec.param_types)
	for legacy in EnhancementRegistry.LEGACY_TYPES:
		if not legacy_seen.has(legacy):
			errors.append("缺少原稿强化类型 %s" % legacy)
	if legacy_seen.has(8) or legacy_seen.has(9):
		errors.append("不能补造原稿没有的 8、9 号强化")
	if value_ids.size() != 3:
		errors.append("VALUE 族必须正好是数值增长三档")
	for enh_id in _index.get("enhancement_def", {}).keys():
		if not EnhancementRegistry.has_id(str(enh_id)):
			errors.append("未知强化不能注册处理器 %s" % enh_id)
	if EnhancementRegistry.normal_drop_allowed("EN_ALCHEMY") or EnhancementRegistry.normal_drop_allowed("EN_FROZEN"):
		errors.append("普通掉落必须排除点金手和冻结")
	for enh_id in EnhancementRegistry.SPECS.keys():
		var allowed := EnhancementRegistry.normal_drop_allowed(str(enh_id))
		if str(enh_id) == "EN_ALCHEMY" or str(enh_id) == "EN_FROZEN":
			if allowed:
				errors.append("%s 不能进入普通掉落" % enh_id)
		elif not allowed:
			errors.append("%s 被错误排除出普通掉落" % enh_id)


func _validate_params(enh_id: String, params, types: Dictionary) -> void:
	if params is not Dictionary:
		errors.append("%s 缺少 params" % enh_id)
		return
	if params.size() != types.size():
		errors.append("%s 的 params 与处理器白名单不一致" % enh_id)
	for key in types.keys():
		if not params.has(key):
			errors.append("%s 缺少参数 %s" % [enh_id, key])
			continue
		var value = params[key]
		match str(types[key]):
			"int":
				if not _is_int_number(value):
					errors.append("%s.%s 必须是整数" % [enh_id, key])
			"float":
				if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
					errors.append("%s.%s 必须是数字" % [enh_id, key])
			"string":
				if typeof(value) != TYPE_STRING or str(value) == "":
					errors.append("%s.%s 必须是字符串" % [enh_id, key])
			"bool":
				if typeof(value) != TYPE_BOOL:
					errors.append("%s.%s 必须是布尔值" % [enh_id, key])
	if enh_id == "EN_ALCHEMY" and params is Dictionary:
		var collection_id := str(params.get("collection_id", ""))
		if collection(collection_id).is_empty():
			errors.append("点金手引用了未知收藏品 %s" % collection_id)
	if enh_id == "EN_FRAGILE" and params is Dictionary:
		var chance := float(params.get("break_p", -1))
		if chance < 0.0 or chance > 1.0:
			errors.append("易碎概率必须在 0 到 1 之间")


func _validate_collection() -> void:
	var entry := collection("COL_SAMPLE")
	if entry.is_empty():
		errors.append("缺少收藏品 COL_SAMPLE")
		return
	if str(entry.get("name", "")) == "" or str(entry.get("behavior", "")) != "DISPLAY_ONLY":
		errors.append("COL_SAMPLE 必须只负责展示")
	if str(entry.get("value_source", "")) != "INSTANCE_SNAPSHOT":
		errors.append("COL_SAMPLE 的估值来源必须是实体快照")


func _expect_int(entry: Dictionary, key: String, table: String, low: int, high: int) -> void:
	if not _is_int_number(entry.get(key, null)):
		errors.append("%s.%s 必须是整数" % [table, key])
		return
	var value := int(entry[key])
	if value < low or value > high:
		errors.append("%s.%s 超出范围" % [table, key])


func _expect_number(entry: Dictionary, key: String, table: String) -> void:
	if not _is_number_value(entry.get(key, null)):
		errors.append("%s.%s 必须是数字" % [table, key])


func _is_number_value(value) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


func _expect_bool(entry: Dictionary, key: String, table: String) -> void:
	if typeof(entry.get(key, null)) != TYPE_BOOL:
		errors.append("%s.%s 必须是布尔值" % [table, key])


func _is_int_number(value) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_equal_approx(float(value), floor(float(value)))


func _same_strings(actual, expected: Array) -> bool:
	if actual is not Array or actual.size() != expected.size():
		return false
	for i in expected.size():
		if str(actual[i]) != str(expected[i]):
			return false
	return true
