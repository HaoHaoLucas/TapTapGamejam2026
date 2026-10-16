class_name RunBattle
extends Control
## Hosted jam equation battle. The run shell calls adopt() and waits for returned_to_tower.

const CARD_SCENE := preload("res://scenes/cards/card_view.tscn")
const HERO_TEX := preload("res://assets/battle/hero.png")
const ENEMY_TEX := preload("res://assets/battle/enemy.png")
const DESIGN := Vector2(1440, 900)
const PHASE_NAME := {
	"PLAYER_ACTIVE": "玩家行动",
	"COMBO": "连击窗口",
	"ENEMY": "敌方",
	"VICTORY": "胜利",
	"DEFEAT": "失败",
	"DECK_EXHAUSTED": "牌库耗尽",
	"IDLE": "未开始",
}
## outcome is VICTORY, DEFEAT, or DECK_EXHAUSTED.
signal returned_to_tower(outcome: String)

var session: CombatSession
var formula: Array[String] = []
var selected_uid: String = ""

var _hp_label: Label
var _hp_fill: ColorRect
var _floor_label: Label
var _enemy_name: Label
var _enemy_hp_label: Label
var _enemy_hp_fill: ColorRect
var _intent_label: Label
var _timer_label: Label
var _timer_extra: Label
var _round_label: Label
var _draw_label: Label
var _discard_label: Label
var _hand_caption: Label
var _combo_status: Label
var _combo_dot_a: Panel
var _combo_dot_b: Panel
var _incoming: Label
var _eq_result: Label
var _pause_button: Button
var _preview: Label
var _warning: Label
var _log: Label
var _eq_box: HBoxContainer
var _hand_box: HBoxContainer
var _combo_layer: Control
var _combo_label: Label
var _signature: String = ""
var _action_seq: int = 0
var _reported: bool = false
var _board: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	_apply_theme()
	_build()
	_apply_host_state()
	resized.connect(_fit_board)
	call_deferred("_fit_board")


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_apply_host_state()
		if visible:
			_refresh_hud()
			_sync_cards(true)


func _process(delta: float) -> void:
	if not visible:
		return
	var battle := _battle()
	if battle == null:
		return
	battle.advance(delta)
	_refresh_hud()
	_sync_cards()
	_note_phase()


func _input(event: InputEvent) -> void:
	if not visible or session == null or event is not InputEventKey or not event.pressed or event.echo:
		return
	var acted := true
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _phase() == "COMBO":
				_combo_click()
			else:
				_commit()
		KEY_B:
			_burn()
		KEY_E:
			_end_turn()
		KEY_ESCAPE:
			_clear_selection()
		KEY_P:
			_toggle_pause()
		_:
			acted = false
	if acted:
		get_viewport().set_input_as_handled()


func adopt(session: CombatSession) -> void:
	self.session = session
	formula.clear()
	selected_uid = ""
	_signature = ""
	_action_seq = 0
	_reported = false
	_set_log("组好算式后提交。连击窗口里点击画面。")
	_refresh_hud()
	_sync_cards(true)


func _fit_board() -> void:
	if _board == null:
		return
	var view := size
	if view.x < 8.0 or view.y < 8.0:
		view = get_viewport_rect().size
	if view.x < 8.0 or view.y < 8.0:
		return
	var fitted := minf(view.x / DESIGN.x, view.y / DESIGN.y)
	_board.scale = Vector2(fitted, fitted)
	_board.size = DESIGN
	_board.position = (view - DESIGN * fitted) * 0.5


func _apply_host_state() -> void:
	var active := visible
	set_process(active)
	set_process_input(active)
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	if active:
		_fit_board()


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.027, 0.067, 0.09)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_board = Control.new()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.size = DESIGN
	add_child(_board)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 10)
	_board.add_child(margin)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	column.add_child(_build_topbar())
	column.add_child(_build_stage())
	column.add_child(_build_controls())
	column.add_child(_build_hand())
	var hint := _label("Enter / 空格 提交    B 烧牌    E 结束回合    Esc 清空    P 暂停", 12, Color(0.62, 0.7, 0.66))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	_combo_layer = ColorRect.new()
	_combo_layer.color = Color(0.027, 0.078, 0.114, 0.72)
	_combo_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_combo_layer.visible = false
	_combo_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_combo_layer.gui_input.connect(_on_combo_input)
	add_child(_combo_layer)
	var burst := PanelContainer.new()
	burst.set_anchors_preset(Control.PRESET_CENTER)
	burst.custom_minimum_size = Vector2(320, 180)
	burst.offset_left = -160
	burst.offset_top = -90
	burst.offset_right = 160
	burst.offset_bottom = 90
	burst.add_theme_stylebox_override("panel", _panel_style())
	_combo_layer.add_child(burst)
	var combo_box := VBoxContainer.new()
	combo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	combo_box.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	burst.add_child(pad)
	pad.add_child(combo_box)
	combo_box.add_child(_label("追击", 12, Color(0.82, 0.76, 0.55)))
	_combo_label = _label("追击时刻", 24, Color(0.937, 0.855, 0.678))
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_box.add_child(_combo_label)
	var combo_button := Button.new()
	combo_button.text = "连点追击"
	combo_button.focus_mode = Control.FOCUS_NONE
	combo_button.custom_minimum_size = Vector2(0, 44)
	combo_button.pressed.connect(_combo_click)
	combo_box.add_child(combo_button)


func _build_topbar() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(0, 64)
	bar.add_theme_stylebox_override("panel", _panel_style(Color(0.043, 0.086, 0.125, 0.96), Color(0.55, 0.58, 0.45, 0.35), 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)
	var brand := VBoxContainer.new()
	brand.custom_minimum_size = Vector2(120, 0)
	brand.add_child(_label("涌现", 22, Color(0.91, 0.86, 0.72)))
	brand.add_child(_label("限时对战", 12, Color(0.706, 0.725, 0.655)))
	row.add_child(brand)
	var life := VBoxContainer.new()
	life.custom_minimum_size = Vector2(220, 0)
	life.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var life_row := HBoxContainer.new()
	life_row.add_theme_constant_override("separation", 8)
	life_row.add_child(_label("生命", 13, Color(0.62, 0.7, 0.66)))
	_hp_label = _label("0 / 0", 16, Color(0.91, 0.86, 0.72))
	life_row.add_child(_hp_label)
	life.add_child(life_row)
	_hp_fill = _hp_bar(life, Color(0.72, 0.42, 0.38))
	row.add_child(life)
	_floor_label = _label("", 14, Color(0.82, 0.84, 0.74))
	_floor_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_floor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_floor_label)
	_pause_button = Button.new()
	_pause_button.text = "暂停"
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.custom_minimum_size = Vector2(88, 40)
	_pause_button.pressed.connect(_toggle_pause)
	row.add_child(_pause_button)
	return bar


func _build_stage() -> Control:
	var stage := HBoxContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 16)
	var hero := VBoxContainer.new()
	hero.custom_minimum_size = Vector2(240, 0)
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hero_art := TextureRect.new()
	hero_art.texture = HERO_TEX
	hero_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_art.custom_minimum_size = Vector2(220, 180)
	hero_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(hero_art)
	var hero_name := _label("实验员", 14, Color(0.784, 0.8, 0.718))
	hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(hero_name)
	stage.add_child(hero)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 4)
	center.add_child(_label("每回合 10 秒", 12, Color(0.51, 0.6, 0.565)))
	var title := _label("用算式击败对手", 18, Color(0.824, 0.816, 0.722))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)
	_round_label = _label("第 1 回合", 13, Color(0.72, 0.78, 0.7))
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_round_label)
	_timer_label = _label("10.0", 48, Color(0.91, 0.86, 0.72))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_timer_label)
	_timer_extra = _label("7.5 秒再抽 1 张", 13, Color(0.7, 0.76, 0.68))
	_timer_extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_timer_extra)
	_log = _label("", 14, Color(0.933, 0.835, 0.651))
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_log)
	_warning = _label("", 13, Color(0.95, 0.72, 0.45))
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_warning)
	stage.add_child(center)
	var enemy := VBoxContainer.new()
	enemy.custom_minimum_size = Vector2(280, 0)
	enemy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy.add_theme_constant_override("separation", 4)
	_intent_label = _label("意图", 14, Color(0.91, 0.86, 0.72))
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enemy.add_child(_intent_label)
	var enemy_art := TextureRect.new()
	enemy_art.texture = ENEMY_TEX
	enemy_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	enemy_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	enemy_art.custom_minimum_size = Vector2(240, 160)
	enemy_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy.add_child(enemy_art)
	_enemy_name = _label("敌人", 16, Color(0.82, 0.84, 0.74))
	_enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy.add_child(_enemy_name)
	_enemy_hp_fill = _hp_bar(enemy, Color(0.72, 0.38, 0.36))
	_enemy_hp_label = _label("0 / 0", 13, Color(0.86, 0.84, 0.72))
	_enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy.add_child(_enemy_hp_label)
	stage.add_child(enemy)
	return stage


func _build_controls() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 132)
	var burn := Button.new()
	burn.text = "烧掉回血\n|点数| × 10"
	burn.focus_mode = Control.FOCUS_NONE
	burn.custom_minimum_size = Vector2(150, 64)
	burn.pressed.connect(_burn)
	row.add_child(burn)
	var eq := PanelContainer.new()
	eq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq.add_theme_stylebox_override("panel", _panel_style())
	row.add_child(eq)
	var eq_pad := MarginContainer.new()
	eq_pad.add_theme_constant_override("margin_left", 10)
	eq_pad.add_theme_constant_override("margin_right", 10)
	eq_pad.add_theme_constant_override("margin_top", 6)
	eq_pad.add_theme_constant_override("margin_bottom", 6)
	eq.add_child(eq_pad)
	var eq_box := VBoxContainer.new()
	eq_box.add_theme_constant_override("separation", 4)
	eq_pad.add_child(eq_box)
	var eq_top := HBoxContainer.new()
	var eq_head := _label("算式", 13, Color(0.64, 0.71, 0.65))
	eq_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq_top.add_child(eq_head)
	var clear := Button.new()
	clear.text = "清空"
	clear.focus_mode = Control.FOCUS_NONE
	clear.custom_minimum_size = Vector2(64, 28)
	clear.pressed.connect(_clear_selection)
	eq_top.add_child(clear)
	eq_box.add_child(eq_top)
	var eq_scroll := ScrollContainer.new()
	eq_scroll.custom_minimum_size = Vector2(0, 116)
	eq_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	eq_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	eq_box.add_child(eq_scroll)
	_eq_box = HBoxContainer.new()
	_eq_box.add_theme_constant_override("separation", 8)
	eq_scroll.add_child(_eq_box)
	var eq_bottom := HBoxContainer.new()
	eq_bottom.add_theme_constant_override("separation", 12)
	eq_box.add_child(eq_bottom)
	_preview = _label("从数字开始，数字和符号交替。", 13, Color(0.75, 0.78, 0.7))
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	eq_bottom.add_child(_preview)
	_eq_result = _label("—", 22, Color(0.93, 0.85, 0.62))
	_eq_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	eq_bottom.add_child(_eq_result)
	var fire := Button.new()
	fire.text = "发射  ↵"
	fire.focus_mode = Control.FOCUS_NONE
	fire.custom_minimum_size = Vector2(108, 44)
	fire.pressed.connect(_commit)
	eq_bottom.add_child(fire)
	var combo := VBoxContainer.new()
	combo.custom_minimum_size = Vector2(150, 0)
	combo.alignment = BoxContainer.ALIGNMENT_CENTER
	combo.add_child(_label("加法追击", 12, Color(0.64, 0.71, 0.65)))
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 8)
	combo.add_child(dots)
	_combo_dot_a = _combo_dot()
	_combo_dot_b = _combo_dot()
	dots.add_child(_combo_dot_a)
	dots.add_child(_combo_dot_b)
	_combo_status = _label("两次正数加法可追击\n乘法会打断", 12, Color(0.82, 0.84, 0.74))
	_combo_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combo.add_child(_combo_status)
	row.add_child(combo)
	var end_col := VBoxContainer.new()
	end_col.custom_minimum_size = Vector2(168, 0)
	var end_turn := Button.new()
	end_turn.text = "结束回合\n可提前结束 · E"
	end_turn.focus_mode = Control.FOCUS_NONE
	end_turn.custom_minimum_size = Vector2(168, 56)
	end_turn.pressed.connect(_end_turn)
	end_col.add_child(end_turn)
	_incoming = _label("", 12, Color(0.78, 0.7, 0.58))
	_incoming.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_incoming.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_col.add_child(_incoming)
	row.add_child(end_col)
	return row


func _build_hand() -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	var caption := HBoxContainer.new()
	_hand_caption = _label("手牌 0", 13, Color(0.82, 0.86, 0.78))
	_hand_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_child(_hand_caption)
	var rule := _label("出牌后本回合不补牌", 12, Color(0.62, 0.7, 0.66))
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.add_child(rule)
	block.add_child(caption)
	var zone := HBoxContainer.new()
	zone.add_theme_constant_override("separation", 10)
	block.add_child(zone)
	_draw_label = _pile_label("抽牌堆")
	zone.add_child(_draw_label.get_parent())
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 176)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	zone.add_child(scroll)
	_hand_box = HBoxContainer.new()
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.add_theme_constant_override("separation", 10)
	_hand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_hand_box)
	_discard_label = _pile_label("弃牌堆")
	zone.add_child(_discard_label.get_parent())
	return block


func _refresh_hud() -> void:
	if _enemy_name == null:
		return
	var battle := _battle()
	if battle == null:
		_enemy_name.text = "等待这场战斗。"
		_timer_label.text = ""
		_timer_extra.text = ""
		_hp_label.text = ""
		_warning.text = ""
		if _combo_layer != null:
			_combo_layer.visible = false
		return
	var phase := str(PHASE_NAME.get(battle.phase, battle.phase))
	_enemy_name.text = _monster_title(battle)
	_enemy_hp_label.text = "%d / %d" % [battle.enemy_hp, battle.enemy_max_hp]
	_set_fill(_enemy_hp_fill, float(battle.enemy_hp) / float(maxi(1, battle.enemy_max_hp)))
	var intent := _intent_text(battle)
	var stolen := 0
	if session != null and session.ctx != null:
		stolen = session.ctx.library.pile(CardInstance.STOLEN).size()
	if stolen > 0:
		intent += "    扣押 %d" % stolen
	_intent_label.text = intent
	_incoming.text = intent
	_hp_label.text = "%d / %d" % [battle.player_hp, battle.player_max_hp]
	_set_fill(_hp_fill, float(battle.player_hp) / float(maxi(1, battle.player_max_hp)))
	var depth := 1
	if session != null and session.ctx != null:
		depth = int(session.ctx.depth)
	_floor_label.text = "第 %d 层    第 %d 回合    %s" % [depth, battle.turn_index, phase]
	_round_label.text = "第 %d 回合 · %s" % [battle.turn_index, phase]
	_paint_clock(battle)
	if _pause_button != null:
		_pause_button.text = "继续" if battle.paused else "暂停"
	var library := session.ctx.library
	var hand_count := library.pile(CardInstance.HAND).size()
	_hand_caption.text = "手牌 %d" % hand_count
	_draw_label.text = "抽牌堆\n%d" % library.pile(CardInstance.DRAW).size()
	_discard_label.text = "弃牌堆\n%d" % library.pile(CardInstance.DISCARD).size()
	_warning.text = _burn_warning()
	_paint_combo(battle)
	var show_combo := battle.phase == "COMBO"
	_combo_layer.visible = show_combo
	if show_combo and _combo_label != null:
		_combo_label.text = "追击 %.1f / %.1f 秒" % [battle.combo_remaining, battle.combo_window]
	_update_preview()


func _paint_clock(battle: CardBattle) -> void:
	var urgent := battle.phase == "PLAYER_ACTIVE" and not battle.paused and battle.turn_remaining <= 2.5
	var color := Color(0.95, 0.55, 0.42) if urgent else Color(0.91, 0.86, 0.72)
	if battle.phase == "COMBO":
		_timer_label.text = "%.1f" % battle.combo_remaining
		_timer_extra.text = "追击还剩 %.1f / %.1f 秒" % [battle.combo_remaining, battle.combo_window]
	elif battle.phase == "PLAYER_ACTIVE":
		_timer_label.text = "%.1f" % battle.turn_remaining
		if battle.delayed_draw_done:
			_timer_extra.text = "本回合加抽已处理"
		else:
			var at := float(session.ctx.catalog.rule().get("delayed_draw_at", 7.5))
			var extra := int(session.ctx.catalog.rule().get("delayed_draw_count", 1))
			_timer_extra.text = "%.1f 秒再抽 %d 张" % [at, extra]
	else:
		_timer_label.text = str(PHASE_NAME.get(battle.phase, battle.phase))
		_timer_extra.text = ""
	if battle.paused:
		_timer_extra.text = "暂停" if _timer_extra.text == "" else _timer_extra.text + "    暂停"
	_timer_label.add_theme_color_override("font_color", color)


func _paint_combo(battle: CardBattle) -> void:
	if _combo_dot_a == null or _combo_dot_b == null or _combo_status == null:
		return
	var hot := Color(0.93, 0.82, 0.52)
	var dim := Color(0.35, 0.42, 0.4)
	_combo_dot_a.modulate = hot if battle.combo_streak >= 1 else dim
	_combo_dot_b.modulate = hot if battle.combo_pending or battle.combo_streak >= 2 else dim
	if battle.phase == "COMBO":
		_combo_status.text = "追击 %.1f 秒" % battle.combo_remaining
	elif battle.combo_streak <= 0:
		_combo_status.text = "两次正数加法可追击\n乘法会打断"
	elif battle.combo_pending:
		_combo_status.text = "回合结束后追击\n%.0f 秒" % battle.combo_window
	else:
		_combo_status.text = "再来一次正数加法\n乘法会打断"


func _update_preview() -> void:
	if _preview == null or session == null or session.ctx == null:
		return
	if formula.is_empty():
		_preview.text = "点数字和符号交替组成算式，再发射。"
		if _eq_result != null:
			_eq_result.text = "—"
		return
	var preview := session.ctx.equation_service.preview(formula, _combat_snapshot())
	if not preview.ok:
		_preview.text = "不能提交：%s" % _reason(str(preview.invalid_reason))
		if _eq_result != null:
			_eq_result.text = "—"
		return
	_preview.text = "%s  结果 %s%s" % [
		preview.primary_op,
		preview.effective_result,
		"  伤害翻倍" if preview.yinyang else "",
	]
	if _eq_result != null:
		_eq_result.text = str(preview.damage)


func _sync_cards(force: bool = false) -> void:
	if session == null or session.ctx == null or _hand_box == null:
		return
	var kept: Array[String] = []
	for card_uid in formula:
		var card := session.ctx.library.get_card(card_uid)
		if card != null and card.zone == CardInstance.HAND:
			kept.append(card_uid)
	formula = kept
	var signature := _hand_signature()
	if not force and signature == _signature:
		_paint_highlights()
		return
	_signature = signature
	_rebuild(_eq_box, formula, true)
	_rebuild(_hand_box, session.ctx.library.pile(CardInstance.HAND), false)
	_update_preview()


func _rebuild(box: HBoxContainer, uids: Array, equation: bool) -> void:
	for child in box.get_children():
		child.queue_free()
	for card_uid in uids:
		var view := CARD_SCENE.instantiate() as CardView
		box.add_child(view)
		view.set_compact(equation)
		view.bind(session.ctx.library, str(card_uid))
		view.set_highlight(_mode(str(card_uid), equation))
		view.pressed.connect(_on_card_pressed)


func _paint_highlights() -> void:
	for view in _eq_box.get_children():
		if view is CardView:
			view.set_highlight(_mode(view.card_uid, true))
			view.refresh()
	for view in _hand_box.get_children():
		if view is CardView:
			view.set_highlight(_mode(view.card_uid, false))
			view.refresh()


func _mode(card_uid: String, equation: bool) -> String:
	if equation or formula.has(card_uid):
		return "equation"
	if card_uid == selected_uid:
		return "selected"
	return ""


func _on_card_pressed(card_uid: String) -> void:
	var battle := _battle()
	if battle != null and battle.paused:
		return
	selected_uid = card_uid
	if session == null or battle == null or battle.phase != "PLAYER_ACTIVE":
		_sync_cards(true)
		return
	var card := session.ctx.library.get_card(card_uid)
	if card == null or card.zone != CardInstance.HAND:
		_sync_cards(true)
		return
	if formula.has(card_uid):
		formula.erase(card_uid)
	elif not card.is_frozen(session.ctx.library.turn_index) and formula.size() < int(session.ctx.catalog.rule().max_formula_tokens):
		formula.append(card_uid)
	_sync_cards(true)


func _commit() -> void:
	var battle := _battle()
	if battle != null and battle.paused:
		_set_log("暂停中。")
		return
	if session == null or battle == null or battle.phase != "PLAYER_ACTIVE":
		return
	_action_seq += 1
	var action_uid := "%s_eq_%d" % [session.ctx.run_id, _action_seq]
	var result := session.ctx.equation_service.commit(formula, action_uid, _combat_snapshot())
	formula.clear()
	if result.get("replayed", false):
		_sync_cards(true)
		_note_phase()
		return
	if not result.ok:
		_set_log("没有提交：%s" % _reason(str(result.reason_code)))
	else:
		_set_log("算式伤害 %s。" % result.damage)
	_sync_cards(true)
	_refresh_hud()
	_note_phase()


func _burn() -> void:
	var battle := _battle()
	if battle != null and battle.paused:
		_set_log("暂停中。")
		return
	if session == null or selected_uid == "":
		return
	_action_seq += 1
	var action_uid := "%s_burn_%d" % [session.ctx.run_id, _action_seq]
	var result := session.ctx.card_service.burn(selected_uid, action_uid)
	formula.erase(selected_uid)
	if result.get("replayed", false):
		_sync_cards(true)
		return
	if not result.ok:
		_set_log("不能烧牌：%s" % _reason(str(result.reason_code)))
	elif result.smolder_flag:
		_set_log("烧了还留在手里，回复 %s。" % result.heal_delta)
	elif int(result.heal_delta) == 0:
		_set_log("牌已消耗，但没有回复生命。")
	else:
		_set_log("烧牌回复 %s。" % result.heal_delta)
	_sync_cards(true)
	_refresh_hud()
	_note_phase()


func _end_turn() -> void:
	var battle := _battle()
	if battle == null:
		return
	if battle.paused:
		_set_log("暂停中。")
		return
	battle.end_player_turn()
	formula.clear()
	_sync_cards(true)
	_refresh_hud()
	_note_phase()


func _combo_click() -> void:
	var battle := _battle()
	if battle == null or battle.paused:
		return
	var result := battle.combo_click()
	if result.get("ok", false):
		_set_log("连击造成 %s 点伤害。" % result.get("damage", 0))
	_refresh_hud()
	_note_phase()


func _clear_selection() -> void:
	formula.clear()
	selected_uid = ""
	_sync_cards(true)
	_update_preview()


func _toggle_pause() -> void:
	var battle := _battle()
	if battle == null:
		return
	battle.paused = not battle.paused
	_refresh_hud()


func _on_combo_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_combo_click()
		_combo_layer.accept_event()


func _note_phase() -> void:
	if _reported or session == null or session.ctx == null or session.ctx.battle == null:
		return
	var phase := str(session.ctx.battle.phase)
	if phase != "VICTORY" and phase != "DEFEAT" and phase != "DECK_EXHAUSTED":
		return
	_reported = true
	returned_to_tower.emit(phase)


func _combat_snapshot() -> Dictionary:
	var battle := _battle()
	if battle == null:
		return {}
	if battle.has_method("combat_snapshot"):
		var snap = battle.call("combat_snapshot")
		if snap is Dictionary:
			return snap
	if "combat_snapshot" in battle and battle.combat_snapshot is Dictionary:
		return battle.combat_snapshot
	return {}


func _monster_title(battle: CardBattle) -> String:
	if "monster_name" in battle and str(battle.monster_name) != "":
		return str(battle.monster_name)
	if "enemy_name" in battle and str(battle.enemy_name) != "":
		return str(battle.enemy_name)
	if session != null and session.monster_name != "":
		return session.monster_name
	return "敌人"


func _intent_text(battle: CardBattle) -> String:
	var info: Dictionary = battle.intent if battle.intent is Dictionary else {}
	if info.is_empty():
		return "攻击 %d" % int(battle.intent_damage)
	var action := str(info.get("action", "STRIKE"))
	var verb := "攻击"
	if action == "SLASH":
		verb = "斩击"
	elif action == "CHARGE":
		verb = "打断" if float(info.get("action_mul", 1.0)) < 1.0 else "蓄力"
	var text := "%s %d" % [verb, int(info.get("damage", battle.intent_damage))]
	var heal := int(info.get("heal", 0))
	if heal > 0:
		text += "，治疗 %d" % heal
	match str(info.get("parity", "")):
		"ODD":
			text += "，奇数"
		"EVEN":
			text += "，偶数"
	match str(info.get("tax_op", "")):
		"ADD":
			text += "，加法减 2"
		"MUL":
			text += "，乘法减 2"
	return text


func _card_kind(card: CardInstance) -> String:
	return str(session.ctx.catalog.card(card.def_id).get("card_kind", ""))


func _burn_warning() -> String:
	if session == null or session.ctx == null or selected_uid == "":
		return ""
	var card := session.ctx.library.get_card(selected_uid)
	if card == null or card.zone != CardInstance.HAND:
		return ""
	var battle := _battle()
	var notes := PackedStringArray()
	if card.is_frozen(session.ctx.library.turn_index):
		notes.append("这张牌冻住了，可以烧，不能放进算式。")
	if _card_kind(card) == "OP":
		var operators := 0
		for zone in [CardInstance.HAND, CardInstance.DRAW, CardInstance.DISCARD, CardInstance.RESOLVING]:
			for card_uid in session.ctx.library.pile(zone):
				var other := session.ctx.library.get_card(str(card_uid))
				if other != null and _card_kind(other) == "OP":
					operators += 1
		if operators <= 1:
			notes.append("这是最后一张符号牌，烧掉之后可能组不出算式。")
	var raw := 0
	if _card_kind(card) == "NUM":
		raw = int(session.ctx.catalog.rule().burn_heal_per_abs) * absi(card.printed_value(session.ctx.catalog))
	if battle != null and (raw == 0 or battle.player_hp >= battle.player_max_hp):
		notes.append("这次烧掉不回血，牌还是会消耗。")
	if card.has_mark("EN_SMOLDER") and not card.smolder_used_run:
		notes.append("这局第一次烧掉回血时，牌会留在手里。")
	return " ".join(notes)


func _hand_signature() -> String:
	var parts := PackedStringArray()
	var battle := _battle()
	parts.append(str(session.ctx.library.turn_index))
	parts.append("" if battle == null else battle.phase)
	for card_uid in session.ctx.library.pile(CardInstance.HAND):
		var card := session.ctx.library.get_card(str(card_uid))
		if card == null:
			continue
		var marks := PackedStringArray()
		for enh_id in card.enhancement_ids:
			marks.append(str(enh_id))
		var frozen := card.is_frozen(session.ctx.library.turn_index)
		parts.append("%s:%s:%s:%s" % [card.card_uid, card.printed_value(session.ctx.catalog), frozen, "|".join(marks)])
	parts.append("#")
	for card_uid in formula:
		parts.append(card_uid)
	parts.append(selected_uid)
	return "|".join(parts)


func _battle() -> CardBattle:
	if session == null or session.ctx == null:
		return null
	return session.ctx.battle


func _phase() -> String:
	var battle := _battle()
	return "" if battle == null else str(battle.phase)


func _apply_theme() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	var ui := Theme.new()
	ui.default_font = font
	ui.default_font_size = 15
	var normal := _panel_style(Color(0.12, 0.2, 0.22, 0.94), Color(0.71, 0.63, 0.42, 0.7), 4)
	var hover := _panel_style(Color(0.22, 0.32, 0.33), Color(0.85, 0.76, 0.52, 0.8), 4)
	var pressed := _panel_style(Color(0.1, 0.16, 0.18), Color(0.85, 0.76, 0.52), 4)
	ui.set_stylebox("normal", "Button", normal)
	ui.set_stylebox("hover", "Button", hover)
	ui.set_stylebox("pressed", "Button", pressed)
	ui.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	ui.set_color("font_color", "Button", Color(0.91, 0.86, 0.72))
	ui.set_color("font_hover_color", "Button", Color(0.97, 0.93, 0.82))
	theme = ui


func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label


func _panel_style(bg: Color = Color(0.125, 0.2, 0.22, 0.94), border: Color = Color(0.71, 0.63, 0.42, 0.53), radius: int = 7) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(1)
	box.border_color = border
	box.set_corner_radius_all(radius)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


func _hp_bar(parent: Node, color: Color) -> ColorRect:
	var track := ColorRect.new()
	track.color = Color(0.12, 0.18, 0.2)
	track.custom_minimum_size = Vector2(160, 8)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(track)
	var fill := ColorRect.new()
	fill.color = color
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	return fill


func _set_fill(fill: ColorRect, ratio: float) -> void:
	if fill == null:
		return
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(ratio, 0.0, 1.0)
	fill.offset_left = 0.0
	fill.offset_top = 0.0
	fill.offset_right = 0.0
	fill.offset_bottom = 0.0


func _pile_label(title: String) -> Label:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(96, 120)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.17, 0.26, 0.255), Color(0.55, 0.58, 0.42, 0.53), 4))
	var label := _label("%s\n0" % title, 14, Color(0.86, 0.84, 0.72))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return label


func _combo_dot() -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(16, 16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.93, 0.82, 0.52)
	style.set_corner_radius_all(8)
	dot.add_theme_stylebox_override("panel", style)
	dot.modulate = Color(0.35, 0.42, 0.4)
	return dot


func _set_log(text: String) -> void:
	if _log != null:
		_log.text = text


func _reason(code: String) -> String:
	match code:
		"LENGTH":
			return "长度要是 3 到 11 的奇数。"
		"ALTERNATION":
			return "数字和符号要交替，开头和结尾都是数字。"
		"DUPLICATE_UID":
			return "同一张牌不能用两次。"
		"NOT_IN_HAND":
			return "这张牌不在手里。"
		"FROZEN":
			return "这张牌还冻着。"
		"PHASE":
			return "现在不能操作。"
		"TIME":
			return "这回合的时间用完了。"
		"BAD_ZONE":
			return "这张牌现在动不了。"
		"ZONE":
			return "这张牌现在动不了。"
		_:
			return code
