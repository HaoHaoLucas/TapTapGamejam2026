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
	root.size = Vector2i(1440, 900)
	await _test_pause_draw_and_combo()
	await _test_manual_pause_and_claim_reset()
	await _test_shell_input_and_new_run()
	await _test_layout_and_sidebar()
	await _test_shell_battle_bag_visible()
	await _test_scaled_grid_and_states()
	if _failures == 0:
		print("PASS: run inventory drawer, pause, input, and layout")
	else:
		push_error("run inventory panel failures: %s" % _failures)
	quit(1 if _failures else 0)


func _test_pause_draw_and_combo() -> void:
	var run := _run_for("bag-pause")
	if run == null:
		return
	_enter(run, "RM_RUST")
	var session := CombatSession.new()
	session.start(run)
	var battle: CardBattle = session.ctx.battle
	var library: CardLibrary = session.ctx.library
	var hand := library.pile(CardInstance.HAND).size()
	battle.player_elapsed_s = 7.4
	battle.delayed_draw_done = false
	var inventory := _inventory()
	root.add_child(inventory)
	await process_frame
	inventory.slide_seconds = 0.05
	inventory.set_sources(run, library, battle)
	inventory.request_open()
	_check(battle.paused, "Opening the bag pauses the fight immediately")
	_check(inventory._pause_badge.visible and inventory._pause_badge.text == "已暂停", "The open bag says the fight is paused")
	battle.advance(1.0)
	_check(is_equal_approx(battle.player_elapsed_s, 7.4), "Paused time does not reach the delayed draw")
	_check(not battle.delayed_draw_done, "The delayed draw does not fire while the bag is open")
	_check(library.pile(CardInstance.HAND).size() == hand, "The bag does not draw a card")
	inventory.request_close()
	_check(battle.paused, "The fight stays paused until the close animation finishes")
	await _settle(inventory)
	_check(not battle.paused, "Closing restores a fight that was running, ratio %s sliding %s" % [inventory._open_ratio, inventory._sliding])
	battle.advance(0.2)
	_check(battle.delayed_draw_done, "The delayed draw happens once after resume")
	_check(library.pile(CardInstance.HAND).size() == hand + 1, "Resume draws one card and does not draw again")
	battle.phase = "COMBO"
	battle.combo_remaining = 3.0
	battle.paused = false
	inventory.request_open()
	battle.advance(1.0)
	_check(is_equal_approx(battle.combo_remaining, 3.0), "The combo window does not tick while the bag is open")
	inventory.request_close()
	await _settle(inventory)
	_check(not battle.paused, "The combo window resumes")
	battle.advance(0.5)
	_check(is_equal_approx(battle.combo_remaining, 2.5), "The combo window continues from where it stopped")
	inventory.queue_free()
	await process_frame


func _test_manual_pause_and_claim_reset() -> void:
	var run := _run_for("bag-manual")
	if run == null:
		return
	_enter(run, "RM_RUST")
	var session := CombatSession.new()
	session.start(run)
	var battle: CardBattle = session.ctx.battle
	battle.paused = true
	var inventory := _inventory()
	root.add_child(inventory)
	await process_frame
	inventory.slide_seconds = 0.05
	inventory.set_sources(run, session.ctx.library, battle)
	inventory.request_open()
	inventory.request_close()
	await _settle(inventory)
	_check(battle.paused, "A fight that was already paused stays paused")
	inventory.request_open()
	_check(battle.paused, "Opening again keeps the manual pause")
	inventory.reset_run()
	_check(battle.paused, "Leaving the run does not write the old pause flag")
	_check(not inventory.blocks_input(), "A new run closes the bag")
	var other := _run_for("bag-next")
	_enter(other, "RM_RUST")
	var next := CombatSession.new()
	next.start(other)
	_check(not next.ctx.battle.paused, "The next fight starts unpaused")
	inventory.set_sources(other, next.ctx.library, next.ctx.battle)
	inventory.request_close()
	_check(not next.ctx.battle.paused, "An abandoned bag does not unpause the next fight")
	inventory.request_open()
	_check(next.ctx.battle.paused, "The next fight can be paused by its own bag")
	inventory.request_close()
	await _settle(inventory)
	_check(not next.ctx.battle.paused, "Closing the next bag resumes only that fight")
	inventory.queue_free()
	await process_frame


func _test_shell_input_and_new_run() -> void:
	var shell = load("res://scenes/run/run_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	_check(shell._inventory != null, "The run shell hosts the bag")
	if shell.run == null or shell._inventory == null:
		shell.queue_free()
		await process_frame
		return
	shell._inventory.slide_seconds = 0.05
	_enter(shell.run, "RM_RUST")
	shell._show_battle()
	await process_frame
	_check(shell._session != null and shell._battle.visible, "The shell battle is open under the bag")
	if shell._session == null:
		shell.queue_free()
		await process_frame
		return
	var library: CardLibrary = shell._session.ctx.library
	var battle: CardBattle = shell._session.ctx.battle
	var hand: Array = library.pile(CardInstance.HAND)
	_check(not hand.is_empty(), "The battle has a hand")
	if hand.is_empty():
		shell.queue_free()
		await process_frame
		return
	var kept := str(hand[0])
	shell._battle.formula.append(kept)
	shell._battle.selected_uid = kept
	shell._selected_offer = "keep-offer"
	shell._selected_cards = [kept]
	var rewards := var_to_str(shell.run.reward_sessions)
	var zones_before := _zones(shell.run)
	shell._inventory.request_open()
	await process_frame
	_check(battle.paused, "The shell battle pauses when the bag opens")
	_check(shell._battle._external_input_blocked, "Battle shortcuts are locked while the bag is open")
	_check(shell._inventory._blocker.visible, "The bag catches mouse input while open")
	for code in [KEY_P, KEY_B, KEY_E, KEY_ENTER, KEY_SPACE, KEY_ESCAPE]:
		shell._inventory._input(_key(code))
		shell._battle._input(_key(code))
	_check(battle.paused, "Shortcuts cannot unpause or dismiss the bag early")
	_check(shell._battle.formula.size() == 1 and shell._battle.formula[0] == kept, "Esc and submit do not clear the equation")
	_check(shell._battle.selected_uid == kept, "Burn does not change the selected card")
	_check(library.pile(CardInstance.HAND).size() == hand.size(), "Shortcuts do not burn or end the turn")
	_check(shell._selected_offer == "keep-offer" and shell._selected_cards == [kept], "The bag does not clear the shell selection")
	_check(var_to_str(shell.run.reward_sessions) == rewards, "The bag does not change reward candidates")
	_check(_zones(shell.run) == zones_before, "Opening the bag does not move run cards")
	await _settle(shell._inventory)
	_check(not battle.paused, "The shell battle resumes after the bag closes")
	_check(not shell._battle._external_input_blocked, "Battle input returns after the bag closes")
	_check(shell._battle.formula.size() == 1 and shell._battle.formula[0] == kept, "The equation is still there after closing")
	shell._inventory.request_open()
	await process_frame
	var burned := ""
	for card_uid in library.pile(CardInstance.HAND):
		if str(card_uid) == kept:
			continue
		var card := library.get_card(str(card_uid))
		if card != null and str(shell._session.ctx.catalog.card(card.def_id).get("card_kind", "")) == "NUM":
			burned = card.card_uid
			break
	_check(burned != "", "A second number card can be burned while the bag is open")
	if burned != "":
		var result = shell._session.ctx.card_service.burn(burned, "bag-open-burn")
		_check(result.get("ok", false), "An already accepted burn still resolves")
		await process_frame
		_check(_grid_has(shell._inventory, burned) == false, "The open bag refreshes after the burn")
	shell._session.ctx.battle.phase = "VICTORY"
	shell._on_return_to_tower("VICTORY")
	await process_frame
	_check(not shell._inventory._pause_claim, "Returning to the tower drops the pause claim")
	if shell._inventory.blocks_input():
		var shown := RunInventoryPresenter.present(shell.run)
		_check(_find_label(shown, kept) == "本局牌库", "After write-back the bag reads the run deck")
		if burned != "":
			_check(_find_label(shown, burned) == "", "The burned card is gone after write-back")
	shell._inventory._kind = RunInventoryPresenter.KIND_NUM
	shell._inventory._selected_uid = "stale"
	shell._inventory._card_scroll.scroll_vertical = 48
	shell._start_run("bag-new-run")
	await process_frame
	_check(shell._inventory._kind == RunInventoryPresenter.KIND_ALL, "A new run resets the kind filter")
	_check(shell._inventory._marks == RunInventoryPresenter.MARKS_ALL, "A new run resets the mark filter")
	_check(shell._inventory._sort_mode == RunInventoryPresenter.SORT_ACQUIRED, "A new run resets the sort")
	_check(shell._inventory._selected_uid == "", "A new run clears the selection")
	_check(shell._inventory._card_scroll.scroll_vertical == 0, "A new run resets the scroll position")
	_check(not shell._inventory.blocks_input(), "A new run closes the bag")
	_enter(shell.run, "RM_RUST")
	shell._show_battle()
	await process_frame
	_check(shell._session != null and not shell._session.ctx.battle.paused, "The next shell fight is not stuck paused")
	shell.queue_free()
	await process_frame


func _test_layout_and_sidebar() -> void:
	var run := _run_for("bag-layout")
	if run == null:
		return
	var target: CardInstance = null
	for card in run.card_instances:
		if str(GameData.card(card.def_id).get("card_kind", "")) == "NUM":
			target = card
			break
	_check(target != null, "Layout run needs a number card")
	if target == null:
		return
	_check(TowerDeck.apply_mark(run, target.card_uid, "EN_RETURN").get("ok", false), "Layout card takes return")
	_check(TowerDeck.apply_mark(run, target.card_uid, "EN_FRAGILE").get("ok", false), "Layout card takes fragile")
	while run.card_instances.size() < 45:
		TowerDeck.create_card(run, "CARD_N1", [], run.depth, "")
	var scene_text := FileAccess.get_file_as_string("res://scenes/run/run_inventory.tscn")
	_check(not scene_text.contains("销毁") and not scene_text.contains("使用"), "The bag scene has no destroy or use action")
	# Raw canvas geometry; actual canvas_items + keep window scaling is checked below.
	for size in [Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1920, 1440)]:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.size = size
		await process_frame
		var stage := Control.new()
		stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(stage)
		var battle := (load("res://scenes/run/run_battle.tscn") as PackedScene).instantiate() as RunBattle
		battle.name = "Battle"
		stage.add_child(battle)
		var inventory := _inventory()
		inventory.set_sources(run)
		inventory.set_input_view(battle)
		stage.add_child(inventory)
		await process_frame
		await process_frame
		inventory.set_battle_clearance(true)
		await process_frame
		inventory.slide_seconds = 0.05
		inventory.request_open()
		await _settle(inventory)
		await process_frame
		var view_size := inventory.size
		var host: Control = inventory.get_node("DrawerHost")
		var panel: Control = inventory.get_node("DrawerHost/Slide/BagPanel")
		var host_rect := host.get_global_rect()
		var panel_rect := panel.get_global_rect()
		var timer: Control = battle.get_node("Board/Margin/Column/TopBar/Clock/Timer")
		var hand: Control = battle.get_node("Hand")
		var timer_rect := timer.get_global_rect()
		var hand_rect := hand.get_global_rect()
		_check(panel_rect.position.y >= timer_rect.end.y - 1.0, "%s panel starts below the countdown, panel=%s timer=%s" % [size, panel_rect, timer_rect])
		_check(host_rect.position.y >= timer_rect.end.y - 1.0, "%s tab starts below the countdown, host=%s timer=%s" % [size, host_rect, timer_rect])
		if hand_rect.position.y < view_size.y:
			_check(panel_rect.end.y <= hand_rect.position.y + 1.0, "%s panel stays above the hand, panel=%s hand=%s" % [size, panel_rect, hand_rect])
		_check(panel_rect.end.y <= host_rect.end.y + 1.0, "%s panel fits the drawer, panel=%s host=%s" % [size, panel_rect, host_rect])
		_check(panel.size.y + 1.0 >= panel.get_combined_minimum_size().y, "%s panel is not forced past its viewport, size=%s min=%s" % [size, panel.size, panel.get_combined_minimum_size()])
		var close: Button = inventory.get_node("DrawerHost/Slide/BagPanel/Margin/Body/Header/CloseButton")
		var close_rect := close.get_global_rect()
		_check(close_rect.position.x >= -1.0 and close_rect.position.y >= -1.0, "%s close button is on screen" % size)
		_check(close_rect.position.x + close_rect.size.x <= view_size.x + 1.0, "%s close button stays inside the width" % size)
		_check(close_rect.position.y + close_rect.size.y <= view_size.y + 1.0, "%s close button stays inside the height" % size)
		_check(close_rect.position.y + close_rect.size.y <= host_rect.position.y + host_rect.size.y + 1.0, "%s close button stays in the drawer" % size)
		var split := inventory.get_node("DrawerHost/Slide/BagPanel/Margin/Body/Split") as HSplitContainer
		var cards: Control = split.get_node("Cards")
		var resources: Control = split.get_node("Resources")
		_check(not resources.visible, "%s hides unfinished collection and meta UI" % size)
		_check(absf(cards.size.x - split.size.x) <= 1.0, "%s cards reclaim the hidden sidebar width" % size)
		var first := inventory._grid.get_child(0) as CardView
		_check(first != null, "%s has a card to select" % size)
		inventory._card_scroll.scroll_vertical = 0
		if first != null:
			inventory._on_card_pressed(first.card_uid)
		await process_frame
		await process_frame
		var detail_scroll: ScrollContainer = inventory._detail_scroll
		var detail_view := detail_scroll.get_global_rect()
		var detail_top := inventory._detail.get_global_rect()
		_check(inventory._card_scroll.scroll_vertical == 0, "%s selecting a card does not require scrolling the grid" % size)
		_check(detail_scroll.scroll_vertical == 0, "%s detail opens at its first line" % size)
		_check(_contains_point(detail_view, detail_top.position + Vector2(4, 4)), "%s detail is on screen after the click, detail=%s view=%s" % [size, detail_top, detail_view])
		_check(_contains_point(host_rect, detail_top.position + Vector2(4, 4)), "%s detail sits inside the drawer" % size)
		inventory._on_card_pressed(target.card_uid)
		await process_frame
		await process_frame
		var detail := inventory._detail.text
		_check(detail.contains("这局第一次打出后回到手里"), "%s detail keeps the full return text" % size)
		_check(detail.contains("15% 的几率碎掉"), "%s detail keeps the full fragile text" % size)
		_check(detail.contains("所在区域：本局牌库"), "%s detail shows where the card is" % size)
		_check(detail.contains("获取层数："), "%s detail shows the floor" % size)
		detail_scroll.scroll_vertical = 100000
		await process_frame
		await process_frame
		var detail_rect := inventory._detail.get_global_rect()
		detail_view = detail_scroll.get_global_rect()
		host_rect = host.get_global_rect()
		var visible_bottom := minf(detail_view.end.y, host_rect.end.y)
		var visible_top := maxf(detail_view.position.y, host_rect.position.y)
		_check(detail_rect.end.y <= visible_bottom + 2.0, "%s last detail line stays visible, text_bottom=%s visible_bottom=%s" % [size, detail_rect.end.y, visible_bottom])
		_check(detail_rect.end.y > visible_top + 8.0, "%s last detail line is inside the viewport, text_bottom=%s visible_top=%s" % [size, detail_rect.end.y, visible_top])
		_check(detail_view.end.y <= host_rect.end.y + 1.0, "%s detail viewport fits the drawer, view=%s host=%s" % [size, detail_view, host_rect])
		var content := inventory._card_scroll.get_child(0) as Control
		var bar := inventory._card_scroll.get_v_scroll_bar()
		_check(bar.max_value - bar.page <= 1.0 or bar.visible, "%s overflowing cards have a scrollbar" % size)
		_check(content.size.y >= inventory._grid.size.y, "%s scroll content contains all rows" % size)
		stage.queue_free()
		await process_frame
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440, 900)
	await process_frame
	var roaming := _inventory()
	roaming.set_battle_clearance(false)
	roaming.set_sources(run)
	root.add_child(roaming)
	await process_frame
	await process_frame
	var roam_host: Control = roaming.get_node("DrawerHost")
	var roam_rect := roam_host.get_global_rect()
	_check(absf(roam_rect.position.y + roam_rect.size.y - roaming.size.y) < 2.0, "Outside battle the drawer reaches the bottom edge, bottom=%s view=%s" % [roam_rect.position.y + roam_rect.size.y, roaming.size])
	var connected := ConnectedMeta.new()
	roaming.set_meta_provider(connected)
	roaming.request_open()
	await _settle(roaming)
	var meta_text := _node_text(roaming.get_node("DrawerHost/Slide/BagPanel/Margin/Body/Split/Resources"))
	_check(meta_text.contains("碎片") and meta_text.contains("3") and meta_text.contains("测试说明"), "A connected provider fills the sidebar")
	_check(not meta_text.contains("金币"), "Connected resources use the provider text")
	roaming.queue_free()
	await process_frame


func _test_shell_battle_bag_visible() -> void:
	for size in [Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1920, 1440)]:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.size = size
		await process_frame
		var shell = load("res://scenes/run/run_shell.tscn").instantiate()
		root.add_child(shell)
		await process_frame
		await process_frame
		_check(shell.run != null and shell._inventory != null, "%s run shell is ready" % size)
		if shell.run == null or shell._inventory == null:
			shell.queue_free()
			await process_frame
			continue
		var inventory: RunInventory = shell._inventory
		_check(is_equal_approx(inventory.slide_seconds, 0.45), "%s keeps the default drawer animation" % size)
		_enter(shell.run, "RM_RUST")
		shell._show_battle()
		inventory.request_open()
		await _settle_default(inventory)
		await process_frame
		var host: Control = inventory.get_node("DrawerHost")
		var panel: Control = inventory.get_node("DrawerHost/Slide/BagPanel")
		var host_rect := host.get_global_rect()
		var panel_rect := panel.get_global_rect()
		_check(host_rect.size.y > 160.0, "%s drawer is tall enough to read, height=%s" % [size, host_rect.size.y])
		_check(panel_rect.size.y > 120.0, "%s panel is more than a border, height=%s" % [size, panel_rect.size.y])
		var cards_seen := 0
		for child in inventory._grid.get_children():
			var view := child as Control
			if view != null and _overlap_height(view.get_global_rect(), host_rect) > 40.0:
				cards_seen += 1
		_check(cards_seen > 0, "%s shows cards inside the open drawer" % size)
		var detail_rect := inventory._detail_scroll.get_global_rect()
		_check(_overlap_height(detail_rect, host_rect) > 16.0, "%s shows the detail area, rect=%s host=%s" % [size, detail_rect, host_rect])
		var resources: Control = inventory.get_node("DrawerHost/Slide/BagPanel/Margin/Body/Split/Resources")
		_check(not resources.visible, "%s keeps unfinished resources hidden" % size)
		var timer: Control = shell._battle.get_node("Board/Margin/Column/TopBar/Clock/Timer")
		_check(panel_rect.position.y >= timer.get_global_rect().end.y - 1.0, "%s panel stays below the countdown" % size)
		shell.queue_free()
		await process_frame


func _test_scaled_grid_and_states() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var capture_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-inventory="):
			capture_dir = arg.trim_prefix("--capture-inventory=")
	if capture_dir != "":
		DirAccess.make_dir_recursive_absolute(capture_dir)
	for window_size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1920, 1440)]:
		root.size = window_size
		await process_frame
		var shell = load("res://scenes/run/run_shell.tscn").instantiate()
		root.add_child(shell)
		await process_frame
		var run: RunState = shell.run
		var target: CardInstance = null
		for card in run.card_instances:
			if str(GameData.card(card.def_id).get("card_kind", "")) == "NUM":
				target = card
				break
		_check(target != null, "Scaled layout has a numeric card")
		_check(TowerDeck.apply_mark(run, target.card_uid, "EN_RETURN").get("ok", false), "Scaled layout applies return")
		_check(TowerDeck.apply_mark(run, target.card_uid, "EN_FRAGILE").get("ok", false), "Scaled layout applies fragile")
		while run.card_instances.size() < 100:
			TowerDeck.create_card(run, "CARD_N1", [], run.depth, "")
		_enter(run, "RM_RUST")
		shell._show_battle()
		var bag: RunInventory = shell._inventory
		bag.slide_seconds = 0.0
		bag.request_open()
		await _layout_frames()
		_check(bag._grid.get_child_count() == 100, "%s lists all 100 cards" % window_size)
		_check_grid_bounds(bag, str(window_size))
		var columns := bag._grid.columns
		await _layout_frames()
		_check(columns == bag._grid.columns, "%s column count settles" % window_size)
		bag._card_scroll.scroll_vertical = 100000
		await _layout_frames()
		var last := bag._grid.get_child(99) as Control
		var scroll_rect := bag._card_scroll.get_global_rect()
		_check(last.get_global_rect().end.y <= scroll_rect.end.y + 1.0, "%s final card row can be read" % window_size)
		var kept_scroll := bag._card_scroll.scroll_vertical
		bag._on_card_pressed(target.card_uid)
		await _layout_frames()
		_check(bag._card_scroll.scroll_vertical == kept_scroll, "%s selection keeps grid scroll" % window_size)
		_check(bag._detail_scroll.scroll_vertical == 0, "%s selection starts detail at top" % window_size)
		_check(bag._detail.text.contains("15% 的几率碎掉"), "%s long mark description is retained" % window_size)
		bag._card_scroll.scroll_vertical = 0
		await _capture_inventory(capture_dir, "battle_%dx%d" % [window_size.x, window_size.y])
		bag.set_meta_provider(ManyMeta.new())
		await _layout_frames()
		var resources := bag._meta_list.get_parent().get_parent() as ScrollContainer
		_check(not resources.is_visible_in_tree(), "Even a connected provider keeps unfinished resource UI hidden")
		bag.set_meta_provider(null)
		_check(bag._meta_empty.visible and bag._meta_empty.text == MetaResourceProvider.DISCONNECTED_TEXT, "Disconnect restores truthful resource hint")
		# Shrink below one toolbar line to exercise whole-group wrapping without changing window scaling.
		var toolbar: HFlowContainer = bag.get_node("DrawerHost/Slide/BagPanel/Margin/Body/Filters")
		var toolbar_probe := toolbar.duplicate() as HFlowContainer
		root.add_child(toolbar_probe)
		toolbar_probe.size = Vector2(390, 0)
		await _layout_frames()
		_check(toolbar_probe.get_child(2).position.y > toolbar_probe.get_child(0).position.y, "Toolbar wraps groups at narrow widths")
		for group in toolbar_probe.get_children():
			_check(group.position.x >= 0 and group.position.x + group.size.x <= toolbar_probe.size.x + 1, "Wrapped filter group fits its row")
		toolbar_probe.free()
		var first_view := bag._grid.get_child(0) as CardView
		await _click_inventory_control(first_view)
		_check(bag._selected_uid == first_view.card_uid, "%s card responds to viewport clicks" % window_size)
		await _click_inventory_control(bag._mark_yes)
		_check(bag._mark_yes.button_pressed and bag._grid.get_child_count() == 1, "%s filter responds to viewport clicks" % window_size)
		await _click_inventory_control(bag._close)
		_check(not bag.blocks_input(), "%s close button responds to viewport clicks" % window_size)
		shell.free()
		await process_frame
	# Empty and filtered-out states use the same viewport and keep the detail area available.
	root.size = Vector2i(1280, 720)
	var empty_run := _run_for("bag-empty-layout")
	empty_run.card_instances.clear()
	var empty_bag := _inventory()
	empty_bag.set_sources(empty_run)
	root.add_child(empty_bag)
	empty_bag.slide_seconds = 0.0
	empty_bag.request_open()
	await _layout_frames()
	_check(empty_bag._empty.visible and empty_bag._grid.get_child_count() == 0, "Empty bag has an explicit placeholder")
	_check(empty_bag._detail.text == "选择一张牌查看详情", "Empty bag has a detail placeholder")
	await _capture_inventory(capture_dir, "roam_empty_1280x720")
	TowerDeck.create_card(empty_run, "CARD_N1", [], empty_run.depth, "")
	empty_bag._reload(false)
	empty_bag._set_marks(RunInventoryPresenter.MARKS_PRESENT)
	await _layout_frames()
	_check(empty_bag._empty.visible and empty_bag._empty.text == "没有符合筛选的卡牌", "No-match filter explains the empty grid")
	await _capture_inventory(capture_dir, "roam_filtered_1280x720")
	empty_bag._set_marks(RunInventoryPresenter.MARKS_ALL)
	_check(empty_bag._grid.get_child_count() == 1, "Clearing filter restores cards")
	empty_bag.free()
	await process_frame
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 900)


func _layout_frames() -> void:
	for _i in 8:
		await process_frame


func _click_inventory_control(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _layout_frames()


func _check_grid_bounds(bag: RunInventory, context: String) -> void:
	var viewport := bag._card_scroll.get_global_rect()
	var bar := bag._card_scroll.get_v_scroll_bar()
	var right := viewport.end.x - (bar.size.x if bar.visible else 0.0)
	for child in bag._grid.get_children():
		var rect := (child as Control).get_global_rect()
		_check(rect.position.x >= viewport.position.x - 1 and rect.end.x <= right + 1, "%s every card fits the scroll viewport, rect=%s right=%s" % [context, rect, right])
	var panel := bag._panel.get_global_rect()
	var detail := bag._detail_scroll.get_global_rect()
	_check(detail.position.x >= viewport.end.x and detail.end.x <= panel.end.x + 1, "%s detail column fits beside grid" % context)
	_check(is_equal_approx(detail.size.x, 260.0), "%s keeps 260px detail width" % context)
	var resources := bag._meta_list.get_parent().get_parent() as Control
	_check(not resources.is_visible_in_tree(), "%s unfinished resource area stays hidden" % context)
	_check(panel.encloses(bag._close.get_global_rect()), "%s close button remains accessible" % context)
	_check(bag._panel.size.y + 1 >= bag._panel.get_combined_minimum_size().y, "%s body fits available drawer height" % context)


func _capture_inventory(directory: String, label: String) -> void:
	if directory == "":
		return
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	_check(error == OK, "Captured %s" % label)


class ManyMeta extends MetaResourceProvider:
	func is_available() -> bool:
		return true

	func list_resources() -> Array:
		var rows: Array = []
		for i in 20:
			rows.append({"id": str(i), "name": "碎片 %d" % i, "count": i + 1, "description": "资源说明：用于检查长列表能够滚动到最后一项。"})
		return rows


func _overlap_height(a: Rect2, b: Rect2) -> float:
	return maxf(0.0, minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y))


func _settle_default(inventory: RunInventory) -> void:
	for _i in 24:
		if not inventory._sliding:
			await process_frame
			return
		await create_timer(0.05).timeout


func _contains_point(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x - 1.0 and point.x <= rect.end.x + 1.0 and point.y >= rect.position.y - 1.0 and point.y <= rect.end.y + 1.0


func _settle(inventory: RunInventory) -> void:
	for _i in 12:
		if not inventory._sliding:
			await process_frame
			return
		await create_timer(0.05).timeout


func _inventory() -> RunInventory:
	var inventory := (load("res://scenes/run/run_inventory.tscn") as PackedScene).instantiate() as RunInventory
	inventory.slide_seconds = 0.05
	return inventory


func _run_for(seed: String) -> RunState:
	var created := RunService.new_run(seed)
	_check(created.get("ok", false), "Could not start %s" % seed)
	if not created.get("ok", false):
		return null
	return created.run


func _enter(run: RunState, room_id: String) -> void:
	var room := GameData.room(room_id)
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


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.echo = false
	event.keycode = code
	event.physical_keycode = code
	return event


func _zones(run: RunState) -> Array:
	var rows: Array = []
	for card in run.card_instances:
		rows.append("%s:%s" % [card.card_uid, card.zone])
	return rows


func _grid_has(inventory: RunInventory, card_uid: String) -> bool:
	for child in inventory._grid.get_children():
		var view := child as CardView
		if view != null and view.card_uid == card_uid:
			return true
	return false


func _find_label(snapshot: Dictionary, card_uid: String) -> String:
	for card in snapshot.get("cards", []):
		if str(card.get("card_uid", "")) == card_uid:
			return str(card.get("zone_label", ""))
	return ""


func _node_text(node: Node) -> String:
	var text := ""
	if node is Label or node is Button:
		text = node.text
	for child in node.get_children():
		text += "\n" + _node_text(child)
	return text


class ConnectedMeta extends MetaResourceProvider:
	func is_available() -> bool:
		return true


	func list_resources() -> Array:
		return [{
			"id": "shard",
			"name": "碎片",
			"icon": null,
			"count": 3,
			"description": "测试说明",
		}]
