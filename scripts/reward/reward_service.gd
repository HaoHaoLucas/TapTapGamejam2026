class_name RewardService
extends RefCounted
## Only this service creates reward sessions and rolls offers.
## Combat victory calls open_combat_rewards. Pizza keeps its quest-local snapshot.


static func open_combat_rewards(run: RunState, room: Dictionary) -> Array:
	var defined := GameData.room(str(room.get("room_id", "")))
	var bundle_id := str(defined.get("reward_bundle_id", ""))
	if bundle_id == "":
		return []
	var bundle := GameData.row("reward_bundle", bundle_id)
	var source_uid := str(room.get("room_uid", ""))
	var sessions: Array = []
	for reward_id in bundle.get("ordered_reward_ids", []):
		var session := _open_plan(run, source_uid, str(reward_id), true)
		if not session.is_empty():
			sessions.append(session)
	return sessions


static func open_special_offers(run: RunState, source_uid: String, pool_id: String, count: int) -> Dictionary:
	var session := _blank_session(run, source_uid, "", pool_id)
	var remaining: Array = []
	for row in GameData.rows("special_card"):
		if str(row.get("pool_id", "")) != pool_id:
			continue
		if not _depth_ok(row, run.depth):
			continue
		remaining.append(row)
	var picked: Array = []
	while picked.size() < count and not remaining.is_empty():
		var weights: Array = []
		for row in remaining:
			weights.append(int(row.get("weight", 0)))
		var index := run.roll_weighted("REWARD", weights)
		picked.append(remaining[index])
		remaining.remove_at(index)
	for row in picked:
		session.offers.append(_card_offer(run, str(row.get("def_id", "")), row.get("enhancement_ids", []), str(row.get("display_name", "")), str(row.get("special_id", ""))))
	run.reward_sessions.append(session)
	return session


static func open_mark_offers(run: RunState, source_uid: String, pool_id: String, count: int) -> Dictionary:
	var session := _blank_session(run, source_uid, "", pool_id)
	_populate_mark_offers(run, session, pool_id, count)
	run.reward_sessions.append(session)
	return session


static func open_cache(run: RunState, source_uid: String, reward_id: String) -> Dictionary:
	var session := _blank_session(run, source_uid, reward_id, "")
	var repair := not TowerDeck.is_deck_valid(run)
	session.repair = repair
	var def_ids: Array = ["CARD_N2", "CARD_N3", "CARD_ADD"] if repair else GameData.card_pool("CP_CACHE").get("fixed_def_ids", [])
	for def_id in def_ids:
		session.offers.append(_card_offer(run, str(def_id), [], "", ""))
	run.reward_sessions.append(session)
	return session


static func build_pizza_snapshot(run: RunState, quest: Dictionary) -> void:
	var reward_seed := str(run.randi_stream("QUEST"))
	var local := RngStream.make(int(reward_seed))
	var plan := GameData.reward(str(quest.get("reward_id", "RW_PIZZA")))
	var count_index := RngStream.pick_index(local, plan.get("grant_count_weights", [25, 50, 25]))
	var count := int(plan.get("grant_count_values", [3, 4, 5])[count_index])
	var depth := int(quest.get("target_depth", run.depth))
	var ctx := {"rng": local}
	var offers: Array = []
	for _i in count:
		var rolled := _roll_card(ctx, plan, depth, true, offers)
		offers.append({
			"offer_uid": run.uid("F"),
			"payload_kind": "CARD",
			"def_id": rolled.def_id,
			"enh_id": "",
			"enhancement_ids": rolled.enhancement_ids,
			"special_id": "",
			"display_name": "",
			"selected": false,
			"discarded": false,
			"eligible_target_uids": [],
		})
	quest.reward_seed = reward_seed
	quest.reward_snapshot = offers


static func plan_sacrifice(run: RunState, sacrifice_uids: Array) -> Dictionary:
	var unique := {}
	for card_uid in sacrifice_uids:
		var key := str(card_uid)
		if unique.has(key):
			return {"ok": false, "error": "这几张里有重复的。"}
		unique[key] = true
		var card := run.find_card(key)
		if card == null or card.zone != "RUN_DECK":
			return {"ok": false, "error": "这张牌不在牌库里。"}
	var size := sacrifice_uids.size()
	if size < 1 or size > 3:
		return {"ok": false, "error": "要交 1 到 3 张。"}
	var remaining: Array = []
	var targets: Array = []
	for card in TowerDeck.deck_cards(run):
		if unique.has(card.card_uid):
			continue
		remaining.append(TowerDeck._snap_instance(card))
		if not TowerDeck.marks_for(run, card.card_uid, "EP_SAFE").is_empty():
			targets.append(card.card_uid)
	if not TowerDeck.is_valid_cards(remaining):
		return {"ok": false, "error": "交完之后，剩下的牌打不出正数。"}
	if targets.size() < size:
		return {"ok": false, "error": "剩下的牌不够改。"}
	targets.sort()
	var pool := targets.duplicate()
	var chosen: Array = []
	for _i in size:
		var index := run.randi_range_stream("ENHANCE", 0, pool.size() - 1)
		chosen.append(str(pool[index]))
		pool.remove_at(index)
	var grants: Array = []
	for card_uid in chosen:
		var options := _weighted_marks(run, card_uid, "EP_SAFE", [])
		if options.is_empty():
			return {"ok": false, "error": "没有能加上的变化。"}
		var weights: Array = []
		for option in options:
			weights.append(int(option.weight))
		var enh_id := str(options[run.roll_weighted("ENHANCE", weights)].enh_id)
		grants.append({"target_uid": card_uid, "enh_id": enh_id})
	return {"ok": true, "grants": grants}


static func commit_mark(run: RunState, session_uid: String, offer_uid: String, target_uid: String, txn_id: String) -> Dictionary:
	var session := run.find_session(session_uid)
	if session.is_empty():
		return {"ok": false, "error": "没有奖励会话"}
	if str(session.get("status", "")) == "COMMITTED":
		return {"ok": true, "duplicate": true, "granted_card_uids": session.get("granted_card_uids", [])}
	if str(session.get("status", "")) != "OPEN":
		return {"ok": false, "error": "奖励已经关闭"}
	var offer := _find_offer(session, offer_uid)
	if offer.is_empty():
		return {"ok": false, "error": "这个选项不在这一次里。"}
	var applied := TowerDeck.apply_mark(run, target_uid, str(offer.get("enh_id", "")))
	if not applied.get("ok", false):
		return {"ok": false, "error": _reason_text(str(applied.get("reason", "")))}
	offer.selected = true
	session.status = "COMMITTED"
	session.applied_txn_id = txn_id
	_log_reward_resolve(run, session, offer, str(offer.get("offer_uid", "")))
	return {"ok": true, "enh_id": offer.enh_id, "target_uid": target_uid, "converted": applied.get("converted", false)}


static func commit_cards(run: RunState, session_uid: String, offer_uid: String, take_all: bool, txn_id: String) -> Dictionary:
	var session := run.find_session(session_uid)
	if session.is_empty():
		return {"ok": false, "error": "没有奖励会话"}
	if str(session.get("status", "")) == "COMMITTED":
		return {"ok": true, "duplicate": true, "granted_card_uids": session.get("granted_card_uids", []).duplicate()}
	if str(session.get("status", "")) != "OPEN":
		return {"ok": false, "error": "奖励已经关闭"}
	var chosen: Array = []
	if take_all:
		chosen = session.offers
	else:
		var offer := _find_offer(session, offer_uid)
		if offer.is_empty():
			return {"ok": false, "error": "候选不存在"}
		chosen = [offer]
	var granted: Array = []
	for offer in chosen:
		if bool(offer.get("discarded", false)):
			continue
		var card := TowerDeck.create_card(run, str(offer.get("def_id", "")), offer.get("enhancement_ids", []), run.depth, "")
		offer.selected = true
		granted.append(card.card_uid)
		_log_reward_resolve(run, session, offer, str(offer.get("offer_uid", "")))
	session.granted_card_uids = granted
	session.status = "COMMITTED"
	session.applied_txn_id = txn_id
	return {"ok": true, "granted_card_uids": granted.duplicate()}


static func skip_session(run: RunState, session_uid: String, txn_id: String) -> void:
	var session := run.find_session(session_uid)
	if session.is_empty() or str(session.get("status", "")) != "OPEN":
		return
	session.status = "SKIPPED"
	session.applied_txn_id = txn_id
	_log_reward_resolve(run, session, {}, "skip")


static func mark_pizza_ready(run: RunState) -> void:
	for quest in run.quest_states:
		if str(quest.get("quest_type", "")) != "PIZZA":
			continue
		if str(quest.get("status", "")) == "ACTIVE" and int(quest.get("target_depth", -1)) == run.depth:
			quest.status = "READY"


static func claim_pizza(run: RunState, quest_uid: String, txn_id: String, discard_offer_uids: Array) -> Dictionary:
	var quest := run.find_quest(quest_uid)
	if quest.is_empty():
		return {"ok": false, "error": "没有披萨任务"}
	if str(quest.get("claim_txn_id", "")) != "":
		return RunState.deep_copy(quest.get("claim_result", {"ok": true, "duplicate": true, "granted_card_uids": []}))
	if str(quest.get("status", "")) != "READY":
		return {"ok": false, "error": "披萨还不能领取"}
	var discard := {}
	for offer_uid in discard_offer_uids:
		discard[str(offer_uid)] = true
	var granted: Array = []
	for offer in quest.get("reward_snapshot", []):
		if discard.has(str(offer.get("offer_uid", ""))):
			offer.discarded = true
			continue
		var card := TowerDeck.create_card(run, str(offer.get("def_id", "")), offer.get("enhancement_ids", []), run.depth, "")
		offer.selected = true
		granted.append(card.card_uid)
	quest.status = "CLAIMED"
	quest.claim_txn_id = txn_id
	quest.claim_result = {"ok": true, "granted_card_uids": granted.duplicate(), "duplicate": false}
	return RunState.deep_copy(quest.claim_result)


static func fail_open_quests(run: RunState) -> void:
	for quest in run.quest_states:
		if str(quest.get("status", "")) in ["ACTIVE", "READY"]:
			quest.status = "FAILED"


static func _open_plan(run: RunState, source_uid: String, reward_id: String, allow_fallback: bool) -> Dictionary:
	var plan := GameData.reward(reward_id)
	if plan.is_empty():
		return {}
	if str(plan.get("payload_kind", "")) == "MARK":
		return _open_mark_plan(run, source_uid, plan, allow_fallback)
	return _open_card_plan(run, source_uid, plan)


static func _open_card_plan(run: RunState, source_uid: String, plan: Dictionary) -> Dictionary:
	var reward_id := str(plan.get("reward_id", ""))
	var pity_before := run.normal_plain_streak
	var session := _blank_session(run, source_uid, reward_id, str(plan.get("mark_pool_id", "")))
	session.pity_before = pity_before
	var count := int(plan.get("offer_count", 3))
	var probs := mark_probabilities(str(plan.get("quality_profile", "NORMAL")), run.depth)
	var face := {"run": run, "stream": "REWARD"}
	var use_pity := reward_id == "RW_NORMAL" and str(plan.get("pity_key", "")) == "COMMON_MARK"
	var raw_ks: Array = []
	var ks: Array = []
	for i in count:
		var raw := _sample_k(face, probs)
		var k := raw
		if use_pity and i == 0 and pity_before >= 2:
			k = maxi(raw, 1)
		raw_ks.append(raw)
		ks.append(k)
	var force_op := false
	var force_num := false
	if reward_id in ["RW_NORMAL", "RW_BOSS_CARD"]:
		var numbers := 0
		var operators := 0
		for card in TowerDeck.deck_cards(run):
			var def := GameData.card(card.def_id)
			if str(def.get("card_kind", "")) == "NUM":
				numbers += 1
			elif str(def.get("operator_code", "")) in ["ADD", "MUL"]:
				operators += 1
		force_op = operators <= 2
		force_num = numbers <= 3
	var built: Array = []
	for i in count:
		var constraint := ""
		if force_op and i == 0:
			constraint = "OP"
		elif force_num and i == 1:
			constraint = "NUM"
		var rolled := _roll_combat_card(run, plan, int(ks[i]), constraint, built)
		var offer := _card_offer(run, str(rolled.get("def_id", "")), rolled.get("enhancement_ids", []), "", "")
		offer.raw_k = int(raw_ks[i])
		offer.k = int(ks[i])
		built.append(offer)
	session.offers = built
	if use_pity:
		var marked := false
		for offer in built:
			if not (offer.get("enhancement_ids", []) as Array).is_empty():
				marked = true
				break
		run.normal_plain_streak = 0 if marked else pity_before + 1
	session.pity_after = run.normal_plain_streak
	_log_reward_generate(run, session)
	run.reward_sessions.append(session)
	return session


static func _open_mark_plan(run: RunState, source_uid: String, plan: Dictionary, allow_fallback: bool) -> Dictionary:
	var pool_id := str(plan.get("mark_pool_id", ""))
	if not TowerDeck.has_mark_target(run, pool_id):
		return _open_fallback(run, source_uid, plan, allow_fallback)
	var session := _blank_session(run, source_uid, str(plan.get("reward_id", "")), pool_id)
	_populate_mark_offers(run, session, pool_id, int(plan.get("offer_count", 3)))
	if (session.get("offers", []) as Array).is_empty():
		return _open_fallback(run, source_uid, plan, allow_fallback)
	for offer in session.offers:
		offer.raw_k = 0
		offer.k = 0
	_log_reward_generate(run, session)
	run.reward_sessions.append(session)
	return session


static func _open_fallback(run: RunState, source_uid: String, plan: Dictionary, allow_fallback: bool) -> Dictionary:
	if not allow_fallback:
		return {}
	var fallback := str(plan.get("fallback_reward_id", ""))
	if fallback == "" or fallback == str(plan.get("reward_id", "")):
		return {}
	return _open_plan(run, source_uid, fallback, false)


static func _populate_mark_offers(run: RunState, session: Dictionary, pool_id: String, count: int) -> void:
	var enh_ids := _roll_mark_ids(run, pool_id, count)
	var targets: Array = []
	for enh_id in enh_ids:
		var eligible := TowerDeck.targets_for_mark(run, enh_id)
		for card_uid in eligible:
			if not targets.has(card_uid):
				targets.append(card_uid)
		session.offers.append({
			"offer_uid": run.uid("F"),
			"payload_kind": "MARK",
			"def_id": "",
			"enh_id": enh_id,
			"enhancement_ids": [enh_id],
			"special_id": "",
			"display_name": TowerDeck.mark_line(enh_id),
			"selected": false,
			"discarded": false,
			"eligible_target_uids": eligible,
		})
	session.target_snapshot = targets


static func _roll_combat_card(run: RunState, plan: Dictionary, mark_count: int, constraint: String, existing: Array) -> Dictionary:
	var rolled := {}
	for attempt in 21:
		rolled = _roll_combat_card_once(run, plan, mark_count, constraint)
		if attempt == 20 or not _same_offer(existing, rolled):
			return rolled
	return rolled


static func _roll_combat_card_once(run: RunState, plan: Dictionary, mark_count: int, constraint: String) -> Dictionary:
	var face := {"run": run, "stream": "REWARD"}
	var mark_ctx := {"run": run, "stream": "ENHANCE"}
	var pool_id := str(plan.get("base_pool_id", ""))
	var def_id := ""
	if constraint == "OP":
		def_id = _sample_operator(face)
	elif constraint == "NUM":
		def_id = _sample_nonzero_number(face, pool_id)
	else:
		def_id = _sample_def(face, pool_id)
	var marks: Array = []
	var mark_pool := str(plan.get("mark_pool_id", ""))
	var guard := 0
	while marks.size() < mark_count and guard < 8:
		guard += 1
		var family := _sample_family(mark_ctx, mark_pool, def_id, marks)
		if family == "":
			break
		var enh_id := _sample_family_on_def(mark_ctx, family, run.depth, def_id, marks)
		if enh_id == "":
			break
		marks.append(enh_id)
	return {"def_id": def_id, "enhancement_ids": marks}


static func _sample_operator(ctx: Dictionary) -> String:
	var kind := _pick_key(ctx, {"ADD": 3, "MUL": 2})
	return "CARD_MUL" if kind == "MUL" else "CARD_ADD"


static func _sample_nonzero_number(ctx: Dictionary, pool_id: String) -> String:
	var pool := GameData.card_pool(pool_id)
	var values: Array = []
	var weights: Array = []
	var abs_values: Array = pool.get("abs_values", [])
	var abs_weights: Array = pool.get("abs_weights", [])
	for i in abs_values.size():
		if int(abs_values[i]) == 0 or int(abs_weights[i]) <= 0:
			continue
		values.append(int(abs_values[i]))
		weights.append(int(abs_weights[i]))
	if values.is_empty():
		return "CARD_N1"
	var abs_value := int(_pick_parallel(ctx, values, weights))
	var sign := _pick_key(ctx, pool.get("sign_weights", {}))
	return "CARD_NM%d" % abs_value if sign == "NEG" else "CARD_N%d" % abs_value


static func _log_reward_generate(run: RunState, session: Dictionary) -> void:
	var rows: Array = []
	for offer in session.get("offers", []):
		rows.append({
			"raw_k": int(offer.get("raw_k", 0)),
			"k": int(offer.get("k", 0)),
			"def_id": str(offer.get("def_id", "")),
			"enhancement_ids": (offer.get("enhancement_ids", []) as Array).duplicate(),
		})
	run.log_event({
		"kind": "reward_generate",
		"depth": run.depth,
		"reward_id": str(session.get("reward_id", "")),
		"offers": rows,
		"pity_before": int(session.get("pity_before", 0)),
		"pity_after": int(session.get("pity_after", 0)),
	})


static func _log_reward_resolve(run: RunState, session: Dictionary, offer: Dictionary, choice: String) -> void:
	run.log_event({
		"kind": "reward_resolve",
		"depth": run.depth,
		"reward_id": str(session.get("reward_id", "")),
		"raw_k": int(offer.get("raw_k", 0)),
		"k": int(offer.get("k", 0)),
		"def_id": str(offer.get("def_id", "")),
		"enhancement_ids": (offer.get("enhancement_ids", []) as Array).duplicate(),
		"choice": choice,
	})


static func _roll_mark_ids(run: RunState, pool_id: String, count: int) -> Array:
	var picked: Array = []
	var families := _legal_families(run, pool_id)
	var remaining := families.duplicate()
	while picked.size() < count and not remaining.is_empty():
		var weights: Array = []
		for family in remaining:
			weights.append(int(family.weight))
		var family: Dictionary = remaining[run.roll_weighted("ENHANCE", weights)]
		remaining.erase(family)
		var enh_id := _pick_family_enh(run, pool_id, str(family.family_id), picked)
		if enh_id != "":
			picked.append(enh_id)
	if picked.size() < count:
		var fresh := _all_legal_enh_options(run, pool_id, picked)
		while picked.size() < count and not fresh.is_empty():
			var weights: Array = []
			for option in fresh:
				weights.append(int(option.weight))
			var option: Dictionary = fresh[run.roll_weighted("ENHANCE", weights)]
			fresh.erase(option)
			picked.append(str(option.enh_id))
	if picked.size() < count:
		var any := _all_legal_enh_options(run, pool_id, [])
		while picked.size() < count and not any.is_empty():
			var weights: Array = []
			for option in any:
				weights.append(int(option.weight))
			picked.append(str(any[run.roll_weighted("ENHANCE", weights)].enh_id))
	return picked


static func _legal_families(run: RunState, pool_id: String) -> Array:
	var families: Array = []
	for entry in GameData.rows("enhancement_pool"):
		if str(entry.get("pool_id", "")) != pool_id or int(entry.get("weight", 0)) <= 0:
			continue
		var family := str(entry.get("family_id", ""))
		if _family_options(run, pool_id, family, []).is_empty():
			continue
		families.append({"family_id": family, "weight": int(entry.get("weight", 0))})
	return families


static func _pick_family_enh(run: RunState, pool_id: String, family: String, already: Array) -> String:
	var options := _family_options(run, pool_id, family, already)
	if options.is_empty():
		return ""
	var weights: Array = []
	for option in options:
		weights.append(int(option.weight))
	return str(options[run.roll_weighted("ENHANCE", weights)].enh_id)


static func _family_options(run: RunState, _pool_id: String, family: String, already: Array) -> Array:
	var options: Array = []
	if family == "VALUE":
		var profile := _variant_row("VAR_DEPTH", run.depth)
		for i in profile.get("enh_ids", []).size():
			var enh_id := str(profile.enh_ids[i])
			if already.has(enh_id):
				continue
			if TowerDeck.targets_for_mark(run, enh_id).is_empty():
				continue
			options.append({"enh_id": enh_id, "weight": int(profile.weights[i])})
		return options
	for enh_id in TowerDeck._family_enh_ids(family):
		if already.has(enh_id):
			continue
		if TowerDeck.targets_for_mark(run, enh_id).is_empty():
			continue
		options.append({"enh_id": enh_id, "weight": 1})
	return options


static func _all_legal_enh_options(run: RunState, pool_id: String, exclude: Array) -> Array:
	var options: Array = []
	for entry in GameData.rows("enhancement_pool"):
		if str(entry.get("pool_id", "")) != pool_id:
			continue
		var family := str(entry.get("family_id", ""))
		for option in _family_options(run, pool_id, family, exclude):
			option = option.duplicate()
			if family == "VALUE":
				option.weight = int(option.weight)
			else:
				option.weight = int(entry.get("weight", 1))
			options.append(option)
	return options


static func _weighted_marks(run: RunState, card_uid: String, pool_id: String, already: Array) -> Array:
	var card := run.find_card(card_uid)
	if card == null:
		return []
	var blocked := {}
	for enh_id in already:
		blocked[str(GameData.enh(str(enh_id)).get("family_id", ""))] = true
	for enh_id in card.enhancement_ids:
		blocked[str(GameData.enh(str(enh_id)).get("family_id", ""))] = true
	var options: Array = []
	for entry in GameData.rows("enhancement_pool"):
		if str(entry.get("pool_id", "")) != pool_id or int(entry.get("weight", 0)) <= 0:
			continue
		var family := str(entry.get("family_id", ""))
		if blocked.has(family):
			continue
		if family == "VALUE":
			var profile := _variant_row("VAR_DEPTH", run.depth)
			var ids: Array = profile.get("enh_ids", [])
			var weights: Array = profile.get("weights", [])
			for i in ids.size():
				if TowerDeck.can_apply_mark(run, card_uid, str(ids[i])).get("ok", false):
					options.append({"enh_id": str(ids[i]), "weight": int(entry.get("weight", 0)) * int(weights[i])})
			continue
		for enh_id in TowerDeck._family_enh_ids(family):
			if TowerDeck.can_apply_mark(run, card_uid, enh_id).get("ok", false):
				options.append({"enh_id": enh_id, "weight": int(entry.get("weight", 0))})
	return options


static func _roll_card(ctx: Dictionary, plan: Dictionary, depth: int, pizza: bool, existing: Array) -> Dictionary:
	var rolled := {}
	for _attempt in 20:
		rolled = _roll_card_once(ctx, plan, depth, pizza)
		if not _same_offer(existing, rolled):
			return rolled
	return rolled


static func _roll_card_once(ctx: Dictionary, plan: Dictionary, depth: int, pizza: bool) -> Dictionary:
	var probs := mark_probabilities(str(plan.get("quality_profile", "NORMAL")), depth)
	var mark_count := _sample_k(ctx, probs)
	var def_id := _sample_def(ctx, str(plan.get("base_pool_id", "")))
	var pool_id := str(plan.get("mark_pool_id", ""))
	var marks: Array = []
	var def := GameData.card(def_id)
	if pizza and str(def.get("card_kind", "")) == "NUM" and mark_count > 0 and _randf(ctx) < 0.75:
		var value_enh := _sample_variant(ctx, "VAR_PIZZA", depth, def_id, marks)
		if value_enh != "":
			marks.append(value_enh)
	var guard := 0
	while marks.size() < mark_count and guard < 8:
		guard += 1
		var family := _sample_family(ctx, pool_id, def_id, marks)
		if family == "":
			break
		var enh_id := _sample_family_on_def(ctx, family, depth, def_id, marks)
		if enh_id == "":
			break
		marks.append(enh_id)
	return {"def_id": def_id, "enhancement_ids": marks}


static func mark_probabilities(profile: String, depth: int) -> Array:
	var base := _normal_probs(depth)
	match profile:
		"FIXED_0", "NONE":
			return [1.0, 0.0, 0.0]
		"BOSS":
			var boss_p2 := minf(0.85, float(base[2]) + 0.15)
			return [0.0, 1.0 - boss_p2, boss_p2]
		"PIZZA":
			var boss_p2 := minf(0.85, float(base[2]) + 0.15)
			var pizza_p2 := minf(0.95, maxf(0.65, boss_p2 + 0.10))
			return [0.0, 1.0 - pizza_p2, pizza_p2]
		_:
			return base


static func _normal_probs(depth: int) -> Array:
	var clamped := maxi(depth, 1)
	if clamped <= 10:
		var curve := GameData.row("quality_curve", clamped)
		return [float(curve.get("p0", 0.0)), float(curve.get("p1", 0.0)), float(curve.get("p2", 0.0))]
	var p0 := maxf(0.05, 0.10 - 0.005 * float(clamped - 10))
	var p2 := minf(0.70, 0.55 + 0.015 * float(clamped - 10))
	return [p0, 1.0 - p0 - p2, p2]


static func _sample_k(ctx: Dictionary, probs: Array) -> int:
	var roll := _randf(ctx)
	if roll < float(probs[0]):
		return 0
	if roll < float(probs[0]) + float(probs[1]):
		return 1
	return 2


static func _sample_def(ctx: Dictionary, pool_id: String) -> String:
	var pool := GameData.card_pool(pool_id)
	var fixed: Array = pool.get("fixed_def_ids", [])
	if not fixed.is_empty():
		return str(fixed[_pick(ctx, _ones(fixed.size()))])
	var kind := _pick_key(ctx, pool.get("kind_weights", {}))
	if kind == "ADD":
		return "CARD_ADD"
	if kind == "MUL":
		return "CARD_MUL"
	var abs_value := int(_pick_parallel(ctx, pool.get("abs_values", []), pool.get("abs_weights", [])))
	if abs_value == 0:
		return "CARD_N0"
	var sign := _pick_key(ctx, pool.get("sign_weights", {}))
	return "CARD_NM%d" % abs_value if sign == "NEG" else "CARD_N%d" % abs_value


static func _sample_variant(ctx: Dictionary, profile_id: String, depth: int, def_id: String, marks: Array) -> String:
	var profile := _variant_row(profile_id, depth)
	var ids: Array = []
	var weights: Array = []
	for i in profile.get("enh_ids", []).size():
		var enh_id := str(profile.enh_ids[i])
		if _mark_fits_def(def_id, enh_id, marks):
			ids.append(enh_id)
			weights.append(int(profile.weights[i]))
	if ids.is_empty():
		return ""
	return str(ids[_pick(ctx, weights)])


static func _sample_family(ctx: Dictionary, pool_id: String, def_id: String, marks: Array) -> String:
	var families: Array = []
	var weights: Array = []
	for entry in GameData.rows("enhancement_pool"):
		if str(entry.get("pool_id", "")) != pool_id or int(entry.get("weight", 0)) <= 0:
			continue
		var family := str(entry.get("family_id", ""))
		if _family_blocked(marks, family):
			continue
		if not _family_has_fit(family, def_id, marks):
			continue
		families.append(family)
		weights.append(int(entry.get("weight", 0)))
	if families.is_empty():
		return ""
	return str(families[_pick(ctx, weights)])


static func _sample_family_on_def(ctx: Dictionary, family: String, depth: int, def_id: String, marks: Array) -> String:
	if family == "VALUE":
		return _sample_variant(ctx, "VAR_DEPTH", depth, def_id, marks)
	for enh_id in TowerDeck._family_enh_ids(family):
		if _mark_fits_def(def_id, enh_id, marks):
			return enh_id
	return ""


static func _family_has_fit(family: String, def_id: String, marks: Array) -> bool:
	for enh_id in TowerDeck._family_enh_ids(family):
		if _mark_fits_def(def_id, enh_id, marks):
			return true
	return false


static func _mark_fits_def(def_id: String, enh_id: String, marks: Array) -> bool:
	var enh := GameData.enh(enh_id)
	var def := GameData.card(def_id)
	if enh.is_empty() or def.is_empty():
		return false
	if enh_id == "EN_ALCHEMY":
		return false
	if not (enh.get("valid_card_kinds", []) as Array).has(str(def.get("card_kind", ""))):
		return false
	if _family_blocked(marks, str(enh.get("family_id", ""))):
		return false
	return marks.size() + int(enh.get("slot_cost", 1)) <= 2


static func _family_blocked(marks: Array, family: String) -> bool:
	for enh_id in marks:
		if str(GameData.enh(str(enh_id)).get("family_id", "")) == family:
			return true
	return false


static func _variant_row(profile_id: String, depth: int) -> Dictionary:
	for row in GameData.rows("variant_profile"):
		if str(row.get("profile_id", "")) != profile_id:
			continue
		var min_depth := int(row.get("min_depth", 1))
		var max_depth := int(row.get("max_depth", 0))
		if depth >= min_depth and (max_depth == 0 or depth <= max_depth):
			return row
	return {}


static func _same_offer(existing: Array, rolled: Dictionary) -> bool:
	var marks: Array = rolled.get("enhancement_ids", []).duplicate()
	marks.sort()
	for offer in existing:
		var other: Array = offer.get("enhancement_ids", []).duplicate()
		other.sort()
		if str(offer.get("def_id", "")) == str(rolled.get("def_id", "")) and other == marks:
			return true
	return false


static func _blank_session(run: RunState, source_uid: String, reward_id: String, pool_id: String) -> Dictionary:
	return {
		"reward_session_uid": run.uid("S"),
		"source_uid": source_uid,
		"reward_id": reward_id,
		"pool_id": pool_id,
		"depth_snapshot": run.depth,
		"status": "OPEN",
		"offers": [],
		"target_snapshot": [],
		"granted_card_uids": [],
		"applied_txn_id": "",
		"pity_before": run.normal_plain_streak,
		"pity_after": run.normal_plain_streak,
		"repair": false,
	}


static func _card_offer(run: RunState, def_id: String, marks: Array, display_name: String, special_id: String) -> Dictionary:
	var copied: Array = []
	for enh_id in marks:
		copied.append(str(enh_id))
	return {
		"offer_uid": run.uid("F"),
		"payload_kind": "CARD",
		"def_id": def_id,
		"enh_id": "",
		"enhancement_ids": copied,
		"special_id": special_id,
		"display_name": display_name,
		"selected": false,
		"discarded": false,
		"eligible_target_uids": [],
	}


static func _find_offer(session: Dictionary, offer_uid: String) -> Dictionary:
	for offer in session.get("offers", []):
		if str(offer.get("offer_uid", "")) == offer_uid:
			return offer
	return {}


static func _depth_ok(row: Dictionary, depth: int) -> bool:
	var min_depth := int(row.get("min_depth", 1))
	var max_depth := int(row.get("max_depth", 0))
	return depth >= min_depth and (max_depth == 0 or depth <= max_depth)


static func _pick(ctx: Dictionary, weights: Array) -> int:
	if ctx.has("rng"):
		return RngStream.pick_index(ctx.rng, weights)
	return (ctx.run as RunState).roll_weighted(str(ctx.stream), weights)


static func _randf(ctx: Dictionary) -> float:
	if ctx.has("rng"):
		return (ctx.rng as RandomNumberGenerator).randf()
	return (ctx.run as RunState).randf_stream(str(ctx.stream))


static func _pick_key(ctx: Dictionary, weights: Dictionary) -> String:
	var keys: Array = weights.keys()
	keys.sort()
	var values: Array = []
	for key in keys:
		values.append(int(weights[key]))
	var index := _pick(ctx, values)
	return str(keys[index]) if index >= 0 else ""


static func _pick_parallel(ctx: Dictionary, values: Array, weights: Array):
	var index := _pick(ctx, weights)
	return values[index]


static func _ones(count: int) -> Array:
	var weights: Array = []
	for _i in count:
		weights.append(1)
	return weights


static func _reason_text(reason: String) -> String:
	match reason:
		"ZONE":
			return "这张牌不在牌库里。"
		"KIND":
			return "这种变化加不到这种牌上。"
		"FAMILY":
			return "这张牌已经有同类的变化了。"
		"SLOTS":
			return "这张牌的变化已经满了。"
		"DECK":
			return "换完之后，剩下的牌打不出正数。"
		_:
			return "这种变化加不上去。"
