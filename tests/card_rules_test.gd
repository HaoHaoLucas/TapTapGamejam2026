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
		await _test_card_view_and_lab()
	await process_frame
	if _failures == 0:
		print("PASS: card rules C01-C12, E01-E08, starter, preview RNG")
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
	_check(_catalog.config_version == "jam_1.0.0", "Config version must be jam_1.0.0")
	_check(_catalog.rows("enhancement_def").size() == 16, "Enhancement table must have 16 rows")
	_check(int(_catalog.rule().hand_target) == 6, "Hand target must be 6")
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
	_check(result.draws.size() == 3, "C01 refills the three played cards")
	_check(run.library.pile(CardInstance.HAND).size() == 6, "C01 hand returns to the target of 6")
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
	_check(not reasons.has("MAGNET") and partner.zone == CardInstance.HAND, "Return must not pull a magnet partner, reasons %s" % str(reasons))
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
	var result := run.draw_service.refill(run.battle.battle_uid, "TEST")
	var reasons: Array = []
	for event in result.events:
		reasons.append(event.draw_reason)
	_check(reasons == ["NORMAL_DRAW", "MAGNET", "NORMAL_DRAW"], "E01 each normal magnet draw brings one partner, got %s" % str(reasons))
	_check(reasons.count("MAGNET") == 1, "E01 magnet draw does not chain")
	var uids := {}
	for event in result.events:
		_check(not uids.has(event.card_uid), "E01 draws each uid once")
		uids[event.card_uid] = true
	_check(uids.has(first.card_uid) and uids.has(second.card_uid) and uids.has(third.card_uid), "E01 draws all three magnets")
	var parked := _fresh(16, "e01b")
	parked.start_battle(50, 1, false)
	for _pad in 5:
		_make(parked, "CARD_N0", [], CardInstance.HAND)
	_make(parked, "CARD_N1", ["EN_MAGNET"], CardInstance.DRAW)
	var buried := _make(parked, "CARD_N2", ["EN_MAGNET"], CardInstance.DISCARD)
	var parked_result := parked.draw_service.refill(parked.battle.battle_uid, "TEST")
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
	var result := run.draw_service.refill(run.battle.battle_uid, "TEST")
	_check(result.events.size() == 3, "E02 draws each ghost once, got %s" % result.events.size())
	_check(run.library.pile(CardInstance.HAND).size() == 3, "E02 stops when the source is empty")
	_check(run.library.normal_hand_count() == 0, "Ghosts do not fill the hand target")
	var seen := {}
	for event in result.events:
		_check(not seen.has(event.card_uid), "E02 never draws the same uid twice")
		seen[event.card_uid] = true
	var again := run.draw_service.refill(run.battle.battle_uid, "TEST2")
	_check(again.events.is_empty(), "E02 does not loop after the deck is exhausted")
	_check(ghosts.size() == 3, "E02 keeps the three ghost entities")


func _test_e03_frozen() -> void:
	var run := _fresh(18, "e03")
	run.start_battle(100, 8, false, 100)
	var op := _make(run, "CARD_ADD", [], CardInstance.HAND)
	var low := _make(run, "CARD_N1", [], CardInstance.HAND)
	var high := _make(run, "CARD_N2", [], CardInstance.HAND)
	var frozen := _make(run, "CARD_N3", ["EN_FROZEN"], CardInstance.DRAW)
	var other := _make(run, "CARD_N4", [], CardInstance.DRAW)
	run.draw_service.refill(run.battle.battle_uid, "OPENING")
	_check(frozen.zone == CardInstance.HAND and frozen.is_frozen(run.battle.turn_index), "E03 frozen card is locked on turn 1")
	var state := run.rng_of("COMBAT").state()
	var blocked := _commit(run, [frozen, op, low], "e03block")
	_check(not blocked.ok and blocked.reason_code == "FROZEN", "E03 cannot play a frozen card")
	_check(frozen.zone == CardInstance.HAND and run.rng_of("COMBAT").state() == state, "A frozen refusal consumes nothing")
	run.battle.end_player_turn()
	_check(frozen.zone == CardInstance.HAND, "E03 frozen card stays through the enemy turn")
	_check(run.battle.turn_index == 2 and not frozen.is_frozen(run.battle.turn_index), "E03 unlocks on the next player turn")
	_check(op.zone == CardInstance.HAND and low.zone == CardInstance.HAND and high.zone == CardInstance.HAND and other.zone == CardInstance.HAND, "The other cards are redrawn")
	var played := _commit(run, [frozen, op, low], "e03play")
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
	for event in deal.refill:
		refill_reasons.append(event.draw_reason)
	var expected: Array = [vanguard_a, vanguard_b]
	expected.sort_custom(func(a, b) -> bool: return str(a.card_uid) < str(b.card_uid))
	var hand: Array = van.library.pile(CardInstance.HAND)
	_check(opening_reasons == ["VANGUARD", "VANGUARD"], "Vanguard enters before the normal refill, got %s" % str(opening_reasons))
	_check(hand[0] == expected[0].card_uid and hand[1] == expected[1].card_uid, "Vanguards are ordered by uid, got %s" % str(hand))
	_check(vanguard_b.is_frozen(van.battle.turn_index) and not vanguard_a.is_frozen(van.battle.turn_index), "Vanguard freezes, and a card without the mark does not")
	_check(not opening_reasons.has("MAGNET") and not refill_reasons.has("MAGNET"), "Vanguard does not magnet")
	_check(plain.zone == CardInstance.HAND, "The remaining card is a normal draw")


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
	_check(lab.run.library.pile(CardInstance.HAND).size() == 6, "Card lab deals a six-card hand")
	_check(lab.get_child_count() > 0, "Card lab builds its own scene")
	lab.queue_free()
