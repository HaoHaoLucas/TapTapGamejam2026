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
	_test_starter_filters_and_capacity()
	_test_collection_and_removed()
	_test_event_and_reward_changes()
	_test_present_does_not_touch_state()
	_test_combat_overlay_and_zones()
	_test_thief_steal_and_return()
	_test_meta_provider()
	_test_face_binding()
	if _failures == 0:
		print("PASS: run inventory snapshots, filters, combat overlay, collections")
	else:
		push_error("run inventory presenter failures: %s" % _failures)
	quit(1 if _failures else 0)


func _test_starter_filters_and_capacity() -> void:
	var run := _run_for("bag-starter")
	if run == null:
		return
	var snap := RunInventoryPresenter.present(run)
	_check(snap.cards.size() == 15, "A new run lists 15 cards, got %s" % snap.cards.size())
	_check(snap.collections.is_empty(), "A new run has no collections")
	var counts: Dictionary = snap.counts
	_check(int(counts.total) == 15, "The total count is the listed cards")
	_check(int(counts.num) + int(counts.op) == 15, "Number and operator counts cover every card")
	_check(int(counts.enhanced) == 0 and int(counts.plain) == 15, "Starter cards are unmarked")
	var seen := {}
	var kinds := {"NUM": 0, "OP": 0}
	for card in snap.cards:
		var uid := str(card.card_uid)
		_check(not seen.has(uid), "Each card keeps its own uid")
		seen[uid] = true
		_check(str(card.zone_label) == "本局牌库", "Outside combat the zone is the run deck")
		_check(int(card.acquired_depth) == 1, "Starter cards were acquired on floor 1")
		kinds[str(card.card_kind)] = int(kinds[str(card.card_kind)]) + 1
	_check(int(kinds.NUM) == int(counts.num) and int(kinds.OP) == int(counts.op), "Kind counts match the cards")
	var source: CardInstance = run.card_instances[0]
	var numeric: CardInstance = null
	for card in run.card_instances:
		if str(GameData.card(card.def_id).get("card_kind", "")) == "NUM":
			numeric = card
			break
	_check(numeric != null, "The starter deck has a number card")
	if numeric == null:
		return
	var copied := TowerDeck.copy_card(run, source)
	snap = RunInventoryPresenter.present(run)
	_check(snap.cards.size() == 16, "A copy is a separate card")
	_check(_find(snap.cards, source.card_uid) != null and _find(snap.cards, copied.card_uid) != null, "Copy and source are both listed")
	_check(str(_find(snap.cards, copied.card_uid).def_id) == source.def_id, "The copy keeps the source face")
	var mark := TowerDeck.apply_mark(run, numeric.card_uid, "EN_NUM1")
	_check(mark.get("ok", false), "A starter number can take a mark")
	snap = RunInventoryPresenter.present(run)
	var marked = _find(snap.cards, numeric.card_uid)
	_check(marked.enhancement_ids == ["EN_NUM1"], "The marked card keeps its own enhancement")
	_check(str(marked.mark_lines[0]).contains("数值增长"), "The snapshot includes the full mark line")
	_check(int(snap.counts.enhanced) == 1 and int(snap.counts.plain) == snap.cards.size() - 1, "Enhanced and plain counts split the list")
	var plain_ops := RunInventoryPresenter.filter_sort(snap.cards, "OP", "MARKED", "ACQUIRED")
	_check(plain_ops.is_empty(), "Operator plus marked filter is empty when no operator is marked")
	var numbers := RunInventoryPresenter.filter_sort(snap.cards, "NUM", "ALL", "VALUE")
	_check(not numbers.is_empty(), "Number filter keeps the number cards")
	var previous := -999999
	var previous_index := -1
	for card in numbers:
		_check(str(card.card_kind) == "NUM", "Number filter excludes operators")
		var value := int(card.printed_value)
		var index := int(card.acquired_index)
		if value == previous:
			_check(index > previous_index, "Equal values keep acquisition order")
		else:
			_check(value > previous, "Value sort is ascending")
		previous = value
		previous_index = index
	var order_before: Array = []
	for card in snap.cards:
		order_before.append(str(card.card_uid))
	RunInventoryPresenter.filter_sort(snap.cards, "ALL", "ALL", "VALUE")
	var order_after: Array = []
	for card in snap.cards:
		order_after.append(str(card.card_uid))
	_check(order_before == order_after, "Sorting returns a copy and leaves the snapshot order")
	for _i in 30:
		TowerDeck.create_card(run, "CARD_N1", [], run.depth, "")
	snap = RunInventoryPresenter.present(run)
	_check(snap.cards.size() > 40, "More than 40 cards stay in the snapshot, got %s" % snap.cards.size())
	_check(int(snap.counts.total) == snap.cards.size(), "The count does not cap the list")


func _test_collection_and_removed() -> void:
	var run := _run_for("bag-collection")
	if run == null:
		return
	var removed: CardInstance = run.card_instances[0]
	var collected: CardInstance = run.card_instances[1]
	removed.zone = CardInstance.REMOVED
	var converted := TowerDeck.apply_mark(run, collected.card_uid, "EN_ALCHEMY")
	_check(converted.get("ok", false), "Alchemy converts a deck card")
	var snap := RunInventoryPresenter.present(run)
	_check(_find(snap.cards, removed.card_uid) == null, "Removed cards stay out of the bag")
	_check(_find(snap.cards, collected.card_uid) == null, "Collections are not card-grid entries")
	_check(int(snap.counts.total) == snap.cards.size(), "Collections are not part of the card count")
	_check(snap.collections.size() == 1, "The converted card is listed once as a collection")
	if snap.collections.is_empty():
		return
	var item: Dictionary = snap.collections[0]
	_check(str(item.card_uid) == collected.card_uid, "The collection keeps the card uid")
	_check(str(item.name) == "藏品", "The collection name comes from the catalog, got %s" % item.name)
	_check(str(item.source_def_id) == collected.def_id, "The collection remembers the source card")
	_check(str(item.source_name) != "", "The source card has a display name")
	_check(int(item.value_score) == int(collected.collection_snapshot.get("value_score", -1)), "The value is the stored score")
	_check(str(item.note) == RunInventoryPresenter.RUN_RECORD_NOTE, "The collection is marked as a run record")


func _test_event_and_reward_changes() -> void:
	var copied := _run_for("bag-copy")
	if copied == null:
		return
	var before := copied.card_instances.size()
	var room_uid := _enter_event(copied, "EV_COPY", "RM_COPY")
	var target := str(TowerDeck.deck_cards(copied)[0].card_uid)
	var copy := EventService.commit(copied, room_uid, {"target_uid": target}, "bag-copy")
	_check(copy.get("ok", false), "Copy event should add a card: %s" % copy.get("error", ""))
	var snap := RunInventoryPresenter.present(copied)
	_check(snap.cards.size() == before + 1, "The bag lists the copied card")
	var smith := _run_for("bag-smith")
	if smith == null:
		return
	var smith_room := _enter_event(smith, "EV_SMITH", "RM_SMITH")
	var view := EventService.make_view(smith, smith_room)
	_check(view.get("offers", []).size() == 3, "Smith opens three marks")
	if (view.get("offers", []) as Array).is_empty():
		return
	var offer: Dictionary = view.offers[0]
	var targets: Array = TowerDeck.targets_for_mark(smith, str(offer.get("enh_id", "")))
	_check(not targets.is_empty(), "Smith has a legal target")
	if targets.is_empty():
		return
	var smith_target := str(targets[0])
	var applied := EventService.commit(smith, smith_room, {"offer_uid": str(offer.get("offer_uid", "")), "target_uid": smith_target}, "bag-smith")
	_check(applied.get("ok", false), "Smith should mark a card: %s" % applied.get("error", ""))
	var smith_snap := RunInventoryPresenter.present(smith)
	var smith_card = _find(smith_snap.cards, smith_target)
	_check(smith_card != null and not (smith_card.enhancement_ids as Array).is_empty(), "The bag shows the event mark")
	var rewarded := _run_for("bag-reward")
	if rewarded == null:
		return
	_enter_room(rewarded, "RM_RUST")
	var opened: Array = RewardService.open_combat_rewards(rewarded, rewarded.current_room)
	_check(opened.size() == 1, "Reward test needs a session")
	if opened.is_empty():
		return
	var session: Dictionary = opened[0]
	var reward_offer: Dictionary = session.get("offers", [{}])[0]
	var claimed := RewardService.commit_cards(rewarded, str(session.get("reward_session_uid", "")), str(reward_offer.get("offer_uid", "")), false, "bag-reward")
	_check(claimed.get("ok", false), "Reward claim should add a card: %s" % claimed.get("error", ""))
	var granted: Array = claimed.get("granted_card_uids", [])
	var reward_snap := RunInventoryPresenter.present(rewarded)
	_check(not granted.is_empty() and _find(reward_snap.cards, str(granted[0])) != null, "The bag lists the claimed card")
	var after_claim := var_to_str(rewarded.reward_sessions)
	RunInventoryPresenter.present(rewarded)
	RunInventoryPresenter.filter_sort(reward_snap.cards, "ALL", "ALL", "VALUE")
	_check(var_to_str(rewarded.reward_sessions) == after_claim, "Reading the bag does not change reward candidates")


func _test_present_does_not_touch_state() -> void:
	var run := _run_for("bag-pure")
	if run == null:
		return
	_enter_room(run, "RM_RUST")
	var session := CombatSession.new()
	session.start(run)
	var before := _fingerprint(run, session.ctx.library)
	var snap := RunInventoryPresenter.present(run, session.ctx.library)
	RunInventoryPresenter.filter_sort(snap.cards, "NUM", "PLAIN", "VALUE")
	RunInventoryPresenter.filter_sort(snap.cards, "OP", "ALL", "ACQUIRED")
	var after := _fingerprint(run, session.ctx.library)
	_check(var_to_str(before) == var_to_str(after), "Presenting and sorting do not change cards, piles, or random state")


func _test_combat_overlay_and_zones() -> void:
	var run := _run_for("bag-combat")
	if run == null:
		return
	_enter_room(run, "RM_RUST")
	var session := CombatSession.new()
	session.start(run)
	var library := session.ctx.library
	var sample: CardInstance = run.card_instances[0]
	var live := library.get_card(sample.card_uid)
	_check(live != null, "Combat keeps the run card uid")
	if live == null:
		return
	var saved_marks: Array = sample.enhancement_ids.duplicate()
	live.enhancement_ids = ["EN_NUM3"]
	var overlaid := RunInventoryPresenter.present(run, library)
	var over_card = _find(overlaid.cards, sample.card_uid)
	_check(over_card != null and over_card.enhancement_ids == ["EN_NUM3"], "Combat overlay shows the live card")
	_check(sample.enhancement_ids == saved_marks, "Overlay does not write the run card")
	var stale := RunInventoryPresenter.present(run)
	_check(_find(stale.cards, sample.card_uid).enhancement_ids == saved_marks, "Without a library the bag keeps the run card")
	live.enhancement_ids = saved_marks.duplicate()
	var draw_before: Array = library.pile(CardInstance.DRAW)
	_check(draw_before.size() > 1, "The draw pile has more than one card")
	var rotated: Array = draw_before.duplicate()
	var moved = rotated.pop_front()
	rotated.append(moved)
	library._piles[CardInstance.DRAW] = rotated
	var ordered := RunInventoryPresenter.present(run, library)
	var shown: Array = []
	for card in ordered.cards:
		if rotated.has(str(card.card_uid)):
			shown.append(str(card.card_uid))
	var expected: Array = rotated.duplicate()
	var index := {}
	for i in run.card_instances.size():
		index[str(run.card_instances[i].card_uid)] = i
	expected.sort_custom(func(a, b): return int(index[a]) < int(index[b]))
	_check(shown == expected, "Draw cards are listed by acquisition, not pile order")
	_check(shown != rotated, "The listed draw order is not the real draw order")
	var hand_seen := false
	var draw_seen := false
	for card in ordered.cards:
		if str(card.zone) == CardInstance.HAND:
			hand_seen = str(card.zone_label) == "手牌"
		if str(card.zone) == CardInstance.DRAW:
			draw_seen = str(card.zone_label) == "抽牌堆"
	_check(hand_seen and draw_seen, "Hand and draw cards are labeled")
	var discard_card := library.get_card(str(rotated[0]))
	_move(session, discard_card, CardInstance.DISCARD)
	var resolving_card := library.get_card(str(rotated[1]))
	_move(session, resolving_card, CardInstance.RESOLVING)
	var zoned := RunInventoryPresenter.present(run, library)
	_check(str(_find(zoned.cards, discard_card.card_uid).zone_label) == "弃牌堆", "Discard is labeled")
	_check(str(_find(zoned.cards, resolving_card.card_uid).zone_label) == "结算中", "Resolving is labeled")
	_move(session, resolving_card, CardInstance.DRAW)
	var burned := _burn_number(session, [])
	_check(burned != "", "A number card can be burned")
	var after_burn := RunInventoryPresenter.present(run, library)
	_check(_find(after_burn.cards, burned) == null, "A burned card leaves the bag")
	_check(int(after_burn.counts.total) == after_burn.cards.size(), "Burned cards are not counted")
	var smolder := _number_in(library, [burned])
	_check(smolder != "", "Smolder needs a number card")
	if smolder != "":
		var marked := session.ctx.card_service.apply_mark(smolder, "EN_SMOLDER", "bag-smolder")
		_check(marked.get("ok", false), "Smolder mark applies: %s" % marked.get("reason_code", ""))
		var smoldered := session.ctx.card_service.burn(smolder, "bag-smolder-burn")
		_check(smoldered.get("ok", false) and not smoldered.get("removed", true), "The first smolder burn keeps the card")
		var smolder_snap := RunInventoryPresenter.present(run, library)
		var smolder_card = _find(smolder_snap.cards, smolder)
		_check(smolder_card != null and bool(smolder_card.smolder_used) and bool(smolder_card.has_smolder), "The bag shows the spent smolder")
	var alchemy := _number_in(library, [burned, smolder])
	if alchemy != "":
		var gold := session.ctx.card_service.apply_mark(alchemy, "EN_ALCHEMY", "bag-gold")
		_check(gold.get("ok", false), "Combat alchemy converts the live card: %s" % gold.get("reason_code", ""))
		var gold_snap := RunInventoryPresenter.present(run, library)
		_check(_find(gold_snap.cards, alchemy) == null, "A combat collection leaves the card grid")
		_check(str(_collection_uid(gold_snap, alchemy).get("card_uid", "")) == alchemy, "A combat collection is grouped beside the cards")
		_check(run.find_card(alchemy).zone == CardInstance.RUN_DECK, "The run card stays untouched until write-back")
	var equation := _stage_equation(session, [burned, smolder, alchemy])
	_check(equation.size() == 3, "Fragile test needs two numbers and an add")
	if equation.size() == 3:
		var fragile: CardInstance = equation[0]
		var symbol: CardInstance = equation[1]
		var returning: CardInstance = equation[2]
		_check(session.ctx.card_service.apply_mark(fragile.card_uid, "EN_FRAGILE", "bag-fragile").get("ok", false), "Fragile applies")
		_check(session.ctx.card_service.apply_mark(returning.card_uid, "EN_RETURN", "bag-return").get("ok", false), "Return applies")
		_arm_fragile_break(session)
		var committed := session.ctx.equation_service.commit([fragile.card_uid, symbol.card_uid, returning.card_uid], "bag-commit")
		_check(committed.get("ok", false), "Equation commit should settle: %s" % committed.get("reason_code", ""))
		var settled := RunInventoryPresenter.present(run, library)
		_check(_find(settled.cards, fragile.card_uid) == null, "A broken fragile card leaves the bag")
		var returned = _find(settled.cards, returning.card_uid)
		_check(returned != null and bool(returned.return_used) and str(returned.zone_label) == "手牌", "The return card stays and shows the spent use")
		var symbol_card = _find(settled.cards, symbol.card_uid)
		_check(symbol_card != null and str(symbol_card.zone_label) == "弃牌堆", "The operator is discarded")
	var draw_left: Array = library.pile(CardInstance.DRAW)
	_check(not draw_left.is_empty(), "A library copy needs a draw card")
	var copied := {}
	if not draw_left.is_empty():
		copied = session.ctx.card_service.copy_card(str(draw_left[0]), "bag-lib-copy")
	_check(copied.get("ok", false), "Combat can copy a card into the library")
	var extra := RunInventoryPresenter.present(run, library)
	var extra_card = _find(extra.cards, str(copied.get("card_uid", "")))
	_check(extra_card != null and int(extra_card.acquired_index) >= run.card_instances.size(), "A library-only card is appended after the run cards")
	_check(run.find_card(str(copied.get("card_uid", ""))) == null, "The library copy is not written into the run")


func _test_thief_steal_and_return() -> void:
	var run := _run_for("bag-thief")
	if run == null:
		return
	_enter_room(run, "RM_THIEF")
	var session := CombatSession.new()
	session.start(run)
	var stolen := str(session.ctx.battle.stolen_card_uid)
	_check(stolen != "", "The thief detains a card")
	if stolen == "":
		return
	var held := RunInventoryPresenter.present(run, session.ctx.library)
	_check(str(_find(held.cards, stolen).zone_label) == "被偷走", "A stolen card is labeled without leaving the bag")
	MonsterRules.note_direct_hit(session.ctx.battle, int(session.ctx.battle.enemy_max_hp))
	var returned := RunInventoryPresenter.present(run, session.ctx.library)
	_check(str(_find(returned.cards, stolen).zone_label) == "手牌", "A returned card is back in hand")


func _test_meta_provider() -> void:
	var provider := MetaResourceProvider.new()
	_check(not provider.is_available(), "Meta resources start disconnected")
	_check(provider.list_resources().is_empty(), "The default provider has no currency")


func _test_face_binding() -> void:
	var run := _run_for("bag-face")
	if run == null:
		return
	var snap := RunInventoryPresenter.present(run)
	var face: Dictionary = snap.cards[0].face
	var view := (load("res://scenes/cards/card_view.tscn") as PackedScene).instantiate() as CardView
	view.bind_face(face)
	_check(view.face_text() == str(face.value_text), "Face binding shows the snapshot")
	_check(view.card_uid == str(face.card_uid), "Face binding keeps the card uid")
	face.value_text = "改不到"
	_check(view.face_text() != "改不到", "The view keeps its own copy of the face")
	var catalog := ConfigCatalog.load_default()
	var ctx := RunContext.new(catalog, 3, "bag-face")
	var card := ctx.library.create_instance("CARD_N4", [], 1, "")
	var zone_before := card.zone
	view.bind(ctx.library, card.card_uid)
	_check(view.face_text() == "4", "The battle bind still reads the live card")
	view.refresh()
	_check(view.face_text() == "4", "Refreshing a battle bind stays on the live card")
	_check(card.zone == zone_before, "Binding a face does not move the card")
	view.free()


func _run_for(seed: String) -> RunState:
	var created := RunService.new_run(seed)
	_check(created.get("ok", false), "Could not start %s" % seed)
	if not created.get("ok", false):
		return null
	return created.run


func _enter_room(run: RunState, room_id: String) -> void:
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


func _enter_event(run: RunState, event_id: String, room_id: String) -> String:
	var room := GameData.room(room_id)
	run.current_room = {
		"room_uid": run.uid("R"),
		"room_id": room_id,
		"content_id": event_id,
		"room_kind": str(room.get("room_kind", "EVENT")),
		"display_key": str(room.get("display_key", "ROOM_EVENT")),
		"scene_key": "event",
		"status": "ENTERED",
	}
	run.phase = "ROOM"
	return str(run.current_room.get("room_uid", ""))


func _fingerprint(run: RunState, library: CardLibrary) -> Dictionary:
	var cards: Array = []
	for card in run.card_instances:
		cards.append(card.to_dict())
	var rng := {}
	for stream in run._rng.keys():
		rng[str(stream)] = run._rng[stream].state
	var piles := {}
	if library != null:
		for zone in CardInstance.ZONES:
			piles[zone] = library.pile(zone)
	return {
		"cards": cards,
		"rng": rng,
		"piles": piles,
		"rewards": RunState.deep_copy(run.reward_sessions),
		"hp": run.hp,
	}


func _find(cards: Array, card_uid: String):
	for card in cards:
		if str(card.get("card_uid", "")) == card_uid:
			return card
	return null


func _collection_uid(snapshot: Dictionary, card_uid: String) -> Dictionary:
	for item in snapshot.get("collections", []):
		if str(item.get("card_uid", "")) == card_uid:
			return item
	return {}


func _move(session: CombatSession, card: CardInstance, zone: String) -> void:
	if card != null and card.zone != zone:
		session.ctx.library.move(card, zone, "SETUP", "bag-setup", session.ctx)


func _burn_number(session: CombatSession, skip: Array) -> String:
	for card_uid in session.ctx.library.pile(CardInstance.HAND):
		if skip.has(str(card_uid)):
			continue
		var card := session.ctx.library.get_card(str(card_uid))
		if card == null or str(session.ctx.catalog.card(card.def_id).get("card_kind", "")) != "NUM":
			continue
		if card.printed_value(session.ctx.catalog) == 0 or not card.enhancement_ids.is_empty():
			continue
		var result := session.ctx.card_service.burn(card.card_uid, "bag-burn-%s" % card.card_uid)
		if result.get("ok", false) and result.get("removed", false):
			return card.card_uid
	return ""


func _number_in(library: CardLibrary, skip: Array) -> String:
	for card in library.all_cards():
		if skip.has(card.card_uid) or card.zone == CardInstance.REMOVED or card.zone == CardInstance.COLLECTION:
			continue
		if str(library.catalog.card(card.def_id).get("card_kind", "")) != "NUM":
			continue
		if not card.enhancement_ids.is_empty():
			continue
		return card.card_uid
	return ""


func _stage_equation(session: CombatSession, skip: Array) -> Array:
	var numbers: Array = []
	var symbol: CardInstance = null
	for card in session.ctx.library.all_cards():
		if skip.has(card.card_uid) or card.zone == CardInstance.REMOVED or card.zone == CardInstance.COLLECTION:
			continue
		if not card.enhancement_ids.is_empty():
			continue
		var kind := str(session.ctx.catalog.card(card.def_id).get("card_kind", ""))
		if kind == "NUM" and numbers.size() < 2 and card.printed_value(session.ctx.catalog) != 0:
			numbers.append(card)
		elif kind == "OP" and symbol == null and card.def_id == "CARD_ADD":
			symbol = card
	if numbers.size() < 2 or symbol == null:
		return []
	for card in [numbers[0], symbol, numbers[1]]:
		_move(session, card, CardInstance.HAND)
	return [numbers[0], symbol, numbers[1]]


func _arm_fragile_break(session: CombatSession) -> void:
	var rng := session.ctx.rng_of("COMBAT")
	var chance := float(session.ctx.catalog.enh("EN_FRAGILE").get("params", {}).get("break_p", 0.15))
	for probe in range(1, 8000):
		rng._rng.seed = probe
		if rng._rng.randf() < chance:
			rng._rng.seed = probe
			return
	_check(false, "Could not find a fragile break roll")
