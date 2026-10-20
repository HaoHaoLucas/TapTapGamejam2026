extends SceneTree

var _failures: int = 0
var _catalog: ConfigCatalog


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
	_catalog = ConfigCatalog.load_default()
	_check(_catalog.ok(), "Catalog failed: %s" % " | ".join(_catalog.errors))
	if _catalog.ok():
		_test_tables_and_rooms()
		_test_rust()
		_test_thief()
		_test_sword()
		_test_ink()
		_test_priest()
		_test_parity()
	if _failures == 0:
		print("PASS: rust 22, thief 23/24, sword intents, ink, parity")
	else:
		push_error("monster rules failures: %s" % _failures)
	quit(1 if _failures else 0)


func _fresh(seed: int, run_id: String) -> RunContext:
	return RunContext.new(_catalog, seed, run_id)


func _make(run: RunContext, def_id: String, marks: Array, zone: String) -> CardInstance:
	var card := run.library.create_instance(def_id, marks, run.depth, "")
	_check(card != null, "Could not create %s" % def_id)
	if card != null and zone != CardInstance.RUN_DECK:
		run.library.move(card, zone, "SETUP", "setup", run)
	return card


func _commit(run: RunContext, cards: Array, action_uid: String) -> Dictionary:
	var uids: Array = []
	for card in cards:
		uids.append(card.card_uid)
	return run.equation_service.commit(uids, action_uid, {})


func _attach(run: RunContext, monster_id: String, floor: int, room_hp: float, room_atk: float) -> CardBattle:
	run.depth = floor
	var battle := CardBattle.new(run)
	run.battle = battle
	MonsterRules.attach(battle, monster_id, floor, room_hp, room_atk)
	return battle


func _seed_fight(run: RunContext) -> void:
	_make(run, "CARD_N1", [], CardInstance.DRAW)
	_make(run, "CARD_N2", [], CardInstance.DRAW)
	_make(run, "CARD_ADD", [], CardInstance.DRAW)
	_make(run, "CARD_MUL", [], CardInstance.DRAW)


func _play_add(run: RunContext, action_uid: String) -> Dictionary:
	return _commit(run, [
		_make(run, "CARD_N3", [], CardInstance.HAND),
		_make(run, "CARD_ADD", [], CardInstance.HAND),
		_make(run, "CARD_N1", [], CardInstance.HAND),
	], action_uid)


func _play_mul(run: RunContext, action_uid: String) -> Dictionary:
	return _commit(run, [
		_make(run, "CARD_N2", [], CardInstance.HAND),
		_make(run, "CARD_MUL", [], CardInstance.HAND),
		_make(run, "CARD_N2", [], CardInstance.HAND),
	], action_uid)


func _test_tables_and_rooms() -> void:
	for encounter_id in ["ENC_RUST", "ENC_PARITY", "ENC_INK", "ENC_PRIEST", "ENC_THIEF", "ENC_SWORD"]:
		var row := GameData.monster_for_encounter(encounter_id)
		_check(str(row.get("monster_id", "")) == MonsterRules.monster_id_for_encounter(encounter_id), "Encounter %s uses the monster table" % encounter_id)
	var floor := GameData.floor_config(1)
	var loaded := MonsterRules.load_floor(1)
	_check(is_equal_approx(float(loaded.get("hp_mul", 0.0)), float(floor.get("hp_mul", -1.0))), "Floor 1 hp multiplier comes from floor_config")
	_check(is_equal_approx(float(loaded.get("atk_mul", 0.0)), float(floor.get("atk_mul", -1.0))), "Floor 1 atk multiplier comes from floor_config")
	var first := MonsterRules.room_multipliers("NORMAL", 1)
	var second := MonsterRules.room_multipliers("NORMAL", 2)
	var boss := MonsterRules.room_multipliers("BOSS", 2)
	_check(is_equal_approx(float(first.hp), 1.0) and is_equal_approx(float(first.atk), 1.0), "The first normal fight stays 1/1")
	_check(is_equal_approx(float(second.hp), 1.1) and is_equal_approx(float(second.atk), 1.05), "The second normal fight uses 1.1 hp and 1.05 atk")
	_check(is_equal_approx(float(boss.hp), 1.0) and is_equal_approx(float(boss.atk), 1.0), "A boss ignores the second-room multipliers")


func _test_rust() -> void:
	var run := _fresh(3, "rust")
	var battle := _attach(run, MonsterRules.MON_RUST, 1, 1.0, 1.0)
	var hp := int(battle.enemy_hp)
	var intent := int(battle.intent_damage)
	_check(hp == 60 and intent == 10, "Rust attaches at 60 hp and intent 10, got %s/%s" % [hp, intent])
	battle.start(0, 0, false, 80)
	_check(battle.enemy_hp == hp and battle.enemy_max_hp == hp and battle.intent_damage == intent, "Start keeps the attached hp and intent")
	_check(battle.player_hp == 80, "Start uses the player hp argument")
	var long := _commit(run, [
		_make(run, "CARD_N2", [], CardInstance.HAND),
		_make(run, "CARD_ADD", [], CardInstance.HAND),
		_make(run, "CARD_N3", [], CardInstance.HAND),
		_make(run, "CARD_ADD", [], CardInstance.HAND),
		_make(run, "CARD_N4", [], CardInstance.HAND),
	], "rust_long")
	_check(long.ok and int(long.raw_result) == 9 and int(long.damage) == 22, "Rust 2+3+4 deals 22, got %s" % long)
	var short := _commit(run, [
		_make(run, "CARD_N3", [], CardInstance.HAND),
		_make(run, "CARD_ADD", [], CardInstance.HAND),
		_make(run, "CARD_N4", [], CardInstance.HAND),
	], "rust_short")
	_check(short.ok and int(short.damage) == 14, "A short rust equation stays 14, got %s" % short)


func _test_thief() -> void:
	var run := _fresh(4, "thief")
	run.library.create_starter()
	var battle := _attach(run, MonsterRules.MON_THIEF, 1, 1.0, 1.0)
	_check(battle.enemy_max_hp == 78 and battle.enemy_hp == 78, "Thief max hp is 78, got %s" % battle.enemy_max_hp)
	MonsterRules.detain_opening(run, battle)
	var stolen := str(battle.stolen_card_uid)
	_check(stolen != "" and run.library.get_card(stolen).zone == CardInstance.STOLEN, "Thief detains a card before the deal")
	var hp := int(battle.enemy_hp)
	var intent := int(battle.intent_damage)
	battle.start(0, 0, true, 100)
	_check(battle.enemy_hp == hp and battle.intent_damage == intent, "Start keeps the thief hp and intent")
	_check(run.library.get_card(stolen).zone == CardInstance.STOLEN, "The detained card is not dealt")
	_check(not run.library.pile(CardInstance.HAND).has(stolen), "The detained card is not in hand")
	MonsterRules.note_legal_equation(battle, "ADD", 23, 23, false)
	battle.apply_damage(23)
	_check(int(battle.thief_progress) == 23 and run.library.get_card(stolen).zone == CardInstance.STOLEN, "23 damage does not return the card")
	MonsterRules.note_legal_equation(battle, "ADD", 1, 1, false)
	_check(int(battle.thief_progress) == 24 and run.library.get_card(stolen).zone == CardInstance.HAND, "24 damage returns the same uid")
	_check(run.library.get_card(stolen).card_uid == stolen, "The returned card keeps its uid")
	var overflow := _fresh(5, "thief_over")
	overflow.library.create_starter()
	var over_battle := _attach(overflow, MonsterRules.MON_THIEF, 1, 1.0, 1.0)
	MonsterRules.detain_opening(overflow, over_battle)
	var over_uid := str(over_battle.stolen_card_uid)
	over_battle.start(0, 0, false, 100)
	over_battle.enemy_hp = 10
	MonsterRules.note_legal_equation(over_battle, "ADD", 100, 100, false)
	over_battle.apply_damage(100)
	_check(int(over_battle.thief_progress) == 10 and overflow.library.get_card(over_uid).zone == CardInstance.STOLEN, "Damage past the remaining hp does not count")
	MonsterRules.note_legal_equation(over_battle, "ADD", 50, 50, false)
	_check(int(over_battle.thief_progress) == 10 and over_battle.enemy_hp == 0, "Overflow past 0 hp does not add progress")


func _test_sword() -> void:
	var phase1 := _fresh(6, "sword1")
	var battle := _attach(phase1, MonsterRules.MON_SWORD, 1, 1.0, 1.0)
	var hp := int(battle.enemy_hp)
	var opening := int(battle.intent_damage)
	battle.start(0, 0, false, 100)
	_seed_fight(phase1)
	_check(battle.enemy_hp == hp and battle.enemy_max_hp == 160, "Start keeps the sword's 160 hp")
	_check(opening == 16 and battle.intent_damage == 16 and str(battle.intent.get("action", "")) == "SLASH", "Floor 1 opens with slash 16")
	battle.end_player_turn()
	_check(battle.intent_damage == 16 and str(battle.intent.get("action", "")) == "SLASH", "The second beat slashes for 16")
	battle.end_player_turn()
	_check(battle.turn_index == 3 and battle.intent_damage == 28 and str(battle.intent.get("action", "")) == "CHARGE", "The third beat charges for 28, got %s" % battle.intent_damage)
	_check(_play_add(phase1, "sword_add").ok and battle.intent_damage == 28, "One positive add does not interrupt the charge")
	_check(_play_mul(phase1, "sword_mul").ok and battle.intent_damage == 12, "Add and mul interrupt the charge to 12, got %s" % battle.intent_damage)
	_check(int(battle.sword_phase) == 1, "Small hits do not change the phase")
	var phase2 := _fresh(7, "sword2")
	var later := _attach(phase2, MonsterRules.MON_SWORD, 1, 1.0, 1.0)
	later.start(0, 0, false, 100)
	_seed_fight(phase2)
	var burst := _commit(phase2, [
		_make(phase2, "CARD_N5", ["EN_ECHO"], CardInstance.HAND),
		_make(phase2, "CARD_MUL", [], CardInstance.HAND),
		_make(phase2, "CARD_N5", [], CardInstance.HAND),
	], "sword_burst")
	_check(burst.ok and int(burst.damage) == 100, "The phase probe deals 100, got %s" % burst)
	_check(later.enemy_hp == 60 and later.intent_damage == 16 and int(later.sword_phase) == 1 and later.sword_phase_pending, "Crossing 50% hp keeps the announced 16")
	later.end_player_turn()
	_check(phase2.battle.player_hp == 84, "The announced slash still hits for 16, got %s" % phase2.battle.player_hp)
	_check(later.sword_phase == 2 and later.intent_damage == 18 and str(later.intent.get("action", "")) == "SLASH", "The next slash is 18, got %s" % later.intent_damage)
	later.end_player_turn()
	_check(later.turn_index == 3 and later.intent_damage == 32 and str(later.intent.get("action", "")) == "CHARGE", "Phase 2 charges for 32, got %s" % later.intent_damage)
	_check(_play_add(phase2, "sword2_add").ok and later.intent_damage == 32, "Phase 2 waits for both primaries")
	_check(_play_mul(phase2, "sword2_mul").ok and later.intent_damage == 14, "Phase 2 interrupt is 14, got %s" % later.intent_damage)


func _test_ink() -> void:
	var run := _fresh(8, "ink")
	var battle := _attach(run, MonsterRules.MON_INK, 1, 1.0, 1.0)
	battle.start(0, 0, false, 100)
	_seed_fight(run)
	var left := _make(run, "CARD_N3", [], CardInstance.HAND)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var right := _make(run, "CARD_N4", [], CardInstance.HAND)
	var preview := run.equation_service.preview([left.card_uid, op.card_uid, right.card_uid], {})
	_check(int(preview.damage) == 6 and int(preview.effective_result) == 3 and not battle.ink_tax_used, "Ink preview halves toward zero without spending the tax")
	var illegal := run.equation_service.commit([left.card_uid], "ink_bad", {})
	_check(not illegal.ok and not battle.ink_tax_used, "An illegal equation does not spend the ink tax")
	var first := _commit(run, [left, op, right], "ink_add")
	_check(first.ok and int(first.damage) == 6 and battle.ink_tax_used, "The first legal equation pays division tax, got %s" % first)
	var replay := _commit(run, [left, op, right], "ink_add")
	_check(replay.replayed and replay.damage == first.damage, "Replaying a committed equation cannot charge tax twice")
	var second := _commit(run, [
		_make(run, "CARD_N3", [], CardInstance.HAND),
		_make(run, "CARD_ADD", [], CardInstance.HAND),
		_make(run, "CARD_N4", [], CardInstance.HAND),
	], "ink_add2")
	_check(second.ok and int(second.damage) == 14, "The second add is not taxed, got %s" % second)
	battle.end_player_turn()
	_check(battle.phase == "COMBO", "Two taxed adds still open the combo window")
	battle.advance(battle.combo_window + 0.05)
	var multiplied := _commit(run, [
		_make(run, "CARD_N3", [], CardInstance.HAND),
		_make(run, "CARD_MUL", [], CardInstance.HAND),
		_make(run, "CARD_N4", [], CardInstance.HAND),
	], "ink_mul")
	_check(battle.turn_index == 2 and multiplied.ok and int(multiplied.damage) == 20, "Turn 2 taxes the first multiply, got %s" % multiplied)
	for values in [["CARD_N2", "CARD_N3", 5, 2], ["CARD_NM2", "CARD_NM3", -5, -2], ["CARD_N1", "CARD_NM1", 0, 0]]:
		var edge := _fresh(81, "ink_edge_" + str(values[2]))
		var edge_battle := _attach(edge, MonsterRules.MON_INK, 1, 1.0, 1.0)
		edge_battle.start(0, 0, false, 100)
		_seed_fight(edge)
		var cards := [_make(edge, values[0], [], CardInstance.HAND), _make(edge, "CARD_ADD", [], CardInstance.HAND), _make(edge, values[1], [], CardInstance.HAND)]
		var result := _commit(edge, cards, "edge")
		_check(result.raw_result == values[2] and result.effective_result == values[3] and edge_battle.ink_tax_used, "Division tax truncates positive/negative/zero and consumes once: %s" % result)
		edge_battle.advance(7.5)
		_check(edge_battle.turn_index == 1 and edge_battle.ink_tax_used, "Delayed draw does not reset the tax")
	var mixed := _fresh(82, "ink_mixed")
	var mixed_battle := _attach(mixed, MonsterRules.MON_INK, 1, 1.0, 1.0)
	mixed_battle.start(0, 0, false, 100)
	_seed_fight(mixed)
	var mixed_result := _commit(mixed, [_make(mixed, "CARD_N1", [], CardInstance.HAND), _make(mixed, "CARD_ADD", [], CardInstance.HAND), _make(mixed, "CARD_N2", [], CardInstance.HAND), _make(mixed, "CARD_MUL", [], CardInstance.HAND), _make(mixed, "CARD_N3", [], CardInstance.HAND)], "mixed")
	_check(mixed_result.primary_op == "MUL" and mixed_result.raw_result == 7 and mixed_result.effective_result == 3, "Odd turn halves mixed multiplication-primary equations too")
	mixed_battle.end_player_turn()
	_check(not mixed_battle.ink_tax_used and mixed_battle.intent.tax_mode == "MUL_SUBTRACT", "Turn boundary resets tax and publishes multiplication mode")
	var untaxed := _play_add(mixed, "even_add")
	_check(untaxed.damage == 8 and not mixed_battle.ink_tax_used, "Even-turn addition does not consume multiplication tax")
	var even_cards := [_make(mixed, "CARD_N1", [], CardInstance.HAND), _make(mixed, "CARD_ADD", [], CardInstance.HAND), _make(mixed, "CARD_N2", [], CardInstance.HAND), _make(mixed, "CARD_MUL", [], CardInstance.HAND), _make(mixed, "CARD_N3", [], CardInstance.HAND)]
	var even_uids: Array = []
	for card in even_cards:
		even_uids.append(card.card_uid)
	var even_preview := mixed.equation_service.preview(even_uids)
	var taxed := _commit(mixed, even_cards, "even_mixed")
	_check(taxed.primary_op == "MUL" and taxed.damage == 10 and even_preview.damage == taxed.damage and mixed_battle.ink_tax_used, "Even-turn mixed multiplication primary subtracts two, consistent with preview")
	var snapshot := _fresh(83, "ink_flat_then_half")
	var snapshot_battle := _attach(snapshot, MonsterRules.MON_INK, 1, 1.0, 1.0)
	snapshot_battle.start(0, 0, false, 100)
	var a := _make(snapshot, "CARD_N3", [], CardInstance.HAND)
	var plus := _make(snapshot, "CARD_ADD", [], CardInstance.HAND)
	var b := _make(snapshot, "CARD_N4", [], CardInstance.HAND)
	var combined := snapshot.equation_service.preview([a.card_uid, plus.card_uid, b.card_uid], {"tax": 2})
	_check(combined.effective_result == 2 and combined.damage == 4, "Flat subtraction precedes division, then normal damage scaling")


func _test_priest() -> void:
	var run := _fresh(84, "priest_forms")
	var battle := _attach(run, MonsterRules.MON_PRIEST, 1, 1.0, 1.0)
	battle.start(0, 0, false, 100)
	_seed_fight(run)
	_check(not battle.priest_heal_cancelled, "Priest begins ready to heal")
	var result := _commit(run, [_make(run, "CARD_NM1", [], CardInstance.HAND), _make(run, "CARD_ADD", [], CardInstance.HAND), _make(run, "CARD_N3", [], CardInstance.HAND)], "cancel_heal")
	_check(result.damage > 0 and battle.priest_heal_cancelled, "Damaging equation containing a negative printed card cancels healing")
	var wounded := battle.enemy_hp
	battle.end_player_turn()
	_check(battle.enemy_hp == wounded and not battle.priest_heal_cancelled and battle.turn_index == 2, "Cancelled heal stays cancelled until next turn, then resets")


func _test_parity() -> void:
	var run := _fresh(9, "parity")
	var battle := _attach(run, MonsterRules.MON_PARITY, 1, 1.0, 1.0)
	battle.start(0, 0, false, 100)
	_check(str(battle.intent.get("parity", "")) == "ODD", "Turn 1 wants an odd result")
	var zero := _commit(run, [
		_make(run, "CARD_N1", [], CardInstance.HAND),
		_make(run, "CARD_ADD", [], CardInstance.HAND),
		_make(run, "CARD_NM1", [], CardInstance.HAND),
	], "parity_zero")
	_check(zero.ok and int(zero.raw_result) == 0 and int(zero.damage) == 0, "Zero is even and still deals 0, got %s" % zero)
	_check(is_equal_approx(float(zero.damage_coefficient), 0.7), "A zero on an odd turn still mismatches")
	var odd := _commit(run, [
		_make(run, "CARD_N3", [], CardInstance.HAND),
		_make(run, "CARD_ADD", [], CardInstance.HAND),
		_make(run, "CARD_N4", [], CardInstance.HAND),
	], "parity_odd")
	_check(odd.ok and int(odd.damage) == 14, "A matching odd result stays 14, got %s" % odd)
	var even := _commit(run, [
		_make(run, "CARD_N2", [], CardInstance.HAND),
		_make(run, "CARD_ADD", [], CardInstance.HAND),
		_make(run, "CARD_N2", [], CardInstance.HAND),
	], "parity_even")
	_check(even.ok and int(even.damage) == 6, "An even result on turn 1 is reduced to 6, got %s" % even)
