class_name RunBattle
extends Control
## Hosted jam equation battle. The run shell calls adopt() and waits for returned_to_tower.

const CARD_SCENE := preload("res://scenes/cards/card_view.tscn")
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

var _monster: Label
var _clock: Label
var _player: Label
var _piles: Label
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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	_build()
	_apply_host_state()


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


func _apply_host_state() -> void:
	var active := visible
	set_process(active)
	set_process_input(active)
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.04, 0.06, 0.09)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)
	var title := Label.new()
	title.text = "战斗    Enter 提交 · 空格同提交 · B 烧牌 · E 结束回合 · Esc 清空 · P 暂停"
	root_box.add_child(title)
	_monster = Label.new()
	_monster.add_theme_font_size_override("font_size", 22)
	_monster.add_theme_color_override("font_color", Color(0.93, 0.86, 0.68))
	root_box.add_child(_monster)
	_clock = Label.new()
	_clock.add_theme_font_size_override("font_size", 28)
	_clock.add_theme_color_override("font_color", Color(0.93, 0.86, 0.68))
	root_box.add_child(_clock)
	_player = Label.new()
	root_box.add_child(_player)
	_piles = Label.new()
	_piles.add_theme_color_override("font_color", Color(0.78, 0.82, 0.74))
	root_box.add_child(_piles)
	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(_preview)
	root_box.add_child(_section("算式"))
	_eq_box = _scroller(root_box, 176, false)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	root_box.add_child(buttons)
	_button(buttons, "提交算式", _commit)
	_button(buttons, "烧牌", _burn)
	_button(buttons, "结束回合", _end_turn)
	_button(buttons, "清空", _clear_selection)
	_button(buttons, "暂停", _toggle_pause)
	_warning = Label.new()
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.add_theme_color_override("font_color", Color(0.95, 0.72, 0.45))
	root_box.add_child(_warning)
	root_box.add_child(_section("手牌"))
	_hand_box = _scroller(root_box, 188, true)
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(_log)
	_combo_layer = ColorRect.new()
	_combo_layer.color = Color(0, 0, 0, 0.55)
	_combo_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_combo_layer.visible = false
	_combo_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_combo_layer.gui_input.connect(_on_combo_input)
	add_child(_combo_layer)
	var combo_box := VBoxContainer.new()
	combo_box.set_anchors_preset(Control.PRESET_CENTER)
	combo_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_combo_layer.add_child(combo_box)
	_combo_label = Label.new()
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_box.add_child(_combo_label)
	var combo_button := Button.new()
	combo_button.text = "连击"
	combo_button.focus_mode = Control.FOCUS_NONE
	combo_button.pressed.connect(_combo_click)
	combo_box.add_child(combo_button)


func _refresh_hud() -> void:
	if _monster == null:
		return
	var battle := _battle()
	if battle == null:
		_monster.text = "等待这场战斗。"
		_clock.text = ""
		_player.text = ""
		_piles.text = ""
		_warning.text = ""
		if _combo_layer != null:
			_combo_layer.visible = false
		return
	_monster.text = "%s    生命 %d/%d    意图 %s" % [
		_monster_title(battle), battle.enemy_hp, battle.enemy_max_hp, _intent_text(battle),
	]
	_clock.text = _clock_text(battle)
	var urgent := battle.phase == "PLAYER_ACTIVE" and not battle.paused and battle.turn_remaining <= 2.5
	_clock.add_theme_color_override("font_color", Color(0.95, 0.55, 0.42) if urgent else Color(0.93, 0.86, 0.68))
	var phase := str(PHASE_NAME.get(battle.phase, battle.phase))
	_player.text = "你的生命 %d/%d    回合 %d    %s" % [battle.player_hp, battle.player_max_hp, battle.turn_index, phase]
	var library := session.ctx.library
	_piles.text = "抽牌 %d    弃牌 %d    扣押 %d" % [
		library.pile(CardInstance.DRAW).size(),
		library.pile(CardInstance.DISCARD).size(),
		library.pile(CardInstance.STOLEN).size(),
	]
	_warning.text = _burn_warning()
	var show_combo := battle.phase == "COMBO"
	_combo_layer.visible = show_combo
	if show_combo:
		_combo_label.text = "追击 %.1f / %.1f 秒，点击任意处" % [battle.combo_remaining, battle.combo_window]
	_update_preview()


func _clock_text(battle: CardBattle) -> String:
	var text := ""
	if battle.phase == "COMBO":
		text = "连击 %.1f / %.1f 秒" % [battle.combo_remaining, battle.combo_window]
	elif battle.phase == "PLAYER_ACTIVE":
		var total := float(session.ctx.catalog.rule().get("turn_seconds", 10))
		text = "剩余 %.1f / %.0f 秒" % [battle.turn_remaining, total]
		if battle.delayed_draw_done:
			text += "    本回合加抽已处理"
		else:
			var at := float(session.ctx.catalog.rule().get("delayed_draw_at", 7.5))
			var extra := int(session.ctx.catalog.rule().get("delayed_draw_count", 1))
			text += "    %.1f 秒再抽 %d 张" % [at, extra]
	else:
		text = str(PHASE_NAME.get(battle.phase, battle.phase))
	if battle.paused:
		text += "    暂停"
	return text


func _update_preview() -> void:
	if _preview == null or session == null or session.ctx == null:
		return
	if formula.is_empty():
		_preview.text = "从数字开始，数字和符号交替，3 到 11 张，最后一张是数字。"
		return
	var preview := session.ctx.equation_service.preview(formula, _combat_snapshot())
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


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _scroller(parent: Node, height: int, expand: bool) -> HBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if expand:
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
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
		"BAD_ZONE":
			return "这张牌现在动不了。"
		"ZONE":
			return "这张牌现在动不了。"
		_:
			return code
