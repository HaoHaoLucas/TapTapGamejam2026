class_name MonsterRules
extends RefCounted
## Six jam monsters on CardBattle. Attach, then detain a thief, then start.
## publish_intent runs at each player-turn start. The 7.5s draw does not call it.

const ENC_RUST := "ENC_RUST"
const ENC_PARITY := "ENC_PARITY"
const ENC_INK := "ENC_INK"
const ENC_PRIEST := "ENC_PRIEST"
const ENC_THIEF := "ENC_THIEF"
const ENC_SWORD := "ENC_SWORD"
const MON_RUST := "MON_RUST"
const MON_PARITY := "MON_PARITY"
const MON_INK := "MON_INK"
const MON_PRIEST := "MON_PRIEST"
const MON_THIEF := "MON_THIEF"
const MON_SWORD := "MON_SWORD"
const ENCOUNTER_MONSTER := {
	ENC_RUST: MON_RUST,
	ENC_PARITY: MON_PARITY,
	ENC_INK: MON_INK,
	ENC_PRIEST: MON_PRIEST,
	ENC_THIEF: MON_THIEF,
	ENC_SWORD: MON_SWORD,
}

const MONSTER_PATH := "res://data/run/monster_config.json"
const FLOOR_PATH := "res://data/run/floor_config.json"
const RUST_COEFF := 1.2
const PARITY_COEFF := 0.7
const INK_TAX := 2
const SWORD_OP_COEFF := 0.6
const SWORD_CHARGE_MUL := 1.75
const SWORD_INTERRUPT_MUL := 0.75
const PRIEST_HEAL := 8.0
const ACTION_STRIKE := "STRIKE"
const ACTION_SLASH := "SLASH"
const ACTION_CHARGE := "CHARGE"


static func monster_id_for_encounter(content_id: String) -> String:
	if GameData.loaded:
		var row := GameData.monster_for_encounter(content_id)
		if not row.is_empty():
			return str(row.get("monster_id", ""))
	return str(ENCOUNTER_MONSTER.get(content_id, ""))


static func load_monster(monster_id: String) -> Dictionary:
	var row := _lookup_monster(monster_id)
	if row.is_empty():
		row = _fallback_monster(monster_id)
	return {
		"id": monster_id,
		"name": str(row.get("name", "")),
		"kind": str(row.get("kind", "")),
		"base_hp": int(row.get("base_hp", 0)),
		"base_atk": int(row.get("base_atk", 0)),
		"min_floor": int(row.get("min_floor", 0)),
		"weight": int(row.get("weight", 0)),
	}


static func load_floor(floor: int) -> Dictionary:
	if floor >= 11:
		return _scaled_floor(floor)
	var row := _lookup_floor(floor)
	if row.is_empty():
		row = _fallback_floor(floor)
	if row.is_empty():
		return {"hp_mul": 1.0, "atk_mul": 1.0, "p1": 0, "p2": 0}
	return {
		"hp_mul": float(row.get("hp_mul", 1.0)),
		"atk_mul": float(row.get("atk_mul", 1.0)),
		"p1": int(row.get("p1", 0)),
		"p2": int(row.get("p2", 0)),
	}


static func room_multipliers(room_kind: String, normal_used: int) -> Dictionary:
	if room_kind == "NORMAL" and normal_used >= 2:
		var rule := _battle_rule_row()
		return {
			"hp": _number(rule, "normal_2_hp", 1.1),
			"atk": _number(rule, "normal_2_atk", 1.05),
		}
	return {"hp": 1.0, "atk": 1.0}


static func compute_max_hp(base_hp: int, hp_mul: float, room_hp: float) -> int:
	return _round_half_up(float(base_hp) * hp_mul * room_hp)


static func compute_attack(base_atk: int, action_mul: float, atk_mul: float, room_atk: float, phase_mul: float) -> int:
	return _round_half_up(float(base_atk) * action_mul * atk_mul * room_atk * phase_mul)


static func detain_opening(ctx, battle) -> void:
	if ctx == null or battle == null:
		return
	if str(battle.monster_id) != MON_THIEF:
		return
	if str(battle.stolen_card_uid) != "":
		return
	var pool := _opening_pool(ctx)
	var ranked := _rank_targets(pool, ctx.catalog)
	for card in ranked:
		if not _removal_leaves_a_fight(ctx, pool, card):
			continue
		ctx.library.move(card, CardInstance.STOLEN, "STEAL", str(battle.battle_uid), ctx)
		battle.stolen_card_uid = str(card.card_uid)
		battle.thief_progress = 0
		return


static func attach(battle, monster_id: String, floor: int, room_hp: float, room_atk: float) -> void:
	if battle == null or monster_id == "":
		return
	var spec := load_monster(monster_id)
	var growth := load_floor(floor)
	var kept_uid := str(battle.stolen_card_uid)
	var kept_progress := int(battle.thief_progress)
	battle.monster_id = str(spec.get("id", monster_id))
	battle.monster_name = str(spec.get("name", ""))
	battle.monster_kind = str(spec.get("kind", ""))
	battle.floor_no = floor
	battle.base_atk = int(spec.get("base_atk", 0))
	battle.hp_mul = float(growth.get("hp_mul", 1.0))
	battle.atk_mul = float(growth.get("atk_mul", 1.0))
	battle.room_hp = room_hp
	battle.room_atk = room_atk
	battle.sword_phase = 1
	battle.sword_phase_pending = false
	battle.phase_mul = 1.0
	battle.monster_armed_turn = 0
	if battle.monster_id == MON_THIEF:
		battle.stolen_card_uid = kept_uid
		battle.thief_progress = kept_progress
	else:
		battle.stolen_card_uid = ""
		battle.thief_progress = 0
	var hp := compute_max_hp(int(spec.get("base_hp", 0)), battle.hp_mul, room_hp)
	battle.enemy_max_hp = hp
	battle.enemy_hp = hp
	publish_intent(battle)


static func publish_intent(battle) -> void:
	if battle == null or str(battle.monster_id) == "":
		return
	_arm_turn(battle)
	_write_intent(battle)


static func equation_mods(battle, entity_count: int, primary_op: String, raw_result: int) -> Dictionary:
	if battle == null or str(battle.monster_id) == "":
		return {"tax": 0, "coefficient": 1.0}
	var tax := 0
	var coefficient := 1.0
	var turn := _player_turn(battle)
	var beat := _beat_index(turn)
	match str(battle.monster_id):
		MON_RUST:
			if entity_count >= 5:
				coefficient *= RUST_COEFF
		MON_PARITY:
			if _wants_odd(turn) != _is_odd(raw_result):
				coefficient *= PARITY_COEFF
		MON_INK:
			if not bool(battle.ink_tax_used) and primary_op == _taxed_op(turn):
				tax = INK_TAX
		MON_SWORD:
			if beat == 1 and primary_op == "ADD":
				coefficient *= SWORD_OP_COEFF
			elif beat == 2 and primary_op == "MUL":
				coefficient *= SWORD_OP_COEFF
	return {"tax": tax, "coefficient": coefficient}


static func note_legal_equation(battle, primary_op: String, raw_result: int, damage: int, had_negative_printed: bool) -> void:
	# Call before HP is reduced. Parity already used the integer result inside equation_mods.
	if battle == null or str(battle.monster_id) == "":
		return
	var monster := str(battle.monster_id)
	if monster == MON_INK and primary_op == _taxed_op(_player_turn(battle)) and not bool(battle.ink_tax_used):
		battle.ink_tax_used = true
	if monster == MON_PRIEST and had_negative_printed and damage > 0:
		battle.priest_heal_cancelled = true
	var actual := 0
	if damage > 0:
		actual = mini(damage, int(battle.enemy_hp))
	if actual > 0:
		_account_thief(battle, actual)
		_account_sword_phase(battle, int(battle.enemy_hp) - actual)
	if monster == MON_SWORD and damage > 0:
		if primary_op == "ADD":
			battle.sword_positive_add = true
		elif primary_op == "MUL":
			battle.sword_positive_mul = true
		_apply_sword_interrupt(battle)


static func note_direct_hit(battle, actual: int) -> void:
	# Combo clicks and other non-equation HP loss. Does not tax, cancel heal, or count a primary.
	if battle == null or str(battle.monster_id) == "" or actual <= 0:
		return
	_account_thief(battle, actual)
	_account_sword_phase(battle, int(battle.enemy_hp))


static func apply_enemy_action(battle) -> void:
	if battle == null:
		return
	if str(battle.monster_id) == "":
		battle.player_hp = maxi(0, int(battle.player_hp) - int(battle.intent_damage))
		return
	battle.player_hp = maxi(0, int(battle.player_hp) - int(battle.intent_damage))
	if int(battle.player_hp) > 0 and str(battle.monster_id) == MON_PRIEST and not bool(battle.priest_heal_cancelled):
		var heal := _round_half_up(PRIEST_HEAL * float(battle.hp_mul) * float(battle.room_hp))
		battle.enemy_hp = mini(int(battle.enemy_max_hp), int(battle.enemy_hp) + heal)
	if str(battle.monster_id) == MON_SWORD and bool(battle.sword_phase_pending):
		battle.sword_phase = 2
		battle.sword_phase_pending = false


static func _arm_turn(battle) -> void:
	var turn := _player_turn(battle)
	if int(battle.monster_armed_turn) == turn:
		return
	battle.monster_armed_turn = turn
	battle.ink_tax_used = false
	battle.priest_heal_cancelled = false
	battle.sword_positive_add = false
	battle.sword_positive_mul = false


static func _write_intent(battle) -> void:
	var monster := str(battle.monster_id)
	var turn := _player_turn(battle)
	var phase_mul := 1.0
	if monster == MON_SWORD and int(battle.sword_phase) >= 2:
		phase_mul = _boss_phase2(battle)
	battle.phase_mul = phase_mul
	var action := ACTION_STRIKE
	var action_mul := 1.0
	var beat := 0
	if monster == MON_SWORD:
		beat = _beat_index(turn)
		if beat == 3:
			action = ACTION_CHARGE
			if bool(battle.sword_positive_add) and bool(battle.sword_positive_mul):
				action_mul = SWORD_INTERRUPT_MUL
			else:
				action_mul = SWORD_CHARGE_MUL
		else:
			action = ACTION_SLASH
	var damage := compute_attack(int(battle.base_atk), action_mul, float(battle.atk_mul), float(battle.room_atk), phase_mul)
	var heal := 0
	if monster == MON_PRIEST:
		heal = _round_half_up(PRIEST_HEAL * float(battle.hp_mul) * float(battle.room_hp))
	var tax_op := ""
	var parity := ""
	if monster == MON_INK:
		tax_op = _taxed_op(turn)
	elif monster == MON_PARITY:
		parity = "ODD" if _wants_odd(turn) else "EVEN"
	var info: Dictionary = battle.intent if battle.intent is Dictionary else {}
	info["damage"] = damage
	info["action"] = action
	info["action_mul"] = action_mul
	info["beat"] = beat
	info["phase"] = int(battle.sword_phase) if monster == MON_SWORD else 1
	info["phase_mul"] = phase_mul
	info["heal"] = heal
	info["tax_op"] = tax_op
	info["parity"] = parity
	battle.intent = info
	battle.intent_damage = damage


static func _apply_sword_interrupt(battle) -> void:
	if str(battle.monster_id) != MON_SWORD:
		return
	if _beat_index(_player_turn(battle)) != 3:
		return
	if not bool(battle.sword_positive_add) or not bool(battle.sword_positive_mul):
		return
	var damage := compute_attack(
		int(battle.base_atk),
		SWORD_INTERRUPT_MUL,
		float(battle.atk_mul),
		float(battle.room_atk),
		float(battle.phase_mul),
	)
	battle.intent_damage = damage
	var info: Dictionary = battle.intent if battle.intent is Dictionary else {}
	info["damage"] = damage
	info["action_mul"] = SWORD_INTERRUPT_MUL
	battle.intent = info


static func _account_thief(battle, actual: int) -> void:
	if str(battle.monster_id) != MON_THIEF or actual <= 0:
		return
	if str(battle.stolen_card_uid) == "":
		return
	var ctx = battle._ctx() if battle.has_method("_ctx") else null
	if ctx == null or ctx.library == null:
		return
	var card = ctx.library.get_card(str(battle.stolen_card_uid))
	if card == null or card.zone != CardInstance.STOLEN:
		return
	battle.thief_progress = int(battle.thief_progress) + actual
	if int(battle.thief_progress) < _return_threshold(int(battle.enemy_max_hp)):
		return
	ctx.library.move(card, CardInstance.HAND, "THIEF_RETURN", str(battle.battle_uid), ctx)


static func _account_sword_phase(battle, hp_after: int) -> void:
	if str(battle.monster_id) != MON_SWORD:
		return
	if int(battle.sword_phase) >= 2:
		return
	if hp_after * 2 <= int(battle.enemy_max_hp):
		battle.sword_phase_pending = true


static func _return_threshold(max_hp: int) -> int:
	if max_hp <= 0:
		return 0
	return (max_hp * 30 + 99) / 100


static func _opening_pool(ctx) -> Array:
	var pool: Array = []
	for card in ctx.library.all_cards():
		if card == null:
			continue
		if card.zone == CardInstance.REMOVED or card.zone == CardInstance.COLLECTION or card.zone == CardInstance.STOLEN:
			continue
		pool.append(card)
	return pool


static func _rank_targets(cards: Array, catalog) -> Array:
	var ranked := cards.duplicate()
	for i in ranked.size():
		var best := i
		for j in range(i + 1, ranked.size()):
			if _rank_before(ranked[j], ranked[best], catalog):
				best = j
		if best != i:
			var swap = ranked[i]
			ranked[i] = ranked[best]
			ranked[best] = swap
	return ranked


static func _rank_before(a, b, catalog) -> bool:
	var a_marks := (a.enhancement_ids as Array).size()
	var b_marks := (b.enhancement_ids as Array).size()
	if a_marks != b_marks:
		return a_marks > b_marks
	var a_abs := absi(int(a.printed_value(catalog)))
	var b_abs := absi(int(b.printed_value(catalog)))
	if a_abs != b_abs:
		return a_abs > b_abs
	return str(a.card_uid) < str(b.card_uid)


static func _removal_leaves_a_fight(ctx, pool: Array, removed) -> bool:
	var numbers: Array = []
	var operators: Array = []
	for card in pool:
		if str(card.card_uid) == str(removed.card_uid):
			continue
		var def: Dictionary = ctx.catalog.card(card.def_id)
		var kind := str(def.get("card_kind", ""))
		if kind == "NUM":
			numbers.append(card)
		elif str(def.get("operator_code", "")) == "ADD" or str(def.get("operator_code", "")) == "MUL":
			operators.append(card)
	if numbers.size() < 2 or operators.is_empty():
		return false
	var scale := float(ctx.catalog.rule().get("damage_scale", 2.0))
	if scale <= 0.0:
		return false
	for op_card in operators:
		var op := str(ctx.catalog.card(op_card.def_id).get("operator_code", ""))
		for i in numbers.size():
			var left := _face_operand(ctx, numbers[i], op)
			for j in range(i + 1, numbers.size()):
				var right := _face_operand(ctx, numbers[j], op)
				var raw := left + right if op == "ADD" else left * right
				if raw <= 0:
					continue
				var scaled := float(raw) * scale
				if scaled > 0.0 and _round_half_up(scaled) > 0:
					return true
	return false


static func _face_operand(ctx, card, primary: String) -> int:
	var value := int(card.printed_value(ctx.catalog))
	if card.has_mark("EN_FLAMMABLE"):
		var params: Dictionary = ctx.catalog.enh("EN_FLAMMABLE").get("params", {})
		if primary == "MUL":
			value += int(params.get("mul_add", 0))
		elif primary == "ADD":
			value += int(params.get("add_add", 0))
	if card.has_mark("EN_ECHO"):
		value *= int(ctx.catalog.enh("EN_ECHO").get("params", {}).get("repeat", 1))
	return value


static func _player_turn(battle) -> int:
	return maxi(1, int(battle.turn_index))


static func _wants_odd(turn: int) -> bool:
	return turn % 2 == 1


static func _is_odd(value: int) -> bool:
	return absi(value) % 2 == 1


static func _taxed_op(turn: int) -> String:
	return "ADD" if turn % 2 == 1 else "MUL"


static func _beat_index(turn: int) -> int:
	return ((turn - 1) % 3) + 1


static func _round_half_up(value: float) -> int:
	return floori(value + 0.5)


static func _boss_phase2(battle) -> float:
	var fallback := _number(_battle_rule_row(), "boss_phase2_atk", 1.15)
	if battle == null or not battle.has_method("_ctx"):
		return fallback
	var ctx = battle._ctx()
	if ctx == null or ctx.catalog == null:
		return fallback
	var rule: Dictionary = ctx.catalog.rule()
	if rule.has("boss_phase2_atk"):
		return float(rule["boss_phase2_atk"])
	return fallback


static func _lookup_monster(monster_id: String) -> Dictionary:
	if GameData.loaded:
		var indexed := GameData.monster(monster_id)
		if not indexed.is_empty():
			return indexed
	for row in _file_rows(MONSTER_PATH):
		if row is Dictionary and str(row.get("monster_id", "")) == monster_id:
			return row
	return {}


static func _lookup_floor(floor: int) -> Dictionary:
	if GameData.loaded:
		var indexed := GameData.floor_config(floor)
		if not indexed.is_empty():
			return indexed
	for row in _file_rows(FLOOR_PATH):
		if row is Dictionary and int(row.get("floor", -1)) == floor:
			return row
	return {}


static func _battle_rule_row() -> Dictionary:
	var path := String(ConfigCatalog.CONFIG_DIR).path_join("battle_rule.json")
	for row in _file_rows(path):
		if row is Dictionary:
			return row
	return {}


static func _file_rows(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var rows = parsed.get("rows", [])
	return rows if rows is Array else []


static func _number(row: Dictionary, key: String, fallback: float) -> float:
	if row.has(key):
		return float(row[key])
	return fallback


static func _scaled_floor(floor: int) -> Dictionary:
	var n := float(floor - 1)
	var steps := float(floor - 10)
	var p0 := maxf(5.0, 10.0 - 0.5 * steps)
	var p2 := minf(70.0, 55.0 + 1.5 * steps)
	return {
		"hp_mul": 1.0 + 0.18 * n + 0.035 * n * n,
		"atk_mul": 1.0 + 0.075 * n + 0.01 * n * n,
		"p1": 100.0 - p0 - p2,
		"p2": p2,
	}


static func _fallback_monster(monster_id: String) -> Dictionary:
	match monster_id:
		MON_RUST:
			return {"name": "锈刃哥布林", "kind": "NORMAL", "base_hp": 60, "base_atk": 10, "min_floor": 1, "weight": 40}
		MON_PARITY:
			return {"name": "单目哥布林", "kind": "NORMAL", "base_hp": 70, "base_atk": 11, "min_floor": 1, "weight": 30}
		MON_INK:
			return {"name": "墨罐哥布林", "kind": "NORMAL", "base_hp": 66, "base_atk": 10, "min_floor": 1, "weight": 30}
		MON_PRIEST:
			return {"name": "深渊牧师", "kind": "NORMAL", "base_hp": 86, "base_atk": 10, "min_floor": 2, "weight": 20}
		MON_THIEF:
			return {"name": "拾荒盗贼", "kind": "NORMAL", "base_hp": 78, "base_atk": 12, "min_floor": 3, "weight": 15}
		MON_SWORD:
			return {"name": "守门剑士", "kind": "BOSS", "base_hp": 160, "base_atk": 16, "min_floor": 1, "weight": 100}
		_:
			return {}


static func _fallback_floor(floor: int) -> Dictionary:
	match floor:
		1:
			return {"hp_mul": 1.0, "atk_mul": 1.0, "p1": 24, "p2": 1}
		2:
			return {"hp_mul": 1.215, "atk_mul": 1.085, "p1": 32, "p2": 3}
		3:
			return {"hp_mul": 1.5, "atk_mul": 1.19, "p1": 38, "p2": 7}
		4:
			return {"hp_mul": 1.855, "atk_mul": 1.315, "p1": 42, "p2": 13}
		5:
			return {"hp_mul": 2.28, "atk_mul": 1.46, "p1": 44, "p2": 20}
		6:
			return {"hp_mul": 2.775, "atk_mul": 1.625, "p1": 44, "p2": 28}
		7:
			return {"hp_mul": 3.34, "atk_mul": 1.81, "p1": 42, "p2": 36}
		8:
			return {"hp_mul": 3.975, "atk_mul": 2.015, "p1": 40, "p2": 43}
		9:
			return {"hp_mul": 4.68, "atk_mul": 2.24, "p1": 37, "p2": 50}
		10:
			return {"hp_mul": 5.455, "atk_mul": 2.485, "p1": 35, "p2": 55}
		_:
			return {}
