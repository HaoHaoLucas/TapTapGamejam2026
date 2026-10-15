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
	_test_copy_once()
	_test_smith_once()
	_test_sacrifice_rolls_back()
	_test_pizza_claim_once()
	_test_cache_fallback()
	_check(RewardService.open_combat_rewards(RunState.new(), {}).is_empty(), "Combat rewards stay empty")
	if _failures == 0:
		print("PASS: event idempotency, sacrifice rollback, pizza claim, cache fallback")
	quit(1 if _failures else 0)


func _test_copy_once() -> void:
	var run := _run_for("copy-seed")
	var room_uid := _enter(run, "EV_COPY", "RM_COPY")
	var before := _cards(run)
	var target: String = str(TowerDeck.deck_cards(run)[0].card_uid)
	var first := EventService.commit(run, room_uid, {"target_uid": target}, "copy-txn")
	_check(first.get("ok", false), "Copy should succeed: %s" % first.get("error", ""))
	_check(TowerDeck.deck_cards(run).size() == before.size() + 1, "Copy adds one card")
	var created := run.find_card(str(first.get("granted_card_uids", [""])[0]))
	var source := run.find_card(target)
	_check(created != null and created.def_id == source.def_id and created.card_uid != source.card_uid, "Copy keeps the def and gets a new uid")
	_check(created.return_used_run == source.return_used_run and created.zone == "RUN_DECK", "Copy keeps used flags and enters the run deck")
	var mid := _cards(run)
	_check(EventService.commit(run, room_uid, {"target_uid": target}, "copy-txn").get("ok", false), "Repeating the txn should succeed as a no-op")
	_check(_cards(run) == mid, "The same copy txn must not add another card")
	_check(EventService.commit(run, room_uid, {"target_uid": target}, "copy-txn-2").get("ok", false), "A second txn on the same room should replay")
	_check(_cards(run) == mid, "A second click must not copy again")


func _test_smith_once() -> void:
	var run := _run_for("smith-seed")
	var room_uid := _enter(run, "EV_SMITH", "RM_SMITH")
	var view := EventService.make_view(run, room_uid)
	_check(view.get("offers", []).size() == 3, "Smith offers three marks")
	var offer: Dictionary = view.offers[0]
	var targets: Array = TowerDeck.targets_for_mark(run, str(offer.get("enh_id", "")))
	_check(not targets.is_empty(), "Smith mark needs a legal target")
	var target := str(targets[0])
	var first := EventService.commit(run, room_uid, {"offer_uid": str(offer.get("offer_uid", "")), "target_uid": target}, "smith-txn")
	_check(first.get("ok", false), "Smith should apply: %s" % first.get("error", ""))
	var mid := _cards(run)
	_check(EventService.commit(run, room_uid, {"offer_uid": str(offer.get("offer_uid", "")), "target_uid": target}, "smith-txn").get("ok", false), "Smith replay should be ok")
	_check(_cards(run) == mid, "Smith must not apply the mark twice")
	_check(EventService.commit(run, room_uid, {"offer_uid": str(offer.get("offer_uid", "")), "target_uid": target}, "smith-txn-2").get("ok", false), "Another smith click replays the room")
	_check(_cards(run) == mid, "Another smith txn must not add a second mark")


func _test_sacrifice_rolls_back() -> void:
	var run := _run_for("sac-seed")
	for card in TowerDeck.deck_cards(run):
		card.enhancement_ids = ["EN_RETURN", "EN_GHOST"]
	var before := _cards(run)
	var room_uid := _enter(run, "EV_SAC", "RM_SAC")
	var uids: Array = []
	for card in TowerDeck.deck_cards(run):
		uids.append(card.card_uid)
		if uids.size() == 3:
			break
	var result := EventService.commit(run, room_uid, {"sacrifice_uids": uids}, "sac-txn")
	_check(not result.get("ok", false), "Sacrifice without mark targets must fail")
	_check(_cards(run) == before, "A failed sacrifice must leave the deck unchanged")


func _test_pizza_claim_once() -> void:
	var run := _run_for("pizza-seed")
	var before := run.card_instances.size()
	var room_uid := _enter(run, "EV_PIZZA", "RM_PIZZA")
	EventService.make_view(run, room_uid)
	var accepted := EventService.commit(run, room_uid, {"accept": true}, "pizza-accept")
	_check(accepted.get("ok", false), "Pizza should be accepted: %s" % accepted.get("error", ""))
	_check(run.quest_states.size() == 1, "Accepting pizza creates one quest")
	var quest: Dictionary = run.quest_states[0]
	_check(str(quest.get("status", "")) == "ACTIVE", "Pizza starts active")
	var target := int(quest.get("target_depth", 0))
	_check(target == run.depth + 1 or target == run.depth + 2, "Pizza target is one or two floors ahead")
	var snapshot: Array = quest.get("reward_snapshot", [])
	_check(snapshot.size() >= 3 and snapshot.size() <= 5, "Pizza snapshot contains 3 to 5 cards")
	_check(run.card_instances.size() == before, "The pizza parcel is not a battle card")
	for card in run.card_instances:
		_check(card.card_uid != str(quest.get("quest_uid", "")), "Quest uid must not be a card uid")
	run.depth = target
	RewardService.mark_pizza_ready(run)
	RewardService.mark_pizza_ready(run)
	_check(str(quest.get("status", "")) == "READY", "Boss victory readies the pizza once")
	_check(run.card_instances.size() == before, "Ready does not grant cards")
	var first := RewardService.claim_pizza(run, str(quest.get("quest_uid", "")), "claim-1", [])
	_check(first.get("ok", false), "Pizza claim should succeed: %s" % first.get("error", ""))
	var granted: Array = first.get("granted_card_uids", [])
	_check(granted.size() == snapshot.size(), "Claim grants the frozen snapshot")
	_check(run.card_instances.size() == before + granted.size(), "Claim adds each snapshot card once")
	var second := RewardService.claim_pizza(run, str(quest.get("quest_uid", "")), "claim-2", [])
	_check(second.get("ok", false), "Second claim callback should report the first result")
	_check(run.card_instances.size() == before + granted.size(), "Second claim must not grant again")
	_check(str(quest.get("status", "")) == "CLAIMED", "Pizza is claimed")
	for card in TowerDeck.deck_cards(run):
		_check(card.card_uid != str(quest.get("quest_uid", "")), "The parcel itself never enters the deck")


func _test_cache_fallback() -> void:
	var rows := GameData.rows("event_def")
	var saved: Array = []
	for row in rows:
		saved.append(str(row.get("condition_id", "")))
		if str(row.get("event_id", "")) != "EV_CACHE":
			row.condition_id = "CAN_SACRIFICE"
	var run := _run_for("cache-seed")
	for card in TowerDeck.deck_cards(run):
		card.enhancement_ids = ["EN_RETURN", "EN_GHOST"]
	run.normal_used = 2
	run.event_used = 0
	run.slot_index = 2
	run.pending_slot = 0
	run.current_room = {}
	run.current_offers = []
	run.visited_content_ids = []
	run.phase = "MAP"
	var generated := MapService.make_offers(run)
	_check(generated.get("ok", false), "Cache generation failed: %s" % generated.get("error", ""))
	_check(run.current_offers.size() == 3, "An empty event pool still offers three rooms")
	for offer in run.current_offers:
		_check(str(offer.get("content_id", "")) == "EV_CACHE", "Illegal normal events fall back to emergency supplies")
		_check(str(offer.get("fallback_reason", "")) == "EVENT_POOL_EMPTY", "Cache fallback should be recorded")
	var normals := run.normal_used
	var events := run.event_used
	_check(MapService.choose_room(run, str(run.current_offers[0].get("offer_uid", ""))).get("ok", false), "Could not enter cache")
	_check(run.event_used == events + 1 and run.normal_used == normals, "Cache consumes one event quota and no combat quota")
	for i in rows.size():
		rows[i].condition_id = saved[i]


func _run_for(seed: String) -> RunState:
	var created := RunService.new_run(seed)
	_check(created.get("ok", false), "Could not start %s: %s" % [seed, created.get("error", "")])
	return created.run


func _enter(run: RunState, event_id: String, room_id: String) -> String:
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


func _cards(run: RunState) -> Array:
	var rows: Array = []
	for card in run.card_instances:
		rows.append(card.to_dict())
	return rows
