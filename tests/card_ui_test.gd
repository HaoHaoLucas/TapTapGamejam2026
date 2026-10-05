extends SceneTree
## Exercises actual Control drag/drop through viewport mouse events.
## Run without --headless to also render build/card_demo.png.

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _motion(position: Vector2, relative: Vector2, held: bool) -> void:
	# Native windows query the OS cursor for drag-local coordinates.
	if DisplayServer.get_name() != "headless":
		Input.warp_mouse(position)
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	if DisplayServer.get_name() == "headless":
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	else:
		# Dispatch directly so queued OS warp events cannot replace the target.
		root.push_input(event)

func _button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	if DisplayServer.get_name() == "headless":
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	else:
		root.push_input(event)

func _drag(view: Control, destination: Vector2, expected_insert: int = -1, screenshot: String = "") -> void:
	var panel: CardPanel = view.card_panel
	var origin := view.get_global_rect().get_center()
	_motion(origin, Vector2.ZERO, false)
	_button(origin, true)
	await process_frame
	_motion(origin + Vector2(20, -20), Vector2(20, -20), true)
	await process_frame
	_check(root.gui_is_dragging(), "Mouse motion must start native Control drag")
	_check(root.gui_get_drag_data().get("card_id") == view.card.instance_id, "Drag must carry the pressed card")
	_motion(destination, destination - origin - Vector2(20, -20), true)
	await process_frame
	if expected_insert >= 0:
		_check(panel._expression_zone.insertion_index == expected_insert, "Hover index expected %d, got %d at %s" % [expected_insert, panel._expression_zone.insertion_index, destination])
	if not screenshot.is_empty():
		await _capture(screenshot)
	# Re-establish the destination after native cursor events/rendering yields.
	_motion(destination, Vector2.ZERO, true)
	_button(destination, false)
	await process_frame
	await process_frame
	_check(panel._expression_zone.insertion_index == -1, "Insertion hint must clear on drop or cancel")

func _view_for(panel: CardPanel, text: String, region: StringName = &"hand") -> Control:
	var row := panel._hand_row if region == &"hand" else panel._expression_row
	for view in row.get_children():
		if not view is PanelContainer:
			continue
		if view.card.display_text() == text:
			return view
	_check(false, "Missing card view: " + text)
	quit(1)
	return null

func _blank(zone: Control) -> Vector2:
	# Bottom-right padding is inside the zone but outside all cards.
	return zone.get_global_rect().end - Vector2(8, 8)

func _half(view: Control, left: bool) -> Vector2:
	return view.global_position + Vector2(view.size.x * (0.25 if left else 0.75), view.size.y * 0.5)

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build")
	var image := root.get_texture().get_image()
	_check(image.save_png("res://build/" + filename + ".png") == OK, "Screenshot must save")

func _check_locked(view: Control) -> void:
	var origin := view.get_global_rect().get_center()
	_motion(origin, Vector2.ZERO, false)
	_button(origin, true)
	_motion(origin + Vector2(20, -20), Vector2(20, -20), true)
	await process_frame
	_check(not root.gui_is_dragging(), "Ended turn must prevent native dragging from both regions")
	_button(origin + Vector2(20, -20), false)

func _click(button: Button) -> void:
	var position := button.get_global_rect().get_center()
	_motion(position, Vector2.ZERO, false)
	_button(position, true)
	_button(position, false)
	await process_frame
	await process_frame

func _run() -> void:
	Input.use_accumulated_input = false
	root.size = Vector2i(1152, 648)
	var demo = load("res://scenes/cards/card_demo.tscn").instantiate()
	root.add_child(demo)
	for frame in range(5):
		await process_frame
	var panel: CardPanel = demo.card_panel
	_check(panel.get_hand_cards().size() == 5, "Demo must render five cards")
	await _drag(_view_for(panel, "3"), Vector2(8, 8))
	_check(panel.get_hand_cards().size() == 5, "Outside drop must leave hand unchanged")
	for value in ["3", "×", "5", "+", "2"]:
		await _drag(_view_for(panel, value), _blank(panel._expression_zone), panel.get_expression_cards().size())
	_check(panel._result_label.text == "结果 17" and panel.get_hand_cards().is_empty(), "All cards must form 3 × 5 + 2")
	await _drag(_view_for(panel, "5", &"expression"), Vector2(8, 8))
	_check(panel.get_expression_cards().size() == 5, "Outside expression drag must preserve card")
	await _drag(_view_for(panel, "5", &"expression"), _half(_view_for(panel, "3", &"expression"), true))
	_check(panel._result_label.text == "结果 17", "Direct expression reordering must be rejected")
	# Return a middle card into an EMPTY hand, then repair on an existing card face.
	await _drag(_view_for(panel, "5", &"expression"), panel._hand_zone.get_global_rect().get_center())
	_check(panel.get_hand_cards().size() == 1 and panel.get_hand_cards()[0].number == 5, "Only middle five must return to empty hand")
	_check(panel._result_label.text == "结果 0 · 未完成", "Removing middle number must show invalid result")
	await _capture("card_demo_incomplete")
	await _drag(_view_for(panel, "5"), _half(_view_for(panel, "+", &"expression"), true), 2, "card_demo_insertion")
	_check(panel._result_label.text == "结果 17", "Middle insertion must repair result")
	# Multiple returns include operator, final number, first number, and a hand-card face.
	await _drag(_view_for(panel, "×", &"expression"), _blank(panel._hand_zone))
	_check(panel._result_label.text.contains("未完成"), "Adjacent numbers must be shown as invalid")
	await _drag(_view_for(panel, "2", &"expression"), _view_for(panel, "×").get_global_rect().get_center())
	await _drag(_view_for(panel, "3", &"expression"), _blank(panel._hand_zone))
	_check(panel.get_hand_cards().size() == 3 and panel.get_expression_cards().size() == 2, "Multiple returns must compact expression")
	await _drag(_view_for(panel, "3"), _half(_view_for(panel, "5", &"expression"), true), 0)
	await _drag(_view_for(panel, "×"), _half(_view_for(panel, "3", &"expression"), false), 1)
	await _drag(_view_for(panel, "2"), _blank(panel._expression_zone), 4)
	_check(panel._result_label.text == "结果 17", "First/last insertion and right-half insertion must repair expression")
	# The gap between two faces must select the same interior index.
	await _drag(_view_for(panel, "×", &"expression"), _blank(panel._hand_zone))
	var first_rect := _view_for(panel, "3", &"expression").get_global_rect()
	var next_rect := _view_for(panel, "5", &"expression").get_global_rect()
	var gap := Vector2((first_rect.end.x + next_rect.position.x) * 0.5, first_rect.get_center().y)
	await _drag(_view_for(panel, "×"), gap, 1)
	await _capture("card_demo")
	await _drag(_view_for(panel, "2", &"expression"), _blank(panel._hand_zone))
	await _click(demo._finish_button)
	_check(not panel.is_turn_active() and demo._output.text == "已结束" and panel.finish_player_turn() == 15, "Finish button must show settlement and lock panel")
	await _check_locked(_view_for(panel, "2"))
	await _check_locked(_view_for(panel, "5", &"expression"))
	await _click(demo._next_button)
	_check(panel.is_turn_active() and panel.get_expression_cards().is_empty() and panel.get_hand_cards().size() == 5, "Next button must restore fixed hand")
	await _drag(_view_for(panel, "+"), panel._burn_zone.get_global_rect().get_center())
	_check(panel.get_hand_cards().size() == 5 and panel.get_pending_heal() == 0, "Burn zone must reject operator")
	await _drag(_view_for(panel, "5"), panel._burn_zone.get_global_rect().get_center())
	_check(panel.get_hand_cards().size() == 4 and panel.get_pending_heal() == 50, "Dragging number into burn zone must remove it and add heal")
	_check(demo._health == 70, "Burn heal must wait for settlement")
	await _capture("card_demo_burn")
	await _click(demo._finish_button)
	_check(demo._health == 100, "Settlement must heal and cap HP")
	await _click(demo._next_button)
	_check(panel.get_hand_cards().size() == 4 and panel.get_pending_heal() == 0, "Burned card must not return next turn")
	await _capture("card_demo")
	# A narrow standalone panel forces wrapped expression rows.
	demo.hide()
	var narrow: CardPanel = load("res://scenes/cards/card_panel.tscn").instantiate()
	narrow.theme = demo.theme
	narrow.position = Vector2(24, 8)
	narrow.size = Vector2(440, 0)
	root.add_child(narrow)
	var cards: Array[CardData] = []
	for number in range(1, 8):
		cards.append(CardData.number_card(number))
	cards.append(CardData.number_card(9))
	narrow.start_player_turn(cards)
	for index in range(7):
		narrow.insert_card(cards[index].instance_id, index)
	for frame in range(5):
		await process_frame
	var wrapped_index := -1
	var first_y: float = narrow._expression_row.get_child(0).global_position.y
	for index in range(narrow._expression_row.get_child_count()):
		if narrow._expression_row.get_child(index).global_position.y > first_y + 10:
			wrapped_index = index
			break
	_check(wrapped_index > 0, "Narrow panel must actually wrap expression cards")
	if wrapped_index > 0:
		var wrapped_view: Control = narrow._expression_row.get_child(wrapped_index)
		await _drag(_view_for(narrow, "9"), _half(wrapped_view, true), wrapped_index)
		_check(narrow.get_expression_cards()[wrapped_index] == cards[7], "Wrapped row must insert at visual target")
		await _drag(_view_for(narrow, "9", &"expression"), _blank(narrow._hand_zone))
		await _drag(_view_for(narrow, "9"), _half(narrow._expression_row.get_child(wrapped_index), false), wrapped_index + 1)
		_check(narrow.get_expression_cards()[wrapped_index + 1] == cards[7], "Wrapped row right-half must insert after target")
	await _capture("card_demo_wrapped")
	if _failures == 0:
		print("PASS: native drag/drop, middle insertion, burn zone, health settlement, wrapped rows and turn locking")
	quit(1 if _failures else 0)
