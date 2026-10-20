extends SceneTree
## 场景化后的对拍判据：把 run_battle.tscn 重新跑一遍固定序列，与迁移前的 gold 逐项比。
## 采集实现刻意与 tests/run_battle_view_dump.gd **各写一份**（不同源），避免镜像实现自己验自己。

const VIEW_PATH := "res://scenes/run/run_battle.tscn"
const GOLD_PATH := "res://tests/gold/run_battle_view_gold.json"
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

var _failures: int = 0
var _skip: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(1440, 900)
	var gold := _load_gold()
	if gold.is_empty():
		_failures += 1
		push_error("读不到 gold：%s" % GOLD_PATH)
		quit(1)
		return

	var created := RunService.new_run(FIXED_SEED)
	_check(created.get("ok", false), "固定 seed 开不了局")
	if not created.get("ok", false):
		quit(1)
		return
	var run: RunState = created.run
	run.current_room = FIXED_ROOM.duplicate(true)
	var session := CombatSession.new()
	session.start(run)
	var packed := load(VIEW_PATH) as PackedScene
	_check(packed != null, "载入失败 %s" % VIEW_PATH)
	if packed == null:
		quit(1)
		return
	var view: RunBattle = packed.instantiate() as RunBattle
	_check(view != null, "根不是 RunBattle")
	if view == null:
		quit(1)
		return
	root.add_child(view)
	_skip = [view._eq_box, view._hand_box]

	var shots := {}
	view.adopt(session)
	shots["a_adopt"] = _capture(view, true)
	_build_formula(view, session)
	shots["b_formula"] = _capture(view)
	view._commit()
	shots["c_commit"] = _capture(view)
	_burn_one(view, session)
	shots["d_burn"] = _capture(view)
	view._end_turn()
	shots["e_end_turn"] = _capture(view)

	var expected: Dictionary = gold.get("checkpoints", {})
	_check(expected.size() == shots.size(), "检查点数量不符：gold %d / 实际 %d" % [expected.size(), shots.size()])
	for key in expected.keys():
		var name := str(key)
		if not shots.has(name):
			_check(false, "少了检查点 %s" % name)
			continue
		_compare_readouts(name, expected[name].get("readouts", {}), shots[name].readouts)
		_compare_cards(name, expected[name].get("cards", {}), shots[name].cards)
		if expected[name].has("tree"):
			_compare_tree(expected[name], shots[name])
		if expected[name].has("links"):
			_compare_links(expected[name], shots[name])

	view.queue_free()
	if _failures == 0:
		print("PASS: battle view keeps every readout, node and link of the pre-migration screen")
	quit(1 if _failures else 0)


func _load_gold() -> Dictionary:
	if not FileAccess.file_exists(GOLD_PATH):
		return {}
	var file := FileAccess.open(GOLD_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


# --- 对拍 -------------------------------------------------------------------


func _compare_readouts(name: String, expected: Dictionary, actual: Dictionary) -> void:
	for key in expected.keys():
		var label := str(key)
		_check(actual.has(label), "%s/%s 缺少读数" % [name, label])
		if not actual.has(label):
			continue
		_check(_same(expected[key], actual[label]), "%s/%s 期望 %s，实际 %s" % [
			name, label, str(expected[key]), str(actual[label]),
		])


func _compare_cards(name: String, expected: Dictionary, actual: Dictionary) -> void:
	for slot in expected.keys():
		var wanted: Array = expected[slot]
		var got: Array = actual.get(str(slot), [])
		_check(wanted.size() == got.size(), "%s/%s 卡片数 期望 %d，实际 %d" % [name, slot, wanted.size(), got.size()])
		var limit := mini(wanted.size(), got.size())
		for index in limit:
			_check(_same(wanted[index], got[index]), "%s/%s 第 %d 张不符：期望 %s，实际 %s" % [
				name, slot, index, str(wanted[index]), str(got[index]),
			])


func _compare_tree(expected: Dictionary, actual: Dictionary) -> void:
	var want: Array = expected.get("tree", [])
	var got: Array = actual.get("tree", [])
	_check(want.size() == got.size(), "静态节点数 期望 %d，实际 %d" % [want.size(), got.size()])
	var limit := mini(want.size(), got.size())
	var reported := 0
	for index in limit:
		if _same(want[index], got[index]):
			continue
		if reported < 12:
			push_error("第 %d 个节点不符\n  gold: %s\n  实际: %s" % [index, str(want[index]), str(got[index])])
			reported += 1
		_failures += 1


func _compare_links(expected: Dictionary, actual: Dictionary) -> void:
	var want: Dictionary = expected.get("links", {})
	var got: Dictionary = actual.get("links", {})
	_check(int(want.get("count", -1)) == int(got.get("count", -2)), "连接数 期望 %s，实际 %s" % [
		str(want.get("count")), str(got.get("count")),
	])
	var want_unique: Array = want.get("unique", [])
	var got_unique: Array = got.get("unique", [])
	for entry in want_unique:
		_check(got_unique.has(entry), "少了连接：%s" % str(entry))
	for entry in got_unique:
		_check(want_unique.has(entry), "多了连接：%s" % str(entry))


func _same(a: Variant, b: Variant) -> bool:
	# gold 走过 JSON，整数会变成浮点，必须按数值比，不能按字符串比。
	# 52.8 这种十进制不是二进制精确值，float32 → JSON → float64 回读会差 1 ULP。
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	if a is Array:
		if not (b is Array) or (a as Array).size() != (b as Array).size():
			return false
		for index in (a as Array).size():
			if not _same(a[index], b[index]):
				return false
		return true
	if a is Dictionary:
		if not (b is Dictionary) or (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for key in (a as Dictionary).keys():
			if not (b as Dictionary).has(key):
				return false
			if not _same(a[key], b[key]):
				return false
		return true
	return str(a) == str(b)


# --- 固定操作序列 -----------------------------------------------------------


func _build_formula(view: RunBattle, session: CombatSession) -> void:
	var numbers: Array = []
	var operators: Array = []
	for uid in session.ctx.library.pile(CardInstance.HAND):
		var card := session.ctx.library.get_card(str(uid))
		if card == null:
			continue
		if str(session.ctx.catalog.card(card.def_id).get("card_kind", "")) == "NUM":
			numbers.append(str(uid))
		else:
			operators.append(str(uid))
	if numbers.size() < 2 or operators.is_empty():
		_check(false, "手牌组不出算式")
		return
	view._on_card_pressed(numbers[0])
	view._on_card_pressed(operators[0])
	view._on_card_pressed(numbers[1])


func _burn_one(view: RunBattle, session: CombatSession) -> void:
	for uid in session.ctx.library.pile(CardInstance.HAND):
		view._on_card_pressed(str(uid))
		if view.selected_uid != "":
			view._burn()
			return


# --- 采集（独立于 dump） ----------------------------------------------------


func _capture(view: RunBattle, full: bool = false) -> Dictionary:
	var shot := {"readouts": _readouts(view), "cards": _cards(view)}
	if full:
		shot["tree"] = _dump_tree(view)
		shot["links"] = _collect_links(view)
	return shot


func _readouts(view: RunBattle) -> Dictionary:
	return {
		"_hp_label": view._hp_label.text,
		"_hp_bar": _ratio(view._hp_bar),
		"_floor_label": view._floor_label.text,
		"_intent_label": view._intent_label.text,
		"_enemy_name": view._enemy_name.text,
		"_enemy_hp_bar": _ratio(view._enemy_hp_bar),
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


func _ratio(bar: TextureProgressBar) -> float:
	if bar == null:
		return -1.0
	return roundf(bar.value / maxf(bar.max_value, 1.0) * 10000.0) / 10000.0


func _color(value: Color) -> Array:
	return [
		roundf(value.r * 1000.0) / 1000.0,
		roundf(value.g * 1000.0) / 1000.0,
		roundf(value.b * 1000.0) / 1000.0,
		roundf(value.a * 1000.0) / 1000.0,
	]
