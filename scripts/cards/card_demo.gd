extends Control
class_name BattleDemo
## 1440×900 timed-arithmetic battle UI driven by CombatEngine (HTML v0.3).

const DESIGN := Vector2(1440, 900)
const ZOOM_MIN := 0.7
const ZOOM_MAX := 2.0
const HERO_TEX := preload("res://assets/battle/hero.png")
const ENEMY_TEX := preload("res://assets/battle/enemy.png")
const RECORD_PATH := "user://emergence_v03.cfg"
const ELEM_META := {
	"fire": {"name": "火", "label": "余烬", "color": Color(0.965, 0.651, 0.427)},
	"ice": {"name": "冰", "label": "霜晶", "color": Color(0.522, 0.847, 0.902)},
	"spark": {"name": "雷", "label": "电荷", "color": Color(0.769, 0.631, 0.98)},
}
const FX_COLORS := {
	"gold": Color(0.894, 0.765, 0.51),
	"fire": Color(0.945, 0.639, 0.424),
	"ice": Color(0.655, 0.91, 0.894),
	"spark": Color(0.773, 0.627, 0.933),
	"steam": Color(0.875, 0.839, 0.675),
	"splash": Color(0.933, 0.702, 0.518),
	"burst": Color(0.918, 0.816, 0.608),
	"heal": Color(0.725, 0.839, 0.663),
	"hurt": Color(0.945, 0.631, 0.545),
}

var engine: CombatEngine
var auto_advance: bool = true
var sound_on: bool = true
var record_path: String = RECORD_PATH
var user_modal: String = ""
var pile_kind: String = "all"

var game: Control
var overlay: ColorRect
var overlay_host: CenterContainer
var toast_label: Label
var banner: VBoxContainer
var banner_title: Label
var banner_sub: Label
var formula_reveal: VBoxContainer
var formula_reveal_main: Label
var formula_reveal_sub: Label
var fx_layer: Control
var burst_panel: PanelContainer
var burst_hit_button: Button
var burst_hits_label: Label
var burst_time_label: Label
var burst_fill: ColorRect
var start_button: Button
var fire_button: Button
var burn_button: Button
var end_turn_button: Button
var clear_button: Button
var preview_checkbox: CheckBox
var hand_buttons: Array[Button] = []
var hp_label: Label
var hp_fill: ColorRect
var deck_label: Label
var sound_button: Button
var location_label: Label
var route_label: Label
var round_label: Label
var race_time_label: Label
var race_decision_label: Label
var race_equations_label: Label
var race_rank_label: Label
var deadline_fill: ColorRect
var intent_label: Label
var enemy_name_label: Label
var enemy_hp_fill: ColorRect
var enemy_hp_label: Label
var enemy_status: HBoxContainer
var enemy_root: Control
var hero_root: Control
var timer_ring: TimerRing
var timer_label: Label
var timer_caption: Label
var timer_extra: Label
var timer_block: Control
var burn_count_label: Label
var eq_slot_a: PanelContainer
var eq_slot_op: PanelContainer
var eq_slot_b: PanelContainer
var eq_result: Label
var eq_result_hint: Label
var dmg_preview: Label
var dmg_preview_hint: Label
var eq_head: Label
var eq_reaction: Label
var combo_status: Label
var combo_dot_a: Panel
var combo_dot_b: Panel
var incoming_label: Label
var hand_mode_label: Label
var hand_rules_label: Label
var draw_pile_label: Label
var discard_pile_label: Label
var feed_lines: VBoxContainer
var overlay_title: Label
var local_record_label: Label
var zoom_label: Label
var ui_zoom: float = 1.0

var _preview_pref: bool = false
var _record_handled: bool = false
var _modal_signature: String = ""
var _banner_gen: int = 0
var _toast_gen: int = 0
var _reveal_gen: int = 0
var _hero_origin: Vector2 = Vector2.ZERO
var _enemy_origin: Vector2 = Vector2.ZERO
var _ui_theme: Theme
var _serif: SystemFont
var _sans: SystemFont


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_theme()
	theme = _ui_theme
	_build_ui()
	engine = CombatEngine.new({
		"seed": CombatEngine.DEFAULT_SEED,
		"on_change": _on_engine_change,
		"on_effect": _on_engine_effect,
		"on_tick": _on_engine_tick,
	})
	resized.connect(_fit_scale)
	_configure_window()
	_fit_scale()
	_refresh()


func _process(delta: float) -> void:
	if auto_advance and engine != null:
		engine.advance(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_scale()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if auto_advance and DisplayServer.get_name() != "headless" and engine != null:
			if user_modal == "" and engine.s.phase in ["player", "burst", "enemy"]:
				open_modal("pause")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.ctrl_pressed or event.meta_pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				adjust_zoom(0.1)
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				adjust_zoom(-0.1)
				get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.ctrl_pressed or event.meta_pressed:
		if event.keycode in [KEY_EQUAL, KEY_KP_ADD, KEY_PLUS]:
			adjust_zoom(0.1)
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			adjust_zoom(-0.1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_0 or event.keycode == KEY_KP_0:
			ui_zoom = 1.0
			_apply_zoom()
			get_viewport().set_input_as_handled()
		return
	if event.alt_pressed:
		return
	if _handle_key(event.keycode, event.unicode):
		get_viewport().set_input_as_handled()


func _fit_scale() -> void:
	if game == null:
		return
	var s: float = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	s = maxf(s, 0.01)
	game.scale = Vector2(s, s)
	game.size = DESIGN
	game.position = (size - DESIGN * s) * 0.5


func _configure_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	win.min_size = Vector2i(960, 600)
	win.content_scale_size = Vector2i(int(DESIGN.x), int(DESIGN.y))
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_apply_zoom()
	if win.size.x < 1280 or win.size.y < 720:
		win.size = Vector2i(1440, 900)


func adjust_zoom(delta: float) -> void:
	ui_zoom = clampf(ui_zoom + delta, ZOOM_MIN, ZOOM_MAX)
	_apply_zoom()


func _apply_zoom() -> void:
	ui_zoom = clampf(ui_zoom, ZOOM_MIN, ZOOM_MAX)
	if DisplayServer.get_name() != "headless":
		get_window().content_scale_factor = ui_zoom
	if zoom_label != null:
		zoom_label.text = "显示 %d%%　Ctrl + 滚轮 / Ctrl ± 缩放" % int(round(ui_zoom * 100.0))


func start_challenge(p_seed: Variant = null) -> void:
	user_modal = ""
	_modal_signature = ""
	_record_handled = false
	_clear_fx()
	hide_toast()
	engine.start(p_seed)
	if _preview_pref:
		engine.set_preview(true)
	_beep("start")


func act(action: String, extra: String = "") -> bool:
	match action:
		"start":
			start_challenge()
			return true
		"new-seed":
			start_challenge(_random_seed())
			return true
		"card":
			return engine.choose_card(extra)
		"fire":
			return engine.fire()
		"clear":
			return engine.clear()
		"burn":
			return engine.toggle_burn()
		"endturn":
			return engine.end_turn()
		"burst":
			return engine.burst_hit()
		"help":
			open_modal("help")
			return true
		"pause":
			open_modal("pause")
			return true
		"close":
			close_modal()
			return true
		"pile":
			pile_kind = extra if extra != "" else "all"
			open_modal("pile")
			return true
		"log":
			open_modal("log")
			return true
		"restart-confirm":
			user_modal = "restart"
			_modal_signature = ""
			call_deferred("_refresh_modal")
			return true
		"export":
			_export_log()
			return true
		"sound":
			sound_on = not sound_on
			if sound_on:
				_beep("select")
			_refresh_top()
			return true
		"fullscreen":
			_toggle_fullscreen()
			return true
	return false


func handle_key(key: Key) -> bool:
	return _handle_key(key, 0)


func open_modal(name: String) -> void:
	if engine == null:
		return
	if engine.s.phase not in ["intro", "player", "burst", "enemy", "victory", "defeat"]:
		return
	user_modal = name
	_modal_signature = ""
	engine.set_paused(true)


func close_modal() -> void:
	user_modal = ""
	_modal_signature = ""
	engine.set_paused(false)


func load_best() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(record_path) != OK:
		return {}
	var section := str(engine.seed)
	if not cfg.has_section(section):
		return {}
	return {
		"score": int(cfg.get_value(section, "score", 0)),
		"time": float(cfg.get_value(section, "time", 0.0)),
		"round": int(cfg.get_value(section, "round", 0)),
	}


func current_overlay() -> String:
	if user_modal != "":
		return user_modal
	if engine != null and engine.s.phase in ["intro", "victory", "defeat"]:
		return str(engine.s.phase)
	return ""


func click_hand(index: int) -> void:
	if index < 0 or index >= engine.s.hand.size():
		return
	var card = engine.s.hand[index]
	if card != null:
		act("card", card.id)


func _handle_key(key: Key, unicode: int) -> bool:
	var ch := String.chr(unicode) if unicode > 0 else ""
	var overlay_key := current_overlay()
	if overlay_key != "":
		if user_modal != "" and (key == KEY_ESCAPE or (key == KEY_P and user_modal == "pause")):
			close_modal()
			return true
		return false
	if key == KEY_P:
		open_modal("pause")
		return true
	if key == KEY_H:
		open_modal("help")
		return true
	if engine.s.phase == "burst":
		if key == KEY_SPACE or key == KEY_ENTER or key == KEY_KP_ENTER:
			engine.burst_hit()
			return true
		return false
	if not engine.active():
		return false
	if key >= KEY_1 and key <= KEY_5:
		click_hand(key - KEY_1)
	elif key >= KEY_KP_1 and key <= KEY_KP_5:
		click_hand(key - KEY_KP_1)
	elif key == KEY_A or key == KEY_PLUS or key == KEY_KP_ADD or ch == "+":
		engine.choose_operator("+")
	elif key == KEY_X or key == KEY_ASTERISK or key == KEY_KP_MULTIPLY or ch == "*" or ch == "×":
		engine.choose_operator("×")
	elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
		engine.fire()
	elif key == KEY_B:
		engine.toggle_burn()
	elif key == KEY_E:
		engine.end_turn()
	elif key == KEY_ESCAPE:
		engine.clear()
	else:
		return false
	return true


func _on_engine_change(_state: Dictionary) -> void:
	_refresh()


func _on_engine_tick(_state: Dictionary) -> void:
	_refresh_timer()
	if race_time_label != null:
		race_time_label.text = "%.1fs" % float(engine.s.stats.time)
	if burst_panel.visible:
		burst_time_label.text = "%.1f 秒" % float(engine.s.burstRemaining)
		var dur: float = maxf(float(engine.s.burstDuration), 0.001)
		_set_fill(burst_fill, float(engine.s.burstRemaining) / dur)


func _on_engine_effect(effect: Dictionary) -> void:
	var kind: String = str(effect.get("type", ""))
	match kind:
		"select":
			_beep("select")
		"message":
			show_toast(str(effect.get("text", "")))
		"damage":
			var amount: int = int(effect.get("amount", 0))
			var dmg_kind: String = str(effect.get("kind", "gold"))
			_float_text(_enemy_float_pos() + Vector2(0, -36), _signed_amount(amount, dmg_kind), _fx_color(dmg_kind))
			_nudge(enemy_root, _enemy_origin, "hit")
		"shot":
			var shot_kind: String = str(effect.get("color", "gold"))
			_float_text(_enemy_float_pos() + Vector2(0, -92), str(effect.get("name", "")), _fx_color(shot_kind), 18)
			_show_formula(str(effect.get("formula", "")), "%s 伤害 · %s" % [effect.get("amount", 0), effect.get("name", "")])
			_nudge(hero_root, _hero_origin, "shoot")
			_beep("shot" if str(effect.get("op", "")) == "+" else "magic")
		"window":
			_float_text(Vector2(1132, 550), "+1 追击窗口", FX_COLORS.gold, 16)
			_beep("window")
		"punch":
			_nudge(hero_root, _hero_origin, "shoot")
			_beep("punch")
		"heal":
			var heal: int = int(effect.get("amount", 0))
			_float_text(Vector2(286, 368), "+%d" % heal, FX_COLORS.heal)
			_beep("heal")
			var card: BattleCard = effect.get("card") as BattleCard
			if card != null:
				var elem_name: String = str(ELEM_META.get(card.elem, {}).get("name", ""))
				show_toast("烧掉 %s %s，回复 %s 生命。本回合不补牌。" % [elem_name, card.value, heal], 1.9)
		"enemyAttack":
			_nudge(enemy_root, _enemy_origin, "attack")
			_nudge(hero_root, _hero_origin, "hurt")
			_float_text(Vector2(281, 357), "−%d" % int(effect.get("amount", 0)), FX_COLORS.hurt)
			_beep("hurt")
		"phase":
			_show_banner(str(effect.get("text", "")), str(effect.get("sub", "")))
		"outcome":
			_beep("victory" if str(effect.get("outcome", "")) == "victory" else "hurt")


func _refresh() -> void:
	if engine == null or game == null:
		return
	_refresh_top()
	_refresh_race()
	_refresh_enemy()
	_refresh_hand()
	_refresh_equation()
	_refresh_controls()
	_refresh_feed()
	_refresh_burst()
	_refresh_timer()
	_maybe_save_best()
	call_deferred("_refresh_modal")


func _refresh_top() -> void:
	var s: Dictionary = engine.s
	hp_label.text = "%s / %s" % [s.hp, s.maxHp]
	_set_fill(hp_fill, float(s.hp) / maxf(float(s.maxHp), 1.0))
	deck_label.text = "牌库 %s / 15" % (int(CombatEngine.CFG.deckSize) - s.burned.size())
	sound_button.text = "♪" if sound_on else "✕"
	sound_button.tooltip_text = "音效：开" if sound_on else "音效：关"
	var phase_text := "你的回合"
	match str(s.phase):
		"enemy":
			phase_text = "敌方行动"
		"burst":
			phase_text = "追击"
		"victory":
			phase_text = "挑战完成"
		"defeat":
			phase_text = "挑战中断"
		"intro":
			phase_text = "准备开始"
	round_label.text = "第 %s 回合 · %s" % [s.round, phase_text]


func _refresh_race() -> void:
	var s: Dictionary = engine.s
	race_time_label.text = "%.1fs" % float(s.stats.time)
	if s.lastDecision == null:
		race_decision_label.text = "—"
	else:
		race_decision_label.text = "%.2fs" % float(s.lastDecision)
	race_equations_label.text = "%02d" % int(s.stats.equations)
	race_rank_label.text = "计分中" if s.ranked else "练习局 · 不计分"
	race_rank_label.modulate = Color(0.737, 0.651, 0.431) if s.ranked else Color(0.62, 0.55, 0.48)


func _refresh_enemy() -> void:
	var enemy: Dictionary = engine.s.enemies[0]
	var intent: Dictionary = engine.intent()
	intent_label.text = "即将 %s  %s" % [intent.verb, intent.damage]
	intent_label.modulate = Color(0.655, 0.91, 0.894) if intent.chilled else Color(0.91, 0.86, 0.72)
	enemy_name_label.text = str(enemy.name)
	enemy_hp_label.text = "%s / %s" % [enemy.hp, enemy.maxHp]
	_set_fill(enemy_hp_fill, float(enemy.hp) / maxf(float(enemy.maxHp), 1.0))
	enemy_root.modulate.a = 0.35 if int(enemy.hp) <= 0 else 1.0
	for child in enemy_status.get_children():
		enemy_status.remove_child(child)
		child.free()
	if int(enemy.burn) > 0:
		_status_pill("灼烧 %s" % enemy.burn, Color(0.945, 0.639, 0.424))
	if enemy.chill:
		_status_pill("下次攻击减半", Color(0.522, 0.847, 0.902))
	if int(enemy.vulnerable) > 0:
		_status_pill("易伤 %s" % enemy.vulnerable, Color(0.769, 0.631, 0.98))


func _refresh_hand() -> void:
	var s: Dictionary = engine.s
	var active: bool = engine.active()
	var live := 0
	for i in hand_buttons.size():
		var btn: Button = hand_buttons[i]
		var card = s.hand[i] if i < s.hand.size() else null
		btn.disabled = (not active) or card == null
		_paint_card(btn, card, i)
		if card != null:
			live += 1
	var label := "手牌 %s / 5" % live
	if s.burnMode:
		label = "烧掉：点数字牌回血，本局移除"
	elif s.phase == "player" and not engine.has_combo():
		label = "凑不出算式，可烧掉或结束回合"
	hand_mode_label.text = label
	hand_mode_label.modulate = Color(0.93, 0.55, 0.38) if s.burnMode else Color(0.82, 0.86, 0.78)
	draw_pile_label.text = "抽牌堆\n%s" % s.draw.size()
	discard_pile_label.text = "弃牌堆\n%s" % s.discard.size()


func _refresh_equation() -> void:
	var s: Dictionary = engine.s
	var preview = engine.preview()
	var nums: Array = engine.cards_selected()
	var op: BattleCard = engine.selected_operator()
	_fill_eq_slot(eq_slot_a, nums[0] if nums.size() > 0 else null, "数字 1")
	_fill_eq_slot(eq_slot_op, op, "符号")
	_fill_eq_slot(eq_slot_b, nums[1] if nums.size() > 1 else null, "数字 2")
	var packed: int = nums.size() + (1 if op != null else 0)
	eq_head.text = "算式 · 提前看结果" if s.showPreview else "算式"
	if preview != null and s.showPreview:
		eq_result.text = _fmt(int(preview.base))
		dmg_preview.text = str(preview.damage)
		eq_result_hint.text = "结果"
		dmg_preview_hint.text = "伤害"
	else:
		eq_result.text = "—"
		eq_result_hint.text = "打出后显示" if preview != null else "还没选齐"
		dmg_preview.text = "%d/3" % packed
		dmg_preview_hint.text = "已选"
	var line := "点两张数字和一张符号，再发射。"
	if s.burnMode:
		line = "点一张数字牌烧掉回血。符号牌不能烧。"
	elif preview != null and s.showPreview:
		line = "%s · %s" % [preview.name, preview.description]
	elif preview != null:
		line = "可以发射。结果打出后才显示。"
	elif str(s.lastEquation) != "":
		line = "上次  %s · %s" % [s.lastEquation, s.reaction]
	eq_reaction.text = line
	fire_button.disabled = preview == null or not engine.active() or s.burnMode
	clear_button.disabled = not engine.active()


func _refresh_controls() -> void:
	var s: Dictionary = engine.s
	var active: bool = engine.active()
	burn_button.disabled = not active
	burn_button.text = "点牌烧掉\n再按 B 取消" if s.burnMode else "烧掉回血\n|点数| × 10"
	burn_count_label.text = "已烧掉 %s · 查看" % s.burned.size()
	combo_dot_a.modulate = Color(0.93, 0.82, 0.52) if int(s.streak) == 1 else Color(0.35, 0.42, 0.4)
	combo_dot_b.modulate = Color(0.93, 0.82, 0.52) if int(s.windows) > 0 else Color(0.35, 0.42, 0.4)
	if int(s.windows) > 0:
		combo_status.text = "回合结束后追击\n%s 秒" % (int(s.windows) * 3)
	elif int(s.streak) == 1:
		combo_status.text = "再来一次正数加法\n乘法会打断"
	else:
		combo_status.text = "两次正数加法可追击\n乘法会打断"
	end_turn_button.disabled = not active
	var main := "结束回合"
	if s.phase == "burst":
		main = "正在追击"
	elif s.phase == "enemy":
		main = "敌方行动"
	var sub := "正在结算"
	if active:
		sub = "开始追击 · E" if int(s.windows) > 0 else "可提前结束 · E"
	end_turn_button.text = "%s\n%s" % [main, sub]
	incoming_label.text = "敌方即将造成 %s 伤害" % engine.intent().damage


func _refresh_feed() -> void:
	for child in feed_lines.get_children():
		feed_lines.remove_child(child)
		child.free()
	var lines: Array = []
	for entry in engine.s.log:
		if str(entry.type) in ["phase", "shuffle"]:
			continue
		lines.append(entry)
	if lines.size() > 2:
		lines = lines.slice(lines.size() - 2)
	if lines.is_empty():
		_feed_line("负数也能打出伤害。")
		_feed_line("尽快出手。")
	else:
		for entry in lines:
			_feed_line(str(entry.text))


func _refresh_burst() -> void:
	var on: bool = engine.s.phase == "burst"
	burst_panel.visible = on
	if not on:
		return
	burst_hits_label.text = "命中 %s 次" % engine.s.burstHits
	burst_time_label.text = "%.1f 秒" % float(engine.s.burstRemaining)
	var dur: float = maxf(float(engine.s.burstDuration), 0.001)
	_set_fill(burst_fill, float(engine.s.burstRemaining) / dur)


func _refresh_timer() -> void:
	var s: Dictionary = engine.s
	var time: float = float(s.remaining)
	var ratio: float = time / float(CombatEngine.CFG.turnSeconds)
	var label := "回合倒计时"
	if s.phase == "burst":
		time = float(s.burstRemaining)
		ratio = time / maxf(float(s.burstDuration), 0.001)
		label = "追击剩余"
	if str(s.phase) in ["enemy", "victory", "defeat"]:
		timer_label.text = {"enemy": "敌方", "victory": "完成", "defeat": "中断"}[str(s.phase)]
		ratio = 1.0 if s.phase == "victory" else 0.0
		label = "正在行动" if s.phase == "enemy" else "战斗结束"
	else:
		timer_label.text = "%.1f" % maxf(0.0, time)
	timer_caption.text = label
	var extra := "时间到后敌方出手"
	if s.paused:
		extra = "已暂停"
	elif s.phase == "burst":
		extra = "连点直到时间结束"
	timer_extra.text = extra
	var urgent: bool = s.phase == "player" and float(s.remaining) <= 8.0
	timer_ring.set_ratio(ratio, urgent)
	_set_fill(deadline_fill, ratio)
	deadline_fill.color = Color(0.88, 0.48, 0.29) if urgent else Color(0.831, 0.718, 0.463)
	timer_block.modulate = Color(1.12, 0.85, 0.75) if urgent else Color.WHITE


func _refresh_modal() -> void:
	if overlay == null or engine == null:
		return
	var key := current_overlay()
	var signature := "%s:%s" % [key, pile_kind if key == "pile" else ""]
	overlay.visible = key != ""
	overlay.color = Color(0.024, 0.075, 0.106, 0.86) if key == "intro" else Color(0.027, 0.078, 0.114, 0.8)
	if signature == _modal_signature:
		return
	_modal_signature = signature
	for child in overlay_host.get_children():
		overlay_host.remove_child(child)
		child.free()
	start_button = null
	preview_checkbox = null
	overlay_title = null
	local_record_label = null
	if key == "":
		return
	var width := 920.0
	var max_height := 640.0
	match key:
		"intro":
			width = 980.0
			max_height = 680.0
		"pause", "restart":
			width = 520.0
			max_height = 0.0
		"help":
			width = 920.0
			max_height = 680.0
		"pile", "log":
			width = 860.0
			max_height = 620.0
		"victory", "defeat":
			width = 840.0
			max_height = 0.0
	var modal := _make_modal_panel(width, max_height)
	modal.name = "ModalPanel"
	overlay_host.add_child(modal)
	var body := modal.get_node("Margin/Scroll/Body") as VBoxContainer
	if key not in ["intro", "victory", "defeat"]:
		var close := _text_button("×", "close")
		close.custom_minimum_size = Vector2(36, 32)
		close.size_flags_horizontal = Control.SIZE_SHRINK_END
		body.add_child(close)
	match key:
		"intro":
			_fill_intro(body)
		"help":
			_fill_help(body)
		"pause":
			_fill_pause(body)
		"restart":
			_fill_restart(body)
		"pile":
			_fill_pile(body)
		"log":
			_fill_log(body)
		"victory", "defeat":
			_fill_outcome(body, key == "victory")


func _maybe_save_best() -> void:
	if _record_handled or engine.s.phase != "victory":
		return
	_record_handled = true
	if not engine.s.ranked:
		return
	var best := load_best()
	var score := engine.score()
	var t := float(engine.s.stats.time)
	if best.is_empty() or score > int(best.score) or (score == int(best.score) and t < float(best.time)):
		var cfg := ConfigFile.new()
		cfg.load(record_path)
		var section := str(engine.seed)
		cfg.set_value(section, "score", score)
		cfg.set_value(section, "time", t)
		cfg.set_value(section, "round", int(engine.s.round))
		cfg.save(record_path)


func _export_log() -> void:
	var payload := JSON.stringify(_jsonable(engine.export_state()), "\t")
	var path := "user://emergence_v03_seed_%d.json" % engine.seed
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(payload)
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(payload)
	show_toast("已导出战斗记录。")


func _build_theme() -> void:
	_sans = SystemFont.new()
	_sans.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	_serif = SystemFont.new()
	_serif.font_names = PackedStringArray(["Georgia", "Times New Roman", "Microsoft YaHei UI", "Microsoft YaHei"])
	_ui_theme = Theme.new()
	_ui_theme.default_font = _sans
	_ui_theme.default_font_size = 16
	_ui_theme.set_color("font_color", "Label", Color(0.86, 0.84, 0.72))
	_ui_theme.set_color("font_color", "Button", Color(0.91, 0.86, 0.72))
	_ui_theme.set_color("font_hover_color", "Button", Color(0.98, 0.93, 0.78))
	_ui_theme.set_color("font_disabled_color", "Button", Color(0.55, 0.58, 0.54, 0.7))
	_ui_theme.set_stylebox("normal", "Button", _sb(Color(0.16, 0.24, 0.27), Color(0.71, 0.63, 0.42, 0.55), 1, 4))
	_ui_theme.set_stylebox("hover", "Button", _sb(Color(0.22, 0.32, 0.33), Color(0.85, 0.76, 0.52, 0.8), 1, 4))
	_ui_theme.set_stylebox("pressed", "Button", _sb(Color(0.12, 0.2, 0.23), Color(0.85, 0.76, 0.52), 1, 4))
	_ui_theme.set_stylebox("disabled", "Button", _sb(Color(0.12, 0.18, 0.2, 0.7), Color(0.45, 0.48, 0.4, 0.4), 1, 4))
	_ui_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	_ui_theme.set_stylebox("panel", "PanelContainer", _sb(Color(0.125, 0.2, 0.22, 0.94), Color(0.71, 0.63, 0.42, 0.53), 1, 7))
	_ui_theme.set_stylebox("panel", "Panel", _sb(Color(0.125, 0.2, 0.22, 0.94), Color(0.71, 0.63, 0.42, 0.53), 1, 7))


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.027, 0.067, 0.09)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	game = Control.new()
	game.name = "Game"
	game.size = DESIGN
	game.clip_contents = true
	add_child(game)
	var world := ColorRect.new()
	world.color = Color(0.078, 0.145, 0.173)
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.add_child(world)
	_build_topbar()
	_build_race()
	_build_stage()
	_build_controls()
	_build_hand()
	_build_burst()
	fx_layer = Control.new()
	fx_layer.name = "FxLayer"
	fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.z_index = 15
	game.add_child(fx_layer)
	_build_toast_and_banner()
	_build_overlay()
	var hint := _label("1–5 选手牌　Enter / 空格 发射　E 结束回合　B 烧掉　P 暂停", 12, Color(0.62, 0.7, 0.66))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(game, hint, Rect2(270, 878, 900, 20))
	var build := _label("v0.3", 11, Color(0.5, 0.58, 0.55))
	_place(game, build, Rect2(20, 878, 240, 20))
	zoom_label = _label("显示 100%　Ctrl + 滚轮 / Ctrl ± 缩放", 11, Color(0.5, 0.58, 0.55))
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(game, zoom_label, Rect2(1100, 878, 320, 20))


func _build_topbar() -> void:
	var bar := Panel.new()
	bar.z_index = 8
	_place(game, bar, Rect2(0, 0, 1440, 68))
	bar.add_theme_stylebox_override("panel", _sb(Color(0.043, 0.086, 0.125, 0.96), Color(0.55, 0.58, 0.45, 0.35), 1, 0))
	var brand := _label("涌现", 24, Color(0.91, 0.86, 0.72), true)
	_place(bar, brand, Rect2(30, 10, 160, 30))
	var sub := _label("限时对战", 11, Color(0.706, 0.725, 0.655))
	_place(bar, sub, Rect2(30, 40, 200, 18))
	var heart := _label("生命", 13, Color(0.62, 0.7, 0.66))
	_place(bar, heart, Rect2(220, 12, 50, 18))
	hp_label = _label("80 / 100", 16, Color(0.91, 0.86, 0.72), true)
	hp_label.name = "HpLabel"
	_place(bar, hp_label, Rect2(270, 8, 120, 22))
	var track := ColorRect.new()
	track.color = Color(0.12, 0.2, 0.22)
	_place(bar, track, Rect2(220, 36, 210, 10))
	hp_fill = ColorRect.new()
	hp_fill.name = "HpFill"
	hp_fill.color = Color(0.72, 0.42, 0.38)
	hp_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_fill.anchor_right = 0.8
	track.add_child(hp_fill)
	location_label = _label("深渊前庭", 14, Color(0.82, 0.84, 0.74), true)
	_place(bar, location_label, Rect2(470, 12, 160, 22))
	route_label = _label("单人挑战", 11, Color(0.7, 0.76, 0.68))
	_place(bar, route_label, Rect2(470, 36, 120, 18))
	deck_label = _label("牌库 15 / 15", 13, Color(0.86, 0.84, 0.72))
	_place(bar, deck_label, Rect2(760, 22, 170, 24))
	var deck_btn := _icon_button("牌库", "pile", "all")
	_place(bar, deck_btn, Rect2(930, 16, 70, 36))
	sound_button = _icon_button("♪", "sound")
	sound_button.name = "SoundButton"
	_place(bar, sound_button, Rect2(1010, 16, 70, 36))
	_place(bar, _icon_button("暂停", "pause"), Rect2(1090, 16, 70, 36))
	_place(bar, _icon_button("规则", "help"), Rect2(1170, 16, 70, 36))
	_place(bar, _icon_button("全屏", "fullscreen"), Rect2(1250, 16, 70, 36))


func _build_race() -> void:
	race_time_label = _metric("用时", "0.0s")
	_place(game, race_time_label.get_parent(), Rect2(36, 78, 110, 56))
	race_decision_label = _metric("最近出手", "—")
	_place(game, race_decision_label.get_parent(), Rect2(160, 78, 110, 56))
	race_equations_label = _metric("完成算式", "00")
	_place(game, race_equations_label.get_parent(), Rect2(284, 78, 110, 56))
	race_rank_label = _label("计分中", 10, Color(0.737, 0.651, 0.431))
	_place(game, race_rank_label, Rect2(36, 142, 220, 16))
	var deadline := ColorRect.new()
	deadline.color = Color(0.22, 0.28, 0.27)
	_place(game, deadline, Rect2(36, 160, 360, 3))
	deadline_fill = ColorRect.new()
	deadline_fill.color = Color(0.831, 0.718, 0.463)
	deadline_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	deadline.add_child(deadline_fill)
	var caption := VBoxContainer.new()
	caption.alignment = BoxContainer.ALIGNMENT_CENTER
	_place(game, caption, Rect2(430, 86, 580, 78))
	caption.add_child(_label("每回合 10 秒", 12, Color(0.51, 0.6, 0.565)))
	var title := _label("用算式击败观测者", 18, Color(0.824, 0.816, 0.722), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(title)
	round_label = _label("第 1 回合 · 准备开始", 12, Color(0.72, 0.78, 0.7))
	round_label.name = "RoundLabel"
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(round_label)
	var feed := VBoxContainer.new()
	_place(game, feed, Rect2(1146, 78, 261, 90))
	var feed_head := HBoxContainer.new()
	feed.add_child(feed_head)
	var feed_title := _label("现场记录", 12, Color(0.56, 0.65, 0.62))
	feed_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_head.add_child(feed_title)
	var log_btn := _text_button("展开记录 ↗", "log")
	log_btn.custom_minimum_size = Vector2(90, 22)
	feed_head.add_child(log_btn)
	feed_lines = VBoxContainer.new()
	feed_lines.name = "FeedLines"
	feed.add_child(feed_lines)


func _build_stage() -> void:
	hero_root = Control.new()
	hero_root.name = "Hero"
	_place(game, hero_root, Rect2(153, 229, 289, 342))
	_hero_origin = hero_root.position
	var hero := TextureRect.new()
	hero.texture = HERO_TEX
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_root.add_child(hero)
	var nameplate := _label("实验员", 14, Color(0.784, 0.8, 0.718), true)
	nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(game, nameplate, Rect2(170, 541, 232, 20))
	var motto := _label("不靠魔法，只靠算式。", 13, Color(0.541, 0.655, 0.647))
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(game, motto, Rect2(170, 561, 232, 16))
	enemy_root = Control.new()
	enemy_root.name = "Enemy"
	_place(game, enemy_root, Rect2(820, 200, 292, 360))
	_enemy_origin = enemy_root.position
	intent_label = _label("回合结束后  裂隙冲击  8", 13, Color(0.91, 0.86, 0.72), true)
	intent_label.name = "IntentLabel"
	intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(enemy_root, intent_label, Rect2(0, 0, 292, 24))
	var enemy := TextureRect.new()
	enemy.texture = ENEMY_TEX
	enemy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	enemy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	enemy.position = Vector2(16, 28)
	enemy.size = Vector2(260, 250)
	enemy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_root.add_child(enemy)
	enemy_name_label = _label("深渊观测者", 14, Color(0.82, 0.84, 0.74), true)
	enemy_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(enemy_root, enemy_name_label, Rect2(0, 278, 292, 20))
	var e_track := ColorRect.new()
	e_track.color = Color(0.12, 0.18, 0.2)
	_place(enemy_root, e_track, Rect2(36, 302, 220, 8))
	enemy_hp_fill = ColorRect.new()
	enemy_hp_fill.color = Color(0.72, 0.38, 0.36)
	enemy_hp_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	e_track.add_child(enemy_hp_fill)
	enemy_hp_label = _label("120 / 120", 12, Color(0.86, 0.84, 0.72))
	enemy_hp_label.name = "EnemyHpLabel"
	enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(enemy_root, enemy_hp_label, Rect2(0, 312, 292, 18))
	enemy_status = HBoxContainer.new()
	enemy_status.alignment = BoxContainer.ALIGNMENT_CENTER
	_place(enemy_root, enemy_status, Rect2(0, 332, 292, 24))


func _build_controls() -> void:
	timer_block = Control.new()
	_place(game, timer_block, Rect2(36, 556, 133, 136))
	timer_ring = TimerRing.new()
	timer_ring.position = Vector2(17, 4)
	timer_ring.size = Vector2(98, 98)
	timer_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_block.add_child(timer_ring)
	timer_label = _label("10.0", 22, Color(0.91, 0.86, 0.72), true)
	timer_label.name = "TimerLabel"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(timer_block, timer_label, Rect2(0, 32, 133, 28))
	timer_caption = _label("回合倒计时", 12, Color(0.64, 0.71, 0.66))
	timer_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(timer_block, timer_caption, Rect2(0, 102, 133, 16))
	timer_extra = _label("时间到后敌方出手", 11, Color(0.56, 0.64, 0.6))
	timer_extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(timer_block, timer_extra, Rect2(0, 118, 133, 16))
	burn_button = _action_button("烧掉回血\n|点数| × 10", "burn")
	burn_button.name = "BurnButton"
	_place(game, burn_button, Rect2(176, 588, 180, 64))
	burn_count_label = _label("已烧掉 0 · 查看", 11, Color(0.7, 0.76, 0.68))
	burn_count_label.mouse_filter = Control.MOUSE_FILTER_STOP
	burn_count_label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			act("pile", "burned")
	)
	_place(game, burn_count_label, Rect2(176, 654, 180, 18))
	var eq := PanelContainer.new()
	eq.name = "EquationPanel"
	_place(game, eq, Rect2(389, 566, 668, 120))
	var eq_inner := MarginContainer.new()
	eq_inner.add_theme_constant_override("margin_left", 14)
	eq_inner.add_theme_constant_override("margin_right", 12)
	eq_inner.add_theme_constant_override("margin_top", 8)
	eq_inner.add_theme_constant_override("margin_bottom", 8)
	eq.add_child(eq_inner)
	var eq_box := VBoxContainer.new()
	eq_inner.add_child(eq_box)
	var eq_top := HBoxContainer.new()
	eq_box.add_child(eq_top)
	eq_head = _label("算式", 13, Color(0.64, 0.71, 0.65))
	eq_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq_top.add_child(eq_head)
	clear_button = _text_button("清空", "clear")
	clear_button.custom_minimum_size = Vector2(64, 24)
	eq_top.add_child(clear_button)
	var eq_row := HBoxContainer.new()
	eq_row.add_theme_constant_override("separation", 8)
	eq_box.add_child(eq_row)
	eq_slot_a = _eq_slot("数字 1")
	eq_slot_op = _eq_slot("符号")
	eq_slot_b = _eq_slot("数字 2")
	eq_row.add_child(eq_slot_a)
	eq_row.add_child(eq_slot_op)
	eq_row.add_child(eq_slot_b)
	var eq_eq := _label("=", 22, Color(0.82, 0.78, 0.62), true)
	eq_eq.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	eq_row.add_child(eq_eq)
	var result_box := VBoxContainer.new()
	eq_result = _label("—", 22, Color(0.93, 0.85, 0.62), true)
	eq_result.name = "EquationResult"
	eq_result_hint = _label("打出后显示", 12, Color(0.62, 0.7, 0.65))
	result_box.add_child(eq_result)
	result_box.add_child(eq_result_hint)
	eq_row.add_child(result_box)
	var dmg_box := VBoxContainer.new()
	dmg_preview_hint = _label("已选", 12, Color(0.62, 0.7, 0.65))
	dmg_preview = _label("0/3", 18, Color(0.91, 0.86, 0.72), true)
	dmg_preview.name = "DamagePreview"
	dmg_box.add_child(dmg_preview_hint)
	dmg_box.add_child(dmg_preview)
	eq_row.add_child(dmg_box)
	fire_button = _action_button("发射  ↵", "fire")
	fire_button.name = "FireButton"
	fire_button.custom_minimum_size = Vector2(88, 52)
	eq_row.add_child(fire_button)
	eq_reaction = _label("点两张数字和一张符号，再发射。", 12, Color(0.75, 0.78, 0.7))
	eq_reaction.name = "EquationReaction"
	eq_reaction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eq_box.add_child(eq_reaction)
	var combo := VBoxContainer.new()
	_place(game, combo, Rect2(1072, 562, 150, 112))
	combo.add_child(_label("加法追击", 12, Color(0.64, 0.71, 0.65)))
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	combo.add_child(dots)
	combo_dot_a = _combo_dot()
	combo_dot_b = _combo_dot()
	dots.add_child(combo_dot_a)
	dots.add_child(combo_dot_b)
	combo_status = _label("两次正数加法可追击\n乘法会打断", 12, Color(0.82, 0.84, 0.74))
	combo_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo.add_child(combo_status)
	end_turn_button = _action_button("结束回合\n可提前结束 · E", "endturn")
	end_turn_button.name = "EndTurnButton"
	_place(game, end_turn_button, Rect2(1234, 576, 178, 60))
	incoming_label = _label("敌方即将造成 8 伤害", 11, Color(0.78, 0.7, 0.58))
	incoming_label.name = "IncomingLabel"
	incoming_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(game, incoming_label, Rect2(1234, 640, 178, 18))


func _build_hand() -> void:
	var caption := HBoxContainer.new()
	_place(game, caption, Rect2(177, 686, 1086, 20))
	hand_mode_label = _label("手牌 0 / 5", 12, Color(0.82, 0.86, 0.78))
	hand_mode_label.name = "HandModeLabel"
	hand_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_child(hand_mode_label)
	hand_rules_label = _label("出牌后本回合不补牌", 12, Color(0.62, 0.7, 0.66))
	hand_rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.add_child(hand_rules_label)
	var zone := HBoxContainer.new()
	zone.name = "HandZone"
	zone.alignment = BoxContainer.ALIGNMENT_CENTER
	zone.add_theme_constant_override("separation", 10)
	_place(game, zone, Rect2(177, 708, 1086, 178))
	hand_buttons.clear()
	for i in 5:
		var btn := Button.new()
		btn.name = "Hand%d" % i
		btn.custom_minimum_size = Vector2(130, 174)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(click_hand.bind(i))
		zone.add_child(btn)
		hand_buttons.append(btn)
		_paint_card(btn, null, i)
	draw_pile_label = _pile_button("抽牌堆", "draw")
	_place(game, draw_pile_label, Rect2(34, 746, 95, 112))
	discard_pile_label = _pile_button("弃牌堆", "discard")
	_place(game, discard_pile_label, Rect2(1310, 746, 95, 112))


func _build_burst() -> void:
	burst_panel = PanelContainer.new()
	burst_panel.name = "BurstPanel"
	burst_panel.visible = false
	burst_panel.z_index = 12
	_place(game, burst_panel, Rect2(570, 288, 300, 210))
	var box := VBoxContainer.new()
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	burst_panel.add_child(pad)
	pad.add_child(box)
	box.add_child(_label("追击", 12, Color(0.82, 0.76, 0.55)))
	var title := _label("追击时刻", 24, Color(0.937, 0.855, 0.678), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	burst_hit_button = _action_button("连点追击", "burst")
	burst_hit_button.name = "BurstHitButton"
	burst_hit_button.custom_minimum_size = Vector2(0, 44)
	box.add_child(burst_hit_button)
	var read := HBoxContainer.new()
	box.add_child(read)
	burst_hits_label = _label("命中 0 次", 12, Color(0.86, 0.84, 0.72))
	burst_hits_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	read.add_child(burst_hits_label)
	burst_time_label = _label("3.0 秒", 12, Color(0.86, 0.84, 0.72))
	burst_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	read.add_child(burst_time_label)
	var track := ColorRect.new()
	track.custom_minimum_size = Vector2(0, 6)
	track.color = Color(0.18, 0.24, 0.25)
	box.add_child(track)
	burst_fill = ColorRect.new()
	burst_fill.color = Color(0.831, 0.718, 0.463)
	burst_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.add_child(burst_fill)
	var hint := _label("连点空格，每下 2 伤害", 12, Color(0.64, 0.71, 0.65))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _build_toast_and_banner() -> void:
	toast_label = _label("", 13, Color(0.933, 0.835, 0.651))
	toast_label.name = "ToastLabel"
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.visible = false
	toast_label.z_index = 28
	_place(game, toast_label, Rect2(340, 500, 760, 40))
	var toast_bg := _sb(Color(0.063, 0.141, 0.176, 0.96), Color(0.71, 0.63, 0.43, 0.53), 1, 4)
	toast_label.add_theme_stylebox_override("normal", toast_bg)
	banner = VBoxContainer.new()
	banner.visible = false
	banner.z_index = 20
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(game, banner, Rect2(470, 250, 500, 70))
	banner_title = _label("", 26, Color(0.93, 0.86, 0.68), true)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_title)
	banner_sub = _label("", 13, Color(0.7, 0.76, 0.68))
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_sub)
	formula_reveal = VBoxContainer.new()
	formula_reveal.visible = false
	formula_reveal.z_index = 18
	formula_reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(game, formula_reveal, Rect2(470, 430, 500, 54))
	formula_reveal_main = _label("", 20, Color(0.93, 0.85, 0.62), true)
	formula_reveal_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	formula_reveal.add_child(formula_reveal_main)
	formula_reveal_sub = _label("", 12, Color(0.78, 0.74, 0.6))
	formula_reveal_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	formula_reveal.add_child(formula_reveal_sub)


func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.027, 0.078, 0.114, 0.8)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 40
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	game.add_child(overlay)
	overlay_host = CenterContainer.new()
	overlay_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(overlay_host)


func _make_modal_panel(width: float, max_height: float = 0.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if max_height > 0.0:
		scroll.custom_minimum_size = Vector2(width - 56, max_height)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		scroll.custom_minimum_size = Vector2(width - 56, 0)
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(width - 80, 0)
	scroll.add_child(body)
	return panel


func _fill_intro(body: VBoxContainer) -> void:
	body.add_child(_label("限时战斗", 12, Color(0.7, 0.74, 0.6)))
	overlay_title = _label("涌现", 56, Color(0.93, 0.86, 0.68), true)
	overlay_title.name = "OverlayTitle"
	body.add_child(overlay_title)
	body.add_child(_label("用数字和符号组成算式，打退观测者。", 16, Color(0.9, 0.84, 0.68), true))
	var copy := _label("每回合抽 5 张牌。点两张数字和一张符号后发射。\n结果默认打出后才显示，可在规则里提前查看。", 14, Color(0.78, 0.82, 0.74))
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(copy)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	start_button = _action_button("开始挑战", "start")
	start_button.name = "StartButton"
	start_button.custom_minimum_size = Vector2(180, 44)
	row.add_child(start_button)
	var help := _text_button("查看规则", "help")
	help.custom_minimum_size = Vector2(140, 44)
	row.add_child(help)
	body.add_child(_label("每回合 10 秒，可按 E 提前结束。", 13, Color(0.64, 0.71, 0.65)))
	local_record_label = _label(_intro_record_text(), 12, Color(0.56, 0.67, 0.6))
	local_record_label.name = "LocalRecord"
	body.add_child(local_record_label)
	body.add_child(_label("怎么打", 16, Color(0.9, 0.84, 0.68), true))
	body.add_child(_label("1. 牌库 15 张：数字 −5 到 +5 各一张，＋ 和 × 各两张。出牌后本回合不补牌。\n   例如 −5 × −2 = 10。", 13, Color(0.78, 0.82, 0.74)))
	body.add_child(_label("2. 三张牌一次攻击。点选后按空格或 Enter 发射，三张牌进入弃牌。", 13, Color(0.78, 0.82, 0.74)))
	body.add_child(_label("3. 数字牌可烧掉回血。连续两次正数加法，回合结束后可追击。", 13, Color(0.78, 0.82, 0.74)))
	var note := _label("没有能量。没有减法和除法。压力来自倒计时和手牌。", 12, Color(0.58, 0.66, 0.6))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)


func _fill_help(body: VBoxContainer) -> void:
	overlay_title = _label("规则", 28, Color(0.93, 0.86, 0.68), true)
	body.add_child(overlay_title)
	body.add_child(_label("默认不提前显示答案。发射后才公布算式结果。", 14, Color(0.78, 0.82, 0.74)))
	var help := _label(
		"回合\n每回合 10 秒，时间到敌方出手。可按 E 提前结束。没有能量，出手次数不限。\n每回合抽 5 张。一次攻击用两张数字和一张符号，三张都进弃牌，当回合不补牌。\n\n牌库\n数字 −5 到 +5 各一张，＋ 和 × 各两张，共 15 张。新回合先弃掉手里剩下的牌再抽。抽牌堆空了会把弃牌洗回。烧掉的牌不会回来。\n\n加法追击\n正数加法打伤害。连续两次正数加法，回合结束后有 3 秒追击，连点空格每下 2 伤害。可跨回合累计。乘法或非正结果会打断。\n\n烧掉回血\n按 B 再点数字牌，回复 |点数| × 10，该牌本局移除。符号牌、0、满血不能烧。系统会留下至少两张还能打出正数攻击的数字牌。\n\n乘法元素\n只有结果为正才触发伤害和元素。非正结果仍消耗三张牌，伤害为 0。\n火×火 叠燃 灼烧 4　　冰×冰 冻结 下次攻击减半　　雷×雷 电弧 额外 6\n火×冰 蒸汽 额外 8　　火×雷 过载 额外 4 且灼烧 2　　冰×雷 超导 后两次正数伤害 +50%\n灼烧在敌方出手前结算，再减半向下取整。\n\n1–5 选手牌　　Enter / 空格 发射　　E 结束　　B 烧掉　　Esc 取消　　P 暂停　　A / X 选 ＋ / ×",
		13, Color(0.78, 0.82, 0.74)
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(860, 0)
	body.add_child(help)
	preview_checkbox = CheckBox.new()
	preview_checkbox.name = "PreviewToggle"
	preview_checkbox.text = "提前看结果和伤害"
	preview_checkbox.set_pressed_no_signal(engine.s.showPreview or _preview_pref)
	preview_checkbox.focus_mode = Control.FOCUS_ALL
	preview_checkbox.toggled.connect(func(pressed: bool) -> void:
		_preview_pref = pressed
		engine.set_preview(pressed)
	)
	body.add_child(preview_checkbox)
	body.add_child(_label("打开后本局改为练习，不计分。", 12, Color(0.58, 0.66, 0.6)))
	var footer := _label("暂停、看牌或打开规则会停表，本局改为练习。没有减法和除法。", 12, Color(0.55, 0.62, 0.58))
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(footer)
	body.add_child(_action_button("返回开始页" if engine.s.phase == "intro" else "返回战斗", "close"))


func _fill_pause(body: VBoxContainer) -> void:
	overlay_title = _label("暂停", 48, Color(0.93, 0.86, 0.68), true)
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(overlay_title)
	var info := _label("计时已停。可以继续打，但本局不再计分。", 15, Color(0.78, 0.82, 0.74))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var resume := _action_button("继续战斗", "close")
	resume.custom_minimum_size = Vector2(140, 44)
	row.add_child(resume)
	var help := _text_button("查看规则", "help")
	help.custom_minimum_size = Vector2(140, 44)
	row.add_child(help)
	var restart := _text_button("重新开始挑战", "restart-confirm")
	restart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart.custom_minimum_size = Vector2(200, 36)
	body.add_child(restart)


func _fill_restart(body: VBoxContainer) -> void:
	overlay_title = _label("重新开始？", 26, Color(0.93, 0.86, 0.68), true)
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(overlay_title)
	var info := _label("本局进度会清空，洗牌顺序不变。", 15, Color(0.78, 0.82, 0.74))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var again := _action_button("重新开始", "start")
	again.custom_minimum_size = Vector2(140, 44)
	row.add_child(again)
	var keep := _text_button("继续当前战斗", "close")
	keep.custom_minimum_size = Vector2(160, 44)
	row.add_child(keep)


func _fill_pile(body: VBoxContainer) -> void:
	var titles := {"all": "全部牌", "draw": "抽牌堆", "discard": "弃牌堆", "burned": "已烧掉"}
	var title: String = str(titles.get(pile_kind, "全部牌"))
	var cards: Array = _pile_cards()
	overlay_title = _label("%s · %s" % [title, cards.size()], 24, Color(0.93, 0.86, 0.68), true)
	body.add_child(overlay_title)
	body.add_child(_label("这些牌已离开本局。" if pile_kind == "burned" else "按类型和数值排列，不是抽牌顺序。", 13, Color(0.78, 0.82, 0.74)))
	var s: Dictionary = engine.s
	body.add_child(_label("手牌 %s　　抽牌 %s　　弃牌 %s　　烧掉 %s" % [_live_count(s.hand), s.draw.size(), s.discard.size(), s.burned.size()], 12, Color(0.7, 0.76, 0.68)))
	if cards.is_empty():
		body.add_child(_label("这里目前没有卡牌。", 14, Color(0.62, 0.7, 0.66)))
	else:
		var list := VBoxContainer.new()
		for card in cards:
			list.add_child(_label(_pile_line(card), 13, Color(0.86, 0.84, 0.72)))
		body.add_child(list)
	body.add_child(_action_button("返回战斗", "close"))


func _fill_log(body: VBoxContainer) -> void:
	overlay_title = _label("战斗记录", 24, Color(0.93, 0.86, 0.68), true)
	body.add_child(overlay_title)
	body.add_child(_label("可导出本局打出的算式、用掉的牌和用时。", 13, Color(0.78, 0.82, 0.74)))
	var log: Array = engine.s.log.duplicate()
	log.reverse()
	if log.is_empty():
		body.add_child(_label("暂无记录", 14, Color(0.62, 0.7, 0.66)))
	else:
		var list := VBoxContainer.new()
		for entry in log:
			list.add_child(_label("第 %s 回合  %s" % [entry.round, entry.text], 12, Color(0.82, 0.84, 0.74)))
		body.add_child(list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	row.add_child(_action_button("返回战斗", "close"))
	row.add_child(_text_button("导出记录", "export"))


func _fill_outcome(body: VBoxContainer, win: bool) -> void:
	var s: Dictionary = engine.s
	overlay_title = _label("挑战完成" if win else "挑战失败", 26, Color(0.93, 0.86, 0.68), true)
	body.add_child(overlay_title)
	body.add_child(_label("观测者已被击败。可以用同一副牌再打一次。" if win else "可以再试。烧掉回血或负负得正，结果会不一样。", 13, Color(0.78, 0.82, 0.74)))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 24)
	body.add_child(grid)
	grid.add_child(_stat_cell("%.2fs" % float(s.stats.time), "用时"))
	grid.add_child(_stat_cell(str(s.round), "战斗回合"))
	grid.add_child(_stat_cell(str(s.stats.equations), "完成算式"))
	grid.add_child(_stat_cell(str(engine.score()), "挑战得分" if win else "已造成伤害 × 10"))
	body.add_child(_label("本局 %s" % engine.seed, 14, Color(0.9, 0.84, 0.68), true))
	body.add_child(_label("剩余生命 %s　·　追击 %s 次　·　烧掉 %s 张" % [s.hp, s.stats.hits, s.burned.size()], 13, Color(0.78, 0.82, 0.74)))
	var note := _label(_outcome_footnote(win), 12, Color(0.62, 0.7, 0.66))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	row.add_child(_action_button("同样洗牌再打", "start"))
	row.add_child(_text_button("换一副牌", "new-seed"))
	row.add_child(_text_button("导出记录", "export"))
	var footer := _label("通关得分 = 向下取整［1200 + 6000 ÷（用时秒数 + 10）+ 剩余生命 × 5 −（回合数 − 1）× 15］。只记在本机。", 10, Color(0.55, 0.62, 0.58))
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(footer)


func _intro_record_text() -> String:
	var best := load_best()
	var line := "本局 %s\n" % engine.seed
	if best.is_empty():
		return line + "还没有通关纪录。"
	return line + "本地最佳 %s 分 · %.2f 秒" % [best.score, best.time]


func _outcome_footnote(win: bool) -> String:
	var best := load_best()
	var line := ""
	if engine.s.ranked:
		if win:
			line = "本局计入本地纪录。"
		else:
			line = "未通关，不更新纪录。"
	else:
		line = "本局曾暂停或提前看结果，不计分。"
	if best.is_empty():
		line += "\n还没有通关纪录。"
	else:
		line += "\n本地最佳：%s 分 / %.2f 秒。" % [best.score, best.time]
	return line


func _paint_card(btn: Button, card: Variant, index: int) -> void:
	for child in btn.get_children():
		btn.remove_child(child)
		child.free()
	btn.text = ""
	var angles: Array[float] = [-4.0, -2.0, 0.0, 2.0, 4.0]
	var rot: float = angles[index]
	btn.pivot_offset = Vector2(65, 174)
	if card == null:
		btn.rotation_degrees = rot
		btn.disabled = true
		btn.add_theme_stylebox_override("normal", _sb(Color(0.1, 0.17, 0.18, 0.35), Color(0.55, 0.62, 0.53, 0.25), 1, 7))
		btn.add_theme_stylebox_override("disabled", btn.get_theme_stylebox("normal"))
		var empty := Label.new()
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.48, 0.6, 0.545))
		var waiting := engine == null or str(engine.s.phase) == "intro"
		empty.text = "等待抽牌" if waiting else "空"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(empty)
		if btn.has_meta("card_id"):
			btn.remove_meta("card_id")
		return
	var selected := false
	if card.type == "operator":
		selected = str(engine.s.operatorId) == card.id
	else:
		selected = engine.s.selected.has(card.id)
	btn.rotation_degrees = 0.0 if selected else rot
	var style := _card_style(card, selected)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("disabled", style)
	var ink := _card_ink(card)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_right = -8
	col.offset_top = 8
	col.offset_bottom = -8
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var order := Label.new()
	order.text = "符号" if card.type == "operator" else (str(engine.s.selected.find(card.id) + 1) if selected and card.type == "number" else "")
	order.add_theme_font_size_override("font_size", 10)
	order.add_theme_color_override("font_color", ink)
	order.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	order.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(order)
	var key := Label.new()
	key.text = str(index + 1)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key.add_theme_font_size_override("font_size", 11)
	key.add_theme_color_override("font_color", ink)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(key)
	var elem := Label.new()
	elem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elem.add_theme_font_size_override("font_size", 12)
	elem.add_theme_color_override("font_color", ink)
	elem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card.type == "operator":
		elem.text = "符号"
	else:
		elem.text = str(ELEM_META[card.elem].name)
	col.add_child(elem)
	var number := Label.new()
	number.text = _card_label(card)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 36)
	number.add_theme_font_override("font", _serif)
	number.add_theme_color_override("font_color", ink)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(number)
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", ink)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card.type == "operator":
		title.text = "加法" if card.op == "+" else "乘法"
	else:
		title.text = str(ELEM_META[card.elem].label)
	col.add_child(title)
	var desc := Label.new()
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", ink.darkened(0.15))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card.type == "operator":
		desc.text = "两次正数加法可追击" if card.op == "+" else "正数乘法触发元素"
	else:
		desc.text = "%s · 烧掉回 %s 血" % [ELEM_META[card.elem].name, absi(card.value) * 10]
	col.add_child(desc)
	btn.set_meta("card_id", card.id)
	btn.tooltip_text = _card_tip(card)


func _card_style(card: BattleCard, selected: bool) -> StyleBoxFlat:
	var bg := Color(0.91, 0.875, 0.77)
	var border := Color(0.816, 0.725, 0.506)
	if card.type == "operator":
		bg = Color(0.2, 0.24, 0.23) if card.op == "+" else Color(0.2, 0.29, 0.31)
		border = Color(0.675, 0.592, 0.408) if card.op == "+" else Color(0.494, 0.647, 0.631)
	else:
		match card.elem:
			"fire":
				bg = Color(0.91, 0.847, 0.72)
			"ice":
				bg = Color(0.894, 0.886, 0.784)
			"spark":
				bg = Color(0.878, 0.867, 0.788)
	if selected:
		border = Color(0.659, 0.89, 0.82)
	elif engine.s.burnMode and card.type == "number":
		border = Color(0.93, 0.55, 0.38)
	return _sb(bg, border, 2 if selected else 1, 7)


func _card_ink(card: BattleCard) -> Color:
	if card.type == "operator":
		return Color(0.91, 0.81, 0.56) if card.op == "+" else Color(0.659, 0.859, 0.839)
	match card.elem:
		"fire":
			return Color(0.439, 0.247, 0.188)
		"ice":
			return Color(0.145, 0.302, 0.341)
		_:
			return Color(0.31, 0.231, 0.396)


func _card_label(card: BattleCard) -> String:
	if card.type == "operator":
		return card.op
	return "+%s" % card.value if card.value > 0 else _fmt(card.value)


func _card_tip(card: BattleCard) -> String:
	if card.type == "operator":
		if card.op == "+":
			return "加法牌\n两数相加。连续两次正数加法可在回合结束后追击。\n发射后与两张数字一起进弃牌。不能烧掉。"
		return "乘法牌\n两数相乘。结果为正才触发元素。\n发射后与两张数字一起进弃牌。不能烧掉。"
	var elem: Dictionary = ELEM_META[card.elem]
	return "数字牌 %s · %s\n再选一张数字和一张符号组成算式。\n发射后进弃牌，本回合不补。\n烧掉最多回复 %s 生命。" % [_card_label(card), elem.name, absi(card.value) * int(CombatEngine.CFG.healPerValue)]


func _fill_eq_slot(slot: PanelContainer, card: Variant, placeholder: String) -> void:
	var lab: Label = slot.get_node("Label")
	if card == null:
		lab.text = placeholder
		lab.add_theme_color_override("font_color", Color(0.62, 0.7, 0.66))
		slot.add_theme_stylebox_override("panel", _sb(Color(0.1, 0.16, 0.18, 0.8), Color(0.45, 0.5, 0.42, 0.4), 1, 4))
		return
	if card.type == "operator":
		lab.text = card.op
	else:
		lab.text = _fmt(card.value)
	lab.add_theme_color_override("font_color", Color(0.93, 0.85, 0.62))
	slot.add_theme_stylebox_override("panel", _sb(Color(0.18, 0.27, 0.27), Color(0.71, 0.63, 0.42, 0.7), 1, 4))


func _eq_slot(placeholder: String) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(78, 48)
	var lab := Label.new()
	lab.name = "Label"
	lab.text = placeholder
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(lab)
	return slot


func _combo_dot() -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(28, 28)
	dot.add_theme_stylebox_override("panel", _sb(Color(0.22, 0.28, 0.27), Color(0.71, 0.63, 0.42, 0.5), 1, 14))
	return dot


func _pile_button(title: String, pile: String) -> Label:
	var lab := Label.new()
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.text = "%s\n0" % title
	lab.mouse_filter = Control.MOUSE_FILTER_STOP
	lab.add_theme_stylebox_override("normal", _sb(Color(0.17, 0.26, 0.255), Color(0.55, 0.58, 0.42, 0.53), 1, 4))
	lab.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			act("pile", pile)
	)
	return lab


func _metric(caption: String, value: String) -> Label:
	var box := VBoxContainer.new()
	box.add_child(_label(caption, 12, Color(0.616, 0.694, 0.655)))
	var lab := _label(value, 22, Color(0.843, 0.8, 0.682), true)
	lab.name = caption
	box.add_child(lab)
	return lab


func _stat_cell(value: String, caption: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	var v := _label(value, 22, Color(0.93, 0.86, 0.68), true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(v)
	var c := _label(caption, 11, Color(0.64, 0.71, 0.65))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(c)
	return box


func _status_pill(text: String, color: Color) -> void:
	var lab := _label(text, 11, color)
	lab.add_theme_stylebox_override("normal", _sb(Color(0.1, 0.16, 0.18, 0.85), color, 1, 8))
	enemy_status.add_child(lab)


func _feed_line(text: String) -> void:
	var lab := _label(text, 11, Color(0.878, 0.816, 0.667))
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	feed_lines.add_child(lab)


func _icon_button(text: String, action: String, extra: String = "") -> Button:
	var btn := _text_button(text, action, extra)
	btn.custom_minimum_size = Vector2(70, 36)
	return btn


func _action_button(text: String, action: String, extra: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void: act(action, extra))
	return btn


func _text_button(text: String, action: String, extra: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void: act(action, extra))
	return btn


func _label(text: String, size_px: int, color: Color, serif: bool = false) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", size_px)
	lab.add_theme_color_override("font_color", color)
	if serif:
		lab.add_theme_font_override("font", _serif)
	return lab


func _place(parent: Control, node: Control, rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size
	parent.add_child(node)


func _set_fill(fill: Control, ratio: float) -> void:
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	fill.offset_left = 0.0
	fill.offset_top = 0.0
	fill.offset_right = 0.0
	fill.offset_bottom = 0.0


func _sb(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(width)
	box.border_color = border
	box.set_corner_radius_all(radius)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


func show_toast(text: String, seconds: float = 2.3) -> void:
	_toast_gen += 1
	var gen := _toast_gen
	toast_label.text = text
	toast_label.visible = true
	var timer := get_tree().create_timer(seconds)
	timer.timeout.connect(func() -> void:
		if gen == _toast_gen:
			toast_label.visible = false
	)


func hide_toast() -> void:
	_toast_gen += 1
	toast_label.visible = false


func _show_banner(text: String, sub: String) -> void:
	_banner_gen += 1
	var gen := _banner_gen
	banner_title.text = text
	banner_sub.text = sub
	banner.visible = true
	var timer := get_tree().create_timer(1.9)
	timer.timeout.connect(func() -> void:
		if gen == _banner_gen:
			banner.visible = false
	)


func _show_formula(formula: String, sub: String) -> void:
	_reveal_gen += 1
	var gen := _reveal_gen
	formula_reveal_main.text = formula
	formula_reveal_sub.text = sub
	formula_reveal.visible = true
	var timer := get_tree().create_timer(1.1)
	timer.timeout.connect(func() -> void:
		if gen == _reveal_gen:
			formula_reveal.visible = false
	)


func _float_text(pos: Vector2, text: String, color: Color, font_size: int = 28) -> void:
	var lab := Label.new()
	lab.text = text
	lab.modulate = color
	lab.position = pos + Vector2(randf_range(-8, 8), 0)
	lab.add_theme_font_size_override("font_size", font_size)
	lab.add_theme_font_override("font", _serif)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(lab)
	var tw := create_tween()
	tw.tween_property(lab, "position:y", lab.position.y - 52.0, 0.85)
	tw.parallel().tween_property(lab, "modulate:a", 0.0, 0.85)
	tw.finished.connect(lab.queue_free)


func _nudge(node: Control, origin: Vector2, mode: String) -> void:
	if node == null:
		return
	node.position = origin
	var tw := create_tween()
	match mode:
		"hit":
			tw.tween_property(node, "position", origin + Vector2(10, 0), 0.05)
			tw.tween_property(node, "position", origin - Vector2(8, 0), 0.05)
			tw.tween_property(node, "position", origin, 0.08)
		"shoot":
			tw.tween_property(node, "position", origin + Vector2(14, 0), 0.07)
			tw.tween_property(node, "position", origin, 0.12)
		"attack":
			tw.tween_property(node, "position", origin + Vector2(-16, 0), 0.1)
			tw.tween_property(node, "position", origin, 0.16)
		"hurt":
			node.modulate = Color(1.0, 0.62, 0.55)
			tw.tween_property(node, "position", origin + Vector2(-10, 0), 0.06)
			tw.tween_property(node, "position", origin, 0.14)
			tw.parallel().tween_property(node, "modulate", Color.WHITE, 0.45)
		_:
			tw.tween_property(node, "position", origin, 0.01)


func _clear_fx() -> void:
	for child in fx_layer.get_children():
		child.queue_free()
	banner.visible = false
	formula_reveal.visible = false
	hero_root.position = _hero_origin
	hero_root.modulate = Color.WHITE
	enemy_root.position = _enemy_origin
	enemy_root.modulate = Color.WHITE


func _enemy_float_pos() -> Vector2:
	return enemy_root.position + Vector2(enemy_root.size.x * 0.5, 140)


func _fx_color(kind: String) -> Color:
	return FX_COLORS.get(kind, FX_COLORS.gold)


func _signed_amount(amount: int, kind: String) -> String:
	if kind == "heal":
		return "+%d" % amount
	if amount == 0:
		return "0"
	return "−%d" % amount


func _beep(kind: String) -> void:
	if not sound_on or DisplayServer.get_name() == "headless":
		return
	var tones := {
		"select": [530.0, 670.0, 0.04],
		"shot": [170.0, 55.0, 0.16],
		"magic": [500.0, 90.0, 0.24],
		"punch": [130.0, 55.0, 0.08],
		"heal": [340.0, 770.0, 0.28],
		"hurt": [105.0, 40.0, 0.22],
		"window": [430.0, 870.0, 0.26],
		"start": [280.0, 680.0, 0.35],
		"victory": [510.0, 1020.0, 0.45],
	}
	var tone: Array = tones.get(kind, tones.select)
	var sample_rate := 22050
	var duration: float = float(tone[2])
	var frames := maxi(int(sample_rate * duration), 2)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(sample_rate)
		var env := 1.0 - t / duration
		var freq := lerpf(float(tone[0]), float(tone[1]), t / duration)
		var sample := int(clampf(sin(t * freq * TAU) * env * 0.22 * 32767.0, -32767.0, 32767.0))
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		show_toast("当前环境没有提供全屏接口。")
		return
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _random_seed() -> int:
	return (Time.get_ticks_msec() ^ int(Time.get_unix_time_from_system())) & CombatRng.UINT32


func _fmt(n: int) -> String:
	return "−%s" % absi(n) if n < 0 else str(n)


func _live_count(cards: Array) -> int:
	var n := 0
	for card in cards:
		if card != null:
			n += 1
	return n


func _pile_cards() -> Array:
	var s: Dictionary = engine.s
	var cards: Array = []
	if pile_kind == "all":
		for card in s.hand:
			if card != null:
				cards.append(card)
		cards.append_array(s.draw)
		cards.append_array(s.discard)
	else:
		cards = s[pile_kind].duplicate()
	cards.sort_custom(func(a: BattleCard, b: BattleCard) -> bool:
		if a.type != b.type:
			return a.type == "number"
		if a.type == "number":
			return a.value < b.value
		return a.op < b.op
	)
	return cards


func _pile_line(card: BattleCard) -> String:
	if card.type == "operator":
		return "%s　　符号" % card.op
	return "%s　　%s" % [_card_label(card), ELEM_META[card.elem].name]


func _jsonable(value: Variant) -> Variant:
	if value is BattleCard:
		return value.to_dict()
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_jsonable(item))
		return out
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _jsonable(value[key])
		return out
	return value


class TimerRing extends Control:
	var ratio: float = 1.0
	var urgent: bool = false

	func set_ratio(value: float, is_urgent: bool = false) -> void:
		ratio = clampf(value, 0.0, 1.0)
		urgent = is_urgent
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.44
		draw_circle(center, radius, Color(0.067, 0.122, 0.153, 0.7))
		draw_arc(center, radius, 0.0, TAU, 48, Color(0.643, 0.655, 0.545, 0.14), 2.5, true)
		var col := Color(0.88, 0.48, 0.29) if urgent else Color(0.831, 0.718, 0.463)
		if ratio > 0.001:
			draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * ratio, 48, col, 3.2, true)
