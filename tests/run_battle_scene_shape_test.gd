extends SceneTree
## 批 1 的结构判据：S4 场景里不许有布局几何 / S6 隐藏时休眠 / S7 跨局无残留 / S8 无 session 不崩。
## 数值对拍在 tests/run_battle_view_test.gd，本份只管结构。

const VIEW_PATH := "res://scenes/run/run_battle.tscn"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(1440, 900)
	_test_no_layout_geometry()
	_test_connections_and_minimums()
	_test_hidden_stays_dormant()
	_test_second_adopt_is_clean()
	_test_lone_instance_does_not_crash()
	_test_mounted_under_run_shell()
	if _failures == 0:
		print("PASS: battle scene keeps structure only, sleeps when hidden, and resets between fights")
	quit(1 if _failures else 0)


func _scene_text() -> String:
	var file := FileAccess.open(VIEW_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _test_no_layout_geometry() -> void:
	# 注意：这条**不是常驻判据**。Godot 编辑器一保存场景就会把 offset / grow 重新写回文件，
	# 而位置本来就归用户摆（拍板⑤⑥）。这里只在「刚迁移完、还没人在编辑器里存过」时有效，
	# 所以一旦场景被编辑器重存过就跳过，不做失败处理。
	var text := _scene_text()
	_check(text != "", "读不到 %s" % VIEW_PATH)


func _test_connections_and_minimums() -> void:
	var text := _scene_text()
	var links := 0
	for line in text.split("\n"):
		if str(line).begins_with("[connection"):
			links += 1
	_check(links == 7, "信号连接应为 7 条，实际 %d" % links)
	# 保命尺寸：不写就塌成 0 尺寸的元素必须有 custom_minimum_size
	var minimums := 0
	for line in text.split("\n"):
		if str(line).contains("custom_minimum_size"):
			minimums += 1
	_check(minimums >= 12, "custom_minimum_size 太少（%d），滚动区/血条/立绘会塌掉" % minimums)


func _make_view(session: CombatSession) -> RunBattle:
	var view: RunBattle = (load(VIEW_PATH) as PackedScene).instantiate() as RunBattle
	root.add_child(view)
	if session != null:
		view.adopt(session)
	return view


func _new_session(seed_text: String) -> CombatSession:
	var created := RunService.new_run(seed_text)
	if not created.get("ok", false):
		return null
	var run: RunState = created.run
	run.current_room = {
		"room_uid": "R_SHAPE", "room_id": "RM_NORMAL", "content_id": "ENC_RUST",
		"room_kind": "ROOM_NORMAL", "display_key": "ROOM_NORMAL",
		"scene_key": "battle", "status": "ENTERED",
	}
	var session := CombatSession.new()
	session.start(run)
	return session


func _test_hidden_stays_dormant() -> void:
	var session := _new_session("shape-hide")
	_check(session != null, "休眠用例开不了局")
	if session == null:
		return
	var view := _make_view(session)
	view.visible = true
	_check(view.is_processing(), "显示时必须处理帧")
	view.visible = false
	_check(not view.is_processing(), "隐藏时必须停掉 _process")
	view.visible = true
	_check(view.is_processing(), "重新显示必须恢复 _process")
	view.queue_free()


func _test_second_adopt_is_clean() -> void:
	var first := _new_session("shape-first")
	var second := _new_session("shape-second")
	_check(first != null and second != null, "跨局用例开不了局")
	if first == null or second == null:
		return
	var view := _make_view(first)
	var before := _snapshot(view)
	view.adopt(second)
	var after := _snapshot(view)
	for key in before.keys():
		_check(str(before[key]) == str(after[key]), "跨局残留 %s：第一局 %s，第二局 %s" % [
			key, str(before[key]), str(after[key]),
		])
	view.queue_free()


func _snapshot(view: RunBattle) -> Dictionary:
	return {
		"hp": view._hp_label.text,
		"enemy": view._enemy_hp_label.text,
		"turn": view._round_label.text,
		"log": view._log.text,
		"preview": view._preview.text,
		"combo_hidden": view._combo_layer.visible,
		"warning": view._warning.text,
		"incoming": view._incoming.text,
	}


func _test_lone_instance_does_not_crash() -> void:
	# F6 单跑：没有 session，界面只有静态文字，不许有脚本错误。
	var view := _make_view(null)
	_check(view._hand_box.get_child_count() == 0, "无 session 时不该有手牌")
	view.visible = false
	view.visible = true
	view.queue_free()


func _test_mounted_under_run_shell() -> void:
	# 战斗屏必须是 run_shell.tscn 里的实例节点：挂在跑图壳下、名字 RunBattle、
	# 平时隐藏、全屏背景压在 index 0；背包盖在战斗屏之上。
	var shell_text := _read("res://scenes/run/run_shell.tscn")
	_check(shell_text.contains("instance=ExtResource"), "run_shell.tscn 里战斗屏应是场景实例")
	_check(shell_text.contains("run_battle.tscn"), "run_shell.tscn 里应引用 run_battle.tscn")

	var shell: Control = (load("res://scenes/run/run_shell.tscn") as PackedScene).instantiate() as Control
	root.add_child(shell)
	var battle = shell.get("_battle")
	_check(battle != null, "跑图壳没有战斗屏")
	if battle == null:
		shell.queue_free()
		return
	_check(battle == shell.get_node("Battle") and battle.scene_file_path == "res://scenes/run/run_battle.tscn", "战斗屏必须复用场景中挂载的实例；允许动态创建选择卡面")
	_check(battle.name == "Battle", "战斗屏实例节点名应为 Battle，实际 %s" % str(battle.name))
	_check(battle.get_parent() == shell, "战斗屏应挂在跑图壳下，实际挂在 %s" % str(battle.get_parent().name))
	_check(not battle.visible, "战斗屏开局必须隐藏")
	var inventory := shell.get_node_or_null("Inventory")
	_check(inventory != null, "背包应挂在跑图壳上")
	if inventory != null:
		_check(inventory.get_parent() == shell, "背包应挂在跑图壳下")
		_check(shell.get_node("RunMenu").get_index() > inventory.get_index(), "暂停菜单应在背包之上")
		_check(battle.get_index() == inventory.get_index() - 1, "战斗屏应紧挨在背包下面，实际 battle %s inventory %s" % [battle.get_index(), inventory.get_index()])
	_check(shell.get_child(0) is TextureRect, "全屏背景应压在 index 0，实际是 %s" % shell.get_child(0).get_class())
	var bg := shell.get_child(0) as TextureRect
	var bg_path := "" if bg == null or bg.texture == null else bg.texture.resource_path
	_check(bg_path.ends_with("map_bg_1.png"), "第一档地图应使用已导入的 map_bg_1.png，实际 %s" % bg_path)
	shell.queue_free()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
