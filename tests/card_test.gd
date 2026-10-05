extends SceneTree

var _failures: int = 0
var _previews: Array[int] = []

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
	panel.preview_changed.connect(func(result: int) -> void: _previews.append(result))
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
	_check(panel.finish_player_turn() == 16, "3 + 5 × 2 must evaluate left to right")
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
	await process_frame
	if _failures == 0:
		print("PASS: calculation, arbitrary returns, insertion, invalid edits, unique cards, previews and turn locking")
	quit(1 if _failures else 0)
