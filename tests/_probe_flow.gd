extends SceneTree
## 临时探针：走真实流程（run_shell 开局 → 选战斗房 → 进战斗），看血条与文本是否跟。

var _shell: Control
var _battle: RunBattle


func _initialize() -> void:
	call_deferred("_run")


func _state(tag: String) -> void:
	var session = _shell.get("_session")
	var battle = session.ctx.battle if session != null and session.ctx != null else null
	print("PROBE %-14s session=%s battle=%s" % [
		tag, str(session != null), str(battle != null)])
	if battle == null:
		print("         hp_label='%s' enemy_label='%s' enemy_name='%s'" % [
			_battle._hp_label.text, _battle._enemy_hp_label.text, _battle._enemy_name.text])
		return
	print("         enemy=%s/%s label='%s' bar=%.1f/%.1f" % [
		str(battle.enemy_hp), str(battle.enemy_max_hp), _battle._enemy_hp_label.text,
		_battle._enemy_hp_bar.value, _battle._enemy_hp_bar.max_value])
	print("         player=%s/%s label='%s' bar=%.1f/%.1f" % [
		str(battle.player_hp), str(battle.player_max_hp), _battle._hp_label.text,
		_battle._hp_bar.value, _battle._hp_bar.max_value])


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	_shell = (load("res://scenes/run/run_shell.tscn") as PackedScene).instantiate() as Control
	root.add_child(_shell)
	_battle = _shell.get("_battle") as RunBattle
	for i in 3:
		await process_frame
	_state("after-ready")

	# 找第一个战斗房并进去
	var run = _shell.get("run")
	if run == null:
		push_error("probe: run 建表失败 %s" % str(_shell.get("_status").text))
		quit(1)
		return
	for room_uid in run.offers:
		var room: Dictionary = run.offers[room_uid]
		if str(room.get("room_kind", "")) == "ROOM_NORMAL":
			_shell.call("_enter_room", str(room_uid))
			break
	for i in 30:
		await process_frame
	_state("entered")

	if _shell.get("_session") != null:
		_battle.call("_end_turn")
		for i in 60:
			await process_frame
		_state("after-end-turn")
	quit(0)
