class_name CardLab
extends Control
## Separate jam_1.0.0 bench. F5 stays on the collection prototype and F6 card_demo stays v0.3.

const CARD_SCENE := preload("res://scenes/cards/card_view.tscn")
const MARK_ORDER: PackedStringArray = [
	"EN_NUM1", "EN_NUM2", "EN_NUM3", "EN_ECHO", "EN_RETURN", "EN_FRAGILE",
	"EN_ALCHEMY", "EN_MAGNET", "EN_YINYANG", "EN_FLAMMABLE", "EN_SMOLDER",
	"EN_COMBO", "EN_FROZEN", "EN_PRICE", "EN_GHOST", "EN_VANGUARD",
]
const PHASE_NAME := {
	"PLAYER_ACTIVE": "玩家行动",
	"COMBO": "连击窗口",
	"ENEMY": "敌方",
	"VICTORY": "胜利",
	"DEFEAT": "失败",
	"DECK_EXHAUSTED": "牌库耗尽",
	"IDLE": "未开始",
}

var run: RunContext
var formula: Array[String] = []
var selected_uid: String = ""

var _status: Label
var _preview: Label
var _warning: Label
var _log: Label
var _eq_box: HBoxContainer
var _hand_box: HBoxContainer
var _mark_option: OptionButton
var _combo_layer: Control
var _combo_button: Button
var _combo_label: Label
var _signature: String = ""
var _action_seq: int = 0


func _ready() -> void:
	set_process_unhandled_input(true)
	_build()
	_boot()


func _process(delta: float) -> void:
	if run == null or run.battle == null:
		return
	run.battle.advance(delta)
	_refresh_hud()
	_sync_cards()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if run != null and run.battle != null and run.battle.phase == "COMBO":
				_combo_click()
			else:
				_commit()
		KEY_B:
			_burn()
		KEY_E:
			_end_turn()
		KEY_ESCAPE:
			formula.clear()
			_sync_cards(true)
		KEY_R:
			_boot()
		KEY_P:
			if run != null and run.battle != null:
				run.battle.paused = not run.battle.paused


func _boot() -> void:
	formula.clear()
	selected_uid = ""
	_signature = ""
	var catalog := ConfigCatalog.load_default()
	run = RunContext.new(catalog, 20261013, "lab")
	if not catalog.ok():
		_status.text = "配置无法启动：%s" % "；".join(catalog.errors)
		return
	run.library.create_starter()
	run.start_battle(120, 8, true, -1)
	_fill_marks()
	_refresh_hud()
	_sync_cards(true)
	_set_log("牌库已洗好。点选手牌组成变长算式，Enter 提交，B 烧牌，E 结束回合。")


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.06, 0.09)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)
	var title := Label.new()
	title.text = "卡牌实验 · jam_1.0.0    手牌目标 6 · 回合 10 秒 · 这不是 v0.3 战斗 Demo"
	root_box.add_child(title)
	_status = Label.new()
	root_box.add_child(_status)
	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD
	root_box.add_child(_preview)
	root_box.add_child(_section("算式"))
	_eq_box = _scroller(root_box, 176)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	root_box.add_child(buttons)
	_button(buttons, "提交算式", _commit)
	_button(buttons, "烧牌", _burn)
	_button(buttons, "结束回合", _end_turn)
	_button(buttons, "清空算式", func() -> void:
		formula.clear()
		_sync_cards(true)
	)
	_button(buttons, "重开", _boot)
	_warning = Label.new()
	_warning.modulate = Color(0.95, 0.72, 0.45)
	root_box.add_child(_warning)
	root_box.add_child(_section("手牌"))
	_hand_box = _scroller(root_box, 188)
	var debug := HBoxContainer.new()
	debug.add_theme_constant_override("separation", 8)
	root_box.add_child(debug)
	var debug_label := Label.new()
	debug_label.text = "给选中的牌加变化"
	debug.add_child(debug_label)
	_mark_option = OptionButton.new()
	_mark_option.custom_minimum_size = Vector2(220, 0)
	debug.add_child(_mark_option)
	_button(debug, "贴上", _apply_mark)
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD
	root_box.add_child(_log)
	_combo_layer = ColorRect.new()
	_combo_layer.color = Color(0, 0, 0, 0.55)
	_combo_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_combo_layer.visible = false
	_combo_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_combo_layer)
	var combo_box := VBoxContainer.new()
	combo_box.set_anchors_preset(Control.PRESET_CENTER)
	combo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_combo_layer.add_child(combo_box)
	_combo_label = Label.new()
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_box.add_child(_combo_label)
	_combo_button = Button.new()
	_combo_button.text = "连击（每次 1 点，最多每秒 5 下）"
	_combo_button.pressed.connect(_combo_click)
	combo_box.add_child(_combo_button)


func _fill_marks() -> void:
	_mark_option.clear()
	for enh_id in MARK_ORDER:
		var entry := run.catalog.enh(enh_id)
		_mark_option.add_item("%s  %s" % [entry.get("name", enh_id), enh_id])
	_mark_option.select(0)


func _refresh_hud() -> void:
	if run == null or run.battle == null:
		return
	var battle := run.battle
	var phase := str(PHASE_NAME.get(battle.phase, battle.phase))
	if battle.paused:
		phase += " · 暂停"
	_status.text = "回合 %d   %s   时间 %.1f   玩家 %d/%d   假想敌人 %d/%d   固定意图 %d   加法连续 %d" % [
		battle.turn_index, phase, battle.turn_remaining,
		battle.player_hp, battle.player_max_hp,
		battle.enemy_hp, battle.enemy_max_hp, battle.intent_damage, battle.combo_streak,
	]
	_warning.text = _burn_warning()
	var show_combo := battle.phase == "COMBO"
	_combo_layer.visible = show_combo
	if show_combo:
		_combo_label.text = "追击 %.1f / %.1f 秒" % [battle.combo_remaining, battle.combo_window]
	_update_preview()


func _update_preview() -> void:
	if run == null:
		return
	if formula.is_empty():
		_preview.text = "从数字开始，数字和符号交替，3 到 11 张，最后一张是数字。"
		return
	var snap := {}
	if run.battle != null:
		snap = {"tax": 0, "damage_coefficient": 1.0}
	var preview := run.equation_service.preview(formula, snap)
	if not preview.ok:
		_preview.text = "当前算式不能提交：%s" % _reason(str(preview.invalid_reason))
		return
	_preview.text = "预览 %s   结果 %s   伤害 %s%s" % [
		preview.primary_op,
		preview.effective_result,
		preview.damage,
		"   伤害翻倍" if preview.yinyang else "",
	]


func _sync_cards(force: bool = false) -> void:
	if run == null:
		return
	var kept: Array[String] = []
	for card_uid in formula:
		var card := run.library.get_card(card_uid)
		if card != null and card.zone == CardInstance.HAND:
			kept.append(card_uid)
	formula = kept
	var signature := _hand_signature()
	if not force and signature == _signature:
		_paint_highlights()
		return
	_signature = signature
	_rebuild(_eq_box, formula, true)
	_rebuild(_hand_box, run.library.pile(CardInstance.HAND), false)
	_update_preview()


func _rebuild(box: HBoxContainer, uids: Array, equation: bool) -> void:
	for child in box.get_children():
		child.queue_free()
	for card_uid in uids:
		var view := CARD_SCENE.instantiate() as CardView
		box.add_child(view)
		view.bind(run.library, str(card_uid))
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
	selected_uid = card_uid
	if run == null or run.battle == null or run.battle.phase != "PLAYER_ACTIVE":
		_sync_cards(true)
		return
	var card := run.library.get_card(card_uid)
	if card == null or card.zone != CardInstance.HAND:
		_sync_cards(true)
		return
	if formula.has(card_uid):
		formula.erase(card_uid)
	elif not card.is_frozen(run.library.turn_index) and formula.size() < int(run.catalog.rule().max_formula_tokens):
		formula.append(card_uid)
	_sync_cards(true)


func _commit() -> void:
	if run == null or run.battle == null or run.battle.phase != "PLAYER_ACTIVE":
		return
	_action_seq += 1
	var result := run.equation_service.commit(formula, "lab_eq_%d" % _action_seq, {})
	formula.clear()
	if result.get("replayed", false):
		return
	if not result.ok:
		_set_log("没有提交：%s" % _reason(str(result.reason_code)))
	else:
		_set_log("算式伤害 %s，去向已结算。" % result.damage)
	_sync_cards(true)


func _burn() -> void:
	if run == null or selected_uid == "":
		return
	_action_seq += 1
	var result := run.card_service.burn(selected_uid, "lab_burn_%d" % _action_seq)
	formula.erase(selected_uid)
	if result.get("replayed", false):
		return
	if not result.ok:
		_set_log("不能烧牌：%s" % _reason(str(result.reason_code)))
	elif result.smolder_flag:
		_set_log("烧了还留在手里，回复 %s。" % result.heal_delta)
	elif result.no_heal:
		_set_log("牌已消耗，但没有回复生命。")
	else:
		_set_log("烧牌回复 %s。" % result.heal_delta)
	_sync_cards(true)


func _end_turn() -> void:
	if run == null or run.battle == null:
		return
	run.battle.end_player_turn()
	formula.clear()
	_sync_cards(true)


func _combo_click() -> void:
	if run == null or run.battle == null:
		return
	var result := run.battle.combo_click()
	if result.ok:
		_set_log("连击造成 %s 点伤害。" % result.damage)
	_refresh_hud()


func _apply_mark() -> void:
	if run == null or selected_uid == "" or _mark_option.selected < 0:
		_set_log("先点一张牌，再选一种变化。")
		return
	var enh_id := MARK_ORDER[_mark_option.selected]
	_action_seq += 1
	var result := run.card_service.apply_mark(selected_uid, enh_id, "lab_mark_%d" % _action_seq, "DEBUG")
	if not result.ok:
		_set_log("没加上去：%s" % _reason(str(result.reason_code)))
	elif enh_id == "EN_ALCHEMY":
		_set_log("点金手收走了，估价 %s。" % result.value_score)
		if selected_uid == result.card_uid:
			selected_uid = ""
	else:
		_set_log("加上了 %s，牌面 %s。" % [str(run.catalog.enh(enh_id).get("name", enh_id)), result.printed_value])
	_sync_cards(true)


func _burn_warning() -> String:
	if run == null or selected_uid == "":
		return ""
	var card := run.library.get_card(selected_uid)
	if card == null or card.zone != CardInstance.HAND:
		return ""
	var notes := PackedStringArray()
	if card.is_frozen(run.library.turn_index):
		notes.append("这张牌冻住了，可以烧，不能放进算式。")
	if card.kind(run.catalog) == "OP":
		var operators := 0
		for zone in CardInstance.FIGHTING_ZONES:
			for card_uid in run.library.pile(zone):
				var other := run.library.get_card(str(card_uid))
				if other.kind(run.catalog) == "OP":
					operators += 1
		if operators <= 1:
			notes.append("这是最后一张符号牌，烧掉之后可能组不出算式。")
	var raw := 0
	if card.kind(run.catalog) == "NUM":
		raw = int(run.catalog.rule().burn_heal_per_abs) * absi(card.printed_value(run.catalog))
	if raw == 0 or run.battle.player_hp >= run.battle.player_max_hp:
		notes.append("这次烧掉不回血，牌还是会消耗。")
	if card.has_mark("EN_SMOLDER") and not card.smolder_used_run:
		notes.append("这局第一次烧掉回血时，牌会留在手里。")
	return " ".join(notes)


func _hand_signature() -> String:
	var parts := PackedStringArray()
	parts.append(str(run.library.turn_index))
	parts.append(run.battle.phase if run.battle != null else "")
	for card_uid in run.library.pile(CardInstance.HAND):
		var card := run.library.get_card(str(card_uid))
		var marks := PackedStringArray()
		for enh_id in card.enhancement_ids:
			marks.append(enh_id)
		parts.append("%s:%s:%s:%s" % [card.card_uid, card.printed_value(run.catalog), card.is_frozen(run.library.turn_index), "|".join(marks)])
	parts.append("#")
	for card_uid in formula:
		parts.append(card_uid)
	parts.append(selected_uid)
	return "|".join(parts)


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _scroller(parent: Node, height: int) -> HBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


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
		"KIND":
			return "这种变化加不到这种牌上。"
		"FAMILY":
			return "这张牌已经有同类的变化了。"
		"SLOTS":
			return "这张牌的变化已经满了。"
		"BAD_ZONE":
			return "这张牌现在动不了。"
		"MISSING_ENH":
			return "没有这种变化。"
		"SAME_DEF":
			return "不能换成原来那张。"
		_:
			return code
