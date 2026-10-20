extends SceneTree
## Art coverage, live/snapshot parity, sign changes and real screen captures.

var failures := 0
var capture := false
const CARD := preload("res://scenes/cards/card_view.tscn")


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func settle() -> void:
	for i in 8:
		await process_frame


func shot(label: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/card-art-qa")
	check(root.get_texture().get_image().save_png("res://build/card-art-qa/" + label + ".png") == OK, "Save " + label)


func enter(shell, room_id: String) -> void:
	shell._start_run("art-" + room_id)
	var room := GameData.room(room_id)
	shell.run.current_room = {"room_uid": shell.run.uid("R"), "room_id": room_id,
		"content_id": room.get("content_id", ""), "room_kind": room.get("room_kind", ""),
		"display_key": room.get("display_key", ""), "scene_key": room.get("scene_key", ""), "status": "ENTERED"}
	shell.run.phase = "ROOM"


func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
	await settle()


func _run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	check(GameData.ensure_loaded(), "Game tables load")
	check(GameData.rows("card_def").size() == 13, "All thirteen definitions covered")
	check(GameData.rows("enhancement_def").size() == 16, "All sixteen enhancements covered")
	for row in GameData.rows("enhancement_def"):
		var id := str(row.enh_id)
		check(CardArt.MARKS.has(id), "Mapped enhancement " + id)
		check(CardArt.texture("marks/" + str(CardArt.MARKS.get(id, "")) + ".png") != null, "Texture for " + id)
	for tone in ["positive", "negative"]:
		for digit in 10:
			check(CardArt.texture("glyphs/%s_%d.png" % [tone, digit]) != null, "Digit %s %d" % [tone, digit])
	for path in ["faces/positive.png", "faces/negative.png", "faces/zero.png", "faces/neutral.png", "faces/back.png", "faces/room.png", "glyphs/add.png", "glyphs/mul.png", "glyphs/minus.png", "marks/slot_available.png", "marks/slot_occupied.png"]:
		check(CardArt.texture(path) != null, "Texture " + path)
	var catalog := ConfigCatalog.load_default()
	var library := CardLibrary.new(catalog, "art-parity")
	for row in GameData.rows("card_def"):
		var id := str(row.def_id)
		var card := library.create_instance(id, [], 1, "")
		var view: CardView = CARD.instantiate()
		root.add_child(view)
		view.bind(library, card.card_uid)
		var data := CardArt.from_parts(id, [], card.card_uid)
		check(view.face_text() == data.value_text, "Live/offer face parity " + id)
		check(view._art.face.card_kind == data.card_kind, "Structured kind " + id)
		check(view._art.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Artwork never intercepts clicks")
		view.queue_free()
	# The same negative base passes through negative, zero and positive after marks.
	for spec in [["CARD_NM2", [], -2], ["CARD_NM2", ["EN_NUM2"], 0], ["CARD_NM2", ["EN_NUM3"], 1], ["CARD_N5", ["EN_NUM3", "EN_FRAGILE"], 11]]:
		var data := CardArt.from_parts(spec[0], spec[1])
		check(data.printed_value == spec[2], "Actual enhanced value %s" % spec[2])
		var card := library.create_instance(spec[0], spec[1], 1, "")
		var view: CardView = CARD.instantiate()
		root.add_child(view)
		view.bind(library, card.card_uid)
		check(view._art.face.printed_value == spec[2], "Live enhanced value")
		check(view._art.face.enhancement_ids.size() == spec[1].size(), "Both mark slots retained")
		view.bind_face(data)
		data.enhancement_ids.append("EN_GHOST")
		check(view._art.face.enhancement_ids.size() == spec[1].size(), "Snapshot is isolated")
		view.queue_free()
	var ghost := library.create_instance("CARD_N1", ["EN_GHOST", "EN_FROZEN"], 1, "")
	ghost.locked_until_turn = library.turn_index + 1
	var state_view: CardView = CARD.instantiate()
	root.add_child(state_view)
	state_view.bind(library, ghost.card_uid)
	check(state_view.state_text().contains("冻结") and state_view.state_text().contains("幽灵"), "Both state labels retained")
	check(state_view._art.face.frozen, "Frozen overlay metadata")
	check(state_view.tooltip_text.contains("幽灵"), "Rules remain in tooltip")
	state_view.set_highlight("equation")
	check(state_view._style.border_color == Color(0.93, 0.78, 0.42), "Equation highlight")
	state_view.set_highlight("selected")
	check(state_view._style.border_color == Color(0.45, 0.78, 0.86), "Selection highlight")
	state_view.queue_free()
	await settle()
	await gallery()
	var shell = load("res://scenes/run/run_shell.tscn").instantiate()
	root.add_child(shell)
	await settle()
	for resolution in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1440, 900), Vector2i(800, 450)]:
		root.size = resolution
		enter(shell, "RM_RUST")
		shell._show_battle()
		shell._battle._process(shell._battle.PREPARE_SECONDS)
		await settle()
		var hand_view := shell._battle._hand_box.get_child(0) as CardView
		var uid := hand_view.card_uid
		await click(hand_view)
		check(shell._battle.formula.has(uid), "Card artwork allows viewport clicks at %s" % resolution)
		check(shell._battle._eq_box.get_child_count() > 0, "Equation renders card artwork")
		shell._session.ctx.battle.paused = true
		await shot("battle-%dx%d" % [resolution.x, resolution.y])
		shell._inventory.slide_seconds = 0.01
		shell._inventory.request_open()
		await create_timer(0.04).timeout
		await settle()
		await shot("inventory-%dx%d" % [resolution.x, resolution.y])
		shell._inventory.request_close()
		await create_timer(0.04).timeout
		enter(shell, "RM_SAC")
		shell._show()
		await settle()
		await shot("event-%dx%d" % [resolution.x, resolution.y])
		var button: Button = shell._body.find_children("*", "Button", true, false)[0]
		var face := button.get_child(0) as CardView
		check(face != null and face._art.face.presentation == "card", "Event uses structured card")
		check(face.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Choice delegates clicks")
	shell.queue_free()
	await settle()
	print("PASS: card art coverage, value signs, snapshots and states" if failures == 0 else "FAIL: %d card art checks" % failures)
	quit(0 if failures == 0 else 1)


func gallery() -> void:
	root.size = Vector2i(1920, 1080)
	var grid := GridContainer.new()
	grid.columns = 10
	grid.position = Vector2(20, 20)
	root.add_child(grid)
	var faces: Array = []
	for row in GameData.rows("card_def"):
		faces.append(CardArt.from_parts(str(row.def_id), []))
	for spec in [["CARD_NM2", ["EN_NUM2"]], ["CARD_NM2", ["EN_NUM3"]], ["CARD_N5", ["EN_NUM3", "EN_FRAGILE"]]]:
		faces.append(CardArt.from_parts(spec[0], spec[1]))
	for id in CardArt.MARKS:
		faces.append(CardArt.from_parts("CARD_N1", [id]))
	for n in [6, 7, 8, 9, 10, -10]:
		var face := CardArt.from_parts("CARD_N1", [])
		face.printed_value = n
		face.value_text = str(n)
		faces.append(face)
	for face in faces:
		var view: CardView = CARD.instantiate()
		grid.add_child(view)
		view.custom_minimum_size = Vector2(177, 246)
		view.bind_face(face)
	await settle()
	await shot("gallery")
	grid.queue_free()
	await settle()
