extends SceneTree
## 一次性 gold 生成器：把「迁移前」的战斗屏拍成基线快照。
## 不是判据 —— 它只产出 gold，比较由 run_battle_view_test 做。
## 跑法：godot --headless --path . --script tests/run_battle_view_dump.gd
##
## 设计要点（见 docs/战斗屏场景化方案.md §7）：
##  - 读数的键用**脚本变量名**（跨迁移稳定），静态文案靠 DFS 序号对齐；
##  - StyleBox 读**生效值**（get_theme_stylebox），因为主题外提后 override 会空；
##  - 几何键一律不进 gold；
##  - 动态卡片容器 `_eq_box` / `_hand_box` 只记子节点数，卡面另开一节记录。

const VIEW_PATH := "res://scenes/run/run_battle.tscn"
const GOLD_PATH := "res://tests/gold/run_battle_view_gold.json"
const GOLD_DIR := "res://tests/gold"
const FIXED_SEED := "gold-battle-view-2026-10-17"
const FIXED_ROOM := {
	"room_uid": "R_GOLD",
	"room_id": "RM_NORMAL",
	"content_id": "ENC_RUST",
	"room_kind": "ROOM_NORMAL",
	"display_key": "ROOM_NORMAL",
	"scene_key": "battle",
	"status": "ENTERED",
}

var _skip: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var created := RunService.new_run(FIXED_SEED)
	if not created.get("ok", false):
		_fail("开局失败：%s" % str(created.get("error", "")))
		return
	var run: RunState = created.run
	run.current_room = FIXED_ROOM.duplicate(true)
	var session := CombatSession.new()
	session.start(run)
	if session.ctx == null or session.ctx.battle == null:
		_fail("CombatSession 没有开出战斗")
		return
	if str(session.monster_id) == "":
		_fail("固定房间没有挂上怪物（content_id=%s）" % str(FIXED_ROOM.content_id))
		return
	var packed := load(VIEW_PATH) as PackedScene
	if packed == null:
		_fail("载入失败：%s" % VIEW_PATH)
		return
	var view: RunBattle = packed.instantiate() as RunBattle
	if view == null:
		_fail("%s 的根不是 RunBattle" % VIEW_PATH)
		return
	root.add_child(view)
	_skip = [view._eq_box, view._hand_box]

	var shots := {}
	view.adopt(session)
	shots["a_adopt"] = _capture(view, true)
	if not _build_formula(view, session):
		_fail("组不出一条合法算式（手牌没有 ≥2 数字 + ≥1 符号）")
		return
	shots["b_formula"] = _capture(view)
	view._commit()
	shots["c_commit"] = _capture(view)
	_burn_one(view, session)
	shots["d_burn"] = _capture(view)
	view._end_turn()
	shots["e_end_turn"] = _capture(view)

	var gold := {
		"view": VIEW_PATH,
		"checkpoints": shots,
	}
	DirAccess.make_dir_recursive_absolute(GOLD_DIR)
	var file := FileAccess.open(GOLD_PATH, FileAccess.WRITE)
	if file == null:
		_fail("写不了 %s（错误 %d）" % [GOLD_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(gold, "\t"))
	file.close()
	print("GOLD: %s" % GOLD_PATH)
	print("GOLD: 检查点 %d 个 / 静态节点 %d 个 / 连接 %d 条（去重 %d）" % [
		shots.size(),
		int(shots["a_adopt"].tree.size()),
		int(shots["a_adopt"].links.count),
		(shots["a_adopt"].links.unique as Array).size(),
	])
	quit(0)


func _fail(message: String) -> void:
	push_error("gold dump: %s" % message)
	quit(1)


# --- 固定操作序列 -----------------------------------------------------------


func _build_formula(view: RunBattle, session: CombatSession) -> bool:
	var numbers: Array = []
	var operators: Array = []
	for uid in session.ctx.library.pile(CardInstance.HAND):
		var card := session.ctx.library.get_card(str(uid))
		if card == null:
			continue
		var kind := str(session.ctx.catalog.card(card.def_id).get("card_kind", ""))
		if kind == "NUM":
			numbers.append(str(uid))
		else:
			operators.append(str(uid))
	if numbers.size() < 2 or operators.is_empty():
		return false
	view._on_card_pressed(numbers[0])
	view._on_card_pressed(operators[0])
	view._on_card_pressed(numbers[1])
	return not view.formula.is_empty()


func _burn_one(view: RunBattle, session: CombatSession) -> void:
	for uid in session.ctx.library.pile(CardInstance.HAND):
		view._on_card_pressed(str(uid))
		if view.selected_uid != "":
			view._burn()
			return


# --- 快照 -------------------------------------------------------------------


func _capture(view: RunBattle, full: bool = false) -> Dictionary:
	var shot := {"readouts": _readouts(view), "cards": _cards(view)}
	if full:
		shot["tree"] = _dump_tree(view)
		shot["links"] = _collect_links(view)
	return shot


func _readouts(view: RunBattle) -> Dictionary:
	return {
		"_hp_label": view._hp_label.text,
		"_hp_fill": _ratio(view._hp_fill),
		"_floor_label": view._floor_label.text,
		"_pause_button": view._pause_button.text,
		"_intent_label": view._intent_label.text,
		"_enemy_name": view._enemy_name.text,
		"_enemy_hp_fill": _ratio(view._enemy_hp_fill),
		"_enemy_hp_label": view._enemy_hp_label.text,
		"_round_label": view._round_label.text,
		"_timer_label": view._timer_label.text,
		"_timer_extra": view._timer_extra.text,
		"_log": view._log.text,
		"_warning": view._warning.text,
		"_preview": view._preview.text,
		"_eq_result": view._eq_result.text,
		"_combo_dot_a": _color(view._combo_dot_a.modulate),
		"_combo_dot_b": _color(view._combo_dot_b.modulate),
		"_combo_status": view._combo_status.text,
		"_incoming": view._incoming.text,
		"_hand_caption": view._hand_caption.text,
		"_draw_label": view._draw_label.text,
		"_discard_label": view._discard_label.text,
		"_combo_layer": view._combo_layer.visible,
		"_combo_label": view._combo_label.text,
		"_board": view._board != null,
		"_eq_box": _live_children(view._eq_box),
		"_hand_box": _live_children(view._hand_box),
	}


func _live_children(node: Node) -> int:
	var live := 0
	for child in node.get_children():
		if not child.is_queued_for_deletion():
			live += 1
	return live


func _dump_tree(view: RunBattle) -> Array:
	var out: Array = []
	_walk(view, out, 0)
	return out


func _walk(node: Node, out: Array, depth: int) -> void:
	out.append(_describe(node, depth))
	if _skip.has(node):
		return
	for child in node.get_children():
		_walk(child, out, depth + 1)


func _describe(node: Node, depth: int) -> Dictionary:
	var d := {"d": depth, "c": node.get_class()}
	if node is Control:
		var c := node as Control
		if c.mouse_filter != Control.MOUSE_FILTER_STOP:
			d["mf"] = c.mouse_filter
		if c.size_flags_horizontal != Control.SIZE_FILL:
			d["sfh"] = c.size_flags_horizontal
		if c.size_flags_vertical != Control.SIZE_FILL:
			d["sfv"] = c.size_flags_vertical
		if c.custom_minimum_size != Vector2.ZERO:
			d["min"] = [c.custom_minimum_size.x, c.custom_minimum_size.y]
		if not c.visible:
			d["vis"] = false
		if c.modulate != Color(1, 1, 1, 1):
			d["mod"] = _color(c.modulate)
		if c.focus_mode != Control.FOCUS_NONE:
			d["fo"] = c.focus_mode
	if node is Label:
		var l := node as Label
		d["t"] = l.text
		d["fs"] = l.get_theme_font_size("font_size")
		d["fc"] = _color(l.get_theme_color("font_color"))
		d["ha"] = l.horizontal_alignment
		d["va"] = l.vertical_alignment
		d["aw"] = l.autowrap_mode
	if node is Button:
		var b := node as Button
		d["t"] = b.text
		d["sb"] = _digest(_button_boxes(b))
	if node is TextureRect:
		var t := node as TextureRect
		d["tex"] = "" if t.texture == null else t.texture.resource_path
		d["em"] = t.expand_mode
		d["sm"] = t.stretch_mode
	if node is ColorRect:
		d["col"] = _color((node as ColorRect).color)
	if node is Panel:
		d["sb"] = _digest(_panel_box((node as Panel).get_theme_stylebox("panel")))
	if node is PanelContainer:
		d["sb"] = _digest(_panel_box((node as PanelContainer).get_theme_stylebox("panel")))
	d["kids"] = node.get_child_count()
	return d


func _digest(value: Variant) -> int:
	return str(value).hash()


func _button_boxes(button: Control) -> Dictionary:
	var out := {}
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		out[state] = _panel_box(button.get_theme_stylebox(state, "Button"))
	return out


func _panel_box(box: StyleBox) -> Dictionary:
	if box == null:
		return {}
	if box is StyleBoxEmpty:
		return {"empty": true}
	if not (box is StyleBoxFlat):
		return {"kind": box.get_class()}
	var flat := box as StyleBoxFlat
	return {
		"bg": _color(flat.bg_color),
		"bc": _color(flat.border_color),
		"bw": [flat.border_width_left, flat.border_width_top, flat.border_width_right, flat.border_width_bottom],
		"cr": [
			flat.corner_radius_top_left, flat.corner_radius_top_right,
			flat.corner_radius_bottom_right, flat.corner_radius_bottom_left,
		],
		"cm": [
			flat.content_margin_left, flat.content_margin_top,
			flat.content_margin_right, flat.content_margin_bottom,
		],
	}


func _cards(view: RunBattle) -> Dictionary:
	return {
		"equation": _card_faces(view._eq_box),
		"hand": _card_faces(view._hand_box),
	}


func _card_faces(box: Node) -> Array:
	var out: Array = []
	if box == null:
		return out
	for child in box.get_children():
		if child.is_queued_for_deletion():
			continue
		var row := {"c": child.get_class()}
		if child.has_method("face_text"):
			row["face"] = child.call("face_text")
			row["mark"] = child.call("mark_text")
			row["state"] = child.call("state_text")
		out.append(row)
	return out


func _collect_links(view: RunBattle) -> Dictionary:
	var raw: Array = []
	_collect_links_of(view, raw)
	raw.sort()
	var unique: Array = []
	for entry in raw:
		if unique.is_empty() or str(unique[unique.size() - 1]) != str(entry):
			unique.append(entry)
	return {"count": raw.size(), "unique": unique}


func _collect_links_of(node: Node, out: Array) -> void:
	if _skip.has(node):
		return
	for sig in node.get_signal_list():
		var signal_name := str(sig.get("name", ""))
		for conn in node.get_signal_connection_list(signal_name):
			var callable: Callable = conn.get("callable", Callable())
			var method := callable.get_method()
			if method.contains("::"):
				continue
			out.append("%s.%s -> %s" % [node.get_class(), signal_name, method])
	for child in node.get_children():
		_collect_links_of(child, out)


# --- 归一化 -----------------------------------------------------------------


func _ratio(fill: ColorRect) -> float:
	if fill == null:
		return -1.0
	return roundf(fill.anchor_right * 10000.0) / 10000.0


func _color(value: Color) -> Array:
	return [
		roundf(value.r * 1000.0) / 1000.0,
		roundf(value.g * 1000.0) / 1000.0,
		roundf(value.b * 1000.0) / 1000.0,
		roundf(value.a * 1000.0) / 1000.0,
	]
