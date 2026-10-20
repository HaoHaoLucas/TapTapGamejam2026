class_name RunBattle
extends Control
## Hosted jam equation battle. The run shell calls adopt() and waits for returned_to_tower.

const CHROME := preload("res://scripts/run/battle_chrome.gd")
const MONSTERS := preload("res://scripts/run/monster_presenter.gd")
const MONSTER_TOOLTIP := preload("res://scripts/run/monster_tooltip.gd")
const PREPARE_SECONDS := 5.0
const VICTORY_SECONDS := 2.0
const DEFEAT_SECONDS := 2.0
enum Presentation { PREPARING, ACTIVE, VICTORY_PRESENTATION, DEFEAT_PRESENTATION, REPORTED }

const CARD_SCENE := preload("res://scenes/cards/card_view.tscn")
const HERO_TEX := preload("res://assets/battle/imported/battle_human_.png")
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

var presentation := Presentation.PREPARING
var presentation_remaining := PREPARE_SECONDS
var _log_remaining := 0.0

var _signature: String = ""
var _action_seq: int = 0
var _reported: bool = false
var _ready_done: bool = false
var _external_input_blocked: bool = false
var _loss_outcome := "DEFEAT"
var _timer_bar: TextureProgressBar
@onready var _hero: TextureRect = $Board/Margin/Column/Stage/Player/TextureRect

@onready var _preparation: PanelContainer = $Board/Margin/Column/Stage/Center/Preparation
@onready var _prepare_name: Label = $Board/Margin/Column/Stage/Center/Preparation/Box/Name
@onready var _prepare_trait: Label = $Board/Margin/Column/Stage/Center/Preparation/Box/Trait
@onready var _prepare_intent: Label = $Board/Margin/Column/Stage/Center/Preparation/Box/Intent
@onready var _trait: Label = $Board/Margin/Column/Stage/Enemy/Trait
@onready var _victory: Control = $VictoryLayer
@onready var _board: Control = $Board
@onready var _hp_label: Label = $Board/Margin/Column/Stage/Player/TextureRect/Life/Row/HpValue
@onready var _hp_bar: TextureProgressBar = $Board/Margin/Column/Stage/Player/TextureRect/Life/Bar
@onready var _floor_label: Label = $Board/Margin/Column/TopBar/Row/Floor
@onready var _intent_label: Label = $Board/Margin/Column/Stage/Enemy/Intent
@onready var _enemy_name: Label = $Board/Margin/Column/Stage/Enemy/Name
@onready var _enemy_hp_bar: TextureProgressBar = $Board/Margin/Column/Stage/Enemy/EnemyArt/Health/Bar
@onready var _enemy_hp_label: Label = $Board/Margin/Column/Stage/Enemy/EnemyArt/Health/HpValue
@onready var _enemy_art: Control = $Board/Margin/Column/Stage/Enemy/EnemyArt
@onready var _round_label: Label = $Board/Margin/Column/Stage/Center/Round
@onready var _timer_label: Label = $Board/Margin/Column/TopBar/Clock/Timer
@onready var _timer_extra: Label = $Board/Margin/Column/TopBar/Clock/TimerExtra
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
	_apply_chrome()
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
	if not is_visible_in_tree() or get_tree().paused:
		return
	var battle := _battle()
	if battle == null:
		return
	_note_phase()
	if _reported:
		return
	if not battle.paused and not _external_input_blocked:
		_enemy_art.advance(delta)
		if presentation == Presentation.PREPARING:
			presentation_remaining = maxf(0.0, presentation_remaining - delta)
			if presentation_remaining <= 0.000001:
				presentation = Presentation.ACTIVE
				# The opening turn starts next frame, with its entire time budget.
		elif presentation == Presentation.VICTORY_PRESENTATION:
			presentation_remaining = maxf(0.0, presentation_remaining - delta)
			if presentation_remaining <= 0.000001:
				_report_outcome("VICTORY")
				return
		elif presentation == Presentation.DEFEAT_PRESENTATION:
			presentation_remaining = maxf(0.0, presentation_remaining - delta)
			_hero.texture = BattleAssets.texture("battle_human_die" if presentation_remaining > 1.0 else "battle_human_die2")
			if presentation_remaining <= 0.000001:
				_report_outcome(_loss_outcome)
				return
		elif presentation == Presentation.ACTIVE:
			battle.advance(delta)
		_log_remaining = maxf(0.0, _log_remaining - delta)
		if _log_remaining <= 0.0:
			_log.text = ""
	_refresh_hud()
	_position_actor_health()
	_sync_cards()
	_note_phase()


func set_external_input_blocked(blocked: bool) -> void:
	_external_input_blocked = blocked


func _input(event: InputEvent) -> void:
	if _external_input_blocked or presentation != Presentation.ACTIVE:
		return
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
	presentation = Presentation.PREPARING
	presentation_remaining = PREPARE_SECONDS
	_external_input_blocked = false
	_loss_outcome = "DEFEAT"
	_hero.texture = HERO_TEX
	_enemy_art.adopt_battle(session.ctx.battle)
	_enemy_art.modulate = Color.WHITE
	_victory.hide()
	_set_log("")
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
	_enemy_name.text = _monster_title(battle)
	_enemy_art.refresh(battle)
	_enemy_hp_label.text = "%d / %d" % [battle.enemy_hp, battle.enemy_max_hp]
	_set_bar(_enemy_hp_bar, battle.enemy_hp, battle.enemy_max_hp)
	var intent := _intent_text(battle)
	var stolen := 0
	if session != null and session.ctx != null:
		stolen = session.ctx.library.pile(CardInstance.STOLEN).size()
	if stolen > 0:
		intent += "    扣押 %d" % stolen
	_intent_label.text = intent
	_incoming.text = ""
	_hp_label.text = "%d / %d" % [battle.player_hp, battle.player_max_hp]
	_set_bar(_hp_bar, battle.player_hp, battle.player_max_hp)
	var depth := 1
	if session != null and session.ctx != null:
		depth = int(session.ctx.depth)
	_floor_label.text = "第 %d 层    第 %d 回合" % [depth, battle.turn_index]
	_round_label.text = "追击" if battle.phase == "COMBO" else ""
	var description := MONSTERS.describe(battle)
	_trait.text = description.summary
	var inspecting := presentation in [Presentation.PREPARING, Presentation.ACTIVE]
	for target in [_trait, _enemy_name]:
		target.tooltip_text = description.tooltip if inspecting else ""
	_prepare_name.text = _monster_title(battle)
	_prepare_trait.text = description.summary
	_prepare_trait.tooltip_text = description.tooltip if inspecting else ""
	_prepare_intent.text = "首回合：" + intent
	_preparation.visible = presentation == Presentation.PREPARING
	_victory.visible = presentation == Presentation.VICTORY_PRESENTATION
	_update_action_states()
	_paint_clock(battle)
	var library := session.ctx.library
	var hand_count := library.pile(CardInstance.HAND).size()
	_hand_caption.text = "手牌 %d" % hand_count
	_draw_label.text = "抽牌堆 %d" % library.pile(CardInstance.DRAW).size()
	_discard_label.text = "弃牌堆 %d" % library.pile(CardInstance.DISCARD).size()
	$Hand/Zone/DrawPile/Backdrop.modulate.a = 0.45 if library.pile(CardInstance.DRAW).is_empty() else 1.0
	$Hand/Zone/DiscardPile/Backdrop.modulate.a = 0.45 if library.pile(CardInstance.DISCARD).is_empty() else 1.0
	_warning.text = _burn_warning()
	_paint_combo(battle)
	var show_combo := battle.phase == "COMBO" and presentation == Presentation.ACTIVE
	_combo_layer.visible = show_combo
	if show_combo and _combo_label != null:
		_combo_label.text = "追击 %.1f / %.1f 秒" % [battle.combo_remaining, battle.combo_window]
	_update_preview()


func _paint_clock(battle: CardBattle) -> void:
	var urgent := battle.phase == "PLAYER_ACTIVE" and not battle.paused and battle.turn_remaining <= 2.5
	var color := Color(0.65, 0.16, 0.12) if urgent else CHROME.INK
	_timer_extra.text = ""
	if _timer_bar != null:
		_timer_bar.max_value = PREPARE_SECONDS if presentation == Presentation.PREPARING else (battle.combo_window if battle.phase == "COMBO" else float(session.ctx.catalog.rule().get("turn_seconds", 10.0)))
		_timer_bar.value = presentation_remaining if presentation == Presentation.PREPARING else (battle.combo_remaining if battle.phase == "COMBO" else battle.turn_remaining)
		_timer_bar.visible = presentation in [Presentation.PREPARING, Presentation.ACTIVE]
	if presentation == Presentation.PREPARING:
		_timer_label.text = str(ceili(presentation_remaining))
		_timer_extra.text = "秒后开战"
	elif presentation in [Presentation.VICTORY_PRESENTATION, Presentation.DEFEAT_PRESENTATION]:
		_timer_label.text = ""
	elif battle.phase in ["COMBO", "PLAYER_ACTIVE"]:
		_timer_label.text = "%.1f" % (battle.combo_remaining if battle.phase == "COMBO" else battle.turn_remaining)
	else:
		_timer_label.text = str(PHASE_NAME.get(battle.phase, battle.phase))
	if battle.paused:
		_timer_extra.text = "暂停" if _timer_extra.text == "" else _timer_extra.text + "    暂停"
	_timer_label.add_theme_color_override("font_color", color)


func _paint_combo(battle: CardBattle) -> void:
	assert(_combo_dot_a != null and _combo_dot_b != null and _combo_status != null, "RunBattle: 连击指示点丢了")
	var hot := Color(0.88, 0.9, 1.0)
	var dim := Color(0.3, 0.32, 0.42)
	_combo_dot_a.modulate = hot if battle.combo_streak >= 1 else dim
	_combo_dot_b.modulate = hot if battle.combo_pending or battle.combo_streak >= 2 else dim
	if battle.phase == "COMBO":
		_combo_status.text = "追击 %.1f 秒" % battle.combo_remaining
	elif battle.combo_streak <= 0:
		_combo_status.text = "0 / 2"
	elif battle.combo_pending:
		_combo_status.text = "就绪 · %.0f 秒" % battle.combo_window
	else:
		_combo_status.text = "1 / 2"


func _update_preview() -> void:
	if _preview == null or session == null or session.ctx == null:
		return
	if formula.is_empty():
		_preview.text = "组合算式"
		if _eq_result != null:
			_eq_result.text = "—"
		return
	var preview := session.ctx.equation_service.preview(formula, _combat_snapshot())
	if not preview.ok:
		_preview.text = _reason(str(preview.invalid_reason))
		if _eq_result != null:
			_eq_result.text = "—"
		return
	_preview.text = "预计伤害" + (" · 翻倍" if preview.yinyang else "")
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
	if not _can_act() or _phase() != "PLAYER_ACTIVE":
		return
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
	if not _can_act() or _phase() != "PLAYER_ACTIVE":
		return
	if formula.is_empty():
		return
	var battle := _battle()
	if battle != null and battle.paused:
		_set_log("暂停中。")
		return
	if session == null or battle == null or battle.phase != "PLAYER_ACTIVE":
		return
	# An incomplete selection stays in place so the player can finish it.
	if not session.ctx.equation_service.preview(formula, _combat_snapshot()).ok:
		_update_preview()
		return
	_action_seq += 1
	var action_uid := "%s_eq_%d" % [session.ctx.run_id, _action_seq]
	var result := session.ctx.equation_service.commit(formula, action_uid, _combat_snapshot())
	if result.ok:
		formula.clear()
	if result.get("replayed", false):
		_sync_cards(true)
		_note_phase()
		return
	if not result.ok:
		_set_log(_reason(str(result.reason_code)))
	else:
		_set_log("算式伤害 %s。" % result.damage)
	_sync_cards(true)
	_refresh_hud()
	_note_phase()


func _burn() -> void:
	if not _can_act() or _phase() != "PLAYER_ACTIVE":
		return
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
	if not _can_act() or _phase() != "PLAYER_ACTIVE":
		return
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
	if not _can_act():
		return
	var battle := _battle()
	if battle == null or battle.paused:
		return
	var result := battle.combo_click()
	if result.get("ok", false):
		_set_log("连击造成 %s 点伤害。" % result.get("damage", 0))
	_refresh_hud()
	_note_phase()


func _clear_selection() -> void:
	if not _can_act() or _phase() != "PLAYER_ACTIVE":
		return
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
	if phase == "VICTORY":
		if presentation != Presentation.VICTORY_PRESENTATION:
			presentation = Presentation.VICTORY_PRESENTATION
			presentation_remaining = VICTORY_SECONDS
			_enemy_art.play_death(session.ctx.battle)
			_combo_layer.hide()
			_preparation.hide()
			_victory.show()
			_log.text = ""
			_warning.text = ""
			_trait.tooltip_text = ""
			_enemy_name.tooltip_text = ""
			_prepare_trait.tooltip_text = ""
			_update_action_states()
		return
	if session.ctx.battle.player_hp <= 0:
		if presentation != Presentation.DEFEAT_PRESENTATION:
			presentation = Presentation.DEFEAT_PRESENTATION
			presentation_remaining = DEFEAT_SECONDS
			_loss_outcome = phase
			_hero.texture = BattleAssets.texture("battle_human_die")
			_combo_layer.hide()
			_preparation.hide()
			_update_action_states()
		return
	_report_outcome(phase)


func _report_outcome(phase: String) -> void:
	if _reported:
		return
	_reported = true
	presentation = Presentation.REPORTED
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
	if heal > 0 and not battle.priest_heal_cancelled:
		text += "，治疗 %d" % heal
	match str(info.get("parity", "")):
		"ODD":
			text += "，奇数"
		"EVEN":
			text += "，偶数"
	match "" if battle.ink_tax_used else str(info.get("tax_mode", "")):
		"HALVE":
			text += "，首式 ÷2"
		"MUL_SUBTRACT":
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


func _set_bar(bar: TextureProgressBar, value: int, max_value: int) -> void:
	if bar == null:
		return
	bar.max_value = maxf(1.0, float(max_value))
	bar.value = clampf(float(value), 0.0, bar.max_value)


func _set_log(text: String) -> void:
	_log_remaining = 2.0 if text != "" else 0.0
	if _log != null:
		_log.text = text


func _reason(code: String) -> String:
	match code:
		"LENGTH":
			return "请按「数字 → 符号 → 数字」补全算式"
		"ALTERNATION":
			return "数字与符号交替，首尾放数字"
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


func _can_act() -> bool:
	var battle := _battle()
	return is_visible_in_tree() and not get_tree().paused and not _external_input_blocked and presentation == Presentation.ACTIVE and battle != null and not battle.paused and battle.phase in ["PLAYER_ACTIVE", "COMBO"]


func _update_action_states() -> void:
	var active := _can_act()
	var player := active and _phase() == "PLAYER_ACTIVE"
	$Board/Margin/Column/Controls/Button.disabled = not player or selected_uid == ""
	$Board/Margin/Column/Controls/Equation/Pad/Box/HBoxContainer/Button.disabled = not player or formula.is_empty()
	var legal := player and not formula.is_empty() and bool(session.ctx.equation_service.preview(formula, _combat_snapshot()).ok)
	$Board/Margin/Column/Controls/FireButton.disabled = not legal
	$Board/Margin/Column/Controls/End/Button.disabled = not player
	for button in [$Board/Margin/Column/Controls/FireButton, $Board/Margin/Column/Controls/End/Button]:
		_paint_art_button(button)
	$ComboLayer/Burst/Pad/Box/Button.disabled = not active or _phase() != "COMBO"


func _apply_chrome() -> void:
	theme = CHROME.make_theme(20)
	# Keep the arena clear of monster names and descriptive captions.
	_enemy_name.hide()
	_prepare_name.hide()
	_intent_label.hide()
	_prepare_intent.hide()
	_trait.hide()
	$Board/Margin/Column/Controls/FireButton/Art.texture = BattleAssets.texture("battle_log_1")
	$Board/Margin/Column/Controls/End/Button/Art.texture = BattleAssets.texture("battle_log_2")
	$Board/Margin/Column/TopBar/Row/PauseButton/Art.texture = BattleAssets.texture("battle_log_continue")
	_hero.texture = HERO_TEX
	_hp_bar.texture_under = BattleAssets.texture("battle_hud_player_bottom")
	_hp_bar.texture_progress = BattleAssets.texture("battle_hud_player_")
	_enemy_hp_bar.texture_under = BattleAssets.texture("battle_hud_monster_bottom")
	_enemy_hp_bar.texture_progress = BattleAssets.texture("battle_hud_monster_")
	for bar in [_hp_bar, _enemy_hp_bar]:
		bar.nine_patch_stretch = true
	$Board/Margin/Column/TopBar/battle_up.texture = BattleAssets.texture("battle_frame_top")
	var bottom := TextureRect.new()
	bottom.name = "BottomFrame"
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.texture = BattleAssets.texture("battle_frame_bottom")
	bottom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -230
	add_child(bottom)
	move_child(bottom, 0)
	_timer_bar = TextureProgressBar.new()
	_timer_bar.name = "TimerBar"
	_timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_bar.texture_under = BattleAssets.texture("battle_hud_timer_bottom")
	_timer_bar.texture_progress = BattleAssets.texture("battle_hud_timer_")
	_timer_bar.nine_patch_stretch = true
	_timer_bar.custom_minimum_size = Vector2(0, 12)
	_timer_bar.step = 0.0
	$Board/Margin/Column.add_child(_timer_bar)
	$Board/Margin/Column.move_child(_timer_bar, 1)
	for path in ["Board/Margin/Column/TopBar/Row/VBoxContainer", "Board/Margin/Column/Stage/Player/Label", "Board/Margin/Column/Stage/Center/Label", "Board/Margin/Column/Stage/Center/Label2", "Board/Margin/Column/Stage/Center/Round", "Hand/Caption/Label2", "Hand/Label", "Board/Margin/Column/Controls/End/Incoming"]:
		get_node(path).hide()
	for path in ["Board/Margin/Column/Controls/Equation", "Hand/Zone/DrawPile", "Hand/Zone/DiscardPile", "ComboLayer/Burst", "Board/Margin/Column/Stage/Center/Preparation", "VictoryLayer/Center/Panel"]:
		var panel := get_node(path) as PanelContainer
		panel.add_theme_stylebox_override("panel", CHROME.paper())
		CHROME.ink_labels(panel)
	var equation_paper := CHROME.paper()
	equation_paper.texture = BattleAssets.texture("battle_hud2_")
	$Board/Margin/Column/Controls/Equation.add_theme_stylebox_override("panel", equation_paper)
	for pile_path in ["Hand/Zone/DrawPile", "Hand/Zone/DiscardPile"]:
		get_node(pile_path).add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		get_node(pile_path + "/Backdrop").show()
		var pile_label := get_node(pile_path + ("/DrawLabel" if pile_path.ends_with("DrawPile") else "/DiscardLabel")) as Label
		pile_label.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
		pile_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.08, 0.12))
		pile_label.add_theme_constant_override("shadow_offset_x", 1)
		pile_label.add_theme_constant_override("shadow_offset_y", 1)
	$Board/Margin/Column/Controls/Button.text = "烧牌"
	$Board/Margin/Column/Controls/Button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	$Board/Margin/Column/Controls/End.alignment = BoxContainer.ALIGNMENT_CENTER
	$Board/Margin/Column/Controls/Equation/Pad/Box/HBoxContainer/Label.hide()
	$Board/Margin/Column/Controls/Equation/Pad/Box/HBoxContainer/Button.text = "清空算式"
	$Board/Margin/Column/Controls/Equation/Pad/Box/HBoxContainer/Button.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	for label in [_trait, _enemy_name, _prepare_trait]:
		label.set_script(MONSTER_TOOLTIP)
	$Board/Margin/Column/Controls/Button.tooltip_text = "烧牌（B）：数字牌回复 |点数| × 10 生命；符号牌不回血。"
	$Board/Margin/Column/Controls/FireButton.tooltip_text = "发射（Enter / 空格）"
	$Board/Margin/Column/Controls/End/Button.tooltip_text = "结束回合（E）"
	$Board/Margin/Column/Controls/Combo.tooltip_text = "连续两次正数加法可在回合结束后追击；乘法会打断积累。"
	$Board/Margin/Column/Controls/Combo.mouse_filter = Control.MOUSE_FILTER_PASS
	_hand_caption.tooltip_text = "出牌后不会立即补牌；回合开始和回合中会按规则抽牌。"
	_hand_caption.mouse_filter = Control.MOUSE_FILTER_PASS
	_timer_label.tooltip_text = "回合限时 10 秒；经过 7.5 秒时额外抽牌。"
	_timer_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_timer_extra.add_theme_color_override("font_color", CHROME.INK)
	$Board/Margin/Column/Stage/Center.add_theme_constant_override("separation", 12)
	for label in [_enemy_name, _trait, _intent_label, _hand_caption, _hp_label, _floor_label]:
		label.add_theme_color_override("font_color", CHROME.LIGHT)
		label.add_theme_font_size_override("font_size", 20)
	_hp_label.add_theme_color_override("font_color", CHROME.LIGHT)
	_floor_label.add_theme_color_override("font_color", CHROME.INK)
	$Board/Margin/Column/Stage/Player/TextureRect/Life/Row/Label.hide()
	_trait.mouse_filter = Control.MOUSE_FILTER_PASS
	_enemy_name.mouse_filter = Control.MOUSE_FILTER_PASS
	_prepare_trait.mouse_filter = Control.MOUSE_FILTER_PASS
	_preview.add_theme_font_size_override("font_size", 18)
	for label in [_combo_status, $Board/Margin/Column/Controls/Combo/Label]:
		label.add_theme_color_override("font_color", CHROME.LIGHT)
		label.add_theme_font_size_override("font_size", 18)
	for label in [_draw_label, _discard_label, _enemy_hp_label]:
		label.add_theme_font_size_override("font_size", 18)
	for path in ["Board/Margin/Column/Controls/FireButton", "Board/Margin/Column/Controls/End/Button", "Board/Margin/Column/TopBar/Row/PauseButton"]:
		var button := get_node(path) as Button
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_entered.connect(_paint_art_button.bind(button))
		button.mouse_exited.connect(_paint_art_button.bind(button))
		button.button_down.connect(_paint_art_button.bind(button))
		button.button_up.connect(_paint_art_button.bind(button))
		button.focus_entered.connect(_paint_art_button.bind(button))
		button.focus_exited.connect(_paint_art_button.bind(button))


func _paint_art_button(button: Button) -> void:
	var art := button.get_node("Art") as TextureRect
	art.modulate = Color(0.6, 0.62, 0.69) if button.disabled else (Color(0.72, 0.75, 0.86) if button.is_pressed() else (Color(1.15, 1.15, 1.2) if button.is_hovered() or button.has_focus() else Color.WHITE))


func _position_actor_health() -> void:
	_layout_actors()
	# Imported art shares a fixed canvas and foot point. Attach HUD to the
	# visible heads, rather than the transparent canvas or the stage edges.
	var factor := minf(_hero.size.x / 720.0, _hero.size.y / 600.0)
	var origin := (_hero.size - Vector2(720, 600) * factor) * 0.5
	_place_actor_health(_hero.get_node("Life"), origin + Vector2(270, 80) * factor)
	_place_actor_health(_enemy_art.get_node("Health"), _enemy_art.head_anchor())


func _layout_actors() -> void:
	var player: Control = _hero.get_parent()
	var enemy: Control = _enemy_art.get_parent()
	# Both sides use the same scale, ground line and distance from centre.
	# The player's authored foot anchor is x=270; monsters use x=360.
	var factor := minf(player.size.x / 720.0, (player.size.y - 100.0) / 600.0)
	var canvas := Vector2(720, 600) * factor
	var ground := player.size.y - 120.0
	_hero.size = canvas
	_hero.position = Vector2(player.size.x * 0.5 - 270.0 * factor, ground - 480.0 * factor)
	_enemy_art.size = canvas
	_enemy_art.position = Vector2(enemy.size.x * 0.5 - 360.0 * factor, ground - 480.0 * factor)
	_intent_label.position = Vector2.ZERO
	_intent_label.size = Vector2(enemy.size.x, 30)
	_enemy_name.position = Vector2(0, player.size.y - 62)
	_enemy_name.size = Vector2(enemy.size.x, 28)
	_trait.position = Vector2(0, player.size.y - 32)
	_trait.size = Vector2(enemy.size.x, 28)


func _place_actor_health(panel: Control, head: Vector2) -> void:
	panel.size = Vector2(240, panel.get_combined_minimum_size().y)
	panel.position = head - Vector2(panel.size.x * 0.5, panel.size.y + 12)
