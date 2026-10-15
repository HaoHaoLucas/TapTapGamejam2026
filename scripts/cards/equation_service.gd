class_name EquationService
extends RefCounted
## Preview is pure. Commit follows the jam settlement order and does not rerun an action id.

var _run: WeakRef


func _init(ctx: RunContext) -> void:
	_run = weakref(ctx)


func preview(ordered_uids: Array, combat_snapshot: Dictionary = {}) -> Dictionary:
	var evaluated := _evaluate(ordered_uids, combat_snapshot)
	return {
		"ok": evaluated.ok,
		"reason_code": str(evaluated.get("reason_code", "")),
		"primary_op": str(evaluated.get("primary_op", "")),
		"raw_result": int(evaluated.get("raw_result", 0)),
		"effective_result": int(evaluated.get("effective_result", 0)),
		"damage": int(evaluated.get("damage", 0)),
		"yinyang": bool(evaluated.get("yinyang", false)),
		"operands": evaluated.get("operands", []),
		"invalid_reason": "" if evaluated.ok else str(evaluated.reason_code),
		"fragile_risk": evaluated.get("fragile_risk", []),
		"capped": bool(evaluated.get("capped", false)),
	}


func commit(ordered_uids: Array, action_uid: String, combat_snapshot: Dictionary = {}) -> Dictionary:
	var ctx := _ctx()
	var replayed := ctx.replay(action_uid)
	if not replayed.is_empty():
		return replayed
	if ctx.battle != null:
		if ctx.battle.phase != "PLAYER_ACTIVE":
			return _fail(action_uid, "PHASE")
		if ctx.battle.turn_remaining <= 0.0:
			return _fail(action_uid, "TIME")
	var evaluated := _evaluate(ordered_uids, combat_snapshot)
	if not evaluated.ok:
		evaluated["replayed"] = false
		ctx.remember(action_uid, evaluated)
		return evaluated
	var cards: Array = []
	for card_uid in evaluated.ordered_uids:
		var card := ctx.library.get_card(str(card_uid))
		cards.append(card)
		ctx.library.move(card, CardInstance.RESOLVING, "RESOLVE", action_uid, ctx)
	if ctx.battle != null:
		ctx.battle.apply_damage(int(evaluated.damage))
		_record_combo(evaluated)
		if ctx.battle.enemy_hp <= 0:
			ctx.battle.phase = "VICTORY"
			ctx.battle.combo_pending = false
	var fragile: Array = []
	for card in cards:
		var broke := false
		if card.has_mark("EN_FRAGILE"):
			var chance := float(ctx.catalog.enh("EN_FRAGILE").params.break_p)
			broke = ctx.rng_of("COMBAT").randf() < chance
		fragile.append({"card_uid": card.card_uid, "broke": broke})
		if broke:
			ctx.library.move(card, CardInstance.REMOVED, "FRAGILE", action_uid, ctx)
			ctx.card_removed.emit(card.card_uid, "FRAGILE")
		elif card.has_mark("EN_RETURN") and not card.return_used_run:
			ctx.library.move(card, CardInstance.HAND, "RETURN", action_uid, ctx)
			card.return_used_run = true
		else:
			ctx.library.move(card, CardInstance.DISCARD, "DISCARD", action_uid, ctx)
	var outcome := "ONGOING"
	var ended := false
	if ctx.battle != null:
		if ctx.battle.phase == "VICTORY":
			outcome = "VICTORY"
			ended = true
		elif not ctx.battle.combo_pending and ctx.library.is_fighting_exhausted():
			ctx.battle.phase = "DECK_EXHAUSTED"
			outcome = "DECK_EXHAUSTED"
			ended = true
	var draws: Array = []
	if not ended:
		var battle_uid := "" if ctx.battle == null else ctx.battle.battle_uid
		draws = ctx.draw_service.refill(battle_uid, "AFTER_EQUATION", action_uid).events
	var equation_uid := action_uid if action_uid != "" else "eq_%d" % Time.get_ticks_usec()
	evaluated["equation_uid"] = equation_uid
	evaluated["action_uid"] = action_uid
	evaluated["fragile"] = fragile
	evaluated["battle_outcome"] = outcome
	evaluated["draws"] = draws
	evaluated["replayed"] = false
	ctx.equation_committed.emit(
		equation_uid,
		evaluated.ordered_uids,
		evaluated.motif_ids,
		str(evaluated.primary_op),
		int(evaluated.effective_result),
		int(evaluated.damage),
		"EQUATION",
	)
	ctx.remember(action_uid, evaluated)
	return evaluated


func _evaluate(ordered_uids: Array, combat_snapshot: Dictionary) -> Dictionary:
	var ctx := _ctx()
	var clean: Array = []
	for card_uid in ordered_uids:
		clean.append(str(card_uid))
	var max_tokens := int(ctx.catalog.rule().max_formula_tokens)
	var result := {"ok": false, "reason_code": "LENGTH", "ordered_uids": clean, "replayed": false}
	if clean.size() < 3 or clean.size() > max_tokens or clean.size() % 2 == 0:
		return result
	var seen := {}
	var cards: Array = []
	for i in clean.size():
		var card_uid: String = clean[i]
		if seen.has(card_uid):
			result.reason_code = "DUPLICATE_UID"
			return result
		seen[card_uid] = true
		var card := ctx.library.get_card(card_uid)
		if card == null:
			result.reason_code = "MISSING_CARD"
			return result
		if card.zone != CardInstance.HAND:
			result.reason_code = "NOT_IN_HAND"
			return result
		if card.is_frozen(ctx.library.turn_index):
			result.reason_code = "FROZEN"
			return result
		var def := ctx.catalog.card(card.def_id)
		var kind := str(def.get("card_kind", ""))
		var expect_num := i % 2 == 0
		if expect_num != (kind == "NUM"):
			result.reason_code = "ALTERNATION"
			return result
		var operator_code := str(def.get("operator_code", ""))
		if kind == "OP" and not ["ADD", "MUL"].has(operator_code):
			result.reason_code = "OPERATOR_DISABLED"
			return result
		cards.append(card)
	var op_codes: Array = []
	for i in cards.size():
		if i % 2 == 1:
			op_codes.append(str(ctx.catalog.card(cards[i].def_id).operator_code))
	var primary := _primary(op_codes)
	var operands: Array = []
	var snap_cards: Array = []
	var motif_ids: Array = []
	var fragile_risk: Array = []
	for i in cards.size():
		var card: CardInstance = cards[i]
		var def := ctx.catalog.card(card.def_id)
		motif_ids.append(str(def.get("motif_id", "")))
		snap_cards.append({
			"card_uid": card.card_uid,
			"printed_value": card.printed_value(ctx.catalog),
			"enhancement_ids": card.enhancement_ids.duplicate(),
			"operator_code": str(def.get("operator_code", "")),
			"motif_id": str(def.get("motif_id", "")),
			"card_kind": str(def.get("card_kind", "")),
		})
		if i % 2 == 0:
			operands.append(_operand(card, primary))
		if card.has_mark("EN_FRAGILE"):
			fragile_risk.append({
				"card_uid": card.card_uid,
				"break_p": float(ctx.catalog.enh("EN_FRAGILE").params.break_p),
			})
	var raw := _eval_expr(operands, op_codes)
	var tax := int(combat_snapshot.get("tax", 0))
	var coefficient := float(combat_snapshot.get("damage_coefficient", 1.0))
	var yinyang := _yinyang(cards)
	var dealt := _damage(raw, tax, coefficient, yinyang)
	result.ok = true
	result.reason_code = "OK"
	result["primary_op"] = primary
	result["operands"] = operands
	result["raw_result"] = raw
	result["tax"] = tax
	result["damage_coefficient"] = coefficient
	result["yinyang"] = yinyang
	result["effective_result"] = dealt.effective_result
	result["damage"] = dealt.damage
	result["capped"] = dealt.capped
	result["damage_kind"] = "EQUATION"
	result["motif_ids"] = motif_ids
	result["fragile_risk"] = fragile_risk
	result["snapshot"] = {
		"ordered_uids": clean.duplicate(),
		"motif_ids": motif_ids.duplicate(),
		"primary_op": primary,
		"cards": snap_cards,
	}
	return result


func _operand(card: CardInstance, primary: String) -> int:
	var ctx := _ctx()
	var value := card.printed_value(ctx.catalog)
	if card.has_mark("EN_FLAMMABLE"):
		var params: Dictionary = ctx.catalog.enh("EN_FLAMMABLE").params
		if primary == "MUL":
			value += int(params.mul_add)
		elif primary == "ADD":
			value += int(params.add_add)
	if card.has_mark("EN_ECHO"):
		value *= int(ctx.catalog.enh("EN_ECHO").params.repeat)
	return value


func _primary(op_codes: Array) -> String:
	var add_count := 0
	var mul_count := 0
	var rightmost := ""
	for code in op_codes:
		var op := str(code)
		if op == "ADD":
			add_count += 1
		elif op == "MUL":
			mul_count += 1
		rightmost = op
	if add_count > mul_count:
		return "ADD"
	if mul_count > add_count:
		return "MUL"
	return rightmost


func _eval_expr(operands: Array, op_codes: Array) -> int:
	var values := operands.duplicate()
	var ops := op_codes.duplicate()
	var index := 0
	while index < ops.size():
		if str(ops[index]) == "MUL":
			values[index] = int(values[index]) * int(values[index + 1])
			values.remove_at(index + 1)
			ops.remove_at(index)
		else:
			index += 1
	var total := int(values[0])
	for op_index in ops.size():
		total += int(values[op_index + 1])
	return total


func _yinyang(cards: Array) -> bool:
	var ctx := _ctx()
	var distinct := {}
	for card in cards:
		if card.has_mark("EN_YINYANG"):
			distinct[card.card_uid] = true
	if distinct.size() < 2:
		return false
	return distinct.size() >= int(ctx.catalog.enh("EN_YINYANG").params.distinct_cards)


func _damage(raw: int, tax: int, coefficient: float, yinyang: bool) -> Dictionary:
	var ctx := _ctx()
	var after := raw - tax
	var scaled := float(maxi(0, after)) * float(ctx.catalog.rule().damage_scale)
	if yinyang:
		scaled *= float(ctx.catalog.enh("EN_YINYANG").params.damage_mult)
	scaled *= coefficient
	var rounded := 0
	if scaled > 0.0:
		rounded = int(floor(scaled + 0.5))
	var cap := int(ctx.catalog.rule().max_equation_damage)
	var capped := rounded > cap
	if capped:
		rounded = cap
	return {"effective_result": after, "damage": rounded, "capped": capped}


func _record_combo(evaluated: Dictionary) -> void:
	var battle := _ctx().battle
	if battle == null:
		return
	var primary := str(evaluated.primary_op)
	var damage := int(evaluated.damage)
	if primary == "ADD" and damage > 0:
		battle.combo_streak += 1
		battle.add_snapshots.append((evaluated.snapshot as Dictionary).duplicate(true))
		if battle.combo_streak >= 2 and not battle.combo_used_this_turn:
			battle.combo_used_this_turn = true
			battle.combo_pending = true
			var left: Dictionary = battle.add_snapshots[-2]
			var right: Dictionary = battle.add_snapshots[-1]
			battle.combo_snapshots = [left.duplicate(true), right.duplicate(true)]
			battle.combo_window = _combo_window(left, right)
	else:
		battle.combo_streak = 0
		battle.add_snapshots.clear()


func _combo_window(left: Dictionary, right: Dictionary) -> float:
	var ctx := _ctx()
	var seen := {}
	var bonus := float(ctx.catalog.enh("EN_COMBO").params.bonus_s)
	for snap in [left, right]:
		for entry in snap.cards:
			var marks: Array = entry.enhancement_ids
			if marks.has("EN_COMBO"):
				seen[str(entry.card_uid)] = true
	var seconds := float(ctx.catalog.rule().combo_base_s) + bonus * float(seen.size())
	return minf(float(ctx.catalog.rule().combo_cap_s), seconds)


func _fail(action_uid: String, reason: String) -> Dictionary:
	var result := {"ok": false, "reason_code": reason, "replayed": false, "damage": 0}
	_ctx().remember(action_uid, result)
	return result


func _ctx() -> RunContext:
	return _run.get_ref() as RunContext
