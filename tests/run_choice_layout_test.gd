extends SceneTree
## Run normally for viewport input tests; add -- --capture for rendered PNGs.

var failures := 0
var shell
var capture := false


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func settle() -> void:
	for i in 8:
		await process_frame


func choices() -> Array[Node]:
	return shell._body.find_children("*", "Button", true, false)


func action(label: String) -> Button:
	for button in shell._actions.get_children():
		if button.text == label:
			return button
	return null


func click(control: Control) -> void:
	check(control != null, "Click target exists")
	if control == null:
		return
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = point
		root.push_input(event, true)
	await settle()


func shot(label: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	var folder := "res://build/layout-qa"
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder + "/" + label + ".png") == OK, "Screenshot saved")


func enter(room_id: String) -> void:
	shell._start_run("layout-" + room_id)
	var room := GameData.room(room_id)
	shell.run.current_room = {"room_uid": shell.run.uid("R"), "room_id": room_id,
		"content_id": room.get("content_id", ""), "room_kind": room.get("room_kind", ""),
		"display_key": room.get("display_key", ""), "scene_key": room.get("scene_key", ""), "status": "ENTERED"}
	shell.run.phase = "ROOM"


func geometry() -> void:
	var buttons := choices()
	for i in buttons.size():
		var rect: Rect2 = buttons[i].get_global_rect()
		check(rect.position.x >= shell._scroll.global_position.x - 1, "Choice fits left content edge")
		check(rect.end.x <= shell._scroll.get_global_rect().end.x + 1, "Choice fits right content edge")
		for j in range(i + 1, buttons.size()):
			check(not rect.intersects(buttons[j].get_global_rect()), "Choices never overlap")
	for button in shell._actions.get_children():
		check(button.get_global_rect().position.y >= shell._scroll.get_global_rect().end.y, "Actions stay below scroll")
		check(button.get_global_rect().end.y <= shell.size.y * 0.94 + 1, "Actions clear the bag tab")


func _run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	shell = load("res://scenes/run/run_shell.tscn").instantiate()
	root.add_child(shell)
	await settle()
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1440, 900), Vector2i(800, 450)]:
		root.size = resolution
		shell._start_run("layout-sizes")
		await settle()
		check(choices().size() == 3, "Three rooms shown")
		check(not shell._scroll.get_v_scroll_bar().visible, "Three rooms fit without scrolling")
		geometry()
		await shot("rooms-%dx%d" % [resolution.x, resolution.y])
		enter("RM_RUST")
		RunService.finish_room(shell.run, "victory")
		shell._show()
		await settle()
		geometry()
		check(not shell._scroll.get_v_scroll_bar().visible, "Three rewards fit at each resolution")
		await shot("reward-%dx%d" % [resolution.x, resolution.y])
	root.size = Vector2i(1280, 720)
	shell._start_run("layout-room-click")
	await settle()
	# Room selection uses actual viewport mouse input, including the child card face.
	await click(choices()[0])
	check(str(shell.run.current_room.get("status", "")) == "ENTERED", "Room click enters room")
	# A single Boss stays centered and does not fill the entire row.
	shell._start_run("layout-boss")
	shell.run.current_offers = [{"offer_uid": "preview-boss", "display_key": "ROOM_BOSS"}]
	shell._show()
	await settle()
	check(absf(choices()[0].get_global_rect().get_center().x - shell.size.x * 0.5) < 2, "Single Boss centered")
	await shot("boss")
	# Real normal reward flow: select, inspect inventory, confirm and continue.
	enter("RM_RUST")
	RunService.finish_room(shell.run, "victory")
	shell._show()
	await settle()
	check(action("确认").disabled, "Reward requires a selection")
	check(not shell._scroll.get_v_scroll_bar().visible, "Normal reward fits without scrolling")
	geometry()
	await shot("reward")
	var before: int = TowerDeck.deck_cards(shell.run).size()
	await click(choices()[0])
	check(not action("确认").disabled, "Selecting reward enables confirm")
	check(root.gui_get_focus_owner() != null and str(root.gui_get_focus_owner().get_meta("focus_key", "")) == shell._selected_offer, "Focus follows selected offer after rebuild")
	var selected: String = shell._selected_offer
	shell._inventory.request_open()
	await create_timer(shell._inventory.slide_seconds + 0.1).timeout
	shell._inventory.request_close()
	await create_timer(shell._inventory.slide_seconds + 0.1).timeout
	check(shell._selected_offer == selected, "Bag preserves selected offer")
	await shot("reward-selected")
	await click(action("确认"))
	check(TowerDeck.deck_cards(shell.run).size() == before + 1, "Confirm grants one card")
	check(not shell._notice.is_empty(), "Grant shows result")
	await shot("result")
	await click(action("继续"))
	if action("跳过") != null:
		await click(action("跳过"))
	check(shell.run.phase != "REWARD", "Skip advances remaining reward")
	# Multi-select: cap at three; preserve scroll and prevent content covering actions.
	enter("RM_SAC")
	shell._show()
	await settle()
	check(action("确认").disabled, "Sacrifice requires cards")
	await shot("sacrifice")
	for i in 4:
		choices()[i].pressed.emit()
		await settle()
	check(shell._selected_cards.size() == 3, "Sacrifice capped at three")
	shell._scroll.scroll_vertical = 180
	await settle()
	choices()[0].pressed.emit()
	await settle()
	check(shell._scroll.scroll_vertical == 180, "Selection preserves scroll offset")
	geometry()
	await shot("sacrifice-selected")
	# Transform preview survives the rebuild.
	enter("RM_TRANS")
	shell._show()
	await settle()
	await click(choices()[0])
	check(shell._status.text.begins_with("会变成"), "Transform preview remains visible")
	await shot("transform")
	# Mark selection exposes targets, clears them on offer change, and remains scrollable.
	enter("RM_SMITH")
	shell._show()
	await settle()
	await click(choices()[0])
	check(choices().size() > 3, "Smith shows legal target cards")
	choices()[3].pressed.emit()
	await settle()
	check(not action("确认").disabled, "Mark plus target enables confirm")
	choices()[1].pressed.emit()
	await settle()
	check(shell._selected_cards.is_empty() and action("确认").disabled, "Changing mark clears target")
	geometry()
	await shot("smith")
	# Boss has consecutive card and mark rewards.
	enter("RM_SWORD")
	RunService.finish_room(shell.run, "victory")
	shell._show()
	await settle()
	await shot("boss-reward")
	await click(action("跳过"))
	check(str(GameData.reward(str(shell._open_reward_session().get("reward_id", ""))).get("payload_kind", "")) == "MARK", "Boss proceeds to mark reward")
	await click(choices()[0])
	check(choices().size() > 3, "Mark reward exposes targets")
	geometry()
	await shot("mark-reward")
	await click(action("跳过"))
	check(shell.run.phase == "FLOOR_CLEAR", "Boss rewards reach floor clear")
	await shot("floor-clear")
	await click(action("继续下一层"))
	check(shell.run.depth == 2 and choices().size() == 3, "Continue floor reaches next room choices")
	# Delayed reward selection uses the same grid and keeps the discard distinction.
	enter("RM_PIZZA")
	shell._show()
	await settle()
	check(shell._title.global_position.y > shell.size.y * 0.29, "Dialogue title joins the central conversation")
	check(shell._scroll.size.x <= shell.size.x * 0.51, "Dialogue wraps within half the screen")
	check(action("收下").get_global_rect().end.y < shell.size.y * 0.7, "Dialogue actions sit near the text")
	geometry()
	await shot("pizza-dialogue")
	await click(action("收下"))
	check(not shell.run.quest_states.is_empty(), "Pizza order accepted by clicking")
	shell._notice = {}
	var quest: Dictionary = shell.run.quest_states[0]
	shell.run.depth = int(quest.target_depth)
	RewardService.build_pizza_snapshot(shell.run, quest)
	quest.status = "READY"
	shell.run.phase = "FLOOR_CLEAR"
	shell._show()
	await settle()
	check(is_equal_approx(shell._scroll.anchor_top, 0.22), "Card selection restores the standard layout")
	await click(choices()[0])
	check(choices()[0].tooltip_text.begins_with("丢掉"), "Discard explicitly marked")
	await shot("pizza")
	await click(action("确认领取"))
	check(shell._pizza_done, "Pizza claim completes")
	shell._notice = {"title": "领取结果", "lines": Array(PackedStringArray(["这是一段较长的强化说明，用于检查结果展示、自动换行和固定操作栏。".repeat(3)]))}
	for i in 10:
		shell._notice.lines.append("强化 %d：获得的变化完整显示，操作按钮始终可用。" % i)
	shell._show()
	await settle()
	geometry()
	await shot("long-result")
	shell._notice = {}
	shell.run.phase = "DEAD"
	shell._show()
	await settle()
	await shot("end")
	await click(action("新的一局"))
	check(choices().size() == 3, "Restart returns to room choices")
	shell.queue_free()
	await settle()
	print("PASS: choice layout, input and flows" if failures == 0 else "FAIL: %d choice layout checks" % failures)
	quit(0 if failures == 0 else 1)
