extends SceneTree
## Headless UI path for the v1.3 hand-retention rule.
## Clicks are viewport mouse events aimed at real Control rects.
## This script never calls Button.pressed.emit, _end_turn, or CardBattle.end_player_turn.


const VIEW_SIZE := Vector2i(1920, 1080)
const END_TURN_PATH := "Board/Margin/Column/ControlsFrame/Controls/End/Button"
const HAND_CAPTION_PATH := "Hand/Caption/Count"
const HAND_ROW_PATH := "Hand/Zone/Scroll/HandRow"

var _failures: PackedStringArray = []
var _log: PackedStringArray = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Freeze the 10s battle clock so aiming frames cannot auto-end the turn.
	Engine.time_scale = 0.0
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_factor = 1.0
	root.size = VIEW_SIZE
	await process_frame
	_note("viewport %s content_scale_mode=%s time_scale=%s" % [root.size, root.content_scale_mode, Engine.time_scale])

	var menu := await _open_main_menu()
	if menu == null:
		_finish()
		return
	var started := await _click_start(menu)
	if not started:
		_finish()
		return
	var shell := await _wait_named("RunShell", 40)
	if shell == null or shell.get("run") == null:
		_fail("开始游戏 did not reach a tower run")
		_finish()
		return
	var battle_button := await _wait_battle_choice(shell)
	if battle_button == null:
		_finish()
		return
	var entered := await _click_control(battle_button, "room 战斗", "_choose_offer")
	if not entered:
		_fail("battle room button did not receive the mouse release")
		_finish()
		return
	if not await _wait_battle_visible(shell):
		_fail("choosing 战斗 did not show the battle screen")
		_finish()
		return

	var battle: RunBattle = shell._battle
	await _cover_control(battle.get_node_or_null(END_TURN_PATH) as Control)
	var before := await _await_hand(battle)
	if before.is_empty():
		_fail("battle hand never became readable")
		_finish()
		return
	_note_hand("before", before)
	if not _hand_ready(before, "opening hand"):
		_finish()
		return

	var end_button := battle.get_node_or_null(END_TURN_PATH) as Button
	if end_button == null:
		_fail("end-turn button is missing from the battle scene")
		_finish()
		return
	var end_art := end_button.get_node_or_null("Art") as TextureRect
	if end_art == null or end_art.texture == null or end_art.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("end-turn button should carry its art and let clicks through")
		_finish()
		return
	var turn_before := int(before["turn"])
	var phase_before := str(before["phase"])
	var hp_before := int(before["hp"])
	if phase_before != "PLAYER_ACTIVE" or turn_before != 1:
		_fail("expected the opening player turn before the click, got turn %s phase %s" % [turn_before, phase_before])
		_finish()
		return

	var ended := await _click_control(end_button, "end-turn 结束回合", "_end_turn")
	if not ended:
		_fail("end-turn button did not receive the mouse release")
		_finish()
		return
	var after := await _await_hand(battle)
	if after.is_empty():
		_fail("hand was not readable after end turn")
		_finish()
		return
	_note_hand("after", after)
	_assert_retention(before, after, hp_before)
	_finish()


func _open_main_menu() -> Node:
	var err := change_scene_to_file("res://scenes/menu/main_menu.tscn")
	if err != OK:
		_fail("main menu failed to load (%s)" % err)
		return null
	var menu := await _wait_named("MainMenu", 40)
	if menu == null:
		_fail("main menu scene did not become current")
		return null
	var stage := menu.get_node_or_null("Stage") as Control
	var start := menu.get_node_or_null("Stage/StartButton") as ArtButton
	for _i in 30:
		if stage != null and start != null and stage.scale.x > 0.01 and start.size.x > 2.0:
			return menu
		await process_frame
	_fail("main menu stage did not lay out (stage=%s start=%s)" % [
		stage.scale if stage != null else Vector2.ZERO,
		start.size if start != null else Vector2.ZERO,
	])
	return null


func _click_start(menu: Node) -> bool:
	var start := menu.get_node_or_null("Stage/StartButton") as ArtButton
	if start == null:
		_fail("StartButton is missing")
		return false
	return await _click_control(start, "menu StartButton", "_start_run")


func _wait_battle_choice(shell: Node) -> Button:
	var button: Button = null
	for _i in 40:
		await process_frame
		button = _find_battle_button(shell)
		if button != null and _rect_ready(button):
			return button
	if button == null:
		var labels := PackedStringArray()
		var body := shell.get("_body") as Node
		if body != null:
			for child in body.get_children():
				if child is Button:
					labels.append(str(child.text))
		_fail("no 战斗 room button on the tower. buttons=%s status=%s" % [
			", ".join(labels),
			str(shell.get("_status").text) if shell.get("_status") != null else "",
		])
		return null
	_fail("战斗 button has no rect %s" % button.get_global_rect())
	return null


func _find_battle_button(shell: Node) -> Button:
	var body := shell.get("_body") as Node
	if body == null:
		return null
	for child in body.get_children():
		if child is Button and str(child.text) == "战斗":
			return child
	return null


func _wait_battle_visible(shell: Node) -> bool:
	for _i in 40:
		await process_frame
		var battle: RunBattle = shell.get("_battle") as RunBattle
		if battle != null and battle.visible and battle.session != null and battle.session.ctx != null and battle.session.ctx.battle != null:
			var caption := battle.get_node_or_null(HAND_CAPTION_PATH) as Label
			if caption != null and str(caption.text).begins_with("手牌"):
				return true
	return false


func _click_control(target: Control, label: String, expected_method: String) -> bool:
	if target == null or not is_instance_valid(target):
		_fail("%s is gone before the click" % label)
		return false
	await _cover_control(target)
	if not _rect_ready(target):
		_fail("%s has no rect %s size=%s visible=%s" % [
			label, target.get_global_rect(), target.size, target.is_visible_in_tree(),
		])
		return false
	var methods := _signal_methods(target, "pressed")
	if methods.find(expected_method) < 0:
		_fail("%s pressed is wired to %s, expected %s" % [label, ", ".join(methods), expected_method])
		return false
	var points := _candidate_points(target)
	if points.is_empty():
		_fail("%s produced no click point" % label)
		return false
	var attempts := mini(points.size(), 6)
	for index in attempts:
		var point: Vector2 = points[index]
		_motion(point)
		var hovered := _hover_matches(target)
		if not hovered:
			await process_frame
			hovered = _hover_matches(target)
		if not hovered:
			_note("aim miss %s point=%s hover=%s rect=%s" % [label, point, _hover_path(), target.get_global_rect()])
			continue
		var hits := {"n": 0}
		var callback := func() -> void:
			hits["n"] = int(hits["n"]) + 1
		target.pressed.connect(callback)
		# Press and release in one turn so a deferred scene change cannot free the control between them.
		_button(point, true)
		_button(point, false)
		var hit := int(hits["n"])
		if is_instance_valid(target) and not target.is_queued_for_deletion() and target.pressed.is_connected(callback):
			target.pressed.disconnect(callback)
		_note("CLICK %s point=%s rect=%s hover=%s hit=%s wired=%s" % [
			label, point, target.get_global_rect() if is_instance_valid(target) else "", _hover_path(), hit, ", ".join(methods),
		])
		await process_frame
		if hit > 0:
			return true
	_note("CLICK FAILED %s rect=%s last_hover=%s" % [label, target.get_global_rect() if is_instance_valid(target) else "", _hover_path()])
	return false


func _candidate_points(target: Control) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if target is ArtButton:
		var art := target as ArtButton
		if art.name == "StartButton" and art.size.x > 1.0 and art.size.y > 1.0:
			var known := Vector2((721.0 + 0.5) / 1454.0 * art.size.x, (328.0 + 0.5) / 681.0 * art.size.y)
			if art._has_point(known):
				points.append(art.get_global_transform() * known)
		var step := 12.0
		var y := step * 0.5
		while y < art.size.y and points.size() < 8:
			var x := step * 0.5
			while x < art.size.x and points.size() < 8:
				var local := Vector2(x, y)
				if art._has_point(local):
					var global := art.get_global_transform() * local
					if not _has_point(points, global):
						points.append(global)
				x += step
			y += step
		return points
	var size := target.size
	if size.x < 2.0 or size.y < 2.0:
		return points
	var fracs: Array[float] = [0.5, 0.35, 0.65, 0.2, 0.8]
	for y_frac in fracs:
		for x_frac in fracs:
			points.append(target.get_global_transform() * Vector2(size.x * x_frac, size.y * y_frac))
			if points.size() >= 6:
				return points
	return points


func _has_point(points: Array[Vector2], point: Vector2) -> bool:
	for existing in points:
		if existing.distance_squared_to(point) < 1.0:
			return true
	return false


func _cover_control(target: Control) -> void:
	if target == null or not _rect_ready(target):
		return
	var rect := target.get_global_rect()
	var need := Vector2i(maxi(root.size.x, ceili(rect.end.x + 8.0)), maxi(root.size.y, ceili(rect.end.y + 8.0)))
	if need == root.size and rect.position.x >= 0.0 and rect.position.y >= 0.0:
		return
	root.size = need
	await process_frame
	await process_frame


func _motion(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.button_mask = 0
	root.push_input(motion, true)


func _button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = false
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)


func _hover_matches(target: Control) -> bool:
	var hovered := root.gui_get_hovered_control()
	var node: Node = hovered
	while node != null:
		if node == target:
			return true
		node = node.get_parent()
	return false


func _hover_path() -> String:
	var hovered := root.gui_get_hovered_control()
	if hovered == null:
		return "<none>"
	return str(hovered.get_path())


func _await_hand(battle: RunBattle) -> Dictionary:
	var row := battle.get_node_or_null(HAND_ROW_PATH)
	var caption := battle.get_node_or_null(HAND_CAPTION_PATH) as Label
	if row == null or caption == null or battle.session == null or battle.session.ctx == null:
		return {}
	var last := {}
	for _i in 20:
		await process_frame
		last = _read_hand(battle, row, caption)
		if int(last["queued"]) == 0 and int(last["view_count"]) > 0 and int(last["view_count"]) == int(last["caption_count"]) and int(last["lib_count"]) == int(last["view_count"]):
			return last
	return last


func _read_hand(battle: RunBattle, row: Node, caption: Label) -> Dictionary:
	var lib: Array[String] = []
	var library := battle.session.ctx.library
	for card_uid in library.pile(CardInstance.HAND):
		lib.append(str(card_uid))
	var view_uids: Array[String] = []
	var view_texts: PackedStringArray = []
	var queued := 0
	for child in row.get_children():
		if not (child is CardView):
			continue
		if child.is_queued_for_deletion():
			queued += 1
			continue
		var view := child as CardView
		view_uids.append(view.card_uid)
		view_texts.append(view.face_text())
	var fight: CardBattle = battle.session.ctx.battle
	var draw_n := 0
	var discard_n := 0
	if library != null:
		draw_n = library.pile(CardInstance.DRAW).size()
		discard_n = library.pile(CardInstance.DISCARD).size()
	return {
		"lib_uids": lib,
		"view_uids": view_uids,
		"texts": view_texts,
		"lib_count": lib.size(),
		"view_count": view_uids.size(),
		"queued": queued,
		"caption": caption.text,
		"caption_count": _caption_count(caption.text),
		"turn": 0 if fight == null else fight.turn_index,
		"phase": "" if fight == null else str(fight.phase),
		"hp": 0 if fight == null else fight.player_hp,
		"elapsed": 0.0 if fight == null else fight.player_elapsed_s,
		"delayed": false if fight == null else fight.delayed_draw_done,
		"draw": draw_n,
		"discard": discard_n,
	}


func _caption_count(text: String) -> int:
	if not text.begins_with("手牌"):
		return -1
	var parts := text.split(" ", false)
	if parts.size() < 2 or not parts[1].is_valid_int():
		return -1
	return int(parts[1])


func _hand_ready(hand: Dictionary, label: String) -> bool:
	var same := true
	var lib: Array = hand["lib_uids"]
	var views: Array = hand["view_uids"]
	if lib.size() != views.size():
		same = false
	else:
		for index in lib.size():
			if str(lib[index]) != str(views[index]):
				same = false
	if not same or int(hand["caption_count"]) != int(hand["view_count"]) or int(hand["view_count"]) < 1:
		_fail("%s mismatch caption='%s' views=%s library=%s" % [label, hand["caption"], views, lib])
		return false
	return true


func _assert_retention(before: Dictionary, after: Dictionary, hp_before: int) -> void:
	if not _hand_ready(after, "next hand"):
		return
	var draw_n := 5
	var battle_rule = null
	# turn_start_draw is the configured new-turn draw. Leftovers must remain in front of it.
	if current_scene != null and current_scene.get("_battle") != null:
		var battle: RunBattle = current_scene._battle
		if battle.session != null and battle.session.ctx != null:
			draw_n = int(battle.session.ctx.catalog.rule().get("turn_start_draw", 5))
			battle_rule = battle.session.ctx.catalog.rule().get("discard_at_turn_end", null)
	_note("rule discard_at_turn_end=%s turn_start_draw=%s" % [battle_rule, draw_n])
	var before_uids: Array = before["view_uids"]
	var after_uids: Array = after["view_uids"]
	var kept := after_uids.size() >= before_uids.size()
	if kept:
		for index in before_uids.size():
			if str(after_uids[index]) != str(before_uids[index]):
				kept = false
				break
	var grew := after_uids.size() == before_uids.size() + draw_n
	var turn_ok := int(after["turn"]) == int(before["turn"]) + 1 and str(after["phase"]) == "PLAYER_ACTIVE"
	var enemy_ok := int(after["hp"]) < hp_before
	if not kept:
		_fail("unused cards left the hand. before=%s after=%s" % [before_uids, after_uids])
	if not grew:
		_fail("hand count %s -> %s, expected leftovers + %s" % [before_uids.size(), after_uids.size(), draw_n])
	if not turn_ok:
		_fail("enemy turn did not return to the next player turn (turn %s phase %s)" % [after["turn"], after["phase"]])
	if not enemy_ok:
		_fail("enemy turn did not land (hp %s -> %s)" % [hp_before, after["hp"]])
	_note("KEPT %s/%s GREW %+d hp %s -> %s turn %s -> %s phase %s discard %s -> %s draw %s -> %s" % [
		before_uids.size() if kept else 0,
		before_uids.size(),
		after_uids.size() - before_uids.size(),
		hp_before,
		after["hp"],
		before["turn"],
		after["turn"],
		after["phase"],
		before["discard"],
		after["discard"],
		before["draw"],
		after["draw"],
	])


func _note_hand(when: String, hand: Dictionary) -> void:
	var cards := PackedStringArray()
	var uids: Array = hand["view_uids"]
	var texts: PackedStringArray = hand["texts"]
	for index in uids.size():
		var face := ""
		if index < texts.size():
			face = str(texts[index])
		cards.append("%s:%s" % [uids[index], face])
	_note("HAND %s count=%s caption='%s' phase=%s turn=%s elapsed=%s delayed=%s cards=%s" % [
		when,
		hand["view_count"],
		hand["caption"],
		hand["phase"],
		hand["turn"],
		hand["elapsed"],
		hand["delayed"],
		", ".join(cards),
	])


func _signal_methods(target: Control, signal_name: String) -> PackedStringArray:
	var methods := PackedStringArray()
	for connection in target.get_signal_connection_list(signal_name):
		var callable: Callable = connection.get("callable", Callable())
		methods.append(str(callable.get_method()))
	return methods


func _rect_ready(control: Control) -> bool:
	if control == null or not control.is_inside_tree() or not control.is_visible_in_tree():
		return false
	var rect := control.get_global_rect()
	return rect.size.x > 4.0 and rect.size.y > 4.0


func _wait_named(node_name: String, frames: int) -> Node:
	for _i in frames:
		await process_frame
		var scene := current_scene
		if scene != null and scene.name == node_name:
			return scene
	return null


func _fail(message: String) -> void:
	_failures.append(message)
	_note("FAIL: " + message)


func _note(message: String) -> void:
	_log.append(message)
	print(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: unused cards stayed in hand and the next player turn drew 5 more")
	else:
		print("FAIL: hand-retention click path (%s)" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
