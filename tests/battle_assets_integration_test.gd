extends SceneTree
## --capture renders the same exercised states into build/asset-qa (use a GPU).

const ENEMY := preload("res://scripts/run/enemy_art.gd")
var failures := 0
var shell: Control
var view: RunBattle
var heard: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func settle() -> void:
	for i in 3:
		await process_frame


func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await settle()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/asset-qa")
	root.get_texture().get_image().save_png("res://build/asset-qa/" + label + ".png")


func enter(encounter: String, depth: int = 1) -> void:
	shell._start_run("asset-restart")
	shell.run.depth = depth
	shell.run.hp = 77
	shell.run.current_room = {"room_uid": "ASSET_" + encounter, "room_id": "RM_" + encounter.trim_prefix("ENC_"), "content_id": encounter, "room_kind": "NORMAL", "scene_key": "battle", "status": "ENTERED"}
	shell._show_battle()
	view.set_process(false)


func combat_state() -> Dictionary:
	var ctx := view.session.ctx
	var cards: Array = []
	for card in ctx.library.all_cards():
		cards.append(card.to_dict())
	return {"cards": cards, "rng": ctx.rng_of("COMBAT").snapshot(), "hp": ctx.battle.player_hp, "enemy_hp": ctx.battle.enemy_hp, "stolen": ctx.battle.stolen_card_uid}


func _run() -> void:
	root.size = Vector2i(1280, 720)
	shell = load("res://scenes/run/run_shell.tscn").instantiate()
	root.add_child(shell)
	view = shell._battle
	await settle()
	var registry := BattleAssets.animations()
	check(registry.get_animation_names().size() == 15, "All fifteen supplied GIFs are registered")
	for key in registry.get_animation_names():
		check(not registry.get_animation_loop(key), "Animation must play once: " + key)
		var expected := 1.8 if key == "rift" else (1.4 if str(key).ends_with("enter") else 1.0)
		check(is_equal_approx(BattleAssets.clip_seconds(key), expected), "Original frame durations: " + key)
		check(registry.get_frame_texture(key, 0).get_image().get_pixel(0, 0).a == 0.0, "Transparent corners: " + key)
		for frame in registry.get_frame_count(key):
			var bitmap := registry.get_frame_texture(key, frame).get_image()
			var bounds := bitmap.get_used_rect()
			check(bounds.size == Vector2i.ZERO or (bounds.position.x > 0 and bounds.position.y > 0 and bounds.end.x < bitmap.get_width() and bounds.end.y < bitmap.get_height()), "Animation effects fit the shared canvas without edge clipping: %s/%d" % [key, frame])
	for depth in [1, 3, 4, 6, 7, 12]:
		var tier := 1 if depth <= 3 else (2 if depth <= 6 else 3)
		check(BattleAssets.tier(depth) == tier, "Depth tier boundary " + str(depth))
	await _test_restart()
	await _test_presentations()
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture_all()
	shell.free()
	await settle()
	if failures == 0:
		print("PASS: asset registry, alpha, timelines, mechanism forms, death and deterministic battle restart")
	quit(1 if failures else 0)


func _test_restart() -> void:
	for encounter in ["ENC_INK", "ENC_THIEF"]:
		enter(encounter)
		var checkpoint: Dictionary = shell._battle_checkpoint.duplicate(true)
		var run_state: Dictionary = shell.run.capture()
		var initial := combat_state()
		var next_random := view.session.ctx.rng_of("COMBAT").randf()
		for attempt in 3:
			view._process(5.0)
			view.formula.append(str(view.session.ctx.library.pile(CardInstance.HAND)[0]))
			view.selected_uid = view.formula[0]
			var card := view.session.ctx.library.get_card(view.formula[0])
			card.return_used_run = true
			view.session.ctx.library.move(card, CardInstance.REMOVED, "TEST", "test", view.session.ctx)
			view.session.ctx.battle.player_hp = 5
			for stream in RunState.STREAMS:
				shell.run.randi_stream(stream)
			shell._inventory.request_open()
			var menu = shell.get_node("RunMenu")
			menu.open_menu()
			check(menu._restart.visible and paused, "Restart available even with bag open")
			menu._ask_leave("restart")
			check(menu._cancel.has_focus(), "Destructive restart defaults focus to Cancel")
			menu._confirm_leave()
			view.set_process(false)
			check(not paused and not shell._inventory.blocks_input() and not view.session.ctx.battle.paused, "Restart clears menu, bag and battle pause claims")
			check(JSON.stringify(combat_state()) == JSON.stringify(initial), "Restart restores complete combat state, card flags, thief UID and RNG")
			check(JSON.stringify(shell.run.capture()) == JSON.stringify(run_state), "Restart restores all five run streams and run state")
			check(JSON.stringify(shell._battle_checkpoint) == JSON.stringify(checkpoint), "Checkpoint remains immutable across retries")
			check(view.session.ctx.rng_of("COMBAT").randf() == next_random, "Next combat random value repeats exactly")
			check(view.presentation == RunBattle.Presentation.PREPARING and view.formula.is_empty() and view.selected_uid == "", "Restart clears selections and repeats preparation")
			await settle()
		view.session.ctx.battle.declare_victory()
		view._note_phase()
		check(not shell.can_restart_battle(), "Restart disabled from victory onset")
		view._process(2.0)
		var settled: String = JSON.stringify(shell.run.capture())
		view._process(2.0)
		check(JSON.stringify(shell.run.capture()) == settled and shell._battle_checkpoint.is_empty(), "Victory writes back once and discards checkpoint")


func _test_presentations() -> void:
	enter("ENC_INK")
	var art: Control = view._enemy_art
	check(art.form == "MON_INK2" and art.mode == "enter", "Ink opens in division form")
	view._process(0.2)
	check(art.elapsed == 0.2, "Rift begins before monster's 0.4 second offset")
	view.session.ctx.battle.paused = true
	view._process(9.0)
	check(art.elapsed == 0.2, "Battle pause freezes animation timeline")
	view.session.ctx.battle.paused = false
	view.set_external_input_blocked(true)
	view._process(9.0)
	check(art.elapsed == 0.2, "Bag input lock freezes animation timeline")
	view.set_external_input_blocked(false)
	view._process(4.8)
	check(art.mode == "idle" and view.session.ctx.battle.turn_remaining == 10.0, "Entrance finishes during preparation, never consumes turn time")
	for encounter in ["ENC_INK", "ENC_PARITY", "ENC_PRIEST"]:
		enter(encounter)
		var battle := view.session.ctx.battle
		view._process(5.0)
		var first: String = view._enemy_art.form
		if encounter == "ENC_PRIEST":
			battle.priest_heal_cancelled = true
		else:
			battle.turn_index = 2
		view._refresh_hud()
		check(view._enemy_art.form != first and view._enemy_art.mode == "idle", "Mechanics change form without replaying entrance: " + encounter)
		var death_form: String = view._enemy_art.form
		battle.enemy_hp = 0
		battle.declare_victory()
		view._note_phase()
		check(view._enemy_art._death_form == death_form and view._enemy_art.mode == "die", "Death locks the killed form: " + encounter)
		view._process(1.0)
		check(view.presentation == RunBattle.Presentation.VICTORY_PRESENTATION, "Death retains two-second victory window")
		# Replacing the session must cancel the old victory handoff.
		enter("ENC_RUST")
		view._process(2.0)
		check(view.presentation == RunBattle.Presentation.PREPARING, "Old victory cannot report into a replacement battle")
	enter("ENC_INK")
	view.session.ctx.battle.player_hp = 0
	view.session.ctx.battle.phase = "DEFEAT"
	view._note_phase()
	check(view.presentation == RunBattle.Presentation.DEFEAT_PRESENTATION and not shell.can_restart_battle(), "HP death blocks actions and restart")
	view._process(0.9)
	check(view._hero.texture == BattleAssets.texture("battle_human_die"), "First second shows kneeling pose")
	paused = true
	view._process(9.0)
	check(is_equal_approx(view.presentation_remaining, 1.1), "Menu pauses player death")
	paused = false
	view._process(0.2)
	check(view._hero.texture == BattleAssets.texture("battle_human_die2"), "Second second shows lying pose")
	view._process(0.9)
	check(not view.visible and shell.run.phase == "DEAD", "Player defeat hands off after two seconds")
	enter("ENC_INK")
	view.session.ctx.battle.phase = "DECK_EXHAUSTED"
	view._note_phase()
	check(not view.visible and view._hero.texture == RunBattle.HERO_TEX, "Positive HP exhaustion does not fake a death")


func _capture_all() -> void:
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		var suffix := str(resolution.x)
		for depth in [1, 4, 7]:
			enter("ENC_INK", depth)
			shell._set_battle_visible(false)
			await capture("map-tier-" + str(depth) + "-" + suffix)
			shell._set_battle_visible(true)
			view._process(5.0)
			await capture("battle-tier-" + str(depth) + "-" + suffix)
		for encounter in ["ENC_INK", "ENC_PARITY", "ENC_PRIEST", "ENC_RUST", "ENC_THIEF", "ENC_SWORD"]:
			enter(encounter)
			view._process(0.2)
			await capture(encounter + "-rift-" + suffix)
			view._process(0.4)
			await capture(encounter + "-enter-" + suffix)
			view._process(4.4)
			await capture(encounter + "-idle-" + suffix)
			if encounter in ["ENC_INK", "ENC_PARITY", "ENC_PRIEST"]:
				if encounter == "ENC_PRIEST":
					view.session.ctx.battle.priest_heal_cancelled = true
				else:
					view.session.ctx.battle.turn_index = 2
				view._refresh_hud()
				await capture(encounter + "-variant-" + suffix)
			view.session.ctx.battle.declare_victory()
			view._note_phase()
			view._process(0.6)
			await capture(encounter + "-death-" + suffix)
		enter("ENC_INK")
		view._process(5.0)
		var bag := shell.get_node("Inventory") as RunInventory
		bag.request_open()
		for frame in 40:
			await process_frame
		await capture("bag-open-" + suffix)
		bag.request_close()
		for frame in 40:
			await process_frame
		var menu = shell.get_node("RunMenu")
		menu.open_menu()
		await capture("menu-" + suffix)
		menu._ask_leave("restart")
		await capture("restart-confirm-" + suffix)
		menu._show_options()
		menu._ask_leave("quit")
		await capture("exit-confirm-" + suffix)
		menu.close_menu()
		view.session.ctx.battle.player_hp = 0
		view.session.ctx.battle.phase = "DEFEAT"
		view._note_phase()
		await capture("player-kneel-" + suffix)
		view._process(1.1)
		await capture("player-lying-" + suffix)
