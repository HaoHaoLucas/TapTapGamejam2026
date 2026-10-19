class_name RunBattle
extends Control
## Hosted jam equation battle. The run shell calls adopt() and waits for returned_to_tower.

const CARD_SCENE := preload("res://scenes/cards/card_view.tscn")
const HERO_TEX := preload("res://assets/battle/hero.png")
const ENEMY_TEX := preload("res://assets/battle/enemy.png")
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

var _signature: String = ""
var _action_seq: int = 0
var _reported: bool = false
var _ready_done: bool = false

@onready var _board: Control = $Board
@onready var _hp_label: Label = $Board/Margin/Column/TopBar/Row/Life/Row/HpValue
@onready var _hp_fill: ColorRect = $Board/Margin/Column/TopBar/Row/Life/Track/Fill
@onready var _floor_label: Label = $Board/Margin/Column/TopBar/Row/Floor
@onready var _pause_button: Button = $Board/Margin/Column/TopBar/Row/PauseButton
@onready var _intent_label: Label = $Board/Margin/Column/Stage/Enemy/Intent
@onready var _enemy_name: Label = $Board/Margin/Column/Stage/Enemy/Name
@onready var _enemy_hp_fill: ColorRect = $Board/Margin/Column/Stage/Enemy/Track/Fill
@onready var _enemy_hp_label: Label = $Board/Margin/Column/Stage/Enemy/HpValue
@onready var _enemy_art: Control = $Board/Margin/Column/Stage/Enemy/EnemyArt
@onready var _round_label: Label = $Board/Margin/Column/Stage/Center/Round
@onready var _timer_label: Label = $Board/Margin/Column/Stage/Center/Timer
@onready var _timer_extra: Label = $Board/Margin/Column/Stage/Center/TimerExtra
@onready var _log: Label = $Board/Margin/Column/Stage/Center/Log
@onready var _warning: Label = $Board/Margin/Column/Stage/Center/Warning
@onready var _eq_box: HBoxContainer = $Board/Margin/Column/Controls/Equation/Pad/Box/Scroll/EqRow
@onready var _preview: Label = $Board/Margin/Column/Controls/Equation/Pad/Box/Bottom/Preview
@onready var _eq_result: Label = $Board/Margin/Column/Controls/Equation/Pad/Box/Bottom/Result
@onready var _combo_dot_a: Panel = $Board/Margin/Column/Controls/Combo/Dots/A
@onready var _combo_dot_b: Panel = $Board/Margin/Column/Controls/Combo/Dots/B
@onready var _combo_status: Label = $Board/Margin/Column/Controls/Combo/Status
@onready var _incoming: Label = $Board/Margin/Column/Controls/End/Incoming
@onready var _hand_caption: Label = $Hand/Caption/Count
@onready var _draw_label: Label = $Hand/Zone/DrawPile/DrawLabel
@onready var _hand_box: HBoxContainer = $Hand/Zone/Scroll/HandRow
@onready var _discard_label: Label = $Hand/Zone/DiscardPile/DiscardLabel
@onready var _combo_layer: Control = $ComboLayer
@onready var _combo_label: Label = $ComboLayer/Burst/Pad/Box/Time


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	_ready_done = true
	_apply_host_state()


func _notification(what: int) -> void:
	if not _ready_done:
		return
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


func _refresh_hud() -> void:
	assert(_enemy_name != null, "RunBattle: $...Enemy/Name 丢了")
	var battle := _battle()
	if battle == null:
		_enemy_name.text = "等待这场战斗。"
		_enemy_art.show_monster("")
		_timer_label.text = ""
		_timer_extra.text = ""
		_hp_label.text = ""
		_warning.text = ""
		if _combo_layer != null:
			_combo_layer.visible = false
		return
	var phase := str(PHASE_NAME.get(battle.phase, battle.phase))
	_enemy_name.text = _monster_title(battle)
	_enemy_art.show_monster(str(battle.monster_id))
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
	assert(_combo_dot_a != null and _combo_dot_b != null and _combo_status != null, "RunBattle: 连击指示点丢了")
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
	assert(_hand_box != null, "RunBattle: $...Hand/Zone/Scroll/HandRow 丢了")
	if session == null or session.ctx == null:
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
