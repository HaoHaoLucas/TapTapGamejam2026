extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _ids(cards: Array) -> Array:
	var out: Array = []
	for card in cards:
		out.append(null if card == null else card.id)
	return out


func _live_ids(cards: Array) -> Array:
	var out: Array = []
	for card in cards:
		if card != null:
			out.append(card.id)
	return out


func _set_hand(engine: CombatEngine, specs: Array) -> void:
	var available: Array = []
	for card in engine.s.hand:
		if card != null:
			available.append(card)
	available.append_array(engine.s.draw)
	available.append_array(engine.s.discard)
	var chosen: Array = []
	for spec in specs:
		var index := -1
		for i in available.size():
			var card: BattleCard = available[i]
			if spec is int and card.type == "number" and card.value == spec:
				index = i
				break
			if spec is String and card.type == "operator" and card.op == spec:
				index = i
				break
		_check(index >= 0, "Requested card must be in the deck: %s" % spec)
		chosen.append(available[index])
		available.remove_at(index)
	while chosen.size() < int(CombatEngine.CFG.handSize) and not available.is_empty():
		chosen.append(available.pop_front())
	engine.s.hand = chosen
	engine.s.draw = available
	engine.s.discard = []
	engine.s.selected = []
	engine.s.operatorId = null
	engine.s.burnMode = false


func _assemble_hand(engine: CombatEngine, id_list: Array) -> void:
	var available: Array = []
	for card in engine.s.hand:
		if card != null:
			available.append(card)
	available.append_array(engine.s.draw)
	available.append_array(engine.s.discard)
	var chosen: Array = []
	for id in id_list:
		var index := -1
		for i in available.size():
			if available[i].id == id:
				index = i
				break
		_check(index >= 0, "Card id must exist: %s" % id)
		chosen.append(available[index])
		available.remove_at(index)
	while chosen.size() < int(CombatEngine.CFG.handSize) and not available.is_empty():
		chosen.append(available.pop_front())
	engine.s.hand = chosen
	engine.s.draw = available
	engine.s.discard = []
	engine.s.selected = []
	engine.s.operatorId = null
	engine.s.burnMode = false


func _pick(engine: CombatEngine, ids: Array) -> void:
	for id in ids:
		_check(engine.choose_card(id), "Must select card %s" % id)


func _pick_first_three(engine: CombatEngine) -> void:
	_pick(engine, [engine.s.hand[0].id, engine.s.hand[1].id, engine.s.hand[2].id])


func _find_card(engine: CombatEngine, id: String) -> BattleCard:
	for zone in [engine.s.hand, engine.s.draw, engine.s.discard, engine.s.burned]:
		for card in zone:
			if card != null and card.id == id:
				return card
	return null


func _run() -> void:
	_test_rng_and_deck()
	_test_invariant_and_draw_order()
	_test_fire_discards_without_refill()
	_test_nonpositive_damage()
	_test_six_reactions()
	_test_combo_and_burst()
	_test_burn_rules()
	_test_intent_and_burn_dot()
	_test_timeout_and_pause()
	_test_score_and_preview_rank()
	await process_frame
	if _failures == 0:
		print("PASS: deck, RNG, invariant, fire, reactions, combo, burn, intent, timeout, pause, score")
	quit(1 if _failures else 0)


func _test_rng_and_deck() -> void:
	var rng := CombatRng.new(CombatRng.DEFAULT_SEED)
	var expected_floats := [
		0.2487912888173014,
		0.41786690312437713,
		0.04105158778838813,
		0.2528557500336319,
		0.5918161415029317,
		0.0885949726216495,
		0.7853207394946367,
		0.2976898842025548,
	]
	for value in expected_floats:
		_check(abs(rng.next_float() - value) < 1e-12, "Mulberry32 stream must match HTML seed 20261009")
	var deck: Array = CombatRng.create_deck()
	_check(deck.size() == 15, "Deck must contain 15 physical cards")
	var ids: Array = []
	for card in deck:
		ids.append(card.id)
	_check(ids == ["n0", "n1", "n2", "n3", "n4", "n5", "n6", "n7", "n8", "n9", "n10", "p0", "p1", "m0", "m1"], "Deck IDs must be n0…n10, p0/p1, m0/m1")
	for value in range(-5, 6):
		var card: BattleCard = deck[value + 5]
		_check(card.type == "number" and card.value == value, "Number card n%s must have value %s" % [value + 5, value])
		_check(card.elem == ["fire", "ice", "spark"][(value + 5) % 3], "Element must cycle fire/ice/spark by (value+5)%3")
	_check(deck[11].op == "+" and deck[12].op == "+" and deck[13].op == "×" and deck[14].op == "×", "Operators must be two + and two ×")
	var engine := CombatEngine.new()
	_check(engine.seed == 20261009, "Default seed must be 20261009")
	_check(engine.s.phase == "intro", "Engine must start on the intro phase")


func _test_invariant_and_draw_order() -> void:
	var engine := CombatEngine.new()
	_check(engine.invariant(), "Intro state must satisfy the card-zone invariant")
	engine.start()
	_check(engine.invariant(), "Start must keep the invariant")
	_check(_ids(engine.s.hand) == ["n3", "n5", "n0", "m1", "n6"], "Seed 20261009 must draw n3, n5, n0, m1, n6")
	_check(_ids(engine.s.draw) == ["p0", "m0", "n4", "n1", "n10", "n9", "n8", "n2", "n7", "p1"], "Remaining draw pile must match HTML shuffle")
	var twin := CombatEngine.new({"seed": 20261009})
	twin.start()
	_check(_ids(twin.s.hand) == _ids(engine.s.hand) and _ids(twin.s.draw) == _ids(engine.s.draw), "The same seed must replay the same shuffle")
	engine.start()
	_check(_ids(engine.s.hand) == ["n3", "n5", "n0", "m1", "n6"], "start() with the same seed must reshuffle identically")


func _test_fire_discards_without_refill() -> void:
	var engine := CombatEngine.new()
	engine.start()
	_pick(engine, ["n0", "n3", "m1"])
	var preview: Dictionary = engine.preview()
	_check(preview.base == 10 and preview.damage == 10 and preview.burn == 4 and preview.name == "余烬叠燃", "First-hand −5 × −2 must be fire-fire for 10")
	_check(engine.fire(), "A complete equation must fire")
	_check(_ids(engine.s.hand) == [null, "n5", null, null, "n6"], "Fired slots must become empty and must not refill")
	_check(_ids(engine.s.discard) == ["n3", "n0", "m1"], "The three consumed cards must enter discard in hand order")
	_check(engine.s.draw.size() == 10, "Firing must not draw replacements")
	_check(engine.s.enemies[0].hp == 110 and engine.s.enemies[0].burn == 4, "Fire-fire must deal 10 and apply 4 burn")
	_check(engine.s.lastEquation == "(−5) × (−2) = 10" and engine.s.reaction == "余烬叠燃", "Equation text must use HTML minus and ×")
	_check(not engine.has_combo(), "Two leftover numbers without an operator cannot form another cast")
	_check(engine.invariant(), "Invariant must hold after firing")
	_check(not engine.fire(), "Firing without a complete equation must fail")


func _test_nonpositive_damage() -> void:
	var negative := CombatEngine.new()
	negative.start()
	_set_hand(negative, [1, -2, "×"])
	_pick_first_three(negative)
	var preview: Dictionary = negative.preview()
	_check(preview.base == -2 and preview.damage == 0 and preview.name == "未形成攻击" and preview.burn == 0, "A negative product must preview 0 damage and no reaction")
	_check(negative.fire(), "Non-positive equations still consume the three cards")
	_check(negative.s.enemies[0].hp == 120 and negative.s.stats.damage == 0 and negative.s.streak == 0, "Non-positive fire must deal 0 and break streak")
	_check(negative.s.reaction == "未形成攻击", "Reaction name must stay 未形成攻击")
	_check(_live_ids(negative.s.hand).size() == 2, "Non-positive fire still discards three cards")
	var zero := CombatEngine.new()
	zero.start()
	_set_hand(zero, [1, 0, "×"])
	_pick_first_three(zero)
	_check(zero.preview().damage == 0 and zero.fire() and zero.s.enemies[0].hp == 120, "Zero product must deal 0")
	var sum := CombatEngine.new()
	sum.start()
	_set_hand(sum, [1, 2, "+"])
	_pick_first_three(sum)
	_check(sum.fire() and sum.s.streak == 1, "Positive addition must start a streak")
	sum.end_turn()
	sum.advance(1.0)
	_set_hand(sum, [-5, 2, "+"])
	_pick_first_three(sum)
	_check(sum.preview().damage == 0 and sum.fire() and sum.s.streak == 0 and sum.s.windows == 0, "A non-positive add must break an unfinished streak")


func _test_six_reactions() -> void:
	var cases := [
		{"nums": [1, 4], "name": "余烬叠燃", "damage": 4, "bonus": 0, "burn": 4, "chill": false, "vulnerable": 0, "hp": 116, "color": "fire"},
		{"nums": [2, 5], "name": "冻结", "damage": 10, "bonus": 0, "burn": 0, "chill": true, "vulnerable": 0, "hp": 110, "color": "ice"},
		{"nums": [1, 2], "name": "蒸汽爆破", "damage": 10, "bonus": 8, "burn": 0, "chill": false, "vulnerable": 0, "hp": 110, "color": "steam"},
		{"nums": [1, 3], "name": "过载", "damage": 7, "bonus": 4, "burn": 2, "chill": false, "vulnerable": 0, "hp": 113, "color": "fire"},
		{"nums": [2, 3], "name": "超导", "damage": 6, "bonus": 0, "burn": 0, "chill": false, "vulnerable": 2, "hp": 114, "color": "spark"},
	]
	for case in cases:
		var engine := CombatEngine.new()
		engine.start()
		_set_hand(engine, [case.nums[0], case.nums[1], "×"])
		_pick_first_three(engine)
		var preview: Dictionary = engine.preview()
		_check(preview.name == case.name and preview.damage == case.damage and preview.bonus == case.bonus, "Preview must match HTML reaction %s" % case.name)
		_check(preview.burn == case.burn and preview.chill == case.chill and preview.vulnerable == case.vulnerable and preview.color == case.color, "Status fields must match %s" % case.name)
		_check(engine.fire(), "Reaction %s must fire" % case.name)
		var enemy: Dictionary = engine.s.enemies[0]
		_check(enemy.hp == case.hp and enemy.burn == case.burn and enemy.chill == case.chill and enemy.vulnerable == case.vulnerable, "Enemy state after %s must match HTML" % case.name)
		_check(engine.s.reaction == case.name and engine.invariant(), "Reaction name and invariant after %s" % case.name)
	var spark := CombatEngine.new()
	spark.start()
	_find_card(spark, "n5").value = 1
	_assemble_hand(spark, ["n5", "n8", "m0"])
	_pick(spark, ["n5", "n8", "m0"])
	var spark_preview: Dictionary = spark.preview()
	_check(spark_preview.name == "电弧穿刺" and spark_preview.bonus == 6 and spark_preview.damage == 9 and spark_preview.color == "spark", "spark-spark must add 6 bonus when the product is positive")
	_check(spark.fire() and spark.s.enemies[0].hp == 111 and spark.s.reaction == "电弧穿刺", "电弧穿刺 must deal 9")
	var vuln := CombatEngine.new()
	vuln.start()
	_set_hand(vuln, [2, 3, "×"])
	_pick_first_three(vuln)
	_check(vuln.fire() and vuln.s.enemies[0].vulnerable == 2, "Superconduct must apply two vulnerable stacks")
	vuln.end_turn()
	vuln.advance(1.0)
	_set_hand(vuln, [1, 2, "+"])
	_pick_first_three(vuln)
	var boosted: Dictionary = vuln.preview()
	_check(boosted.factor == 1.5 and boosted.damage == 5, "Vulnerable 1+2 must ceil 4.5 to 5")
	_check(vuln.fire() and vuln.s.enemies[0].vulnerable == 1 and vuln.s.enemies[0].hp == 109, "The attack that consumed vulnerable must leave one stack")


func _test_combo_and_burst() -> void:
	var engine := CombatEngine.new()
	engine.start()
	_set_hand(engine, [1, 2, "+"])
	_pick_first_three(engine)
	_check(engine.fire() and engine.s.streak == 1 and engine.s.windows == 0, "First positive add stores a cross-turn streak")
	engine.end_turn()
	engine.advance(1.0)
	_set_hand(engine, [3, 4, "+"])
	_pick_first_three(engine)
	_check(engine.fire() and engine.s.streak == 0 and engine.s.windows == 1, "Second positive add must open a burst window")
	_check(engine.end_turn() and engine.s.phase == "burst" and engine.s.burstDuration == 3.0 and engine.s.windows == 0, "Ending the turn with a window must enter the 3s burst")
	var hp: int = engine.s.enemies[0].hp
	_check(engine.burst_hit() and engine.s.enemies[0].hp == hp - 2, "Each burst hit must deal 2")
	_check(not engine.burst_hit(), "Burst hits must respect the 0.055s cooldown")
	engine.advance(0.06)
	_check(engine.burst_hit() and engine.s.burstHits == 2 and engine.s.enemies[0].hp == hp - 4, "A second hit must land after the cooldown")
	engine.advance(3.0)
	_check(engine.s.phase == "enemy" and engine.s.enemyStage == "windup", "Burst timeout must hand the turn to the enemy")
	var interrupted := CombatEngine.new()
	interrupted.start()
	_set_hand(interrupted, [1, 2, "+"])
	_pick_first_three(interrupted)
	interrupted.fire()
	interrupted.end_turn()
	interrupted.advance(1.0)
	_set_hand(interrupted, [1, 4, "×"])
	_pick_first_three(interrupted)
	interrupted.fire()
	_check(interrupted.s.streak == 0 and interrupted.s.windows == 0, "Multiplication must break an unfinished add streak")


func _test_burn_rules() -> void:
	var engine := CombatEngine.new()
	engine.start()
	_set_hand(engine, [0, 1, 2, "+", "×"])
	var plus: BattleCard = engine.s.hand[3]
	var zero: BattleCard = engine.s.hand[0]
	_check(not engine.burn(plus.id), "Operators cannot be burned")
	_check(not engine.burn(zero.id), "0 cannot be burned")
	engine.s.hp = 100
	_check(not engine.burn(engine.s.hand[1].id), "Burning is refused at full HP")
	engine.s.hp = 80
	_check(engine.burn(engine.s.hand[2].id), "A non-zero number must burn while HP is missing")
	_check(engine.s.hp == 100 and engine.s.stats.healing == 20 and _ids(engine.s.burned) == ["n7"], "Burning 2 must heal 20 and exile n7")
	_check(_ids(engine.s.hand) == ["n5", "n6", null, "p0", "m1"], "Burned slot stays empty and is not refilled")
	_check(engine.invariant(), "Invariant must hold after a legal burn")
	var locked := CombatEngine.new()
	locked.start()
	var all_cards: Array = []
	for zone in [locked.s.hand, locked.s.draw, locked.s.discard]:
		for card in zone:
			if card != null:
				all_cards.append(card)
	var keep: Array = []
	var exile: Array = []
	for card in all_cards:
		if card.id in ["n5", "n0", "n6"] or card.type == "operator":
			keep.append(card)
		else:
			exile.append(card)
	var hand: Array = []
	for id in ["n5", "n0", "n6", "p0", "m0"]:
		for card in keep:
			if card.id == id:
				hand.append(card)
				break
	var draw: Array = []
	for card in keep:
		if not hand.has(card):
			draw.append(card)
	locked.s.hand = hand
	locked.s.draw = draw
	locked.s.discard = []
	locked.s.burned = exile
	locked.s.selected = []
	locked.s.operatorId = null
	_check(locked.invariant(), "Exiling unused numbers must keep a legal 15-card layout")
	_check(not locked.burn("n6") and locked.s.hand[2].id == "n6", "Burning the last positive partner of 0 and −5 must be refused")
	_check(locked.invariant(), "A refused burn must leave every card in a zone")


func _test_intent_and_burn_dot() -> void:
	var intents := [
		{"round": 1, "damage": 8, "verb": "裂隙冲击"},
		{"round": 2, "damage": 10, "verb": "裂隙冲击"},
		{"round": 3, "damage": 12, "verb": "深渊崩解"},
		{"round": 4, "damage": 13, "verb": "深渊崩解"},
		{"round": 5, "damage": 14, "verb": "深渊崩解"},
	]
	for row in intents:
		var probe := CombatEngine.new()
		probe.start()
		probe.s.round = row.round
		var intent: Dictionary = probe.intent()
		_check(intent.damage == row.damage and intent.verb == row.verb, "Round %s intent must match HTML" % row.round)
	var engine := CombatEngine.new()
	engine.start()
	_check(engine.intent().damage == 8, "Round 1 intent is 8")
	_set_hand(engine, [1, 4, "×"])
	_pick_first_three(engine)
	engine.fire()
	_check(engine.s.enemies[0].hp == 116 and engine.s.enemies[0].burn == 4, "Fire-fire sets up 4 burn")
	engine.end_turn()
	engine.advance(0.24)
	_check(engine.s.enemies[0].hp == 112 and engine.s.enemies[0].burn == 2, "Burn ticks for current stacks then halves")
	_check(engine.s.hp == 72 and engine.s.phase == "enemy" and engine.s.enemyStage == "recover", "After DoT the enemy still hits for 8")
	engine.advance(0.28)
	_check(engine.s.round == 2 and engine.s.phase == "player" and engine.intent().damage == 10, "Recover must start round 2 with intent 10")
	var chilled := CombatEngine.new()
	chilled.start()
	_set_hand(chilled, [2, 5, "×"])
	_pick_first_three(chilled)
	chilled.fire()
	_check(chilled.intent().damage == 4 and chilled.intent().chilled, "Freeze must halve the pending 8 to 4")
	chilled.end_turn()
	chilled.advance(0.24)
	_check(chilled.s.hp == 76 and not chilled.s.enemies[0].chill, "A chilled hit deals 4 and then clears freeze")


func _test_timeout_and_pause() -> void:
	var engine := CombatEngine.new()
	engine.start()
	engine.advance(10.0)
	_check(engine.s.phase == "enemy" and engine.s.enemyStage == "windup", "A full 10s must end the player turn")
	_check(engine.s.remaining == 0.0 and engine.s.stats.skips == 1, "Timeout with no equation counts as a skip")
	_check(is_equal_approx(engine.s.stats.time, 10.0) and is_equal_approx(engine.clock, 10.0), "Player time and clock must both accumulate 10s")
	_check(engine.s.hp == 80, "Timeout itself must not apply the enemy hit yet")
	var paused := CombatEngine.new()
	paused.start()
	paused.set_paused(true)
	_check(not paused.s.ranked and paused.active() == false, "Pausing during play cancels ranked status")
	var remaining: float = paused.s.remaining
	paused.advance(5.0)
	_check(paused.s.remaining == remaining, "Advance must not tick while paused")
	paused.set_paused(false)
	paused.set_preview(true)
	_check(not paused.s.ranked and paused.s.showPreview, "Assist preview also cancels ranked status")
	var intro := CombatEngine.new()
	intro.set_paused(true)
	_check(intro.s.ranked, "Pausing on the intro screen must not unrank")
	intro.set_preview(true)
	_check(intro.s.ranked, "Preview on intro must not unrank")


func _test_score_and_preview_rank() -> void:
	var engine := CombatEngine.new()
	engine.start()
	_check(engine.score() == 0, "Unfinished battles score 10 × damage")
	_set_hand(engine, [1, 4, "×"])
	_pick_first_three(engine)
	engine.fire()
	_check(engine.score() == 40, "4 damage must score 40 before victory")
	engine.s.phase = "victory"
	_check(engine.score() == 2200, "Victory with 0 time and 80 HP on round 1 must be 2200")
	_check(engine.choose_card("n6") == false, "Victory must freeze further card choices")
	engine.s.selected = ["missing"]
	_check(not engine.invariant(), "Selected IDs that are not live number cards must fail the invariant")
