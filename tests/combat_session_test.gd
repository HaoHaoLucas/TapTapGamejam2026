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
	_test_hosted_deck()
	_test_write_back_outcomes()
	_test_room_multipliers()
	_test_default_start()
	if _failures == 0:
		print("PASS: jam battle write-back, thief return, room multipliers, v0.3 default start")
	quit(1 if _failures else 0)


func _test_hosted_deck() -> void:
	var run := _run_for("combat-dock")
	if run == null:
		return
	_enter(run, "RM_RUST")
	var sample: CardInstance = null
	for card in TowerDeck.deck_cards(run):
		if str(GameData.card(card.def_id).get("card_kind", "")) == "NUM":
			sample = card
			break
	_check(sample != null, "Starter deck needs a number card")
	if sample == null:
		return
	sample.enhancement_ids = ["EN_NUM3"]
	var base_value := int(GameData.card(sample.def_id).get("base_value", 0))
	var session := CombatSession.new()
	session.start(run)
	var battle := session.ctx.battle
	_check(battle.player_hp == 100 and battle.player_max_hp == 100, "A new run enters combat at 100/100")
	_check(battle.monster_id == "MON_RUST" and battle.monster_name == "锈刃哥布林", "The rust room opens the rust monster, got %s" % battle.monster_name)
	_check(battle.enemy_hp == 60 and battle.enemy_max_hp == 60 and battle.intent_damage == 10, "Floor 1 rust is 60 hp and intent 10")
	_check(session.ctx.library.pile(CardInstance.HAND).size() == 5, "The jam battle draws 5")
	_check(session.ctx.library.card_count() == 15 and session.projected_uids.size() == 15, "The jam battle keeps the 15 card run deck")
	var projected := session.ctx.library.get_card(sample.card_uid)
	_check(projected != null and projected.printed_value(session.ctx.catalog) == base_value + 3, "Number cards keep the printed value")
	_check(projected.printed_value(session.ctx.catalog) == CardService.printed_value_of(sample), "The battle card uses the printed value")
	_check(CardService.printed_value_of({"def_id": sample.def_id, "enhancement_ids": ["EN_FRAGILE"]}) == base_value + 3, "Fragile adds to the printed value")
	_check(projected.enhancement_ids == ["EN_NUM3"], "Projected cards keep enhancement ids")
	for card_uid in session.projected_uids:
		_check(run.find_card(str(card_uid)) != null, "Battle ids must be run card uids")
		_check(str(card_uid).contains("_C"), "Hosted ids are not the standalone n0 deck")
	var burned := _burn_one(session, sample.card_uid)
	_check(burned != "", "A number card should be burnable")
	_check(session.ctx.library.pile(CardInstance.HAND).size() == 4, "Burn does not refill the hand")
	var outcome := session.write_back(run)
	_check(outcome == "PLAYER_ACTIVE", "An open fight writes back its phase, got %s" % outcome)
	for card_uid in session.projected_uids:
		var inst := run.find_card(str(card_uid))
		if str(card_uid) == burned:
			_check(inst.zone == "REMOVED", "Burned uid returns as REMOVED")
		else:
			_check(inst.zone == "RUN_DECK", "Unburned battle cards return to the run deck")
	_check(run.hp == int(battle.player_hp), "Player HP is written back")


func _test_write_back_outcomes() -> void:
	_check(_outcome("RM_RUST", "VICTORY") == "victory", "VICTORY writes back as a win")
	_check(_outcome("RM_RUST", "DEFEAT") == "defeat", "DEFEAT writes back as a loss")
	_check(_outcome("RM_RUST", "DECK_EXHAUSTED") == "defeat", "DECK_EXHAUSTED writes back as a loss")
	var run := _run_for("thief-return")
	if run == null:
		return
	_enter(run, "RM_THIEF")
	var session := CombatSession.new()
	session.start(run)
	var stolen := str(session.ctx.battle.stolen_card_uid)
	_check(stolen != "" and session.ctx.library.get_card(stolen).zone == CardInstance.STOLEN, "The thief battle detains a card")
	var burned := _burn_one(session, stolen)
	_check(burned != "" and burned != stolen, "Burn a card that is still in hand")
	_check(session.write_back(run) != "", "Thief write-back returns an outcome")
	_check(run.find_card(stolen).zone == "RUN_DECK", "A stolen card left at the end returns to the run deck")
	_check(run.find_card(burned).zone == "REMOVED", "A removed card stays removed")


func _test_room_multipliers() -> void:
	var second := _started("RM_RUST", 2)
	if second == null:
		return
	var rust: CardBattle = second.ctx.battle
	_check(rust.enemy_max_hp == 66 and rust.intent_damage == 11, "The second normal fight scales rust to 66 hp and 11 atk, got %s/%s" % [rust.enemy_max_hp, rust.intent_damage])
	var boss := _started("RM_SWORD", 2)
	if boss == null:
		return
	var sword: CardBattle = boss.ctx.battle
	_check(sword.enemy_max_hp == 160 and sword.intent_damage == 16, "A boss stays 160/16 when normal_used is 2, got %s/%s" % [sword.enemy_max_hp, sword.intent_damage])


func _test_default_start() -> void:
	var engine := CombatEngine.new()
	engine.start()
	_check(engine.seed == 20261009, "Default seed stays 20261009")
	_check(engine.s.hp == 80 and engine.s.maxHp == 100, "Standalone start stays at 80/100")
	_check(int(engine.s.enemies[0].hp) == 120, "Standalone enemy stays at 120")
	_check(engine.s.allIds.size() == 15 and engine.s.hand.size() == 5, "Standalone deck stays 15 cards and draws 5")
	_check(engine.s.hand[0].id == "n3", "Standalone shuffle for seed 20261009 is unchanged")
	_check(engine.invariant(), "Default invariant still expects 15 cards")


func _run_for(seed: String) -> RunState:
	var created := RunService.new_run(seed)
	_check(created.get("ok", false), "Could not start %s" % seed)
	if not created.get("ok", false):
		return null
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


func _started(room_id: String, normal_used: int) -> CombatSession:
	var run := _run_for("%s-%s" % [room_id, normal_used])
	if run == null:
		return null
	_host = run
	run.normal_used = normal_used
	_enter(run, room_id)
	var session := CombatSession.new()
	session.start(run)
	return session


func _outcome(room_id: String, phase: String) -> String:
	var session := _started(room_id, 0)
	if session == null or _host == null:
		return ""
	session.ctx.battle.phase = phase
	return session.write_back(_host)


func _burn_one(session: CombatSession, skip_uid: String) -> String:
	session.ctx.battle.player_hp = 40
	for card_uid in session.ctx.library.pile(CardInstance.HAND):
		if str(card_uid) == skip_uid:
			continue
		var card := session.ctx.library.get_card(str(card_uid))
		if card == null:
			continue
		var kind := str(session.ctx.catalog.card(card.def_id).get("card_kind", ""))
		if kind != "NUM" or card.printed_value(session.ctx.catalog) == 0:
			continue
		var result := session.ctx.card_service.burn(card.card_uid, "burn-%s" % card.card_uid)
		if result.get("ok", false) and result.get("removed", false):
			return card.card_uid
	return ""


var _host: RunState
