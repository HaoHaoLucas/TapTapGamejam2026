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
	_test_default_start()
	if _failures == 0:
		print("PASS: hosted deck uids, burned cards removed, default start unchanged")
	quit(1 if _failures else 0)


func _test_hosted_deck() -> void:
	var created := RunService.new_run("combat-dock")
	_check(created.get("ok", false), "Hosted run failed to start")
	if not created.get("ok", false):
		return
	var run: RunState = created.run
	var sample: CardInstance = null
	for card in TowerDeck.deck_cards(run):
		if str(GameData.card(card.def_id).get("card_kind", "")) == "NUM":
			sample = card
			break
	_check(sample != null, "Starter deck needs a number card")
	sample.enhancement_ids = ["EN_NUM3"]
	var base_value := int(GameData.card(sample.def_id).get("base_value", 0))
	var session := CombatSession.new()
	session.start(run)
	var engine := session.engine
	_check(engine.s.hp == 100 and engine.s.maxHp == 100, "A new run enters combat at 100/100")
	_check(int(engine.s.enemies[0].hp) == 120 and str(engine.s.enemies[0].name) == "深渊观测者", "Hosted fights still use the watcher")
	_check(engine.s.hand.size() == 5 and engine.s.allIds.size() == 15, "Hosted combat keeps a 5 card hand and the run deck")
	_check(engine.invariant(), "External deck invariant should follow the actual card count")
	var projected: BattleCard = null
	for zone in [engine.s.hand, engine.s.draw, engine.s.discard]:
		for card in zone:
			if card != null and card.id == sample.card_uid:
				projected = card
	_check(projected != null and projected.value == base_value + 3, "Number cards project the printed value")
	_check(projected.value == CardService.printed_value_of(sample), "Projection uses the printed value")
	_check(CardService.printed_value_of({"def_id": sample.def_id, "enhancement_ids": ["EN_FRAGILE"]}) == base_value + 3, "Fragile adds to the printed value")
	_check(projected.enhancement_ids == ["EN_NUM3"], "Projected cards keep enhancement ids")
	_check(projected.marks.has("数值增长 +3"), "Marks are carried for display")
	for card_id in engine.s.allIds:
		_check(run.find_card(str(card_id)) != null, "Battle ids must be run card uids")
		_check(str(card_id).contains("_C"), "Hosted ids are not the standalone n0 deck")
	var burned := _burn_one(engine)
	_check(burned != "", "A number card should be burnable")
	_check(session.write_back(run) != "", "Write-back returns the battle phase")
	for card_id in session.projected_uids:
		var inst := run.find_card(str(card_id))
		if str(card_id) == burned:
			_check(inst.zone == "REMOVED", "Burned uid returns as REMOVED")
		else:
			_check(inst.zone == "RUN_DECK", "Unburned battle cards return to the run deck")
	_check(run.hp == int(engine.s.hp), "Player HP is written back")


func _test_default_start() -> void:
	var engine := CombatEngine.new()
	engine.start()
	_check(engine.seed == 20261009, "Default seed stays 20261009")
	_check(engine.s.hp == 80 and engine.s.maxHp == 100, "Standalone start stays at 80/100")
	_check(int(engine.s.enemies[0].hp) == 120, "Standalone enemy stays at 120")
	_check(engine.s.allIds.size() == 15 and engine.s.hand.size() == 5, "Standalone deck stays 15 cards and draws 5")
	_check(engine.s.hand[0].id == "n3", "Standalone shuffle for seed 20261009 is unchanged")
	_check(engine.invariant(), "Default invariant still expects 15 cards")


func _burn_one(engine: CombatEngine) -> String:
	engine.s.hp = 40
	var pool: Array = []
	for zone in [engine.s.hand, engine.s.draw, engine.s.discard]:
		for card in zone:
			if card != null and card.type == "number" and card.value != 0:
				pool.append(card)
	for card in pool:
		_place_in_hand(engine, card)
		if engine.burn(card.id):
			return card.id
	return ""


func _place_in_hand(engine: CombatEngine, card: BattleCard) -> void:
	if engine.s.hand.has(card):
		return
	engine.s.draw.erase(card)
	engine.s.discard.erase(card)
	if engine.s.hand.size() >= int(CombatEngine.CFG.handSize):
		var displaced = engine.s.hand[0]
		engine.s.hand[0] = card
		if displaced != null:
			engine.s.draw.append(displaced)
	else:
		engine.s.hand.append(card)
