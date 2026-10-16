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
	_catalog = ConfigCatalog.load_default()
	_check(_catalog.ok(), "Catalog failed: %s" % " | ".join(_catalog.errors))
	if _catalog.ok():
		_test_config_and_starter()
		_test_c01_plain_add()
		_test_c02_signed_value()
		_test_c03_echo()
		_test_c04_yinyang()
		_test_c05_c06_c07_flammable()
		_test_c08_c09_burn()
		_test_c10_echo_yinyang()
		_test_c11_tax()
		_test_c12_coefficient()
		_test_illegal_and_replay()
		_test_return_zero_is_not_draw()
		_test_marks_copy_transform_sacrifice()
		_test_e01_magnet()
		_test_e02_ghosts()
		_test_e03_frozen()
		_test_e04_flags_persist()
		_test_e05_fragile_before_return()
		_test_e06_victory_before_exhaustion()
		_test_e07_alchemy_price()
		_test_e08_preview_rng()
		_test_combo_and_vanguard()
		_test_draw_clock()
		_test_hand_composition()
		await _test_card_view_and_lab()
	await process_frame
	if _failures == 0:
		print("PASS: card rules C01-C12, E01-E08, 5+1 draw, hand mix, starter, preview RNG")
	else:
		push_error("card rules failures: %s" % _failures)
	quit(1 if _failures else 0)


func _fresh(seed: int, run_id: String) -> RunContext:
	return RunContext.new(_catalog, seed, run_id)


func _make(run: RunContext, def_id: String, marks: Array, zone: String) -> CardInstance:
	var card := run.library.create_instance(def_id, marks, run.depth, "")
	_check(card != null, "Could not create %s %s" % [def_id, marks])
	if card != null and zone != CardInstance.RUN_DECK:
		run.library.move(card, zone, "SETUP", "setup", run)
	return card


func _commit(run: RunContext, cards: Array, action_uid: String, snapshot: Dictionary = {}) -> Dictionary:
	var uids: Array = []
	for card in cards:
		uids.append(card.card_uid)
	return run.equation_service.commit(uids, action_uid, snapshot)


func _fill_hand_and_draw(run: RunContext) -> void:
	while run.library.normal_hand_count() < 6:
		_make(run, "CARD_N0", [], CardInstance.HAND)
	for _deck in 3:
		_make(run, "CARD_N1", [], CardInstance.DRAW)


func _fragile_break_seed() -> int:
	var chance := float(_catalog.enh("EN_FRAGILE").params.break_p)
	for seed in range(1, 400):
		var probe := _fresh(seed, "probe")
		if probe.rng_of("COMBAT").randf() < chance:
			return seed
	return -1


func _test_config_and_starter() -> void:
	_check(_catalog.config_version == "jam_1.2.0", "Config version must be jam_1.2.0")
	_check(str(_catalog.rule().get("ruleset_id", "")) == "RULE_JAM_10S", "Ruleset stays RULE_JAM_10S")
	_check(_catalog.rows("enhancement_def").size() == 16, "Enhancement table must have 16 rows")
	_check(not _catalog.rule().has("hand_target"), "hand_target is gone")
	_check(int(_catalog.rule().get("turn_start_draw", 0)) == 5, "Turn start draws 5")
	_check(is_equal_approx(float(_catalog.rule().get("delayed_draw_at", 0.0)), 7.5), "Delayed draw is at 7.5s")
	_check(int(_catalog.rule().get("delayed_draw_count", 0)) == 1, "Delayed draw count is 1")
	_check(int(_catalog.rule().get("hand_limit", -1)) == 0, "Hand limit is 0")
	_check(is_equal_approx(float(_catalog.rule().damage_scale), 2.0), "Damage scale must be 2")
	_check(int(_catalog.rule().max_equation_damage) == 2000000, "Damage cap must be 2000000")
	_check(int(_catalog.enh("EN_NUM1").params.add) == 1, "EN_NUM1 adds 1")
	_check(int(_catalog.enh("EN_NUM2").params.add) == 2, "EN_NUM2 adds 2")
	_check(int(_catalog.enh("EN_NUM3").params.add) == 3, "EN_NUM3 adds 3")
	_check(int(_catalog.enh("EN_FRAGILE").params.add) == 3, "Fragile adds 3")
	_check(is_equal_approx(float(_catalog.enh("EN_FRAGILE").params.break_p), 0.15), "Fragile chance is 0.15")
	_check(int(_catalog.enh("EN_ALCHEMY").slot_cost) == 0, "Alchemy costs no slot")
	_check(not EnhancementRegistry.normal_drop_allowed("EN_ALCHEMY"), "Alchemy is excluded from normal drops")
	_check(not EnhancementRegistry.normal_drop_allowed("EN_FROZEN"), "Frozen is excluded from normal drops")
	for enh_id in ["EN_NUM1", "EN_ECHO", "EN_RETURN", "EN_PRICE", "EN_VANGUARD"]:
		_check(str(_catalog.enh(enh_id).handler_id) == enh_id, "Handler id must equal enh id %s" % enh_id)
	var total := 0
	for row in _catalog.starter_rows():
		total += int(row.starter_count)
	_check(total == 15, "STARTER_JAM counts must sum to 15")
	var run := _fresh(1, "starter")
	var cards := run.library.create_starter()
	_check(cards.size() == 15, "Starter must create 15 entities")
	var uids := {}
	var defs := {}
	for card in cards:
		_check(not uids.has(card.card_uid), "Starter uids must be unique")
		uids[card.card_uid] = true
		defs[card.def_id] = int(defs.get(card.def_id, 0)) + 1
		_check(card.zone == CardInstance.RUN_DECK, "Starter cards begin in RUN_DECK")
	_check(int(defs.get("CARD_ADD", 0)) == 2 and int(defs.get("CARD_MUL", 0)) == 2, "Starter has two ADD and two MUL")
	_check(defs.size() == 13, "Starter uses 11 numbers plus ADD and MUL")
	var seeds := {}
	for stream_name in RunContext.STREAMS:
		var stream := run.rng_of(stream_name)
		_check(stream.seed_value == CardRng.derive_seed(1, stream_name), "Stream seed must match SHA-256 derivation")
		_check(not seeds.has(stream.seed_value), "The five streams must have distinct seeds")
		seeds[stream.seed_value] = stream_name
	var numbered := _make(run, "CARD_N5", [], CardInstance.HAND)
	_check(numbered.printed_value(_catalog) == 5, "Printed value starts at the base")
	run.card_service.apply_mark(numbered.card_uid, "EN_NUM1", "starter_mark")
	_check(numbered.printed_value(_catalog) == 6, "Printed value is recomputed from the current mark")


func _test_c01_plain_add() -> void:
	var run := _fresh(2, "c01")
	var left := _make(run, "CARD_N3", [], CardInstance.HAND)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var right := _make(run, "CARD_N4", [], CardInstance.HAND)
	for _stay in 3:
		_make(run, "CARD_N0", [], CardInstance.HAND)
	for _deck in 3:
		_make(run, "CARD_N1", [], CardInstance.DRAW)
	var state := run.rng_of("COMBAT").state()
	var heard: Array = []
	run.equation_committed.connect(func(_equation_uid, _uids, _motifs, primary, effective, damage, kind) -> void:
		heard.append({"primary": primary, "effective": effective, "damage": damage, "kind": kind})
	)
	var result := _commit(run, [left, op, right], "c01")
	_check(result.ok and result.raw_result == 7 and result.effective_result == 7 and result.damage == 14, "C01 must be 7 and 14 damage, got %s" % result)
	_check(result.primary_op == "ADD", "C01 primary op is ADD")
	_check(left.zone == CardInstance.DISCARD and op.zone == CardInstance.DISCARD and right.zone == CardInstance.DISCARD, "C01 played cards go to discard")
	_check(result.draws.is_empty(), "C01 does not refill the played cards")
	_check(run.library.pile(CardInstance.HAND).size() == 3, "C01 leaves the three unplayed cards")
	_check(run.library.pile(CardInstance.DRAW).size() == 3, "C01 leaves the draw pile alone")
	_check(run.rng_of("COMBAT").state() == state, "C01 does not roll combat RNG")
	_check(heard.size() == 1 and heard[0].damage == 14 and heard[0].kind == "EQUATION", "C01 emits equation_committed once")
	var replay := _commit(run, [left, op, right], "c01")
	_check(replay.replayed and replay.damage == 14, "Duplicate action uid replays the commit")
	_check(heard.size() == 1, "Replay must not emit equation_committed again")
	_check(run.library.pile(CardInstance.DISCARD).size() == 3, "Replay must not discard again")


func _test_c02_signed_value() -> void:
	var run := _fresh(3, "c02")
	var left := _make(run, "CARD_NM5", ["EN_NUM3"], CardInstance.HAND)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var right := _make(run, "CARD_N4", [], CardInstance.HAND)
	_check(left.printed_value(_catalog) == -2, "C02 printed value is -2")
	var result := _commit(run, [left, op, right], "c02")
	_check(result.raw_result == 2 and result.damage == 4, "C02 damage must be 4, got %s" % result)


func _test_c03_echo() -> void:
	var run := _fresh(4, "c03")
	var left := _make(run, "CARD_N3", ["EN_ECHO"], CardInstance.HAND)
	var op := _make(run, "CARD_MUL", [], CardInstance.HAND)
	var right := _make(run, "CARD_N4", [], CardInstance.HAND)
	var before := run.library.card_count()
	var result := _commit(run, [left, op, right], "c03")
	_check(result.operands == [6, 4] and result.raw_result == 24 and result.damage == 48, "C03 must be 6×4 for 48, got %s" % result)
	_check(result.ordered_uids.size() == 3 and run.library.card_count() == before, "Echo does not create a card")


func _test_c04_yinyang() -> void:
	var run := _fresh(5, "c04")
	var left := _make(run, "CARD_N3", ["EN_YINYANG"], CardInstance.HAND)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var right := _make(run, "CARD_N4", ["EN_YINYANG"], CardInstance.HAND)
	var result := _commit(run, [left, op, right], "c04")
	_check(result.yinyang and result.damage == 28, "C04 yinyang damage must be 28, got %s" % result)
	var echo := _fresh(5, "c04b")
	var echoed := _make(echo, "CARD_N3", ["EN_ECHO", "EN_YINYANG"], CardInstance.HAND)
	var times := _make(echo, "CARD_MUL", [], CardInstance.HAND)
	var plain := _make(echo, "CARD_N4", [], CardInstance.HAND)
	var single := _commit(echo, [echoed, times, plain], "c04b")
	_check(not single.yinyang and single.damage == 48, "One echoed yinyang card is not a second uid, got %s" % single)


func _test_c05_c06_c07_flammable() -> void:
	var mul_run := _fresh(6, "c05")
	var mul_card := _make(mul_run, "CARD_N3", ["EN_FLAMMABLE"], CardInstance.HAND)
	var mul_op := _make(mul_run, "CARD_MUL", [], CardInstance.HAND)
	var mul_right := _make(mul_run, "CARD_N4", [], CardInstance.HAND)
	var mul_result := _commit(mul_run, [mul_card, mul_op, mul_right], "c05")
	_check(mul_result.primary_op == "MUL" and mul_result.raw_result == 32 and mul_result.damage == 64, "C05 must be 64, got %s" % mul_result)
	_check(mul_card.printed_value(_catalog) == 3, "Flammable must not write printed value")
	var add_run := _fresh(6, "c06")
	var add_card := _make(add_run, "CARD_N3", ["EN_FLAMMABLE"], CardInstance.HAND)
	var add_op := _make(add_run, "CARD_ADD", [], CardInstance.HAND)
	var add_right := _make(add_run, "CARD_N4", [], CardInstance.HAND)
	var add_result := _commit(add_run, [add_card, add_op, add_right], "c06")
	_check(add_result.primary_op == "ADD" and add_result.raw_result == 4 and add_result.damage == 8, "C06 must be 8, got %s" % add_result)
	_check(add_card.printed_value(_catalog) == 3, "C06 printed value stays 3")
	var tie := _fresh(6, "c07")
	var tie_card := _make(tie, "CARD_N3", ["EN_FLAMMABLE"], CardInstance.HAND)
	var tie_add := _make(tie, "CARD_ADD", [], CardInstance.HAND)
	var tie_two := _make(tie, "CARD_N2", [], CardInstance.HAND)
	var tie_mul := _make(tie, "CARD_MUL", [], CardInstance.HAND)
	var tie_four := _make(tie, "CARD_N4", [], CardInstance.HAND)
	var tie_result := _commit(tie, [tie_card, tie_add, tie_two, tie_mul, tie_four], "c07")
	_check(tie_result.primary_op == "MUL" and tie_result.raw_result == 16 and tie_result.damage == 32, "C07 rightmost MUL must deal 32, got %s" % tie_result)


func _test_c08_c09_burn() -> void:
	var run := _fresh(7, "c08")
	run.start_battle(100, 8, false, 80)
	var card := _make(run, "CARD_NM2", ["EN_FRAGILE"], CardInstance.HAND)
	_check(card.printed_value(_catalog) == 1, "C08 printed value is 1")
	var state := run.rng_of("COMBAT").state()
	var result := run.card_service.burn(card.card_uid, "c08")
	_check(result.ok and result.heal_delta == 10 and run.battle.player_hp == 90, "C08 heals 10 to 90, got %s" % result)
	_check(result.removed and card.zone == CardInstance.REMOVED, "Ordinary burn removes the card")
	_check(run.rng_of("COMBAT").state() == state, "Burn does not roll fragile")
	var full := _fresh(7, "c08full")
	full.start_battle(100, 8, false, 100)
	var full_card := _make(full, "CARD_N2", [], CardInstance.HAND)
	var full_result := full.card_service.burn(full_card.card_uid, "full")
	_check(full_result.ok and full_result.heal_delta == 0 and full_result.removed, "Full HP burn still consumes the card")
	var op_run := _fresh(7, "c08op")
	op_run.start_battle(100, 8, false, 50)
	var op_card := _make(op_run, "CARD_ADD", [], CardInstance.HAND)
	var op_result := op_run.card_service.burn(op_card.card_uid, "op")
	_check(op_result.ok and op_result.heal_delta == 0 and op_result.removed and op_run.battle.player_hp == 50, "Operator burn heals 0")
	var smolder := _fresh(8, "c09")
	smolder.start_battle(100, 8, false, 20)
	var stay := _make(smolder, "CARD_N4", ["EN_SMOLDER"], CardInstance.HAND)
	var first := smolder.card_service.burn(stay.card_uid, "c09a")
	_check(first.heal_delta == 40 and first.smolder_flag and not first.removed and stay.zone == CardInstance.HAND, "C09 first burn stays, got %s" % first)
	_check(smolder.battle.player_hp == 60 and stay.smolder_used_run, "C09 first burn reaches 60 and spends the charge")
	var second := smolder.card_service.burn(stay.card_uid, "c09b")
	_check(second.heal_delta == 40 and second.removed and stay.zone == CardInstance.REMOVED, "C09 second burn removes, got %s" % second)
	_check(smolder.battle.player_hp == 100, "C09 second burn reaches 100")


func _test_c10_echo_yinyang() -> void:
	var run := _fresh(9, "c10")
	var left := _make(run, "CARD_N3", ["EN_ECHO", "EN_YINYANG"], CardInstance.HAND)
	var op := _make(run, "CARD_MUL", [], CardInstance.HAND)
	var right := _make(run, "CARD_N4", ["EN_YINYANG"], CardInstance.HAND)
	var before := run.library.card_count()
	var result := _commit(run, [left, op, right], "c10")
	_check(result.operands[0] == 6 and result.raw_result == 24 and result.yinyang and result.damage == 96, "C10 damage must be 96, got %s" % result)
	_check(run.library.card_count() == before, "C10 echo stays one entity")


func _test_c11_tax() -> void:
	var run := _fresh(10, "c11")
	var left := _make(run, "CARD_N5", ["EN_YINYANG"], CardInstance.HAND)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var right := _make(run, "CARD_N4", ["EN_YINYANG"], CardInstance.HAND)
	var before := left.printed_value(_catalog)
	var result := _commit(run, [left, op, right], "c11", {"tax": 2})
	_check(result.raw_result == 9 and result.effective_result == 7 and result.damage == 28, "C11 taxed yinyang damage must be 28, got %s" % result)
	_check(left.printed_value(_catalog) == before, "Tax must not write the card")


func _test_c12_coefficient() -> void:
	var run := _fresh(11, "c12")
	var first := [
		_make(run, "CARD_N3", [], CardInstance.HAND),
		_make(run, "CARD_ADD", [], CardInstance.HAND),
		_make(run, "CARD_N4", [], CardInstance.HAND),
	]
	var second := [
		_make(run, "CARD_N3", [], CardInstance.HAND),
		_make(run, "CARD_ADD", [], CardInstance.HAND),
		_make(run, "CARD_N4", [], CardInstance.HAND),
	]
	var taxed := _commit(run, first, "c12a", {"damage_coefficient": 0.6})
	_check(taxed.damage == 8, "C12 14×0.6 must round to 8, got %s" % taxed)
	var fresh := _commit(run, second, "c12b", {"damage_coefficient": 1.0})
	_check(fresh.damage == 14, "The next output must read the new coefficient, got %s" % fresh)


func _test_illegal_and_replay() -> void:
	var run := _fresh(12, "bad")
	var card := _make(run, "CARD_N3", [], CardInstance.HAND)
	var state := run.rng_of("COMBAT").state()
	var result := run.equation_service.commit([card.card_uid], "bad", {})
	_check(not result.ok and result.reason_code == "LENGTH", "A short formula is illegal")
	_check(card.zone == CardInstance.HAND and run.rng_of("COMBAT").state() == state, "Illegal formula consumes nothing and no RNG")
	var again := run.equation_service.commit([card.card_uid, card.card_uid, card.card_uid], "bad", {})
	_check(again.replayed and card.zone == CardInstance.HAND, "The same action uid does not play a new formula")


func _test_return_zero_is_not_draw() -> void:
	var run := _fresh(13, "ret")
	run.library.turn_index = 1
	var returned := _make(run, "CARD_N0", ["EN_RETURN", "EN_MAGNET"], CardInstance.HAND)
	returned.locked_until_turn = -1
	var other := _make(run, "CARD_N0", [], CardInstance.HAND)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	_make(run, "CARD_N1", [], CardInstance.DRAW)
	var partner := _make(run, "CARD_N2", ["EN_MAGNET"], CardInstance.DRAW)
	var result := _commit(run, [returned, op, other], "ret")
	var reasons: Array = []
	for event in result.draws:
		reasons.append(event.draw_reason)
	_check(result.damage == 0 and returned.zone == CardInstance.HAND and returned.return_used_run, "Zero damage still returns once, got %s" % result)
	_check(returned.locked_until_turn == -1, "Return must not refresh the lock")
	_check(result.draws.is_empty() and not reasons.has("MAGNET") and partner.zone == CardInstance.DRAW, "Return must not pull a magnet partner, reasons %s" % str(reasons))
	var frozen_run := _fresh(13, "ret_frozen")
	frozen_run.library.turn_index = 1
	var frozen_return := _make(frozen_run, "CARD_N0", ["EN_RETURN", "EN_FROZEN"], CardInstance.HAND)
	frozen_return.locked_until_turn = -1
	var frozen_other := _make(frozen_run, "CARD_N1", [], CardInstance.HAND)
	var frozen_op := _make(frozen_run, "CARD_ADD", [], CardInstance.HAND)
	var frozen_result := _commit(frozen_run, [frozen_return, frozen_op, frozen_other], "ret_frozen")
	_check(frozen_result.ok and frozen_return.zone == CardInstance.HAND and frozen_return.locked_until_turn == -1, "Return must not freeze the card again")


func _test_marks_copy_transform_sacrifice() -> void:
	var run := _fresh(14, "mark")
	run.start_battle(100, 1, false, 40)
	var card := _make(run, "CARD_N5", [], CardInstance.HAND)
	var first := run.card_service.apply_mark(card.card_uid, "EN_NUM1", "num1")
	_check(first.ok and card.printed_value(_catalog) == 6, "NUM1 raises 5 to 6")
	var clash := run.card_service.can_apply_mark(card.card_uid, "EN_NUM3")
	_check(not clash.ok and clash.reason_code == "FAMILY", "NUM1 and NUM3 cannot share a card")
	_check(card.printed_value(_catalog) == 6, "A rejected upgrade must not replace NUM1")
	_check(run.card_service.apply_mark(card.card_uid, "EN_ECHO", "echo").ok, "Echo can occupy the second slot")
	var third := run.card_service.can_apply_mark(card.card_uid, "EN_RETURN")
	_check(not third.ok and third.reason_code == "SLOTS", "The third mark is refused")
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	_check(run.card_service.can_apply_mark(op.card_uid, "EN_ECHO").reason_code == "KIND", "Echo is number only")
	var removed_signals: Array = []
	run.card_removed.connect(func(card_uid: String, reason: String) -> void:
		removed_signals.append(reason)
	)
	var state := run.rng_of("COMBAT").state()
	var hp := run.battle.player_hp
	var sacrificed := _make(run, "CARD_N3", ["EN_FRAGILE"], CardInstance.HAND)
	var sacrifice := run.card_service.sacrifice(sacrificed.card_uid, "sac")
	_check(sacrifice.ok and sacrifice.heal_delta == 0 and sacrificed.zone == CardInstance.REMOVED, "Sacrifice removes without healing")
	_check(run.battle.player_hp == hp and run.rng_of("COMBAT").state() == state, "Sacrifice does not heal or roll fragile")
	_check(removed_signals == ["SACRIFICE"], "Sacrifice emits card_removed once")
	var alchemy := run.card_service.can_apply_mark(card.card_uid, "EN_ALCHEMY")
	_check(alchemy.ok, "Alchemy can target a full card")


func _test_e01_magnet() -> void:
	var run := _fresh(15, "e01")
	run.start_battle(50, 1, false)
	var first := _make(run, "CARD_N1", ["EN_MAGNET"], CardInstance.DRAW)
	var second := _make(run, "CARD_N2", ["EN_MAGNET"], CardInstance.DRAW)
	var third := _make(run, "CARD_N3", ["EN_MAGNET"], CardInstance.DRAW)
	var result := run.draw_service.draw_count(1, run.battle.battle_uid, "TEST")
	var reasons: Array = []
	for event in result.events:
		reasons.append(event.draw_reason)
	_check(reasons == ["NORMAL_DRAW", "MAGNET"], "E01 one base draw pulls one magnet and does not chain, got %s" % str(reasons))
	_check(reasons.count("NORMAL_DRAW") == 1 and run.library.pile(CardInstance.HAND).size() == 2, "E01 the extra magnet does not consume the base draw")
	_check(run.library.pile(CardInstance.DRAW).size() == 1, "E01 one magnet stays for a later base draw")
	var uids := {}
	for event in result.events:
		_check(not uids.has(event.card_uid), "E01 draws each uid once")
		uids[event.card_uid] = true
	_check(uids.has(first.card_uid), "E01 the first pile card is the base draw")
	var follow := run.draw_service.draw_count(1, run.battle.battle_uid, "TEST2")
	var follow_reasons: Array = []
	for event in follow.events:
		follow_reasons.append(event.draw_reason)
	_check(follow_reasons == ["NORMAL_DRAW"], "E01 a magnet partner does not pull the last card, got %s" % str(follow_reasons))
	_check(first.zone == CardInstance.HAND and second.zone == CardInstance.HAND and third.zone == CardInstance.HAND, "E01 two base draws bring all three magnets")
	var parked := _fresh(16, "e01b")
	parked.start_battle(50, 1, false)
	_make(parked, "CARD_N1", ["EN_MAGNET"], CardInstance.DRAW)
	var buried := _make(parked, "CARD_N2", ["EN_MAGNET"], CardInstance.DISCARD)
	var parked_result := parked.draw_service.draw_count(1, parked.battle.battle_uid, "TEST")
	var parked_reasons: Array = []
	for event in parked_result.events:
		parked_reasons.append(event.draw_reason)
	_check(parked_reasons == ["NORMAL_DRAW"], "Magnet does not reshuffle just to find a partner, got %s" % str(parked_reasons))
	_check(buried.zone == CardInstance.DISCARD, "The discard magnet stays buried")


func _test_e02_ghosts() -> void:
	var run := _fresh(17, "e02")
	run.start_battle(50, 1, false)
	var ghosts: Array = []
	for def_id in ["CARD_N1", "CARD_N2", "CARD_N3"]:
		ghosts.append(_make(run, def_id, ["EN_GHOST"], CardInstance.DRAW))
	for _plain in 6:
		_make(run, "CARD_N4", [], CardInstance.DRAW)
	var result := run.draw_service.draw_count(5, run.battle.battle_uid, "TEST")
	_check(result.events.size() == 5, "E02 a draw of 5 stays 5 when ghosts are in the pile, got %s" % result.events.size())
	_check(run.library.pile(CardInstance.HAND).size() == 5, "E02 puts those five cards in hand")
	_check(run.library.pile(CardInstance.DRAW).size() == 4, "E02 does not keep drawing to skip ghosts")
	_check(run.library.normal_hand_count() == 2, "E02 ghosts sit in the five and do not add draws")
	var seen := {}
	for event in result.events:
		_check(not seen.has(event.card_uid), "E02 never draws the same uid twice")
		seen[event.card_uid] = true
	for ghost in ghosts:
		_check(ghost.zone == CardInstance.HAND, "E02 still draws an existing ghost card")
	var again := run.draw_service.draw_count(0, run.battle.battle_uid, "TEST2")
	_check(again.events.is_empty(), "E02 a zero count does not draw")
	_check(GameData.ensure_loaded(), "E02 reward tables load")
	var offered := false
	for row in GameData.mark_pool_rows("EP_SAFE", 1):
		if str(row.get("enh_id", "")) == "EN_GHOST":
			offered = true
	_check(not offered, "E02 weight 0 keeps EN_GHOST out of the roll")
	for row in GameData.rows("enhancement_pool"):
		if str(row.get("enh_id", "")) == "EN_GHOST":
			_check(is_equal_approx(float(row.get("weight", -1.0)), 0.0), "E02 EN_GHOST weight stays 0")


func _test_e03_frozen() -> void:
	var run := _fresh(18, "e03")
	run.start_battle(100, 8, false, 100)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var low := _make(run, "CARD_N1", [], CardInstance.HAND)
	var high := _make(run, "CARD_N2", [], CardInstance.HAND)
	var frozen := _make(run, "CARD_N3", ["EN_FROZEN"], CardInstance.DRAW)
	for _filler in 8:
		_make(run, "CARD_N4", [], CardInstance.DRAW)
	run.draw_service.draw_count(1, run.battle.battle_uid, "OPENING")
	_check(frozen.zone == CardInstance.HAND and frozen.is_frozen(run.battle.turn_index), "E03 frozen card is locked on turn 1")
	var state := run.rng_of("COMBAT").state()
	var blocked := _commit(run, [frozen, op, low], "e03block")
	_check(not blocked.ok and blocked.reason_code == "FROZEN", "E03 cannot play a frozen card")
	_check(frozen.zone == CardInstance.HAND and run.rng_of("COMBAT").state() == state, "A frozen refusal consumes nothing")
	run.battle.end_player_turn()
	_check(frozen.zone == CardInstance.HAND, "E03 frozen card stays through the enemy turn")
	_check(run.battle.turn_index == 2 and not frozen.is_frozen(run.battle.turn_index), "E03 unlocks on the next player turn")
	_check(run.library.pile(CardInstance.HAND).size() == 6, "E03 keeps the frozen card and still draws 5")
	_check(op.zone == CardInstance.DISCARD and low.zone == CardInstance.DISCARD and high.zone == CardInstance.DISCARD, "E03 discards the unfrozen hand")
	var play_op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var play_low := _make(run, "CARD_N1", [], CardInstance.HAND)
	var played := _commit(run, [frozen, play_op, play_low], "e03play")
	_check(played.ok and played.damage == 8, "E03 plays the unlocked card, got %s" % played)


func _test_e04_flags_persist() -> void:
	var run := _fresh(19, "e04")
	run.start_battle(200, 1, false, 100)
	var source := _make(run, "CARD_N3", ["EN_RETURN"], CardInstance.HAND)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var partner := _make(run, "CARD_N1", [], CardInstance.HAND)
	_check(_commit(run, [source, op, partner], "e04play").ok, "E04 setup equation plays")
	_check(source.return_used_run and source.zone == CardInstance.HAND, "The source returns and records the use")
	source.locked_until_turn = 9
	run.depth = 4
	var copied := run.card_service.copy_card(source.card_uid, "e04copy")
	var copy := run.library.get_card(str(copied.card_uid))
	_check(copied.ok and copy.card_uid != source.card_uid and copy.return_used_run, "Copy keeps the used return flag and a new uid")
	_check(copy.acquired_depth == 4 and copy.zone == CardInstance.RUN_DECK and copy.locked_until_turn == -1, "Copy uses the current depth and does not copy battle lock")
	var transformed := _make(run, "CARD_N2", ["EN_RETURN"], CardInstance.HAND)
	var add2 := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var five := _make(run, "CARD_N5", [], CardInstance.HAND)
	_check(_commit(run, [transformed, add2, five], "e04trans_play").ok, "Transform setup plays")
	_check(transformed.return_used_run, "Transform source has used return")
	var same := run.card_service.transform_card(transformed.card_uid, "CARD_N2", "e04same")
	_check(not same.ok and same.reason_code == "SAME_DEF", "Transform excludes the original def")
	var wrong := run.card_service.transform_card(transformed.card_uid, "CARD_ADD", "e04kind")
	_check(not wrong.ok and wrong.reason_code == "KIND", "Transform stays in the same kind")
	var changed := run.card_service.transform_card(transformed.card_uid, "CARD_N4", "e04change")
	_check(changed.ok and transformed.def_id == "CARD_N4" and transformed.return_used_run and transformed.has_mark("EN_RETURN"), "Transform keeps uid, marks, and used flags")
	run.battle.end_battle()
	_check(source.return_used_run and copy.return_used_run and transformed.return_used_run, "A new battle does not reset used flags")
	run.start_battle(200, 1, false, 100)
	_check(source.return_used_run and copy.return_used_run and transformed.return_used_run, "Flags survive the next battle start")
	run.library.move(copy, CardInstance.HAND, "SETUP", "e04hand", run)
	var copy_op := _make(run, "CARD_MUL", [], CardInstance.HAND)
	var copy_num := _make(run, "CARD_N4", [], CardInstance.HAND)
	_fill_hand_and_draw(run)
	var copy_reasons: Array = []
	run.card_zone_changed.connect(func(card_uid: String, _from_zone: String, _to_zone: String, reason: String, _txn: String) -> void:
		if card_uid == copy.card_uid:
			copy_reasons.append(reason)
	)
	var copy_play := _commit(run, [copy, copy_op, copy_num], "e04copyplay")
	_check(copy_play.ok and copy.zone == CardInstance.DISCARD and copy.return_used_run, "A copied used return does not return again")
	_check(not copy_reasons.has("RETURN"), "Copy does not emit a return move")
	run.library.move(transformed, CardInstance.HAND, "SETUP", "e04hand2", run)
	var trans_op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var trans_num := _make(run, "CARD_N1", [], CardInstance.HAND)
	_fill_hand_and_draw(run)
	var trans_reasons: Array = []
	run.card_zone_changed.connect(func(card_uid: String, _from_zone: String, _to_zone: String, reason: String, _txn: String) -> void:
		if card_uid == transformed.card_uid:
			trans_reasons.append(reason)
	)
	var trans_play := _commit(run, [transformed, trans_op, trans_num], "e04transplay")
	_check(trans_play.ok and transformed.zone == CardInstance.DISCARD and transformed.return_used_run, "A transformed used return does not refresh")
	_check(not trans_reasons.has("RETURN"), "Transform does not emit a return move")


func _test_e05_fragile_before_return() -> void:
	var seed := _fragile_break_seed()
	_check(seed > 0, "Need a seed whose first combat roll breaks")
	var run := _fresh(seed, "e05")
	var card := _make(run, "CARD_N3", ["EN_FRAGILE", "EN_RETURN"], CardInstance.HAND)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var other := _make(run, "CARD_N4", [], CardInstance.HAND)
	var gone: Array = []
	var destinations: Array = []
	run.card_removed.connect(func(card_uid: String, reason: String) -> void:
		if card_uid == card.card_uid:
			gone.append(reason)
	)
	run.card_zone_changed.connect(func(card_uid: String, _from_zone: String, to_zone: String, _reason: String, _txn: String) -> void:
		if card_uid == card.card_uid:
			destinations.append(to_zone)
	)
	var result := _commit(run, [card, op, other], "e05")
	var broke := false
	for roll in result.fragile:
		if roll.card_uid == card.card_uid:
			broke = bool(roll.broke)
	_check(broke and card.zone == CardInstance.REMOVED and not card.return_used_run, "E05 break removes the card before return")
	_check(destinations == [CardInstance.RESOLVING, CardInstance.REMOVED], "E05 never returns to hand, got %s" % str(destinations))
	_check(gone == ["FRAGILE"], "E05 emits fragile removal")


func _test_e06_victory_before_exhaustion() -> void:
	var seed := _fragile_break_seed()
	_check(seed > 0, "E06 needs a breaking seed")
	var run := _fresh(seed, "e06")
	run.start_battle(99, 1, false, 100)
	var card := _make(run, "CARD_N1", ["EN_FRAGILE"], CardInstance.HAND)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var other := _make(run, "CARD_N2", [], CardInstance.HAND)
	var preview := run.equation_service.preview([card.card_uid, op.card_uid, other.card_uid], {})
	run.battle.enemy_hp = int(preview.damage)
	run.battle.enemy_max_hp = int(preview.damage)
	var result := _commit(run, [card, op, other], "e06")
	_check(result.battle_outcome == "VICTORY" and run.battle.phase == "VICTORY" and run.battle.enemy_hp == 0, "E06 winning equation is victory, got %s" % result)
	_check(card.zone == CardInstance.REMOVED and run.library.is_fighting_exhausted(), "The same equation would have exhausted the deck")
	_check(run.battle.phase != "DECK_EXHAUSTED", "Victory is not overwritten by deck exhaustion")


func _test_e07_alchemy_price() -> void:
	var run := _fresh(20, "e07")
	var card := _make(run, "CARD_N3", ["EN_PRICE"], CardInstance.HAND)
	var removed: Array = []
	run.card_removed.connect(func(_card_uid: String, reason: String) -> void:
		removed.append(reason)
	)
	var result := run.card_service.apply_mark(card.card_uid, "EN_ALCHEMY", "e07", "DEBUG")
	_check(result.ok and result.value_score == 80 and card.collection_value() == 80, "E07 value score doubles once to 80, got %s" % result)
	_check(card.zone == CardInstance.COLLECTION and not card.has_mark("EN_ALCHEMY"), "Alchemy is not stored as a mark")
	_check(str(card.collection_snapshot.collection_id) == "COL_SAMPLE", "Alchemy stores COL_SAMPLE")
	_check(removed.is_empty(), "Alchemy does not emit card_removed")
	_check(card.collection_value() == 80, "Reading the snapshot does not double it again")
	var symbol := _make(run, "CARD_ADD", ["EN_PRICE"], CardInstance.HAND)
	var symbol_result := run.card_service.apply_mark(symbol.card_uid, "EN_ALCHEMY", "e07op")
	_check(symbol_result.value_score == 50, "Operator price ignores the absolute-value term, got %s" % symbol_result)
	run.start_battle(30, 1, true, 100)
	_check(card.zone == CardInstance.COLLECTION and symbol.zone == CardInstance.COLLECTION, "Collection cards stay out of the next battle")
	_check(not run.library.pile(CardInstance.DRAW).has(card.card_uid) and not run.library.pile(CardInstance.HAND).has(card.card_uid), "Alchemy never enters the draw pile")


func _test_e08_preview_rng() -> void:
	var left := _fresh(21, "e08a")
	var right := _fresh(21, "e08b")
	var left_cards := [
		_make(left, "CARD_N3", ["EN_FRAGILE"], CardInstance.HAND),
		_make(left, "CARD_ADD", [], CardInstance.HAND),
		_make(left, "CARD_N4", [], CardInstance.HAND),
	]
	var right_cards := [
		_make(right, "CARD_N3", ["EN_FRAGILE"], CardInstance.HAND),
		_make(right, "CARD_ADD", [], CardInstance.HAND),
		_make(right, "CARD_N4", [], CardInstance.HAND),
	]
	var uids: Array = []
	for card in left_cards:
		uids.append(card.card_uid)
	var state := left.rng_of("COMBAT").state()
	for _i in 100:
		left.equation_service.preview(uids, {})
	_check(left.rng_of("COMBAT").state() == state, "E08 one hundred previews do not move combat RNG")
	var left_result := _commit(left, left_cards, "e08a")
	var right_result := _commit(right, right_cards, "e08b")
	_check(bool(left_result.fragile[0].broke) == bool(right_result.fragile[0].broke), "E08 the next fragile roll matches a run that did not preview")
	_check(left.rng_of("COMBAT").state() == right.rng_of("COMBAT").state(), "E08 combat state matches after the real roll")


func _test_combo_and_vanguard() -> void:
	var echo := _fresh(22, "combo_echo")
	echo.start_battle(500, 1, false, 100)
	var echoed := _make(echo, "CARD_N3", ["EN_ECHO"], CardInstance.HAND)
	var echo_op := _make(echo, "CARD_ADD", [], CardInstance.HAND)
	var echo_four := _make(echo, "CARD_N4", [], CardInstance.HAND)
	_commit(echo, [echoed, echo_op, echo_four], "combo_echo")
	_check(echo.battle.combo_streak == 1 and not echo.battle.combo_pending, "Echo is one ADD output, not a combo")
	var same := _fresh(23, "combo_same")
	same.start_battle(500, 1, false, 100)
	var repeater := _make(same, "CARD_N3", ["EN_COMBO", "EN_RETURN"], CardInstance.HAND)
	var add_a := _make(same, "CARD_ADD", [], CardInstance.HAND)
	var one := _make(same, "CARD_N1", [], CardInstance.HAND)
	var add_b := _make(same, "CARD_ADD", [], CardInstance.HAND)
	var two := _make(same, "CARD_N2", [], CardInstance.HAND)
	_commit(same, [repeater, add_a, one], "combo_same_a")
	_commit(same, [repeater, add_b, two], "combo_same_b")
	_check(is_equal_approx(same.battle.combo_window, 5.0) and same.battle.combo_pending, "The same combo uid in both formulas is a 5s window")
	same.battle.end_player_turn()
	_check(same.battle.phase == "COMBO", "Ending the turn opens the combo window")
	var interval := 1.0 / float(same.catalog.rule().combo_click_rate_cap)
	var hp := same.battle.enemy_hp
	_check(same.battle.combo_click().ok and same.battle.enemy_hp == hp - 1, "A combo click deals 1")
	_check(not same.battle.combo_click().ok, "Combo clicks are capped at 5 per second")
	same.battle.advance(interval)
	_check(same.battle.combo_click().ok and same.battle.enemy_hp == hp - 2, "A click lands after 0.2s")
	var pair := _fresh(24, "combo_pair")
	pair.start_battle(500, 1, false, 100)
	var first := _make(pair, "CARD_N3", ["EN_COMBO"], CardInstance.HAND)
	var pair_add := _make(pair, "CARD_ADD", [], CardInstance.HAND)
	var pair_one := _make(pair, "CARD_N1", [], CardInstance.HAND)
	var second := _make(pair, "CARD_N4", ["EN_COMBO"], CardInstance.HAND)
	var pair_add2 := _make(pair, "CARD_ADD", [], CardInstance.HAND)
	var pair_two := _make(pair, "CARD_N2", [], CardInstance.HAND)
	_commit(pair, [first, pair_add, pair_one], "combo_pair_a")
	_commit(pair, [second, pair_add2, pair_two], "combo_pair_b")
	_check(is_equal_approx(pair.battle.combo_window, 8.0), "Two combo cards make an 8s window")
	var burned := _fresh(25, "combo_burn")
	burned.start_battle(500, 1, false, 80)
	var burn_a := _make(burned, "CARD_N3", [], CardInstance.HAND)
	var burn_add := _make(burned, "CARD_ADD", [], CardInstance.HAND)
	var burn_one := _make(burned, "CARD_N1", [], CardInstance.HAND)
	var burn_b := _make(burned, "CARD_N4", [], CardInstance.HAND)
	var burn_add2 := _make(burned, "CARD_ADD", [], CardInstance.HAND)
	var burn_two := _make(burned, "CARD_N2", [], CardInstance.HAND)
	var fodder := _make(burned, "CARD_N0", [], CardInstance.HAND)
	_commit(burned, [burn_a, burn_add, burn_one], "combo_burn_a")
	_check(burned.battle.combo_streak == 1, "The first add starts the streak")
	burned.card_service.burn(fodder.card_uid, "combo_burn_fodder")
	_check(burned.battle.combo_streak == 1 and not burned.battle.combo_pending, "Burn does not count and does not reset the streak")
	_commit(burned, [burn_b, burn_add2, burn_two], "combo_burn_b")
	_check(burned.battle.combo_pending, "The second add still opens the window after a burn")
	var reset := _fresh(26, "combo_mul")
	reset.start_battle(500, 1, false, 100)
	var reset_a := _make(reset, "CARD_N1", [], CardInstance.HAND)
	var reset_add := _make(reset, "CARD_ADD", [], CardInstance.HAND)
	var reset_b := _make(reset, "CARD_N2", [], CardInstance.HAND)
	var reset_c := _make(reset, "CARD_N3", [], CardInstance.HAND)
	var reset_mul := _make(reset, "CARD_MUL", [], CardInstance.HAND)
	var reset_d := _make(reset, "CARD_N4", [], CardInstance.HAND)
	_commit(reset, [reset_a, reset_add, reset_b], "combo_mul_a")
	_commit(reset, [reset_c, reset_mul, reset_d], "combo_mul_b")
	_check(reset.battle.combo_streak == 0 and not reset.battle.combo_pending, "MUL resets the add streak")
	var van := _fresh(27, "van")
	van.start_battle(80, 1, false, 100)
	var vanguard_a := _make(van, "CARD_N1", ["EN_VANGUARD", "EN_MAGNET"], CardInstance.RUN_DECK)
	var vanguard_b := _make(van, "CARD_N2", ["EN_VANGUARD", "EN_FROZEN"], CardInstance.RUN_DECK)
	var plain := _make(van, "CARD_N3", [], CardInstance.RUN_DECK)
	var deal := van.draw_service.opening_deal(van.battle.battle_uid)
	var opening_reasons: Array = []
	for event in deal.opening:
		opening_reasons.append(event.draw_reason)
	var refill_reasons: Array = []
	for event in deal.draws:
		refill_reasons.append(event.draw_reason)
	var expected: Array = [vanguard_a, vanguard_b]
	expected.sort_custom(func(a, b) -> bool: return str(a.card_uid) < str(b.card_uid))
	var hand: Array = van.library.pile(CardInstance.HAND)
	_check(opening_reasons == ["VANGUARD", "VANGUARD"], "Vanguard enters before the normal refill, got %s" % str(opening_reasons))
	_check(hand[0] == expected[0].card_uid and hand[1] == expected[1].card_uid, "Vanguards are ordered by uid, got %s" % str(hand))
	_check(vanguard_b.is_frozen(van.battle.turn_index) and not vanguard_a.is_frozen(van.battle.turn_index), "Vanguard freezes, and a card without the mark does not")
	_check(not opening_reasons.has("MAGNET") and not refill_reasons.has("MAGNET"), "Vanguard does not magnet")
	_check(plain.zone == CardInstance.HAND, "The remaining card is a normal draw")
	var quota := _fresh(271, "van_quota")
	quota.start_battle(80, 1, false, 100)
	for _g in 2:
		_make(quota, "CARD_N1", ["EN_VANGUARD"], CardInstance.RUN_DECK)
	for _plain_card in 4:
		_make(quota, "CARD_N3", [], CardInstance.RUN_DECK)
	var quota_deal := quota.draw_service.opening_deal(quota.battle.battle_uid)
	_check(quota_deal.opening.size() == 2 and quota_deal.draws.size() == 3, "Two vanguards leave max(0, 5-G) normal draws, got %s" % quota_deal.draws.size())
	_check(quota.library.pile(CardInstance.HAND).size() == 5, "Vanguard plus the normal draws fill five cards")
	_check(quota.library.pile(CardInstance.DRAW).size() == 1, "The spare plain card stays in the draw pile")
	var crowd := _fresh(272, "van_crowd")
	crowd.start_battle(80, 1, false, 100)
	for _g in 6:
		_make(crowd, "CARD_N1", ["EN_VANGUARD"], CardInstance.RUN_DECK)
	var delayed_plain := _make(crowd, "CARD_N4", [], CardInstance.RUN_DECK)
	var crowd_deal := crowd.draw_service.opening_deal(crowd.battle.battle_uid)
	_check(crowd_deal.opening.size() == 6 and crowd_deal.draws.is_empty(), "More than five vanguards enter and skip the start draw")
	_check(delayed_plain.zone == CardInstance.DRAW and crowd.library.pile(CardInstance.HAND).size() == 6, "The plain card waits through a crowded opening")
	crowd.battle.advance(7.5)
	_check(delayed_plain.zone == CardInstance.HAND and crowd.battle.delayed_draw_done, "The 7.5s draw still happens after a crowded opening")
	crowd.battle.advance(1.0)
	_check(crowd.library.pile(CardInstance.HAND).size() == 7 and crowd.battle.phase == "PLAYER_ACTIVE", "The delayed draw happens once")


func _listen(run: RunContext) -> Array:
	var moves: Array = []
	run.card_zone_changed.connect(func(_card_uid: String, _from_zone: String, to_zone: String, reason: String, _txn: String) -> void:
		moves.append({"to": to_zone, "reason": reason})
	)
	return moves


func _drew_then_ended(moves: Array) -> bool:
	var drew := false
	var ends := 0
	for move in moves:
		if str(move.reason) == "END_TURN":
			if not drew:
				return false
			ends += 1
		elif not drew and str(move.to) == CardInstance.HAND:
			drew = true
	return drew and ends == 6


func _stock(run: RunContext) -> void:
	for _i in 12:
		_make(run, "CARD_N1", [], CardInstance.RUN_DECK)
	_make(run, "CARD_ADD", [], CardInstance.RUN_DECK)


func _test_draw_clock() -> void:
	var opening := _fresh(40, "draw5")
	_stock(opening)
	opening.start_battle(300, 1, true, 100)
	_check(opening.library.pile(CardInstance.HAND).size() == 5, "Turn start draws exactly 5")
	_check(opening.library.pile(CardInstance.DRAW).size() == 8, "Turn start does not refill the hand to 6")
	opening.battle.advance(7.5)
	_check(opening.library.pile(CardInstance.HAND).size() == 6 and opening.battle.delayed_draw_done, "Crossing 7.5 draws one card")
	opening.battle.advance(1.0)
	_check(opening.library.pile(CardInstance.HAND).size() == 6 and opening.battle.phase == "PLAYER_ACTIVE", "The delayed draw happens once")
	var played := _fresh(41, "no_refill_play")
	played.start_battle(300, 1, false, 80)
	var left := _make(played, "CARD_N3", [], CardInstance.HAND)
	var op := _make(played, "CARD_ADD", [], CardInstance.HAND)
	var right := _make(played, "CARD_N4", [], CardInstance.HAND)
	for _deck in 4:
		_make(played, "CARD_N1", [], CardInstance.DRAW)
	var play := _commit(played, [left, op, right], "no_refill_play")
	_check(play.ok and play.draws.is_empty(), "Play does not refill")
	_check(played.library.pile(CardInstance.HAND).is_empty() and played.library.pile(CardInstance.DRAW).size() == 4, "Play leaves the draw pile")
	var burned := _fresh(42, "no_refill_burn")
	burned.start_battle(300, 1, false, 40)
	var fodder := _make(burned, "CARD_N2", [], CardInstance.HAND)
	for _deck in 3:
		_make(burned, "CARD_N1", [], CardInstance.DRAW)
	var burn := burned.card_service.burn(fodder.card_uid, "no_refill_burn")
	_check(burn.ok and burn.removed, "Burn removes the card")
	_check(burned.library.pile(CardInstance.HAND).is_empty() and burned.library.pile(CardInstance.DRAW).size() == 3, "Burn does not refill")
	var seed := _fragile_break_seed()
	_check(seed > 0, "Fragile refill check needs a breaking seed")
	var fragile := _fresh(seed, "no_refill_fragile")
	fragile.start_battle(300, 1, false, 100)
	var card := _make(fragile, "CARD_N3", ["EN_FRAGILE"], CardInstance.HAND)
	var fragile_op := _make(fragile, "CARD_ADD", [], CardInstance.HAND)
	var other := _make(fragile, "CARD_N4", [], CardInstance.HAND)
	for _deck in 2:
		_make(fragile, "CARD_N1", [], CardInstance.DRAW)
	var broke := _commit(fragile, [card, fragile_op, other], "no_refill_fragile")
	_check(broke.ok and broke.draws.is_empty() and card.zone == CardInstance.REMOVED, "Fragile break does not refill")
	_check(fragile.library.pile(CardInstance.DRAW).size() == 2, "Fragile leaves the draw pile")
	var early := _fresh(43, "early_end")
	_stock(early)
	early.start_battle(300, 1, true, 100)
	var early_reasons := _listen(early)
	early.battle.advance(7.4)
	_check(early.library.pile(CardInstance.HAND).size() == 5, "Time before 7.5 does not draw")
	early.battle.end_player_turn()
	_check(not _drew_then_ended(early_reasons), "Ending before 7.5 does not grant the extra card, got %s" % str(early_reasons))
	var exact := _fresh(44, "exact_end")
	_stock(exact)
	exact.start_battle(300, 1, true, 100)
	var exact_reasons := _listen(exact)
	exact.battle.player_elapsed_s = 7.5
	exact.battle.end_player_turn()
	_check(_drew_then_ended(exact_reasons), "Ending at 7.5 draws before the turn ends, got %s" % str(exact_reasons))
	var crossed := _fresh(45, "cross_frame")
	_stock(crossed)
	crossed.start_battle(300, 1, true, 100)
	var crossed_reasons := _listen(crossed)
	crossed.battle.advance(7.0)
	_check(crossed.library.pile(CardInstance.HAND).size() == 5, "7.0 seconds has not drawn yet")
	crossed.battle.advance(3.0)
	_check(_drew_then_ended(crossed_reasons), "A frame crossing 7.5 and 10 draws before the turn ends, got %s" % str(crossed_reasons))
	_check(crossed.battle.turn_index == 2 and crossed.battle.phase == "PLAYER_ACTIVE", "That frame then ends the turn")


func _hand_roles(run: RunContext) -> Dictionary:
	var operators := 0
	var numbers := 0
	for card_uid in run.library.pile(CardInstance.HAND):
		var card := run.library.get_card(str(card_uid))
		var def := _catalog.card(card.def_id)
		if str(def.get("card_kind", "")) == "NUM":
			numbers += 1
		elif str(def.get("operator_code", "")) == "ADD" or str(def.get("operator_code", "")) == "MUL":
			operators += 1
	return {"operators": operators, "numbers": numbers}


func _test_hand_composition() -> void:
	var mixed := _fresh(90, "mix")
	mixed.start_battle(40, 1, false)
	var numbers: Array = []
	for _i in 5:
		numbers.append(_make(mixed, "CARD_N1", [], CardInstance.DRAW))
	var operator := _make(mixed, "CARD_ADD", ["EN_MAGNET", "EN_GHOST"], CardInstance.DRAW)
	var partner := _make(mixed, "CARD_N2", ["EN_MAGNET"], CardInstance.DRAW)
	var mixed_result := mixed.draw_service.draw_count(5, mixed.battle.battle_uid, "TURN_START", mixed.battle.battle_uid)
	var mixed_reasons: Array = []
	for event in mixed_result.events:
		mixed_reasons.append(event.draw_reason)
	var mixed_hand: Array = mixed.library.pile(CardInstance.HAND)
	var mixed_counts := _hand_roles(mixed)
	_check(mixed_reasons == ["NORMAL_DRAW", "NORMAL_DRAW", "NORMAL_DRAW", "NORMAL_DRAW", "NORMAL_DRAW"], "Repairing five numbers does not draw or magnet, got %s" % str(mixed_reasons))
	_check(mixed_hand.size() == 5 and int(mixed_counts.operators) >= 1 and int(mixed_counts.numbers) >= 2, "A draw pile that still has an operator cannot deal five numbers, got %s" % str(mixed_counts))
	_check(mixed_hand == [numbers[0].card_uid, numbers[1].card_uid, numbers[2].card_uid, numbers[3].card_uid, operator.card_uid], "The last drawn number is the one swapped for the operator, got %s" % str(mixed_hand))
	_check(mixed.library.pile(CardInstance.DRAW) == [numbers[4].card_uid, partner.card_uid], "The swapped number takes the operator slot and the magnet partner stays undrawn")
	var bare := _fresh(91, "bare")
	bare.start_battle(40, 1, false)
	for _i in 5:
		_make(bare, "CARD_N3", [], CardInstance.DRAW)
	var buried := _make(bare, "CARD_MUL", [], CardInstance.DISCARD)
	bare.draw_service.draw_count(5, bare.battle.battle_uid, "TURN_START", bare.battle.battle_uid)
	var bare_counts := _hand_roles(bare)
	_check(int(bare_counts.operators) == 0 and int(bare_counts.numbers) == 5, "No operator left in the draw pile keeps the shuffled numbers, got %s" % str(bare_counts))
	_check(buried.zone == CardInstance.DISCARD and bare.library.pile(CardInstance.DRAW).is_empty(), "Discard is not reshuffled just to find an operator")
	var heavy := _fresh(92, "heavy")
	heavy.start_battle(40, 1, false)
	for _i in 5:
		_make(heavy, "CARD_MUL", [], CardInstance.DRAW)
	var heavy_one := _make(heavy, "CARD_N1", [], CardInstance.DRAW)
	var heavy_two := _make(heavy, "CARD_N2", [], CardInstance.DRAW)
	heavy.draw_service.draw_count(5, heavy.battle.battle_uid, "TURN_START", heavy.battle.battle_uid)
	var heavy_counts := _hand_roles(heavy)
	_check(heavy.library.pile(CardInstance.HAND).size() == 5 and int(heavy_counts.operators) >= 1 and int(heavy_counts.numbers) >= 2, "Five operators are repaired with two numbers, got %s" % str(heavy_counts))
	_check(heavy_one.zone == CardInstance.HAND and heavy_two.zone == CardInstance.HAND and heavy.library.pile(CardInstance.DRAW).size() == 2, "Both numbers come from the draw pile without an extra draw")
	var no_numbers := _fresh(93, "no_numbers")
	no_numbers.start_battle(40, 1, false)
	for _i in 5:
		_make(no_numbers, "CARD_ADD", [], CardInstance.DRAW)
	var buried_number := _make(no_numbers, "CARD_N4", [], CardInstance.DISCARD)
	no_numbers.draw_service.draw_count(5, no_numbers.battle.battle_uid, "TURN_START", no_numbers.battle.battle_uid)
	var no_counts := _hand_roles(no_numbers)
	_check(int(no_counts.numbers) == 0 and int(no_counts.operators) == 5 and buried_number.zone == CardInstance.DISCARD, "Numbers left only in discard stay there")
	var ready := _fresh(94, "ready")
	ready.start_battle(40, 1, false)
	var ready_cards: Array = [
		_make(ready, "CARD_N1", [], CardInstance.DRAW),
		_make(ready, "CARD_N2", [], CardInstance.DRAW),
		_make(ready, "CARD_ADD", [], CardInstance.DRAW),
		_make(ready, "CARD_N3", [], CardInstance.DRAW),
		_make(ready, "CARD_N4", [], CardInstance.DRAW),
	]
	var extra := _make(ready, "CARD_MUL", [], CardInstance.DRAW)
	ready.draw_service.draw_count(5, ready.battle.battle_uid, "TURN_START", ready.battle.battle_uid)
	var expected: Array = []
	for card in ready_cards:
		expected.append(card.card_uid)
	_check(ready.library.pile(CardInstance.HAND) == expected and extra.zone == CardInstance.DRAW, "A hand that already has an operator and two numbers stays in draw order")
	var magnet := _fresh(95, "magnet_spare")
	magnet.start_battle(40, 1, false)
	for _i in 4:
		_make(magnet, "CARD_N1", [], CardInstance.DRAW)
	var base := _make(magnet, "CARD_N2", ["EN_MAGNET"], CardInstance.DRAW)
	var magnet_op := _make(magnet, "CARD_ADD", [], CardInstance.DRAW)
	var magnet_partner := _make(magnet, "CARD_N3", ["EN_MAGNET"], CardInstance.DRAW)
	var magnet_result := magnet.draw_service.draw_count(5, magnet.battle.battle_uid, "TURN_START", magnet.battle.battle_uid)
	var magnet_hits := 0
	for event in magnet_result.events:
		if str(event.draw_reason) == "MAGNET":
			magnet_hits += 1
	_check(magnet_result.events.size() == 6 and magnet_hits == 1, "The base magnet still draws one partner and the swap does not chain, got %s" % magnet_result.events.size())
	_check(base.zone == CardInstance.DRAW and magnet_partner.zone == CardInstance.HAND and magnet_op.zone == CardInstance.HAND, "The normally drawn magnet is swapped before its partner")
	_check(magnet.library.pile(CardInstance.HAND).size() == 6, "The magnet extra stays in hand and the swap adds no card")
	var late := _fresh(96, "late_mix")
	late.start_battle(50, 1, false)
	var staying: Array = []
	for _i in 4:
		staying.append(_make(late, "CARD_N5", [], CardInstance.HAND))
	var late_number := _make(late, "CARD_N1", [], CardInstance.DRAW)
	var late_op := _make(late, "CARD_ADD", [], CardInstance.DRAW)
	late.battle.advance(7.5)
	var late_counts := _hand_roles(late)
	_check(late.battle.delayed_draw_done and late_op.zone == CardInstance.HAND and late_number.zone == CardInstance.DRAW, "The 7.5s draw swaps a surplus number for an operator and stays consumed")
	_check(late.library.pile(CardInstance.HAND).size() == 5 and int(late_counts.operators) >= 1 and int(late_counts.numbers) >= 2, "The delayed draw does not pull a second card, got %s" % str(late_counts))
	for card in staying:
		_check(card.zone == CardInstance.HAND, "Cards already in hand stay when the new number can be swapped")
	late.battle.advance(1.0)
	_check(late.library.pile(CardInstance.HAND).size() == 5 and late.battle.delayed_draw_done and late.battle.phase == "PLAYER_ACTIVE", "The swap does not mark the delayed draw unconsumed")
	var van := _fresh(97, "van_mix")
	van.start_battle(80, 1, false)
	var vanguard_one := _make(van, "CARD_N1", ["EN_VANGUARD"], CardInstance.RUN_DECK)
	var vanguard_two := _make(van, "CARD_N2", ["EN_VANGUARD"], CardInstance.RUN_DECK)
	for _i in 3:
		_make(van, "CARD_N3", [], CardInstance.RUN_DECK)
	var van_op := _make(van, "CARD_ADD", [], CardInstance.RUN_DECK)
	van.draw_service.opening_deal(van.battle.battle_uid)
	var van_counts := _hand_roles(van)
	_check(vanguard_one.zone == CardInstance.HAND and vanguard_two.zone == CardInstance.HAND, "Opening repair keeps the placed vanguards")
	_check(van_op.zone == CardInstance.HAND and van.library.pile(CardInstance.HAND).size() == 5, "Opening repair brings the operator in without an extra draw")
	_check(int(van_counts.operators) >= 1 and int(van_counts.numbers) >= 2, "The opening hand meets the minimum, got %s" % str(van_counts))
	var symbols := _fresh(98, "van_ops")
	symbols.start_battle(80, 1, false)
	var symbol_one := _make(symbols, "CARD_ADD", ["EN_VANGUARD"], CardInstance.RUN_DECK)
	var symbol_two := _make(symbols, "CARD_MUL", ["EN_VANGUARD"], CardInstance.RUN_DECK)
	for _i in 3:
		_make(symbols, "CARD_ADD", [], CardInstance.RUN_DECK)
	_make(symbols, "CARD_N1", [], CardInstance.RUN_DECK)
	_make(symbols, "CARD_N2", [], CardInstance.RUN_DECK)
	symbols.draw_service.opening_deal(symbols.battle.battle_uid)
	var symbol_counts := _hand_roles(symbols)
	_check(symbol_one.zone == CardInstance.HAND and symbol_two.zone == CardInstance.HAND, "Surplus normal operators are swapped before opening vanguards")
	_check(symbols.library.pile(CardInstance.HAND).size() == 5 and int(symbol_counts.numbers) >= 2 and int(symbol_counts.operators) >= 1, "An operator-heavy opening still receives two numbers, got %s" % str(symbol_counts))
	var crowd := _fresh(99, "van_only")
	crowd.start_battle(80, 1, false)
	var held: Array = []
	for _i in 5:
		held.append(_make(crowd, "CARD_N4", ["EN_VANGUARD"], CardInstance.RUN_DECK))
	var crowd_op := _make(crowd, "CARD_MUL", [], CardInstance.RUN_DECK)
	var crowd_deal := crowd.draw_service.opening_deal(crowd.battle.battle_uid)
	var displaced := 0
	for card in held:
		if card.zone == CardInstance.DRAW:
			displaced += 1
	_check(crowd_deal.draws.is_empty() and crowd.library.pile(CardInstance.HAND).size() == 5, "Five vanguards still skip the normal opening draw")
	_check(crowd_op.zone == CardInstance.HAND and displaced == 1, "A vanguard leaves only when no normal card can, got %s" % displaced)


func _test_card_view_and_lab() -> void:
	var run := _fresh(28, "view")
	var card := _make(run, "CARD_N5", [], CardInstance.HAND)
	var negative := _make(run, "CARD_NM5", [], CardInstance.HAND)
	var ghost := _make(run, "CARD_N1", ["EN_GHOST"], CardInstance.HAND)
	ghost.locked_until_turn = 2
	run.library.turn_index = 1
	var view := (load("res://scenes/cards/card_view.tscn") as PackedScene).instantiate() as CardView
	view.bind(run.library, card.card_uid)
	_check(view.face_text() == "5", "Card view shows the printed number")
	run.card_service.apply_mark(card.card_uid, "EN_NUM1", "view_mark")
	view.refresh()
	_check(view.face_text() == "6", "Card view refreshes the recomputed value")
	view.bind(run.library, negative.card_uid)
	_check(view.face_text() == "−5", "Card view uses the number face")
	view.bind(run.library, ghost.card_uid)
	_check(view.mark_text().contains("幽灵") and view.state_text().contains("幽灵") and view.state_text().contains("冻结"), "Card view shows the ghost mark and the frozen state")
	view.free()
	var lab := (load("res://scenes/cards/card_lab.tscn") as PackedScene).instantiate() as CardLab
	root.add_child(lab)
	await process_frame
	_check(lab.run != null and lab.run.battle != null, "Card lab boots a battle")
	_check(lab.run.battle.phase == "PLAYER_ACTIVE", "Card lab starts in the player turn")
	_check(lab.run.library.pile(CardInstance.HAND).size() == 5, "Card lab deals a five-card hand")
	_check(lab.get_child_count() > 0, "Card lab builds its own scene")
	lab.queue_free()
