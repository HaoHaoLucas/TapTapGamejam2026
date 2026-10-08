extends SceneTree

var _failures: int = 0
var _previews: Array[float] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _play(panel: CardPanel, card: CardData) -> void:
	_check(panel.accept_drop(panel.drag_payload(card.instance_id)), "Legal card must be accepted: " + card.display_text())

func _return(panel: CardPanel, card: CardData) -> void:
	_check(panel.accept_drop(panel.drag_payload(card.instance_id, &"expression"), &"hand"), "Expression card must return: " + card.display_text())

func _run() -> void:
	var panel: CardPanel = load("res://scenes/cards/card_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	panel.preview_changed.connect(func(result: float) -> void: _previews.append(result))
	var three := CardData.number_card(3)
	var five := CardData.number_card(5)
	var multiply := CardData.operator_card("×")
	var plus := CardData.operator_card("+")
	var two := CardData.number_card(2)
	var hand: Array[CardData] = [three, five, multiply, plus, two]
	panel.start_player_turn(hand)
	_check(panel.get_hand_cards().size() == 5, "Turn must start with all supplied cards")
	_play(panel, multiply)
	_check(not ExpressionEvaluator.is_valid(panel.get_expression_cards()) and _previews.back() == 0, "Operator-first edits must preview zero")
	_return(panel, multiply)
	var signal_count := _previews.size()
	_check(not panel.accept_drop(null), "Non-card drops must be rejected")
	_check(not panel.accept_drop(panel.drag_payload(999999)), "Unknown card must be rejected")
	var foreign_payload := panel.drag_payload(three.instance_id)
	foreign_payload["panel"] = root
	_check(not panel.accept_drop(foreign_payload), "Foreign panel must be rejected")
	_check(not panel.accept_drop(panel.drag_payload(three.instance_id), &"hand"), "Hand-to-hand drops must be rejected")
	_check(not panel.insert_card(three.instance_id, 10), "Invalid insertion index must not remove card")
	_check(_previews.size() == signal_count, "Rejected operations must not emit previews")
	_play(panel, three)
	_check(not panel.accept_drop(panel.drag_payload(three.instance_id)), "A card cannot be played twice")
	_play(panel, five)
	_check(not ExpressionEvaluator.is_valid(panel.get_expression_cards()) and _previews.back() == 0, "Adjacent numbers are editable but evaluate to zero")
	_return(panel, five)
	_play(panel, multiply)
	_check(_previews.back() == 3, "Pending operator must keep completed result")
	_play(panel, five)
	_check(_previews.back() == 15, "3 × 5 must preview 15")
	_play(panel, plus)
	_play(panel, two)
	_check(_previews.back() == 17, "3 × 5 + 2 must preview 17")
	_check(hand.size() == 5, "Panel must not mutate caller's array")
	var played: Array[CardData] = [three, multiply, five, plus, two]
	for index in range(played.size()):
		var card := played[index]
		var remaining := played.duplicate()
		remaining.remove_at(index)
		_return(panel, card)
		_check(panel.get_expression_cards() == remaining, "Returning any card must preserve the others' order")
		_check(panel.get_hand_cards().back() == card, "Returned card must go to end of hand")
		_check(not panel.return_card(card.instance_id), "Returning the same card twice must fail")
		_check(panel.insert_card(card.instance_id, index), "Card must be insertable at original index")
		_check(panel.get_expression_cards() == played and _previews.back() == 17, "Repairing expression must restore 17")
	_return(panel, five)
	_check(_previews.back() == 0 and not ExpressionEvaluator.is_valid(panel.get_expression_cards()), "Removing middle number must invalidate expression")
	_return(panel, multiply)
	_check(_previews.back() == 5, "Multiple returns must recompute the remaining 3 + 2")
	_check(panel.insert_card(multiply.instance_id, 1), "Operator must insert at interior index")
	_check(panel.insert_card(five.instance_id, 2), "Number must repair the interior gap")
	_check(_previews.back() == 17, "Multiple-card repair must restore 17")
	_return(panel, two)
	_check(_previews.back() == 15, "Returning trailing number must update preview")
	_play(panel, two)
	var expression_payload := panel.drag_payload(five.instance_id, &"expression")
	_check(not panel.accept_drop(expression_payload), "Direct expression reordering is not supported")
	_check(panel.finish_player_turn() == 17, "Finish must return expression result")
	_check(panel.finish_player_turn() == 17, "Repeated finish must be idempotent")
	_check(not panel.return_card(five.instance_id), "Finished turn must lock return")
	_check(not panel.accept_drop(expression_payload, &"hand"), "Finished turn must reject return payloads")
	_check(panel.get_expression_cards().size() == 5, "Finished turn must preserve expression")
	_check(not panel.accept_drop(panel.drag_payload(two.instance_id)), "Finished turn must lock drops")
	var old_payload := panel.drag_payload(three.instance_id)
	panel.start_player_turn(hand)
	_check(not panel.accept_drop(old_payload), "Payload from previous turn must be rejected")
	_play(panel, five)
	_check(not panel.accept_drop(expression_payload, &"hand"), "Old return payload must fail even if the card is played again")
	_return(panel, five)
	_check(panel.get_expression_cards().is_empty() and panel.get_hand_cards().size() == 5, "Next turn must reset expression and hand")
	_play(panel, three)
	_play(panel, plus)
	_play(panel, five)
	_play(panel, multiply)
	_play(panel, two)
	_check(panel.finish_player_turn() == 13, "3 + 5 × 2 must multiply before adding")
	panel.start_player_turn(hand)
	_check(panel.finish_player_turn() == 0, "Empty expression must settle to zero")
	panel.start_player_turn(hand)
	_play(panel, three)
	_play(panel, multiply)
	_check(panel.finish_player_turn() == 3, "Trailing operator must not affect settlement")
	for invalid in [[multiply], [three, five], [three, multiply, plus, two]]:
		var invalid_cards: Array[CardData] = []
		invalid_cards.assign(invalid)
		panel.start_player_turn(invalid_cards)
		for card in invalid_cards:
			_play(panel, card)
		_check(panel.finish_player_turn() == 0, "Invalid expression must settle to zero")
	var second_three := CardData.number_card(3)
	_check(three.instance_id != second_three.instance_id, "Equal-valued cards must have unique IDs")
	panel.start_player_turn([three, plus, second_three])
	_play(panel, three)
	_play(panel, plus)
	_play(panel, second_three)
	_return(panel, three)
	_check(panel.get_expression_cards() == [plus, second_three], "Equal values must not confuse returned instance")
	_check(panel.insert_card(three.instance_id, 0), "First card must insert before existing expression")
	_check(panel.finish_player_turn() == 6, "Equal-valued physical cards can both be played")
	var subtraction: Array[CardData] = [CardData.number_card(-3), CardData.operator_card("-"), CardData.number_card(5)]
	_check(ExpressionEvaluator.evaluate(subtraction) == -8, "Signed integer and subtraction must work")
	panel.reset_battle()
	var negative := CardData.number_card(-3)
	var burns: Array[int] = []
	panel.card_burned.connect(func(_id: int, heal: int) -> void: burns.append(heal))
	panel.start_player_turn([negative, plus, five])
	_check(not panel.accept_drop(panel.drag_payload(plus.instance_id), &"burn"), "Operators cannot be burned")
	_check(panel.accept_drop(panel.drag_payload(negative.instance_id), &"burn"), "Hand number must burn")
	_check(panel.get_pending_heal() == 30 and burns == [30], "Negative number burn must use absolute value and emit once")
	_check(not panel.burn_card(negative.instance_id), "Burn cannot be repeated")
	_check(not panel.insert_card(negative.instance_id, 0), "Burned card cannot be played")
	_play(panel, five)
	_check(not panel.accept_drop(panel.drag_payload(five.instance_id, &"expression"), &"burn"), "Expression cards must return to hand before burning")
	panel.finish_player_turn()
	_check(not panel.burn_card(five.instance_id) and panel.get_pending_heal() == 30, "Finish must preserve pending heal and lock burn")
	panel.start_player_turn([negative, plus, five])
	_check(panel.get_hand_cards() == [plus, five] and panel.get_pending_heal() == 0, "Burned IDs must remain excluded next turn, pending heal resets")
	panel.reset_battle()
	panel.start_player_turn([negative])
	_check(panel.get_hand_cards() == [negative], "New battle must reset burned IDs")
	_run_formula(panel)
	await process_frame
	if _failures == 0:
		print("PASS: calculation, precedence, division, formula slots, arbitrary returns, insertion, invalid edits, unique cards, previews and turn locking")
	quit(1 if _failures else 0)

func _cards_for(values: Array) -> Array[CardData]:
	var cards: Array[CardData] = []
	for value in values:
		if value is String:
			cards.append(CardData.operator_card(value))
		else:
			cards.append(CardData.number_card(int(value)))
	return cards

func _symbol_template() -> Array[FormulaSlot]:
	var slots: Array[FormulaSlot] = [
		FormulaSlot.open_number(), FormulaSlot.locked_operator("÷"),
		FormulaSlot.open_number(), FormulaSlot.locked_operator("-"),
		FormulaSlot.open_number(), FormulaSlot.locked_operator("×"),
		FormulaSlot.open_number(),
	]
	return slots

func _number_template() -> Array[FormulaSlot]:
	var slots: Array[FormulaSlot] = [
		FormulaSlot.locked_number(-1), FormulaSlot.open_operator(),
		FormulaSlot.locked_number(2), FormulaSlot.open_operator(),
		FormulaSlot.locked_number(6), FormulaSlot.open_operator(),
		FormulaSlot.locked_number(-3),
	]
	return slots

func _mixed_template() -> Array[FormulaSlot]:
	var slots: Array[FormulaSlot] = [
		FormulaSlot.locked_number(8), FormulaSlot.locked_operator("÷"),
		FormulaSlot.open_number(), FormulaSlot.open_operator(), FormulaSlot.open_number(),
	]
	return slots

func _run_formula(panel: CardPanel) -> void:
	_check(ExpressionEvaluator.evaluate(_cards_for([3, "×", 5, "+", 2])) == 17, "3 × 5 + 2 stays left-to-right within precedence")
	_check(ExpressionEvaluator.evaluate(_cards_for([3, "+", 5, "×", 2])) == 13, "3 + 5 × 2 must be 13")
	_check(ExpressionEvaluator.evaluate(_cards_for([3, "+", 5, "×"])) == 8, "Trailing multiply must be ignored")
	_check(ExpressionEvaluator.evaluate(_cards_for([8, "÷", 4, "×", 2])) == 4, "Same-level multiply and divide go left to right")
	_check(ExpressionEvaluator.evaluate(_cards_for([8, "-", 3, "-", 2])) == 3, "Same-level add and subtract go left to right")
	_check(ExpressionEvaluator.evaluate(_cards_for([8, "÷", 2, "-", 3, "×", 4])) == -8, "8 ÷ 2 − 3 × 4 must be -8")
	var eight_thirds := ExpressionEvaluator.inspect_cards(_cards_for([8, "÷", 3]))
	_check(eight_thirds.result.equals(8, 3) and eight_thirds.result.display_text() == "2.666…", "8 ÷ 3 must stay eight thirds")
	_check(ExpressionEvaluator.inspect_cards(_cards_for([10, "÷", 3, "×", 3])).result.is_int(10), "10 ÷ 3 × 3 must return to 10")
	_check(ExpressionEvaluator.inspect_cards(_cards_for([8, "÷", 3, "×", 3])).result.is_int(8), "8 ÷ 3 × 3 must return to 8")
	_check(ExpressionEvaluator.inspect_cards(_cards_for([1, "÷", 3, "×", 3])).result.is_int(1), "1 ÷ 3 × 3 must return to 1")
	var negative_half := ExpressionEvaluator.inspect_cards(_cards_for([-7, "÷", 2]))
	_check(negative_half.result.equals(-7, 2) and negative_half.result.display_text() == "-3.5", "-7 ÷ 2 must be -3.5")
	_check(ExpressionEvaluator.inspect_cards(_cards_for([-8, "÷", 3, "×", 3])).result.is_int(-8), "-8 ÷ 3 × 3 must return to -8")
	_check(ExpressionEvaluator.inspect_cards(_cards_for([7, "÷", -2])).result.equals(-7, 2), "7 ÷ -2 must be -7/2")
	_check(ExpressionEvaluator.inspect_cards(_cards_for([-8, "÷", -3])).result.equals(8, 3), "-8 ÷ -3 must be 8/3")
	_check(ExpressionEvaluator.inspect_cards(_cards_for([1, "÷", 2])).result.display_text() == "0.5", "1 ÷ 2 must display one half")
	_check(ExpressionEvaluator.evaluate(_cards_for([0, "÷", 2])) == 0, "Zero divided by a number is zero")
	_check(not ExpressionEvaluator.inspect_cards(_cards_for([0, "÷", 2])).divided_by_zero, "A zero dividend is not division by zero")
	var pending := ExpressionEvaluator.inspect_cards(_cards_for([8, "÷"]))
	_check(pending.result.is_int(8) and not pending.divided_by_zero, "Trailing division must not execute")
	var zeroed := ExpressionEvaluator.inspect_cards(_cards_for([8, "÷", 0, "+", 5]))
	_check(zeroed.result.is_int(0) and zeroed.divided_by_zero, "8 ÷ 0 + 5 must be division by zero")
	_check(ExpressionEvaluator.evaluate(_cards_for([5, "+", 8, "÷", 0])) == 0, "5 + 8 ÷ 0 must be zero")
	var broken := ExpressionEvaluator.inspect_cards(_cards_for([8, "÷", 0, 5]))
	_check(broken.result.is_int(0) and not broken.valid and not broken.divided_by_zero, "Invalid structure must not execute division")
	var shown := _cards_for([8, "÷", 3])
	panel.reset_battle()
	panel.start_player_turn(shown)
	for card in shown:
		_play(panel, card)
	_check(panel._result_label.text == "结果 2.666…" and panel.get_exact_result().equals(8, 3), "Panel must show 2.666… while keeping eight thirds")
	panel.reset_battle()
	var only: Array[FormulaSlot] = [FormulaSlot.locked_number(6)]
	panel.start_player_turn([])
	_check(panel.apply_formula_constraint(only), "A single locked number is a valid formula")
	_check(panel._result_label.text == "定式 6 · 结果 6" and _previews.back() == 6, "Complete locked formula must settle immediately")
	_check(panel.finish_player_turn() == 6, "Locked formula must finish to its value")
	var eight := CardData.number_card(8)
	var two := CardData.number_card(2)
	var three := CardData.number_card(3)
	var four := CardData.number_card(4)
	var plus := CardData.operator_card("+")
	var times := CardData.operator_card("×")
	var minus := CardData.operator_card("-")
	var blueprint := _symbol_template()
	var special := CardData.special_card(blueprint)
	_check(blueprint[0] != special.slots[0], "Special card stores its own template copy")
	var deck: Array[CardData] = [eight, two, three, four, plus, times, minus, special]
	panel.start_player_turn(deck)
	_play(panel, eight)
	_play(panel, plus)
	_play(panel, two)
	var signals := _previews.size()
	var hand_before := panel.get_hand_cards()
	var expression_before := panel.get_expression_cards()
	var empty_template: Array[FormulaSlot] = []
	var even_template: Array[FormulaSlot] = [FormulaSlot.open_number(), FormulaSlot.open_operator()]
	var operator_first: Array[FormulaSlot] = [FormulaSlot.open_operator(), FormulaSlot.open_number(), FormulaSlot.open_operator()]
	var adjacent: Array[FormulaSlot] = [FormulaSlot.open_number(), FormulaSlot.open_number(), FormulaSlot.open_number()]
	_check(not panel.apply_formula_constraint(empty_template), "Empty template must be rejected")
	_check(not panel.apply_formula_constraint(even_template), "Template ending on an operator must be rejected")
	_check(not panel.apply_formula_constraint(operator_first), "Template starting on an operator must be rejected")
	_check(not panel.apply_formula_constraint(adjacent), "Non-alternating template must be rejected")
	_check(_previews.size() == signals, "Rejected formulas must not emit previews")
	_check(panel.get_hand_cards() == hand_before and panel.get_expression_cards() == expression_before, "Rejected formulas must leave the current cards")
	_check(not panel.has_formula_constraint(), "Rejected formulas must not install a constraint")
	_check(not panel.insert_card(special.instance_id, 0), "Special cards are not inserted into a free expression")
	_check(panel.accept_drop(panel.drag_payload(special.instance_id)), "Dropping a special card must play its formula")
	_check(deck.size() == 8 and deck[7] == special, "Playing a special must not mutate or burn the caller array")
	_check(panel.get_hand_cards() == [three, four, times, minus, eight, plus, two], "Expression cards return to the end and the special leaves")
	_check(panel.has_formula_constraint() and panel.get_expression_cards().is_empty(), "Special card installs an empty formula")
	var open_formula := "定式 □ ÷ □ - □ × □ · 结果 0 · 未完成"
	_check(panel._result_label.text == open_formula and _previews.back() == 0, "Open formula must preview unfinished")
	special.slots[1].operator = "+"
	blueprint[1].operator = "×"
	_check(panel.insert_card(eight.instance_id, 0), "Number must fill the first open slot")
	_check(panel._result_label.text.begins_with("定式 8 ÷ "), "Filling must use the copied template")
	_check(blueprint[0].card == null and special.slots[0].card == null, "Filling must not write into either blueprint")
	_check(panel.return_card(eight.instance_id), "A filled slot card must return to hand")
	_check(panel.get_hand_cards().back() == eight and panel.get_expression_cards().is_empty(), "Returned slot card goes to the end")
	_check(panel._result_label.text == open_formula, "Clearing a slot must show the formula unfinished again")
	_check(not panel.insert_card(plus.instance_id, 0), "Operator must not fill a number slot")
	_check(not panel.insert_card(eight.instance_id, 1), "Locked slot must reject a card")
	_check(not panel.insert_card(eight.instance_id, -1) and not panel.insert_card(eight.instance_id, 7), "Formula index outside the slots must fail")
	_check(panel.get_expression_cards().is_empty(), "Rejected slot fills must not move cards")
	_check(panel.insert_card(eight.instance_id, 0), "First open number accepts 8")
	_check(not panel.insert_card(two.instance_id, 0), "Occupied slot must reject another card")
	_check(panel.insert_card(two.instance_id, 2), "Second open number accepts 2")
	_check(panel.insert_card(three.instance_id, 4), "Third open number accepts 3")
	_check(panel.insert_card(four.instance_id, 6), "Fourth open number accepts 4")
	_check(_previews.back() == -8 and panel.finish_player_turn() == -8, "8 ÷ 2 − 3 × 4 under a symbol lock must be -8")
	_check(panel._result_label.text == "定式 8 ÷ 2 - 3 × 4 · 结果 -8", "Completed symbol lock must show the filled formula")
	panel.start_player_turn(deck)
	_play(panel, eight)
	_play(panel, two)
	var monster := _number_template()
	_check(panel.apply_formula_constraint(monster), "Monster formula must replace the free expression")
	_check(panel.get_hand_cards() == [three, four, plus, times, minus, special, eight, two], "Reapplying a formula returns physical cards to the end")
	_check(panel._result_label.text == "定式 -1 □ 2 □ 6 □ -3 · 结果 0 · 未完成", "Number lock must show open operator slots")
	monster[0].number = 99
	signals = _previews.size()
	var locked_hand := panel.get_hand_cards()
	var locked_label := panel._result_label.text
	_check(not panel.apply_formula_constraint(empty_template), "Invalid template must not replace an active formula")
	_check(_previews.size() == signals and panel.get_hand_cards() == locked_hand and panel._result_label.text == locked_label, "Invalid template must leave the active formula unchanged")
	_check(panel.insert_card(plus.instance_id, 1), "First open operator accepts +")
	_check(panel._result_label.text.begins_with("定式 -1 +"), "Installed locked numbers must ignore later caller edits")
	_check(monster[1].card == null, "Filling an operator must not mutate the caller template")
	_check(panel.insert_card(times.instance_id, 3) and panel.insert_card(minus.instance_id, 5), "Remaining operator slots must fill in order")
	_check(panel._result_label.text == "定式 -1 + 2 × 6 - -3 · 结果 14", "Number lock must use precedence")
	_check(panel.finish_player_turn() == 14 and panel.finish_player_turn() == 14, "Finished formula must stay settled")
	_check(not panel.apply_formula_constraint(_number_template()), "Finished turn must reject a new formula")
	panel.start_player_turn(deck)
	_check(not panel.has_formula_constraint() and panel.get_hand_cards() == deck, "Next turn clears the formula and restores the special card")
	_check(panel.insert_card(eight.instance_id, 0) and panel.insert_card(plus.instance_id, 1), "Clearing a formula restores free insertion")
	_check(panel.get_expression_cards() == [eight, plus], "Free insertion index is a card position again")
	panel.start_player_turn([eight, two, three, times])
	var mixed := _mixed_template()
	_check(panel.apply_formula_constraint(mixed), "Mixed lock must install")
	_check(not panel.insert_card(times.instance_id, 2), "Mixed lock must reject an operator in a number slot")
	_check(not panel.insert_card(two.instance_id, 3), "Mixed lock must reject a number in an operator slot")
	_check(panel.insert_card(two.instance_id, 2) and panel.insert_card(times.instance_id, 3) and panel.insert_card(three.instance_id, 4), "Mixed lock must accept matching cards")
	_check(mixed[2].card == null and _previews.back() == 12, "8 ÷ 2 × 3 must be 12 without mutating the template")
	_check(panel._result_label.text == "定式 8 ÷ 2 × 3 · 结果 12", "Mixed lock must show locked and filled cells")
	var zero := CardData.number_card(0)
	var divide := CardData.operator_card("÷")
	panel.start_player_turn([eight, divide, zero])
	_play(panel, eight)
	_play(panel, divide)
	_check(panel._result_label.text == "结果 8", "Pending division must keep the completed value")
	_play(panel, zero)
	_check(panel._result_label.text == "结果 0 · 除以零" and panel.finish_player_turn() == 0, "Executed division by zero must display and settle as zero")
	var formula_zero: Array[FormulaSlot] = [FormulaSlot.open_number(), FormulaSlot.locked_operator("÷"), FormulaSlot.open_number()]
	panel.start_player_turn([eight, zero])
	_check(panel.apply_formula_constraint(formula_zero), "Division formula must install")
	_check(panel.insert_card(eight.instance_id, 0), "Eight must fill the dividend slot")
	_check(panel._result_label.text == "定式 8 ÷ □ · 结果 0 · 未完成", "An open slot must stay unfinished even beside a division")
	_check(panel.insert_card(zero.instance_id, 2), "Zero must fill the divisor slot")
	_check(panel._result_label.text == "定式 8 ÷ 0 · 结果 0 · 除以零" and panel.finish_player_turn() == 0, "A filled division by zero must be labeled")
	var burned := CardData.number_card(-4)
	var burn_plus := CardData.operator_card("+")
	var burn_special := CardData.special_card(_symbol_template())
	panel.start_player_turn([burned, burn_plus, burn_special])
	_check(panel.apply_formula_constraint(_number_template()), "Formula can be applied while a special card remains in hand")
	_check(not panel.burn_card(burn_plus.instance_id), "Operators cannot be burned during a formula")
	_check(not panel.burn_card(burn_special.instance_id), "Special cards cannot be burned")
	_check(panel.burn_card(burned.instance_id) and panel.get_pending_heal() == 40, "Numbers can still be burned during a formula")
	_check(panel.has_formula_constraint() and panel.get_hand_cards() == [burn_plus, burn_special], "Burn must leave the formula and the other cards")
	panel.reset_battle()
	_check(not panel.has_formula_constraint() and panel.get_hand_cards().is_empty() and panel.get_pending_heal() == 0, "Reset must clear the formula, hand, and pending heal")
	panel.start_player_turn([burned, burn_plus, burn_special])
	_check(panel.get_hand_cards() == [burned, burn_plus, burn_special] and not panel.has_formula_constraint(), "New battle must restore burned ids and the special card")
