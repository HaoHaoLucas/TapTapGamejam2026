class_name EventService
extends RefCounted
## Seven event handlers. Config never supplies executable scripts.


static func make_view(run: RunState, room_uid: String) -> Dictionary:
	if run.event_views.has(room_uid):
		var existing: Dictionary = run.event_views[room_uid]
		var session_uid := str(existing.get("reward_session_uid", ""))
		if session_uid != "":
			var session := run.find_session(session_uid)
			if not session.is_empty():
				existing.offers = session.offers
		return existing
	var room := run.current_room
	if str(room.get("room_uid", "")) != room_uid or str(room.get("status", "")) != "ENTERED":
		return {"ok": false, "error": "房间未进入"}
	var event := GameData.event(str(room.get("content_id", "")))
	if event.is_empty():
		return {"ok": false, "error": "没有事件定义"}
	var view := {
		"ok": true,
		"room_uid": room_uid,
		"event_id": str(event.get("event_id", "")),
		"name": str(event.get("name", "")),
		"text": str(event.get("text", "")),
		"handler_id": str(event.get("handler_id", "")),
		"input_mode": str(event.get("input_mode", "")),
		"can_skip": bool(event.get("can_skip", true)),
		"params": RunState.deep_copy(event.get("params", {})),
		"offers": [],
		"eligible_target_uids": [],
		"disabled_reason": "",
		"repair": false,
		"reward_session_uid": "",
		"previews": {},
	}
	match view.handler_id:
		"COPY_CARD":
			for card in TowerDeck.deck_cards(run):
				view.eligible_target_uids.append(card.card_uid)
		"SACRIFICE_MARK":
			for card in TowerDeck.deck_cards(run):
				view.eligible_target_uids.append(card.card_uid)
		"SPECIAL_OFFER":
			var session := RewardService.open_special_offers(run, room_uid, str(view.params.get("pool_id", "")), int(view.params.get("offers", 3)))
			view.reward_session_uid = str(session.get("reward_session_uid", ""))
			view.offers = session.offers
		"MARK_OFFER":
			var session := RewardService.open_mark_offers(run, room_uid, str(view.params.get("pool_id", "")), int(view.params.get("offers", 3)))
			view.reward_session_uid = str(session.get("reward_session_uid", ""))
			view.offers = session.offers
			if session.offers.is_empty():
				view.disabled_reason = "现在没有能加到牌上的变化。"
		"ACCEPT_PIZZA":
			if TowerDeck.has_open_pizza(run):
				view.disabled_reason = "已经有一份披萨在送了。"
		"TRANSFORM_CARD":
			for card in TowerDeck.deck_cards(run):
				if TowerDeck.legal_transform_defs(run, card.card_uid).is_empty():
					continue
				view.eligible_target_uids.append(card.card_uid)
			if view.eligible_target_uids.is_empty():
				view.disabled_reason = "没有能换掉的牌。"
		"BASIC_CACHE":
			var session := RewardService.open_cache(run, room_uid, str(view.params.get("reward_id", "RW_CACHE")))
			view.reward_session_uid = str(session.get("reward_session_uid", ""))
			view.offers = session.offers
			view.repair = bool(session.get("repair", false))
			if view.repair:
				view.input_mode = "ACCEPT_OR_SKIP"
		_:
			push_error("未实现的事件处理器 %s" % view.handler_id)
			return {"ok": false, "error": "未实现的事件处理器"}
	run.event_views[room_uid] = view
	return view


static func freeze_preview(run: RunState, room_uid: String, target_uid: String) -> Dictionary:
	var view: Dictionary = run.event_views.get(room_uid, {})
	if view.is_empty():
		view = make_view(run, room_uid)
	if not view.get("ok", false):
		return view
	var previews: Dictionary = view.previews
	if previews.has(target_uid):
		return previews[target_uid]
	var legal := TowerDeck.legal_transform_defs(run, target_uid)
	if legal.is_empty():
		return {"ok": false, "error": "这张牌换不了。"}
	var weights: Array = []
	for _def_id in legal:
		weights.append(1)
	var def_id := str(legal[run.roll_weighted("ENHANCE", weights)])
	var preview := {
		"ok": true,
		"preview_uid": run.uid("P"),
		"target_uid": target_uid,
		"def_id": def_id,
		"label": TowerDeck.describe_parts(def_id, _kept_marks(run, target_uid, def_id), ""),
	}
	previews[target_uid] = preview
	view.previews = previews
	run.event_views[room_uid] = view
	return preview


static func commit(run: RunState, room_uid: String, payload: Dictionary, txn_id: String) -> Dictionary:
	if txn_id.is_empty():
		return {"ok": false, "error": "缺少事务"}
	if run.txn_results.has(txn_id):
		return RunState.deep_copy(run.txn_results[txn_id])
	var room_key := "room:%s" % room_uid
	if run.txn_results.has(room_key):
		return RunState.deep_copy(run.txn_results[room_key])
	if str(run.current_room.get("room_uid", "")) != room_uid or str(run.current_room.get("status", "")) != "ENTERED":
		return {"ok": false, "error": "房间未进入"}
	var snapshot := run.capture()
	var result := _commit_inner(run, room_uid, payload, txn_id)
	if not result.get("ok", false):
		run.rollback(snapshot)
		run.log_event({
			"kind": "event_commit",
			"room_uid": room_uid,
			"txn_id": txn_id,
			"ok": false,
			"error": str(result.get("error", "")),
		})
		return result
	run.applied_txn_ids.append(txn_id)
	var stored: Dictionary = RunState.deep_copy(result)
	run.txn_results[txn_id] = stored
	run.txn_results["room:%s" % room_uid] = stored
	run.log_event({
		"kind": "event_commit",
		"room_uid": room_uid,
		"txn_id": txn_id,
		"ok": true,
		"created": result.get("granted_card_uids", []),
		"enh_id": str(result.get("enh_id", "")),
		"target_uid": str(result.get("target_uid", "")),
	})
	return result


static func _commit_inner(run: RunState, room_uid: String, payload: Dictionary, txn_id: String) -> Dictionary:
	var view := make_view(run, room_uid)
	if not view.get("ok", false):
		return view
	var event := GameData.event(str(view.get("event_id", "")))
	if bool(payload.get("skip", false)) or (str(view.get("handler_id", "")) == "ACCEPT_PIZZA" and payload.has("accept") and not bool(payload.get("accept", false))):
		if not bool(event.get("can_skip", true)):
			return {"ok": false, "error": "这一间不能直接离开。"}
		if str(view.get("reward_session_uid", "")) != "":
			RewardService.skip_session(run, str(view.get("reward_session_uid", "")), txn_id)
		return {"ok": true, "skipped": true, "granted_card_uids": []}
	match str(view.get("handler_id", "")):
		"COPY_CARD":
			return _copy(run, payload)
		"SACRIFICE_MARK":
			return _sacrifice(run, view, payload)
		"SPECIAL_OFFER":
			return _special(run, view, payload, txn_id)
		"MARK_OFFER":
			return _mark(run, view, payload, txn_id)
		"ACCEPT_PIZZA":
			return _pizza(run, view, payload, room_uid)
		"TRANSFORM_CARD":
			return _transform(run, view, payload)
		"BASIC_CACHE":
			return _cache(run, view, payload, txn_id)
		_:
			return {"ok": false, "error": "未实现的事件处理器"}


static func _copy(run: RunState, payload: Dictionary) -> Dictionary:
	var target := run.find_card(str(payload.get("target_uid", "")))
	if target == null or target.zone != "RUN_DECK":
		return {"ok": false, "error": "只能复印牌库里的牌。"}
	var created := TowerDeck.copy_card(run, target)
	return {"ok": true, "granted_card_uids": [created.card_uid], "target_uid": target.card_uid}


static func _sacrifice(run: RunState, view: Dictionary, payload: Dictionary) -> Dictionary:
	var uids: Array = payload.get("sacrifice_uids", [])
	var params: Dictionary = view.get("params", {})
	if uids.size() < int(params.get("min", 1)) or uids.size() > int(params.get("max", 3)):
		return {"ok": false, "error": "要交 1 到 3 张，不能重复。"}
	var plan := RewardService.plan_sacrifice(run, uids)
	if not plan.get("ok", false):
		return plan
	for card_uid in uids:
		var card := run.find_card(str(card_uid))
		card.zone = "REMOVED"
	var applied: Array = []
	for grant in plan.get("grants", []):
		var result := TowerDeck.apply_mark(run, str(grant.get("target_uid", "")), str(grant.get("enh_id", "")))
		if not result.get("ok", false):
			return {"ok": false, "error": "没加上去。"}
		applied.append(grant)
	return {"ok": true, "granted_card_uids": [], "marks": applied, "removed": uids.duplicate()}


static func _special(run: RunState, view: Dictionary, payload: Dictionary, txn_id: String) -> Dictionary:
	var offer_uid := str(payload.get("offer_uid", ""))
	if not _offer_exists(view, offer_uid):
		return {"ok": false, "error": "这张不在这一次的三张里。"}
	return RewardService.commit_cards(run, str(view.get("reward_session_uid", "")), offer_uid, false, txn_id)


static func _mark(run: RunState, view: Dictionary, payload: Dictionary, txn_id: String) -> Dictionary:
	var offer_uid := str(payload.get("offer_uid", ""))
	var target_uid := str(payload.get("target_uid", ""))
	if not _offer_exists(view, offer_uid):
		return {"ok": false, "error": "这个选项不在这一次里。"}
	return RewardService.commit_mark(run, str(view.get("reward_session_uid", "")), offer_uid, target_uid, txn_id)


static func _pizza(run: RunState, view: Dictionary, payload: Dictionary, room_uid: String) -> Dictionary:
	if not bool(payload.get("accept", false)):
		return {"ok": true, "skipped": true, "granted_card_uids": []}
	if TowerDeck.has_open_pizza(run):
		return {"ok": false, "error": "已经有一份披萨在送了。"}
	var params: Dictionary = view.get("params", {})
	var offset := int(params.get("offsets", [1, 2])[run.roll_weighted("QUEST", params.get("weights", [1, 1]))])
	var quest := {
		"quest_uid": run.uid("Q"),
		"quest_type": "PIZZA",
		"source_room_uid": room_uid,
		"accepted_depth": run.depth,
		"target_depth": run.depth + offset,
		"status": "ACTIVE",
		"reward_id": str(params.get("reward_id", "RW_PIZZA")),
		"reward_seed": "",
		"reward_snapshot": [],
		"claim_txn_id": "",
		"claim_result": {},
	}
	run.quest_states.append(quest)
	RewardService.build_pizza_snapshot(run, quest)
	return {"ok": true, "quest_uid": quest.quest_uid, "target_depth": quest.target_depth, "granted_card_uids": []}


static func _transform(run: RunState, view: Dictionary, payload: Dictionary) -> Dictionary:
	var target_uid := str(payload.get("target_uid", ""))
	var preview_uid := str(payload.get("preview_uid", ""))
	var previews: Dictionary = view.get("previews", {})
	var preview: Dictionary = previews.get(target_uid, {})
	if preview.is_empty() or str(preview.get("preview_uid", "")) != preview_uid:
		return {"ok": false, "error": "刚才的结果过期了，再选一次。"}
	var card := run.find_card(target_uid)
	if card == null or card.zone != "RUN_DECK":
		return {"ok": false, "error": "这张牌不在牌库里。"}
	var def_id := str(preview.get("def_id", ""))
	if not TowerDeck.legal_transform_defs(run, target_uid).has(def_id):
		return {"ok": false, "error": "换完之后，剩下的牌打不出正数。"}
	var kind := str(GameData.card(def_id).get("card_kind", ""))
	card.def_id = def_id
	card.enhancement_ids = TowerDeck.compatible_marks(card.enhancement_ids, kind)
	card.opening_priority = 100 if card.enhancement_ids.has("EN_VANGUARD") else 0
	return {"ok": true, "target_uid": target_uid, "def_id": def_id, "granted_card_uids": []}


static func _cache(run: RunState, view: Dictionary, payload: Dictionary, txn_id: String) -> Dictionary:
	if bool(view.get("repair", false)):
		if not bool(payload.get("accept", false)):
			return {"ok": false, "error": "这箱补给要确认才能拿走。"}
		return RewardService.commit_cards(run, str(view.get("reward_session_uid", "")), "", true, txn_id)
	var offer_uid := str(payload.get("offer_uid", ""))
	if not _offer_exists(view, offer_uid):
		return {"ok": false, "error": "这张不在这箱补给里。"}
	return RewardService.commit_cards(run, str(view.get("reward_session_uid", "")), offer_uid, false, txn_id)


static func _offer_exists(view: Dictionary, offer_uid: String) -> bool:
	for offer in view.get("offers", []):
		if str(offer.get("offer_uid", "")) == offer_uid:
			return true
	return false


static func _kept_marks(run: RunState, target_uid: String, def_id: String) -> Array:
	var card := run.find_card(target_uid)
	if card == null:
		return []
	return TowerDeck.compatible_marks(card.enhancement_ids, str(GameData.card(def_id).get("card_kind", "")))
