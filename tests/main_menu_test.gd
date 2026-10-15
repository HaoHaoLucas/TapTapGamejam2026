extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/menu/main_menu.tscn") as PackedScene
	var menu := scene.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var stage := menu.get_node("Stage") as Control
	var buttons: Array[ArtButton] = [
		menu.get_node("Stage/StartButton") as ArtButton,
		menu.get_node("Stage/NewButton") as ArtButton,
		menu.get_node("Stage/OptionsButton") as ArtButton,
		menu.get_node("Stage/QuitButton") as ArtButton,
	]
	for button in buttons:
		if not _check(button != null, "Menu ArtButton missing"):
			return
		var normal := button.get_node("Normal") as TextureRect
		var hover := button.get_node("Hover") as TextureRect
		if not _check(normal.modulate.a == 1.0, "Normal art should start visible"):
			return
		if not _check(hover.modulate.a == 0.0, "Hover art should start hidden"):
			return
	var start := buttons[0]
	start.set_hovering(true, true)
	var hover_on := start.get_node("Hover") as TextureRect
	var normal_on := start.get_node("Normal") as TextureRect
	if not _check(hover_on.modulate.a == 1.0, "Hover art should show while hovering"):
		return
	if not _check(normal_on.modulate.a == 0.0, "Normal art should hide while hovering"):
		return
	start.set_hovering(false, true)
	if not _check(normal_on.modulate.a == 1.0, "Normal art should return"):
		return
	if not _check(hover_on.modulate.a == 0.0, "Hover art should hide again"):
		return
	if not _check(not start._has_point(Vector2(0, 0)), "Transparent corner must miss"):
		return
	# btn_start_normal.png pixel (721, 328) is opaque parchment. Map it into the control.
	var start_local := Vector2(
		(721.0 + 0.5) / 1454.0 * start.size.x,
		(328.0 + 0.5) / 681.0 * start.size.y
	)
	if not _check(start._has_point(start_local), "Parchment interior must hit"):
		return
	if not _check(stage.scale.x > 0.0 and stage.scale.y > 0.0, "Stage must be fitted before the pointer test"):
		return

	# A real window focuses 开始游戏 in _ready. Headless skips that, so do it here.
	# Focus must not pin the hover art; the pointer has to drive the crossfade.
	start.grab_focus()
	if not _check(start.has_focus(), "开始游戏 should hold keyboard focus"):
		return
	var hits: Array[Vector2] = [start_local]
	for index in range(1, buttons.size()):
		var hit := _opaque_local(buttons[index])
		if hit.x < 0.0:
			return
		hits.append(hit)
	for index in buttons.size():
		var button := buttons[index]
		_move_mouse(_stage_to_view(stage, button.position + hits[index]))
		if not await _wait_art(button, true):
			return
		if not _check(root.gui_get_hovered_control() == button, "%s should receive the pointer" % button.name):
			return
		for other_index in buttons.size():
			if not await _wait_art(buttons[other_index], other_index == index):
				return
	var empty := _stage_to_view(stage, Vector2(160, 200))
	_move_mouse(empty)
	for button in buttons:
		if not await _wait_art(button, false):
			return
	if not _check(start.has_focus(), "Leaving the parchment must not require releasing focus"):
		return
	if not _check(root.gui_get_hovered_control() != start, "Empty stage space must leave 开始游戏"):
		return

	var new_button := buttons[1]
	new_button.pressed.emit()
	var cancel := menu.get_node("Stage/NewGameLayer/CancelButton") as ArtButton
	var confirm := menu.get_node("Stage/NewGameLayer/ConfirmButton") as ArtButton
	if not _check(cancel.has_focus(), "取消 is focused when the new-game layer opens"):
		return
	var cancel_local := _exclusive_local(cancel, confirm)
	if cancel_local.x < 0.0:
		return
	var confirm_local := _exclusive_local(confirm, cancel)
	if confirm_local.x < 0.0:
		return
	_move_mouse(_stage_to_view(stage, cancel.position + cancel_local))
	if not await _wait_art(cancel, true):
		return
	if not await _wait_art(confirm, false):
		return
	if not _check(root.gui_get_hovered_control() == cancel, "取消 parchment should receive the pointer"):
		return
	_move_mouse(_stage_to_view(stage, confirm.position + confirm_local))
	if not await _wait_art(confirm, true):
		return
	if not await _wait_art(cancel, false):
		return
	if not _check(root.gui_get_hovered_control() == confirm, "确认 parchment should receive the pointer"):
		return
	_move_mouse(empty)
	if not await _wait_art(cancel, false):
		return
	if not await _wait_art(confirm, false):
		return
	if not _check(cancel.has_focus(), "取消 keeps focus after the pointer leaves"):
		return

	print("PASS: main menu idle, hover, and alpha mask")
	quit()


func _check(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error(message)
	quit(1)
	return false


func _stage_to_view(stage: Control, stage_point: Vector2) -> Vector2:
	return stage.position + stage.scale * stage_point


func _move_mouse(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	# point is already in viewport space (stage position and scale). Local coords
	# skip the window's screen transform, which is not 1:1 in headless.
	root.push_input(motion, true)


func _wait_art(button: ArtButton, hovering: bool) -> bool:
	var hover := button.get_node("Hover") as TextureRect
	var normal := button.get_node("Normal") as TextureRect
	var hover_alpha := 1.0 if hovering else 0.0
	var normal_alpha := 0.0 if hovering else 1.0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 400:
		if is_equal_approx(hover.modulate.a, hover_alpha) and is_equal_approx(normal.modulate.a, normal_alpha):
			return true
		await process_frame
	return _check(
		false,
		"%s art did not settle (hover %s, normal %s, want hover %s)" % [
			button.name, hover.modulate.a, normal.modulate.a, hovering,
		]
	)


func _opaque_local(button: ArtButton) -> Vector2:
	var point := _first_hit(button, null)
	if not _check(point.x >= 0.0, "%s needs an opaque pixel" % button.name):
		return Vector2(-1, -1)
	return point


func _exclusive_local(button: ArtButton, other: ArtButton) -> Vector2:
	var point := _first_hit(button, other)
	if not _check(point.x >= 0.0, "%s needs an opaque pixel the other button misses" % button.name):
		return Vector2(-1, -1)
	return point


func _first_hit(button: ArtButton, blocked_by: ArtButton) -> Vector2:
	var step := 12.0
	var y := step * 0.5
	while y < button.size.y:
		var x := step * 0.5
		while x < button.size.x:
			var point := Vector2(x, y)
			if button._has_point(point) and (blocked_by == null or not blocked_by._has_point(point)):
				return point
			x += step
		y += step
	return Vector2(-1, -1)
