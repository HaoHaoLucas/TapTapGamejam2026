extends SceneTree

var _failures: int = 0


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
	_test_bundle_keys()
	_test_quality_formula()
	_test_boss_marks()
	_test_pity()
	_test_type_guarantee()
	_test_mark_fallback()
	_test_commit_once()
	_test_victory_flow()
	_test_skip_then_map()
	_test_boss_phase()
	_test_event_clear()
	_test_defeat()
	_test_pizza_and_events_ignore_pity()
	_test_reward_streams()
	_test_direct_value_roll()
	await process_frame
	if _failures == 0:
		print("PASS: reward quality, pity, type guarantee, boss fallback, victory flow")
	else:
		push_error("reward rules failures: %s" % _failures)
	quit(1 if _failures else 0)


func _test_bundle_keys() -> void:
	for room_id in ["RM_RUST", "RM_PARITY", "RM_INK", "RM_PRIEST", "RM_THIEF"]:
		_check(str(GameData.room(room_id).get("reward_bundle_id", "")) == "RB_NORMAL", "%s uses RB_NORMAL" % room_id)
	_check(str(GameData.room("RM_SWORD").get("reward_bundle_id", "")) == "RB_BOSS", "Boss uses RB_BOSS")
	for room_id in ["RM_COPY", "RM_SAC", "RM_MAGE", "RM_SMITH", "RM_PIZZA", "RM_TRANS", "RM_CACHE"]:
		_check(str(GameData.room(room_id).get("reward_bundle_id", "")) == "", "%s has no combat bundle" % room_id)
	_check(RewardService.open_combat_rewards(RunState.new(), {}).is_empty(), "A room without an id does not open rewards")


func _test_quality_formula() -> void:
	for depth in range(1, 11):
		var curve := GameData.row("quality_curve", depth)
		var probs: Array = RewardService.mark_probabilities("NORMAL", depth)
		_check(is_equal_approx(float(probs[0]), float(curve.get("p0", -1))), "Normal p0 at depth %s" % depth)
		_check(is_equal_approx(float(probs[1]), float(curve.get("p1", -1))), "Normal p1 at depth %s" % depth)
		_check(is_equal_approx(float(probs[2]), float(curve.get("p2", -1))), "Normal p2 at depth %s" % depth)
	for depth in [11, 12, 20, 30]:
		var p0 := maxf(0.05, 0.10 - 0.005 * float(depth - 10))
		var p2 := minf(0.70, 0.55 + 0.015 * float(depth - 10))
		var probs: Array = RewardService.mark_probabilities("NORMAL", depth)
		_check(is_equal_approx(float(probs[0]), p0), "Tail p0 at depth %s" % depth)
		_check(is_equal_approx(float(probs[2]), p2), "Tail p2 at depth %s" % depth)
		_check(is_equal_approx(float(probs[1]), 1.0 - p0 - p2), "Tail p1 at depth %s" % depth)
	for depth in [1, 10, 11, 40]:
		var normal: Array = RewardService.mark_probabilities("NORMAL", depth)
		var boss: Array = RewardService.mark_probabilities("BOSS", depth)
		var boss_p2 := minf(0.85, float(normal[2]) + 0.15)
		_check(is_equal_approx(float(boss[0]), 0.0), "Boss p0 stays 0 at depth %s" % depth)
		_check(is_equal_approx(float(boss[2]), boss_p2), "Boss p2 at depth %s" % depth)
		_check(is_equal_approx(float(boss[1]), 1.0 - boss_p2), "Boss p1 at depth %s" % depth)


func _test_boss_marks() -> void:
	for depth in [1, 11]:
		var run := _run_for("boss-marks-%s" % depth)
		run.depth = depth
		run.normal_plain_streak = 4
		_enter(run, "RM_SWORD")
		var opened: Array = RewardService.open_combat_rewards(run, run.current_room)
		_check(not opened.is_empty(), "Boss opens a reward at depth %s" % depth)
		if opened.is_empty():
			continue
		var session: Dictionary = opened[0]
		_check(str(session.get("reward_id", "")) == "RW_BOSS_CARD", "First boss reward is the card plan")
		_check(run.normal_plain_streak == 4, "Boss card rewards do not change pity")
		_check(int(session.get("pity_before", -1)) == 4 and int(session.get("pity_after", -1)) == 4, "Boss session keeps the pity counters")
		for offer in session.get("offers", []):
			_check(int(offer.get("raw_k", 0)) >= 1 and int(offer.get("k", 0)) >= 1, "Boss mark count is at least 1 at depth %s" % depth)
			_check((offer.get("enhancement_ids", []) as Array).size() >= 1, "Boss candidate carries a mark at depth %s" % depth)
		_check(_has_generate(run, "RW_BOSS_CARD"), "Boss generation is logged")


func _test_pity() -> void:
	var lucky := -1
	for n in 80:
		var probe := _run_for("pity-%s" % n)
		_enter(probe, "RM_RUST")
		if _count_plain_panels(probe) >= 2:
			lucky = n
			break
	_check(lucky >= 0, "Two plain normal panels should appear within 80 seeds")
	if lucky < 0:
		return
	var run := _run_for("pity-%s" % lucky)
	_enter(run, "RM_RUST")
	for panel in 2:
		var opened: Array = RewardService.open_combat_rewards(run, run.current_room)
		_check(opened.size() == 1, "Plain search opens one normal session")
		if opened.is_empty():
			return
		var session: Dictionary = opened[0]
		_check(not _has_marks(session), "The searched panels are plain")
		_check(int(session.get("pity_before", -1)) == panel, "Pity before matches the streak")
		_check(int(session.get("pity_after", -1)) == panel + 1, "A plain panel adds one to the streak")
		_check(run.normal_plain_streak == panel + 1, "The run streak matches pity_after")
		var encoded := JSON.stringify(session.get("offers", []))
		var reward_state := str(run.rng_states.REWARD.state)
		var enhance_state := str(run.rng_states.ENHANCE.state)
		var streak := run.normal_plain_streak
		RewardService.skip_session(run, str(session.get("reward_session_uid", "")), "plain-%s" % panel)
		_check(run.normal_plain_streak == streak, "Skipping a plain panel does not change pity")
		_check(JSON.stringify(session.get("offers", [])) == encoded, "Skipping does not reroll offers")
		_check(str(run.rng_states.REWARD.state) == reward_state, "Skipping does not draw the reward stream")
		_check(str(run.rng_states.ENHANCE.state) == enhance_state, "Skipping does not draw the enhance stream")
	var third: Array = RewardService.open_combat_rewards(run, run.current_room)
	_check(third.size() == 1, "The pity panel opens")
	if third.is_empty():
		return
	var pity_session: Dictionary = third[0]
	var offer: Dictionary = pity_session.get("offers", [{}])[0]
	_check(int(pity_session.get("pity_before", -1)) >= 2, "The third panel records the armed pity")
	_check(int(offer.get("k", 0)) == maxi(int(offer.get("raw_k", 0)), 1), "Pity lifts only an empty first roll")
	_check(int(offer.get("k", 0)) >= 1, "The first offer is guaranteed one mark slot")
	_check((offer.get("enhancement_ids", []) as Array).size() >= 1, "The first offer receives a mark")
	_check(int(pity_session.get("pity_after", -1)) == 0, "Any mark clears the streak")
	_check(run.normal_plain_streak == 0, "The run streak is cleared")
	var encoded_third := JSON.stringify(pity_session.get("offers", []))
	var streak_after := run.normal_plain_streak
	var reward_after := str(run.rng_states.REWARD.state)
	var sessions_before := run.reward_sessions.size()
	RewardService.skip_session(run, str(pity_session.get("reward_session_uid", "")), "pity-skip")
	_check(JSON.stringify(pity_session.get("offers", [])) == encoded_third, "Skipping the pity panel does not reroll")
	_check(run.normal_plain_streak == streak_after, "Skipping the pity panel does not count again")
	_check(str(run.rng_states.REWARD.state) == reward_after, "Skipping the pity panel does not draw again")
	_check(run.reward_sessions.size() == sessions_before, "Skipping does not open another session")
	_check(_has_resolve(run, "skip", ""), "Skip is logged")


func _test_type_guarantee() -> void:
	_check_type_case("type-both", 2, 3, true, true)
	_check_type_case("type-ops", 2, 11, true, false)
	_check_type_case("type-nums", 4, 3, false, true)


func _check_type_case(seed: String, operator_limit: int, number_limit: int, force_op: bool, force_num: bool) -> void:
	var run := _run_for(seed)
	_enter(run, "RM_RUST")
	_keep_deck(run, number_limit, operator_limit)
	var counts := _deck_counts(run)
	_check(int(counts.get("operators", -1)) == operator_limit, "%s keeps %s operators" % [seed, operator_limit])
	_check(int(counts.get("numbers", -1)) == number_limit, "%s keeps %s numbers" % [seed, number_limit])
	var expected: Array = _expected_raw_ks(run, "NORMAL", 3)
	var opened: Array = RewardService.open_combat_rewards(run, run.current_room)
	_check(opened.size() == 1, "%s opens one session" % seed)
	if opened.is_empty():
		return
	var session: Dictionary = opened[0]
	_check(str(session.get("reward_id", "")) == "RW_NORMAL", "%s is a normal card reward" % seed)
	var offers: Array = session.get("offers", [])
	_check(offers.size() == 3, "%s offers three cards" % seed)
	if offers.size() != 3:
		return
	for i in 3:
		var offer: Dictionary = offers[i]
		_check(int(offer.get("raw_k", -1)) == int(expected[i]), "%s offer %s keeps the sampled K, got %s expected %s" % [seed, i, offer.get("raw_k", -1), expected[i]])
		_check(int(offer.get("k", -1)) == int(expected[i]), "%s type guarantee does not change K" % seed)
	if force_op:
		_check(_is_operator(str(offers[0].get("def_id", ""))), "%s first offer is an operator, got %s" % [seed, offers[0].get("def_id", "")])
	if force_num:
		_check(_is_nonzero_number(str(offers[1].get("def_id", ""))), "%s second offer is a non-zero number, got %s" % [seed, offers[1].get("def_id", "")])


func _test_mark_fallback() -> void:
	var run := _run_for("fallback")
	run.normal_plain_streak = 5
	_enter(run, "RM_SWORD")
	_block_mark_targets(run)
	_check(not TowerDeck.has_mark_target(run, "EP_SMITH"), "The blocked deck has no smith target")
	var opened: Array = RewardService.open_combat_rewards(run, run.current_room)
	_check(opened.size() == 2, "Fallback still opens two sessions, got %s" % opened.size())
	if opened.size() < 2:
		return
	_check(str(opened[0].get("reward_id", "")) == "RW_BOSS_CARD", "Boss still offers a card first")
	_check(str(opened[1].get("reward_id", "")) == "RW_BOSS_CARD", "A mark with no target falls back to boss cards")
	_check(run.reward_sessions.size() == 2, "The empty mark session is not kept")
	for session in run.reward_sessions:
		_check(str(session.get("reward_id", "")) != "RW_BOSS_MARK", "No mark session remains")
		_check((session.get("offers", []) as Array).size() == 3, "Fallback cards are a full pick")
		for offer in session.get("offers", []):
			_check(str(offer.get("payload_kind", "")) == "CARD", "Fallback offers are cards")
			_check(str(offer.get("def_id", "")) != "", "Fallback offers have a card")
	_check(run.normal_plain_streak == 5, "Boss fallback does not change pity")


func _test_commit_once() -> void:
	var run := _run_for("commit-once")
	_enter(run, "RM_RUST")
	var opened: Array = RewardService.open_combat_rewards(run, run.current_room)
	_check(opened.size() == 1, "Commit test needs a normal session")
	if opened.is_empty():
		return
	var session: Dictionary = opened[0]
	var offer: Dictionary = session.get("offers", [{}])[0]
	var before := run.card_instances.size()
	var first := RewardService.commit_cards(run, str(session.get("reward_session_uid", "")), str(offer.get("offer_uid", "")), false, "reward-txn")
	_check(first.get("ok", false), "Claim should succeed: %s" % first.get("error", ""))
	_check(run.card_instances.size() == before + 1, "Claim adds one card")
	var granted: Array = first.get("granted_card_uids", [])
	_check(granted.size() == 1, "Claim returns the new uid")
	if granted.is_empty():
		return
	var created := run.find_card(str(granted[0]))
	_check(created != null and created.zone == "RUN_DECK", "Claimed card enters the run deck")
	_check(created.def_id == str(offer.get("def_id", "")), "Claimed card keeps the offer")
	var logged := run.logs.size()
	var second := RewardService.commit_cards(run, str(session.get("reward_session_uid", "")), str(offer.get("offer_uid", "")), false, "reward-txn")
	_check(second.get("ok", false) and bool(second.get("duplicate", false)), "The same txn is a duplicate")
	_check(second.get("granted_card_uids", []) == granted, "The duplicate returns the first grant")
	_check(run.card_instances.size() == before + 1, "The same txn does not grant again")
	_check(run.logs.size() == logged, "A duplicate txn is not logged again")
	var third := RewardService.commit_cards(run, str(session.get("reward_session_uid", "")), str(offer.get("offer_uid", "")), false, "reward-txn-2")
	_check(third.get("ok", false) and bool(third.get("duplicate", false)), "A second txn cannot claim a closed session")
	_check(run.card_instances.size() == before + 1, "A second txn does not grant again")
	_check(_has_resolve(run, str(offer.get("offer_uid", "")), str(offer.get("def_id", ""))), "Claim logs the choice")


func _test_victory_flow() -> void:
	var run := _run_for("victory-flow")
	_enter(run, "RM_RUST")
	var fight := CombatSession.new()
	fight.start(run)
	var during := {}
	for card_uid in fight.projected_uids:
		during[str(card_uid)] = true
	fight.write_back(run)
	var finished := RunService.finish_room(run, "victory")
	_check(finished.get("ok", false), "Victory should open rewards: %s" % finished.get("error", ""))
	_check(run.phase == "REWARD", "Victory waits on the reward phase")
	_check(str(run.current_room.get("status", "")) == "RESOLVED", "The room stays resolved")
	_check(str(run.current_room.get("room_id", "")) == "RM_RUST", "The reward room is kept")
	_check(run.current_offers.is_empty(), "The next rooms wait until the reward is closed")
	var session := _open_session(run)
	_check(str(session.get("reward_id", "")) == "RW_NORMAL", "Normal victory opens RW_NORMAL")
	_check(_has_generate(run, "RW_NORMAL"), "Generation is logged")
	var offer: Dictionary = session.get("offers", [{}])[0]
	var before := run.card_instances.size()
	var claimed := RewardService.commit_cards(run, str(session.get("reward_session_uid", "")), str(offer.get("offer_uid", "")), false, "victory-txn")
	_check(claimed.get("ok", false), "Victory claim should succeed")
	var new_uid := str(claimed.get("granted_card_uids", [""])[0])
	_check(run.card_instances.size() == before + 1, "Victory claim adds one card")
	_check(not during.has(new_uid), "The new card is not in the fight that just ended")
	_check(fight.ctx.library.get_card(new_uid) == null, "The finished fight does not contain the new card")
	_check(run.find_card(new_uid) != null and run.find_card(new_uid).zone == "RUN_DECK", "The new card enters the run deck")
	_check(run.phase == "REWARD", "Claiming does not leave the reward phase by itself")
	_check(run.current_offers.is_empty(), "Claiming does not roll the next rooms")
	var advanced := RunService.continue_after_rewards(run)
	_check(advanced.get("ok", false), "Continuing after the claim should open the map: %s" % advanced.get("error", ""))
	_check(run.phase == "MAP", "A normal room returns to the map")
	_check(run.current_offers.size() == 3, "The next rooms appear after the reward closes")
	var nxt := CombatSession.new()
	nxt.start(run)
	var created := run.find_card(new_uid)
	var projected := nxt.ctx.library.get_card(new_uid)
	_check(projected != null, "The next fight projects the new card")
	if projected != null and created != null:
		_check(projected.enhancement_ids == created.enhancement_ids, "The next fight keeps enhancement ids")
		if str(GameData.card(created.def_id).get("card_kind", "")) == "NUM":
			_check(projected.printed_value(nxt.ctx.catalog) == CardService.printed_value_of(created), "The next fight uses the printed value")
		_check(fight.ctx.library.get_card(new_uid) == null, "The finished fight still does not contain the new card")


func _test_skip_then_map() -> void:
	var run := _run_for("skip-map")
	_enter(run, "RM_RUST")
	var finished := RunService.finish_room(run, "victory")
	_check(finished.get("ok", false) and run.phase == "REWARD", "Skip path starts on the reward phase")
	var session := _open_session(run)
	var streak := run.normal_plain_streak
	var encoded := JSON.stringify(session.get("offers", []))
	RewardService.skip_session(run, str(session.get("reward_session_uid", "")), "skip-map")
	_check(run.normal_plain_streak == streak, "Skip after victory does not change pity again")
	_check(JSON.stringify(session.get("offers", [])) == encoded, "Skip after victory does not reroll")
	_check(run.current_offers.is_empty() and run.phase == "REWARD", "Skip alone does not roll the map")
	var advanced := RunService.continue_after_rewards(run)
	_check(advanced.get("ok", false) and run.current_offers.size() == 3, "Skip then continue reveals the next rooms")
	_check(_has_resolve(run, "skip", ""), "Skip is logged")


func _test_boss_phase() -> void:
	var run := _run_for("boss-flow")
	run.normal_plain_streak = 3
	var quest := {
		"quest_uid": run.uid("Q"),
		"quest_type": "PIZZA",
		"status": "ACTIVE",
		"target_depth": run.depth,
		"reward_id": "RW_PIZZA",
		"reward_snapshot": [],
	}
	run.quest_states.append(quest)
	run.slot_index = 5
	run.normal_used = 2
	run.event_used = 2
	_enter(run, "RM_SWORD")
	var finished := RunService.finish_room(run, "victory")
	_check(finished.get("ok", false), "Boss victory should succeed: %s" % finished.get("error", ""))
	_check(run.phase == "REWARD", "Boss rewards come before the floor clear")
	_check(str(quest.get("status", "")) == "READY", "Pizza is marked ready while rewards are open")
	_check(run.normal_plain_streak == 3, "Boss rewards do not change normal pity")
	_check(run.current_offers.is_empty(), "Boss victory does not roll another floor")
	var ids: Array = []
	for session in run.reward_sessions:
		if str(session.get("source_uid", "")) == str(run.current_room.get("room_uid", "")):
			ids.append(str(session.get("reward_id", "")))
	_check(ids == ["RW_BOSS_CARD", "RW_BOSS_MARK"], "Boss bundle order is card then mark, got %s" % str(ids))
	if run.reward_sessions.size() < 2:
		return
	RewardService.skip_session(run, str(run.reward_sessions[0].get("reward_session_uid", "")), "boss-skip-1")
	var early := RunService.continue_after_rewards(run)
	_check(not early.get("ok", false), "The mark session still blocks the floor")
	_check(run.phase == "REWARD", "Phase stays on rewards")
	RewardService.skip_session(run, str(run.reward_sessions[1].get("reward_session_uid", "")), "boss-skip-2")
	var done := RunService.continue_after_rewards(run)
	_check(done.get("ok", false) and run.phase == "FLOOR_CLEAR", "Both closed sessions enter floor clear")
	_check(run.normal_plain_streak == 3, "Closing boss rewards still ignores pity")


func _test_event_clear() -> void:
	var run := _run_for("event-clear")
	run.normal_plain_streak = 2
	_enter(run, "RM_MAGE")
	var before := run.reward_sessions.size()
	var finished := RunService.finish_room(run, "clear")
	_check(finished.get("ok", false), "Event clear should continue the floor: %s" % finished.get("error", ""))
	_check(run.phase != "REWARD", "Event clear does not open the combat reward phase")
	_check(run.reward_sessions.size() == before, "Event clear does not open combat rewards")
	_check(run.normal_plain_streak == 2, "Event clear does not change pity")
	_check(run.current_offers.size() == 3, "Event clear still advances the map")


func _test_defeat() -> void:
	var run := _run_for("defeat")
	_enter(run, "RM_RUST")
	var finished := RunService.finish_room(run, "defeat")
	_check(finished.get("ok", false) and bool(finished.get("ended", false)), "Defeat still ends the run")
	_check(run.phase == "DEAD" and run.outcome == "defeat", "Defeat path stays unchanged")
	_check(run.reward_sessions.is_empty(), "Defeat does not open rewards")
	_check(run.phase != "REWARD", "Defeat does not enter the reward phase")


func _test_pizza_and_events_ignore_pity() -> void:
	var run := _run_for("side-rewards")
	run.normal_plain_streak = 2
	var reward_state := str(run.rng_states.REWARD.state)
	var enhance_state := str(run.rng_states.ENHANCE.state)
	var quest := {
		"reward_id": "RW_PIZZA",
		"target_depth": run.depth,
		"reward_snapshot": [],
		"reward_seed": "",
	}
	RewardService.build_pizza_snapshot(run, quest)
	var parcel: Array = quest.get("reward_snapshot", [])
	_check(run.normal_plain_streak == 2, "Pizza does not touch pity")
	_check(str(run.rng_states.REWARD.state) == reward_state, "Pizza does not draw the reward stream")
	_check(str(run.rng_states.ENHANCE.state) == enhance_state, "Pizza does not draw the enhance stream")
	_check(parcel.size() >= 3 and parcel.size() <= 5, "Pizza still builds its parcel")
	var special := RewardService.open_special_offers(run, "mage", "SP_MAGE", 3)
	var cache := RewardService.open_cache(run, "cache", "RW_CACHE")
	var smith := RewardService.open_mark_offers(run, "smith", "EP_SMITH", 3)
	_check((special.get("offers", []) as Array).size() == 3, "Mage still offers three cards")
	_check((cache.get("offers", []) as Array).size() == 3, "Cache still offers three cards")
	_check((smith.get("offers", []) as Array).size() == 3, "Smith still offers three marks")
	_check(run.normal_plain_streak == 2, "Mage, smith, and cache do not touch pity")


func _test_reward_streams() -> void:
	var left := _run_for("streams")
	_enter(left, "RM_RUST")
	left.normal_plain_streak = 2
	var right := RunState.from_dict(left.to_dict())
	var enhance_before := str(left.rng_states.ENHANCE.state)
	right.randi_stream("ENHANCE")
	var left_open: Array = RewardService.open_combat_rewards(left, left.current_room)
	var right_open: Array = RewardService.open_combat_rewards(right, right.current_room)
	_check(left_open.size() == 1 and right_open.size() == 1, "Both stream probes open a normal reward")
	if left_open.is_empty() or right_open.is_empty():
		return
	var left_offers: Array = left_open[0].get("offers", [])
	var right_offers: Array = right_open[0].get("offers", [])
	_check(left_offers.size() == 3 and right_offers.size() == 3, "Stream probe offers three cards")
	if left_offers.size() != 3 or right_offers.size() != 3:
		return
	for i in 3:
		_check(int(left_offers[i].get("raw_k", -1)) == int(right_offers[i].get("raw_k", -2)), "Quality uses the reward stream")
		_check(int(left_offers[i].get("k", -1)) == int(right_offers[i].get("k", -2)), "Pity uses the sampled quality")
	_check(str(left_offers[0].get("def_id", "")) == str(right_offers[0].get("def_id", "x")), "Card face uses the reward stream")
	_check((left_offers[0].get("enhancement_ids", []) as Array).size() >= 1, "Pity places a mark on the first offer")
	_check(str(left.rng_states.ENHANCE.state) != enhance_before, "Marks draw the enhance stream")


func _test_direct_value_roll() -> void:
	for pool_id in ["EP_SAFE", "EP_SMITH"]:
		for depth in [1, 2]:
			var weights := {}
			for row in GameData.mark_pool_rows(pool_id, depth):
				var enh_id := str(row.get("enh_id", ""))
				_check(enh_id != "EN_GHOST", "%s still offers EN_GHOST at depth %s" % [pool_id, depth])
				weights[enh_id] = float(row.get("weight", 0.0))
			_check(is_equal_approx(float(weights.get("EN_NUM1", -1.0)), 21.0), "%s EN_NUM1 is 21 at depth %s" % [pool_id, depth])
			_check(is_equal_approx(float(weights.get("EN_NUM2", -1.0)), 7.5), "%s EN_NUM2 is 7.5 at depth %s" % [pool_id, depth])
			_check(is_equal_approx(float(weights.get("EN_NUM3", -1.0)), 1.5), "%s EN_NUM3 is 1.5 at depth %s" % [pool_id, depth])
	var total := 0.0
	for row in GameData.mark_pool_rows("EP_SAFE", 1):
		total += float(row.get("weight", 0.0))
	_check(is_equal_approx(total, 94.0), "Ghost's 6 points stay out of the safe pool, total %s" % total)
	for row in GameData.rows("enhancement_pool"):
		if str(row.get("enh_id", "")).begins_with("EN_NUM"):
			_check(str(row.get("variant_profile_id", "")) == "", "Value marks are one direct roll, not a variant step")
	var profiles := {}
	for row in GameData.rows("variant_profile"):
		profiles[str(row.get("profile_id", ""))] = true
	_check(profiles.has("VAR_PIZZA") and not profiles.has("VAR_DEPTH"), "Combat value marks do not use VAR_DEPTH")
	var run := _run_for("value-direct")
	var counts := {}
	for i in 400:
		var session := RewardService.open_mark_offers(run, "value-%s" % i, "EP_SAFE", 1)
		var offers: Array = session.get("offers", [])
		if offers.is_empty():
			continue
		var enh_id := str(offers[0].get("enh_id", ""))
		_check(enh_id != "EN_GHOST", "A rolled mark is not EN_GHOST")
		counts[enh_id] = int(counts.get(enh_id, 0)) + 1
	var num1 := int(counts.get("EN_NUM1", 0))
	var num2 := int(counts.get("EN_NUM2", 0))
	var num3 := int(counts.get("EN_NUM3", 0))
	_check(num1 > num2 * 1.5 and num2 > num3, "Value marks follow 21/7.5/1.5, got %s/%s/%s" % [num1, num2, num3])
	var special := RewardService.open_special_offers(run, "fist", "SP_MAGE", 6)
	var specials: Array = special.get("offers", [])
	_check(specials.size() == 5, "SP_FIST weight 0 leaves five mage cards, got %s" % specials.size())
	for offer in specials:
		_check(str(offer.get("special_id", "")) != "SP_FIST", "SP_FIST is not offered")
		_check(not (offer.get("enhancement_ids", []) as Array).has("EN_GHOST"), "The stopped fist is not offered")


func _count_plain_panels(run: RunState) -> int:
	var plain := 0
	for _panel in 2:
		var opened: Array = RewardService.open_combat_rewards(run, run.current_room)
		if opened.is_empty() or _has_marks(opened[0]):
			break
		plain += 1
		RewardService.skip_session(run, str(opened[0].get("reward_session_uid", "")), "scan")
	return plain


func _expected_raw_ks(run: RunState, profile: String, count: int) -> Array:
	var probe := RunState.from_dict(run.to_dict())
	var probs: Array = RewardService.mark_probabilities(profile, probe.depth)
	var ks: Array = []
	for _i in count:
		var roll := probe.randf_stream("REWARD")
		var k := 2
		if roll < float(probs[0]):
			k = 0
		elif roll < float(probs[0]) + float(probs[1]):
			k = 1
		ks.append(k)
	return ks


func _keep_deck(run: RunState, number_limit: int, operator_limit: int) -> void:
	var numbers := 0
	var operators := 0
	for card in run.card_instances:
		var def := GameData.card(card.def_id)
		if str(def.get("card_kind", "")) == "NUM":
			if numbers < number_limit:
				numbers += 1
				card.zone = "RUN_DECK"
			else:
				card.zone = "REMOVED"
		elif str(def.get("operator_code", "")) in ["ADD", "MUL"]:
			if operators < operator_limit:
				operators += 1
				card.zone = "RUN_DECK"
			else:
				card.zone = "REMOVED"
		else:
			card.zone = "REMOVED"


func _deck_counts(run: RunState) -> Dictionary:
	var numbers := 0
	var operators := 0
	for card in TowerDeck.deck_cards(run):
		var def := GameData.card(card.def_id)
		if str(def.get("card_kind", "")) == "NUM":
			numbers += 1
		elif str(def.get("operator_code", "")) in ["ADD", "MUL"]:
			operators += 1
	return {"numbers": numbers, "operators": operators}


func _block_mark_targets(run: RunState) -> void:
	var numbers: Array = []
	var add: CardInstance = null
	for card in run.card_instances:
		card.zone = "REMOVED"
		card.enhancement_ids = []
		var def := GameData.card(card.def_id)
		if str(def.get("card_kind", "")) == "NUM" and int(def.get("base_value", 0)) > 0 and numbers.size() < 2:
			numbers.append(card)
		elif add == null and str(def.get("operator_code", "")) == "ADD":
			add = card
	for card in numbers:
		card.zone = "RUN_DECK"
		card.enhancement_ids = ["EN_ECHO", "EN_FRAGILE"]
	add.zone = "RUN_DECK"
	add.enhancement_ids = ["EN_RETURN", "EN_YINYANG"]


func _has_marks(session: Dictionary) -> bool:
	for offer in session.get("offers", []):
		if not (offer.get("enhancement_ids", []) as Array).is_empty():
			return true
	return false


func _is_operator(def_id: String) -> bool:
	var def := GameData.card(def_id)
	return str(def.get("card_kind", "")) == "OP" and str(def.get("operator_code", "")) in ["ADD", "MUL"]


func _is_nonzero_number(def_id: String) -> bool:
	var def := GameData.card(def_id)
	return str(def.get("card_kind", "")) == "NUM" and int(def.get("base_value", 0)) != 0


func _open_session(run: RunState) -> Dictionary:
	var room_uid := str(run.current_room.get("room_uid", ""))
	for session in run.reward_sessions:
		if str(session.get("source_uid", "")) != room_uid:
			continue
		if str(session.get("status", "")) == "OPEN":
			return session
	return {}


func _has_generate(run: RunState, reward_id: String) -> bool:
	for entry in run.logs:
		if str(entry.get("kind", "")) != "reward_generate":
			continue
		if str(entry.get("reward_id", "")) != reward_id or int(entry.get("depth", 0)) != run.depth:
			continue
		var offers: Array = entry.get("offers", [])
		if offers.is_empty():
			continue
		var row: Dictionary = offers[0]
		if row.has("raw_k") and row.has("k") and row.has("def_id") and row.has("enhancement_ids"):
			return true
	return false


func _has_resolve(run: RunState, choice: String, def_id: String) -> bool:
	for entry in run.logs:
		if str(entry.get("kind", "")) != "reward_resolve":
			continue
		if str(entry.get("choice", "")) != choice:
			continue
		if def_id != "" and str(entry.get("def_id", "")) != def_id:
			continue
		if not entry.has("raw_k") or not entry.has("k") or not entry.has("def_id") or not entry.has("enhancement_ids"):
			continue
		if str(entry.get("reward_id", "")) == "" or int(entry.get("depth", 0)) <= 0:
			continue
		return true
	return false


func _run_for(seed: String) -> RunState:
	var created := RunService.new_run(seed)
	_check(created.get("ok", false), "Could not start %s: %s" % [seed, created.get("error", "")])
	if not created.get("ok", false):
		var blank := RunState.new()
		blank.init_new(seed)
		return blank
	return created.run


func _enter(run: RunState, room_id: String) -> void:
	var room := GameData.room(room_id)
	run.current_offers = []
	run.current_room = {
		"room_uid": run.uid("R"),
		"room_id": room_id,
		"content_id": str(room.get("content_id", "")),
		"room_kind": str(room.get("room_kind", "")),
		"display_key": str(room.get("display_key", "")),
		"scene_key": str(room.get("scene_key", "")),
		"status": "ENTERED",
	}
	run.phase = "ROOM"
