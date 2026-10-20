extends Control
## Tower after the main menu. A new run opens on the first room choice.

const DISPLAY := {
	"ROOM_NORMAL": "战斗",
	"ROOM_EVENT": "奇遇",
	"ROOM_BOSS": "Boss",
}

var run: RunState
var _session: CombatSession
@onready var _battle: RunBattle = $Battle
@onready var _inventory: RunInventory = $Inventory
var _battle_room := ""
var _battle_checkpoint: Dictionary = {}
@onready var _body: VBoxContainer = $Layout/Column/Scroll/Body
@onready var _scroll: ScrollContainer = $Layout/Column/Scroll
@onready var _header: Label = $Layout/Column/Header
@onready var _status: Label = $Layout/Column/Heading/Status
@onready var _title: Label = $Layout/Column/Heading/Title
@onready var _actions: HBoxContainer = $Layout/Column/Actions
const CARD_SCENE := preload("res://scenes/cards/card_view.tscn")
var _page_key := ""
var _restore_scroll := 0
var _restore_focus := ""
var _fit_queued := false
var _selected_offer := ""
var _selected_cards: Array = []
var _pizza_done := false
var _notice: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	var ui := Theme.new()
	ui.default_font = font
	ui.default_font_size = 30
	ui.set_color("font_color", "Label", Color(0.9, 0.88, 0.8))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.09, 0.12, 0.18, 0.96)
		style.border_color = Color(0.44, 0.47, 0.54)
		style.set_border_width_all(2)
		style.set_corner_radius_all(12)
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.content_margin_top = 16
		style.content_margin_bottom = 16
		if state in ["hover", "pressed", "focus"]:
			style.border_color = Color(0.93, 0.78, 0.42)
			style.set_border_width_all(3)
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
		if state == "disabled":
			style.bg_color = Color(0.09, 0.12, 0.18, 0.6)
		ui.set_stylebox(state, "Button", style)
	$Layout.theme = ui
	_scroll.resized.connect(_queue_fit)
	_battle.returned_to_tower.connect(_on_return_to_tower)
	$RunMenu.restart_battle_requested.connect(restart_battle)
	move_child(_battle, -1)
	if _inventory != null:
		_inventory.bind_host(self)
		_inventory.set_input_view(_battle)
		move_child(_inventory, -1)
	move_child($RunMenu, -1)
	# The shared pause entry uses the battle art on every run screen.
	$Battle/Board/Margin/Column/TopBar/Row/PauseButton.hide()
	$Battle/Hand/Label.text = $Battle/Hand/Label.text.replace("Esc 清空", "Esc 菜单")
	_start_run(str(Time.get_unix_time_from_system()))


func _start_run(seed: String) -> void:
	_battle_room = ""
	_battle_checkpoint = {}
	_pizza_done = false
	_selected_offer = ""
	_selected_cards = []
	_session = null
	_notice = {}
	_page_key = ""
	if _battle != null:
		_battle.visible = false
	var created := RunService.new_run(seed)
	if not created.get("ok", false):
		run = null
		_header.text = "无法开局"
		var lines := PackedStringArray()
		for err in created.get("errors", [created.get("error", "")]):
			lines.append(str(err))
		_clear_body()
		_title.text = "无法开局"
		_set_status("\n".join(lines))
		if _inventory != null:
			_inventory.reset_run()
		return
	run = created.run
	if _inventory != null:
		_inventory.reset_run()
	_show()


func _show() -> void:
	if run == null:
		return
	_header.text = "第 %d 层    生命 %d/%d    牌库 %d" % [run.depth, run.hp, run.max_hp, TowerDeck.deck_cards(run).size()]
	if not _notice.is_empty():
		_show_notice()
		return
	if run.phase == "ERROR":
		_set_battle_visible(false)
		_clear_body()
		_title.text = "无法继续"
		_body.add_child(_hint(run.last_error))
		return
	if run.phase == "DEAD":
		_show_end("你倒下了，本局结束。")
		return
	if run.phase == "ENDED":
		_show_end("本局已结束。")
		return
	if run.phase == "FLOOR_CLEAR":
		_show_floor_clear()
		return
	if run.phase == "REWARD":
		_show_reward()
		return
	if str(run.current_room.get("status", "")) == "ENTERED":
		if str(run.current_room.get("scene_key", "")) == "battle":
			_show_battle()
		else:
			_show_event()
		return
	_show_choices()


func _show_choices() -> void:
	_set_battle_visible(false)
	_clear_body()
	_title.text = "选择下一间房间"
	_selected_offer = ""
	_selected_cards = []
	if run.current_offers.is_empty():
		_set_status("前面没有路了。")
		return
	_set_status("第 %d 间，选一条路。" % run.pending_slot)
	for offer in run.current_offers:
		var label := str(DISPLAY.get(str(offer.get("display_key", "")), "房间"))
		var button := _choice(label, "room")
		var uid := str(offer.get("offer_uid", ""))
		button.pressed.connect(_choose_offer.bind(uid))
		_add_choice(button, uid)


func _choose_offer(offer_uid: String) -> void:
	var result := MapService.choose_room(run, offer_uid)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "进不去。")))
		return
	_show()


func _show_battle() -> void:
	_clear_body()
	var room_uid := str(run.current_room.get("room_uid", ""))
	if _battle_room == room_uid and _session != null:
		_set_battle_visible(true)
		return
	_set_battle_visible(false)
	# Capture BEFORE start() advances the COMBAT stream or detains a card.
	_battle_checkpoint = run.capture().duplicate(true)
	_session = CombatSession.new()
	_session.start(run)
	if _battle != null:
		_battle.adopt(_session)
	_battle_room = room_uid
	_set_battle_visible(true)


func _on_return_to_tower(outcome: String) -> void:
	if _session == null:
		return
	_set_battle_visible(false)
	var phase := _session.write_back(run)
	if _inventory != null:
		_inventory.detach_combat()
	_battle_room = ""
	_session = null
	_battle_checkpoint = {}
	_selected_offer = ""
	_selected_cards = []
	if _is_battle_loss(phase) or _is_battle_loss(outcome) or run.hp <= 0:
		RunService.finish_room(run, "defeat")
	else:
		RunService.finish_room(run, "victory")
	_show()


func can_restart_battle() -> bool:
	return _battle != null and _battle.visible and _session != null and not _battle_checkpoint.is_empty() and _battle.presentation in [RunBattle.Presentation.PREPARING, RunBattle.Presentation.ACTIVE] and _session.ctx.battle.phase in ["PLAYER_ACTIVE", "COMBO"]


func restart_battle() -> void:
	if not can_restart_battle():
		return
	var checkpoint := _battle_checkpoint.duplicate(true)
	if _inventory != null:
		_inventory.reset_run()
	_battle.hide()
	_session = null
	_battle_room = ""
	run.rollback(checkpoint)
	_selected_offer = ""
	_selected_cards = []
	_notice = {}
	_page_key = ""
	_show_battle()


func _is_battle_loss(phase: String) -> bool:
	return phase == "defeat" or phase == "DEFEAT" or phase == "DECK_EXHAUSTED"


func _show_event() -> void:
	_set_battle_visible(false)
	_clear_body()
	var room_uid := str(run.current_room.get("room_uid", ""))
	var view := EventService.make_view(run, room_uid)
	if not view.get("ok", false):
		_set_status(str(view.get("error", "这个奇遇打不开。")))
		return
	_title.text = str(view.get("name", "奇遇"))
	var dialogue := str(view.get("input_mode", "")) == "ACCEPT_OR_SKIP" and not bool(view.get("repair", false))
	_set_dialogue_layout(dialogue)
	var pizza := _active_pizza()
	if _status.text == "" and not pizza.is_empty():
		_set_status("披萨在第 %d 层的 Boss 之后到。" % int(pizza.get("target_depth", 0)))
	var blurb := str(view.get("text", ""))
	if blurb != "":
		var description := _hint(blurb)
		if dialogue:
			description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_body.add_child(description)
	if str(view.get("disabled_reason", "")) != "":
		_body.add_child(_hint(str(view.disabled_reason)))
	match str(view.get("input_mode", "")):
		"CARD_ONE":
			_show_card_choices(view, false)
		"CARD_MULTI":
			_show_card_choices(view, true)
		"OFFER_ONE":
			_show_offers(view)
		"ACCEPT_OR_SKIP":
			_show_accept(view)
		_:
			_body.add_child(_hint("这里没什么可做的。"))
	if bool(view.get("can_skip", true)):
		var leave := _button("离开")
		leave.pressed.connect(_skip_event.bind(room_uid))
		_actions.add_child(leave)


func _show_card_choices(view: Dictionary, multi: bool) -> void:
	if multi:
		_body.add_child(_hint(_multi_status()))
	for card_uid in view.get("eligible_target_uids", []):
		var card := run.find_card(str(card_uid))
		if card == null:
			continue
		var picked := _selected_cards.has(str(card_uid))
		var label := TowerDeck.describe_card(card)
		if picked:
			label = "已选\n" + label
		var button := _choice(label, "grid", true, CardArt.from_parts(card.def_id, card.enhancement_ids, card.card_uid))
		button.pressed.connect(_select_card.bind(str(card_uid), multi, str(view.get("room_uid", ""))))
		_add_choice(button, str(card_uid))
	var confirm := _button("确认")
	confirm.disabled = _selected_cards.is_empty()
	confirm.pressed.connect(_confirm_cards.bind(str(view.get("room_uid", "")), str(view.get("handler_id", "")), multi))
	_actions.add_child(confirm)


func _select_card(card_uid: String, multi: bool, room_uid: String) -> void:
	if multi:
		if _selected_cards.has(card_uid):
			_selected_cards.erase(card_uid)
		elif _selected_cards.size() < 3:
			_selected_cards.append(card_uid)
		_set_status(_multi_status())
		call_deferred("_show_event")
		return
	_selected_cards = [card_uid]
	var view := EventService.make_view(run, room_uid)
	if str(view.get("handler_id", "")) == "TRANSFORM_CARD":
		var preview := EventService.freeze_preview(run, room_uid, card_uid)
		if preview.get("ok", false):
			_set_status("会变成 %s" % str(preview.get("label", "")))
		else:
			_set_status(str(preview.get("error", "换不了。")))
	else:
		_set_status("选好了这张牌。")
	call_deferred("_show_event")


func _confirm_cards(room_uid: String, handler_id: String, multi: bool) -> void:
	var payload := {}
	if multi:
		payload = {"sacrifice_uids": _selected_cards.duplicate()}
	elif handler_id == "TRANSFORM_CARD":
		if _selected_cards.is_empty():
			_set_status("先选一张牌。")
			return
		var preview: Dictionary = EventService.make_view(run, room_uid).get("previews", {}).get(_selected_cards[0], {})
		if preview.is_empty():
			preview = EventService.freeze_preview(run, room_uid, _selected_cards[0])
		if not preview.get("ok", false):
			_set_status(str(preview.get("error", "换不了。")))
			return
		payload = {"target_uid": _selected_cards[0], "preview_uid": str(preview.get("preview_uid", ""))}
	else:
		if _selected_cards.is_empty():
			_set_status("先选一张牌。")
			return
		payload = {"target_uid": _selected_cards[0]}
	_commit_event(room_uid, payload)


func _show_offers(view: Dictionary) -> void:
	var handler := str(view.get("handler_id", ""))
	for offer in view.get("offers", []):
		var label := str(offer.get("display_name", ""))
		if str(offer.get("payload_kind", "")) == "CARD":
			label = TowerDeck.describe_parts(str(offer.get("def_id", "")), offer.get("enhancement_ids", []), "")
		var uid := str(offer.get("offer_uid", ""))
		if uid == _selected_offer:
			label = "已选\n" + label
		var offered_card := str(offer.get("payload_kind", "")) == "CARD"
		var art_face := CardArt.from_parts(str(offer.get("def_id", "")), offer.get("enhancement_ids", [])) if offered_card else {"enh_id": str(offer.get("enh_id", ""))}
		var button := _choice(label, "strip" if handler == "MARK_OFFER" else "large", offered_card, art_face)
		button.pressed.connect(_select_offer.bind(uid, handler))
		_add_choice(button, uid)
	if handler == "MARK_OFFER" and _selected_offer != "":
		_body.add_child(_hint("选一张牌，把刚才那项加上去。"))
		var enh_id := ""
		for offer in view.get("offers", []):
			if str(offer.get("offer_uid", "")) == _selected_offer:
				enh_id = str(offer.get("enh_id", ""))
		for card_uid in TowerDeck.targets_for_mark(run, enh_id):
			var card := run.find_card(card_uid)
			var picked := _selected_cards.has(str(card_uid))
			var label := TowerDeck.describe_card(card)
			if picked:
				label = "已选\n" + label
			var button := _choice(label, "grid", true, CardArt.from_parts(card.def_id, card.enhancement_ids, card.card_uid))
			button.pressed.connect(_select_card.bind(card_uid, false, str(view.get("room_uid", ""))))
			_add_choice(button, str(card_uid))
	var confirm := _button("确认")
	confirm.disabled = _selected_offer == "" or (handler == "MARK_OFFER" and _selected_cards.is_empty())
	confirm.pressed.connect(_confirm_offer.bind(str(view.get("room_uid", "")), handler))
	_actions.add_child(confirm)


func _select_offer(offer_uid: String, handler: String) -> void:
	_selected_offer = offer_uid
	_selected_cards = []
	if handler == "MARK_OFFER":
		_set_status("选好了变化，再选一张牌。")
		call_deferred("_show_event")
		return
	_set_status("选好了。")
	call_deferred("_show_event")


func _confirm_offer(room_uid: String, handler: String) -> void:
	if _selected_offer == "":
		_set_status("先选一项。")
		return
	if handler == "MARK_OFFER":
		if _selected_cards.is_empty():
			_set_status("再选一张牌。")
			return
		_commit_event(room_uid, {"offer_uid": _selected_offer, "target_uid": _selected_cards[0]})
		return
	_commit_event(room_uid, {"offer_uid": _selected_offer})


func _show_accept(view: Dictionary) -> void:
	if bool(view.get("repair", false)):
		_body.add_child(_hint("这副牌已经打不出正数了。确认后拿走 +2、+3 和加号。"))
		for offer in view.get("offers", []):
			_body.add_child(_hint(TowerDeck.describe_parts(str(offer.get("def_id", "")), [], "")))
		var take := _button("领取")
		take.pressed.connect(_commit_event.bind(str(view.get("room_uid", "")), {"accept": true}))
		_actions.add_child(take)
		return
	var accept := _button("收下")
	accept.pressed.connect(_commit_event.bind(str(view.get("room_uid", "")), {"accept": true}))
	_actions.add_child(accept)
	var decline := _button("放弃")
	decline.pressed.connect(_commit_event.bind(str(view.get("room_uid", "")), {"accept": false}))
	_actions.add_child(decline)


func _skip_event(room_uid: String) -> void:
	_commit_event(room_uid, {"skip": true})


func _commit_event(room_uid: String, payload: Dictionary) -> void:
	var view := EventService.make_view(run, room_uid)
	var title := str(view.get("name", "奇遇"))
	var txn := run.uid("T")
	var result := EventService.commit(run, room_uid, payload, txn)
	if not result.get("ok", false):
		_set_status(str(result.get("error", "没做成。")))
		call_deferred("_show_event")
		return
	var lines := _event_result_lines(result)
	_selected_offer = ""
	_selected_cards = []
	if str(run.current_room.get("status", "")) == "ENTERED" and str(run.current_room.get("room_uid", "")) == room_uid:
		RunService.finish_room(run, "clear")
	if lines.is_empty():
		call_deferred("_show")
		return
	_notice = {"title": title, "lines": lines}
	call_deferred("_show")


func _show_reward() -> void:
	_set_battle_visible(false)
	_clear_body()
	_title.text = "挑选战利品"
	var session := _open_reward_session()
	if session.is_empty():
		_body.add_child(_hint("奖励已经拿完了。"))
		var onward := _button("继续")
		onward.pressed.connect(_finish_reward_step)
		_actions.add_child(onward)
		return
	var known := false
	for offer in session.get("offers", []):
		if str(offer.get("offer_uid", "")) == _selected_offer:
			known = true
			break
	if not known:
		_selected_offer = ""
		_selected_cards = []
	if _status.text == "" and _selected_offer == "" and _selected_cards.is_empty():
		_set_status("挑一份战利品。")
	elif _status.text == "" and _selected_cards.is_empty():
		_set_status("选好了这一项。")
	elif _status.text == "":
		_set_status("选好了这张牌。")
	var plan := GameData.reward(str(session.get("reward_id", "")))
	if str(plan.get("payload_kind", "")) == "MARK":
		_show_mark_reward(session)
	else:
		_show_card_reward(session)


func _show_card_reward(session: Dictionary) -> void:
	_body.add_child(_hint("选一张放进牌库，也可以不要。"))
	var session_uid := str(session.get("reward_session_uid", ""))
	for offer in session.get("offers", []):
		var label := TowerDeck.describe_parts(str(offer.get("def_id", "")), offer.get("enhancement_ids", []), "")
		var uid := str(offer.get("offer_uid", ""))
		if uid == _selected_offer:
			label = "已选\n" + label
		var button := _choice(label, "large", true, CardArt.from_parts(str(offer.get("def_id", "")), offer.get("enhancement_ids", [])))
		button.pressed.connect(_select_reward_offer.bind(uid, false))
		_add_choice(button, uid)
	var confirm := _button("确认")
	confirm.disabled = _selected_offer == ""
	confirm.pressed.connect(_confirm_card_reward.bind(session_uid))
	_actions.add_child(confirm)
	_add_reward_skip(session)


func _show_mark_reward(session: Dictionary) -> void:
	_body.add_child(_hint("先选一种变化，再选一张牌。也可以不要。"))
	var session_uid := str(session.get("reward_session_uid", ""))
	for offer in session.get("offers", []):
		var label := TowerDeck.mark_line(str(offer.get("enh_id", "")))
		var uid := str(offer.get("offer_uid", ""))
		if uid == _selected_offer:
			label = "已选\n" + label
		var button := _choice(label, "strip", false, {"enh_id": str(offer.get("enh_id", ""))})
		button.pressed.connect(_select_reward_offer.bind(uid, true))
		_add_choice(button, uid)
	if _selected_offer != "":
		_body.add_child(_hint("选一张牌，把刚才那项加上去。"))
		var targets: Array = []
		for offer in session.get("offers", []):
			if str(offer.get("offer_uid", "")) == _selected_offer:
				targets = offer.get("eligible_target_uids", [])
				break
		for card_uid in targets:
			var card := run.find_card(str(card_uid))
			if card == null:
				continue
			var picked := _selected_cards.has(str(card_uid))
			var label := TowerDeck.describe_card(card)
			if picked:
				label = "已选\n" + label
			var button := _choice(label, "grid", true, CardArt.from_parts(card.def_id, card.enhancement_ids, card.card_uid))
			button.pressed.connect(_select_reward_card.bind(str(card_uid)))
			_add_choice(button, str(card_uid))
	var confirm := _button("确认")
	confirm.disabled = _selected_offer == "" or _selected_cards.is_empty()
	confirm.pressed.connect(_confirm_mark_reward.bind(session_uid))
	_actions.add_child(confirm)
	_add_reward_skip(session)


func _add_reward_skip(session: Dictionary) -> void:
	var plan := GameData.reward(str(session.get("reward_id", "")))
	if not bool(plan.get("can_skip", true)):
		return
	var skip := _button("跳过")
	skip.pressed.connect(_skip_reward.bind(str(session.get("reward_session_uid", ""))))
	_actions.add_child(skip)


func _select_reward_offer(offer_uid: String, marks: bool) -> void:
	_selected_offer = offer_uid
	_selected_cards = []
	if marks:
		_set_status("选好了变化，再选一张牌。")
		call_deferred("_show")
		return
	_set_status("选好了。")
	call_deferred("_show")


func _select_reward_card(card_uid: String) -> void:
	_selected_cards = [card_uid]
	_set_status("选好了这张牌。")
	call_deferred("_show")


func _confirm_card_reward(session_uid: String) -> void:
	if _selected_offer == "":
		_set_status("先选一项。")
		return
	var result := RewardService.commit_cards(run, session_uid, _selected_offer, false, run.uid("T"))
	if not result.get("ok", false):
		_set_status(str(result.get("error", "没拿到牌。")))
		return
	var lines := PackedStringArray()
	lines.append("放进牌库：")
	for card_uid in result.get("granted_card_uids", []):
		lines.append(_face_block(str(card_uid)))
	if lines.size() > 1:
		_notice = {"title": "战利品", "lines": lines}
	_finish_reward_step()


func _confirm_mark_reward(session_uid: String) -> void:
	if _selected_offer == "":
		_set_status("先选一项。")
		return
	if _selected_cards.is_empty():
		_set_status("再选一张牌。")
		return
	var target_uid := str(_selected_cards[0])
	var result := RewardService.commit_mark(run, session_uid, _selected_offer, target_uid, run.uid("T"))
	if not result.get("ok", false):
		_set_status(str(result.get("error", "没加上去。")))
		return
	var lines := PackedStringArray()
	lines.append("给 %s 加上了 %s" % [_brief(target_uid), TowerDeck.mark_line(str(result.get("enh_id", "")))])
	if bool(result.get("converted", false)):
		lines.append("这张牌收进了收藏。")
	_notice = {"title": "战利品", "lines": lines}
	_finish_reward_step()


func _skip_reward(session_uid: String) -> void:
	RewardService.skip_session(run, session_uid, run.uid("T"))
	_finish_reward_step()


func _finish_reward_step() -> void:
	_selected_offer = ""
	_selected_cards = []
	if _open_reward_session().is_empty() and run.phase == "REWARD":
		var result := RunService.continue_after_rewards(run)
		if not result.get("ok", false):
			_set_status(str(result.get("error", "不能继续")))
	call_deferred("_show")


func _open_reward_session() -> Dictionary:
	var room_uid := str(run.current_room.get("room_uid", ""))
	for session in run.reward_sessions:
		if str(session.get("source_uid", "")) != room_uid:
			continue
		if str(session.get("status", "")) == "OPEN":
			return session
	return {}


func _show_floor_clear() -> void:
	_set_battle_visible(false)
	_clear_body()
	_title.text = "楼层完成"
	var quest := _ready_pizza()
	if not quest.is_empty() and not _pizza_done:
		_show_pizza(quest)
		return
	_summary(["这层的 Boss 倒了。"])
	var onward := _button("继续下一层")
	onward.pressed.connect(_continue_floor.bind(true))
	_actions.add_child(onward)
	var stop := _button("结束本局")
	stop.pressed.connect(_continue_floor.bind(false))
	_actions.add_child(stop)


func _show_pizza(quest: Dictionary) -> void:
	_title.text = "披萨到了"
	_body.add_child(_hint("披萨到了。不想要的牌可以丢掉。"))
	for offer in quest.get("reward_snapshot", []):
		var offer_uid := str(offer.get("offer_uid", ""))
		var verb := "丢掉\n" if _selected_cards.has(offer_uid) else "带走\n"
		var button := _choice(verb + TowerDeck.describe_parts(str(offer.get("def_id", "")), offer.get("enhancement_ids", []), ""), "grid", true, CardArt.from_parts(str(offer.get("def_id", "")), offer.get("enhancement_ids", [])))
		button.pressed.connect(_toggle_discard.bind(offer_uid))
		_add_choice(button, offer_uid)
	var claim := _button("确认领取")
	claim.pressed.connect(_claim_pizza.bind(str(quest.get("quest_uid", ""))))
	_actions.add_child(claim)


func _toggle_discard(offer_uid: String) -> void:
	if _selected_cards.has(offer_uid):
		_selected_cards.erase(offer_uid)
	else:
		_selected_cards.append(offer_uid)
	call_deferred("_show_floor_clear")


func _claim_pizza(quest_uid: String) -> void:
	var result := RewardService.claim_pizza(run, quest_uid, run.uid("T"), _selected_cards.duplicate())
	if not result.get("ok", false):
		_set_status(str(result.get("error", "不能领取")))
		return
	_pizza_done = true
	_selected_cards = []
	_show()


func _continue_floor(continue_run: bool) -> void:
	_pizza_done = false
	RunService.finish_floor(run, continue_run)
	_show()


func _show_end(message: String) -> void:
	_set_battle_visible(false)
	_clear_body()
	_title.text = "本局结束"
	_summary([message])
	var again := _button("新的一局")
	again.pressed.connect(func() -> void: _start_run(str(Time.get_ticks_usec())))
	_actions.add_child(again)


func _active_pizza() -> Dictionary:
	for quest in run.quest_states:
		if str(quest.get("quest_type", "")) == "PIZZA" and str(quest.get("status", "")) == "ACTIVE":
			return quest
	return {}


func _ready_pizza() -> Dictionary:
	for quest in run.quest_states:
		if str(quest.get("quest_type", "")) == "PIZZA" and str(quest.get("status", "")) == "READY" and int(quest.get("target_depth", -1)) == run.depth:
			return quest
	return {}


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func _set_battle_visible(show_battle: bool) -> void:
	if _battle == null:
		return
	if run != null:
		$Background.texture = BattleAssets.background(run.depth, show_battle)
	$Layout.visible = not show_battle
	_battle.visible = show_battle
	_body.visible = not show_battle
	_header.visible = not show_battle
	_status.visible = not show_battle and _status.text != ""
	if _inventory != null:
		_inventory.set_battle_clearance(show_battle)


func inventory_sources() -> Dictionary:
	var library: CardLibrary = null
	var battle: CardBattle = null
	if _session != null and _session.is_live():
		library = _session.ctx.library
		battle = _session.ctx.battle
	return {"run": run, "library": library, "battle": battle}


func set_inventory_input_locked(locked: bool) -> void:
	if _battle != null:
		_battle.set_external_input_blocked(locked)


func _clear_body() -> void:
	_set_dialogue_layout(false)
	var key := "error"
	if run != null:
		key = "%s/%s/%s/%s/%s/%s" % [
			run.phase, str(run.current_room.get("room_uid", "")), run.pending_slot,
			str(_open_reward_session().get("reward_session_uid", "")),
			not _notice.is_empty(), _pizza_done,
		]
	_restore_scroll = _scroll.scroll_vertical if key == _page_key else 0
	var focus := get_viewport().gui_get_focus_owner()
	_restore_focus = str(focus.get_meta("focus_key", "")) if focus != null and key == _page_key else ""
	if key != _page_key:
		_set_status("")
	_page_key = key
	for container in [_body, _actions]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_queue_fit()


func _set_dialogue_layout(enabled: bool) -> void:
	# Short conversations read as one group, rather than three distant screen bands.
	var heading := $Layout/Column/Heading as Control
	heading.anchor_top = 0.30 if enabled else 0.08
	heading.anchor_bottom = 0.39 if enabled else 0.22
	_scroll.anchor_left = 0.25 if enabled else 0.1
	_scroll.anchor_right = 0.75 if enabled else 0.9
	_scroll.anchor_top = 0.40 if enabled else 0.22
	_scroll.anchor_bottom = 0.55 if enabled else 0.8
	_actions.anchor_top = 0.57 if enabled else 0.8
	_actions.anchor_bottom = 0.69 if enabled else 0.94


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 76)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if text in ["确认", "确认领取", "领取", "收下", "继续", "继续下一层", "新的一局"]:
		var primary: StyleBoxFlat = $Layout.theme.get_stylebox("normal", "Button").duplicate()
		primary.bg_color = Color(0.23, 0.2, 0.13, 0.98)
		primary.border_color = Color(0.83, 0.7, 0.4)
		button.add_theme_stylebox_override("normal", primary)
		button.add_theme_color_override("font_color", Color(0.97, 0.89, 0.69))
	return button


func _choice(text: String, mode: String = "large", card_face: bool = true, face_data: Dictionary = {}) -> Button:
	var button := _button("")
	button.theme = $Layout.theme
	button.set_meta("choice_key", text.trim_prefix("已选\n"))
	button.set_meta("mode", mode)
	button.tooltip_text = text
	var picked := text.begins_with("已选\n") or text.begins_with("丢掉\n")
	var state := "已选" if picked else ""
	var clean := text.trim_prefix("已选\n")
	if clean.begins_with("带走\n") or clean.begins_with("丢掉\n"):
		state = clean.get_slice("\n", 0)
		clean = clean.substr(clean.find("\n") + 1)
	var dimensions := Vector2(360, 480)
	if mode == "grid":
		dimensions = Vector2(264, 340)
	elif mode == "strip":
		dimensions = Vector2(420, 220)
	button.custom_minimum_size = dimensions
	button.size_flags_vertical = Control.SIZE_FILL
	var face: CardView = CARD_SCENE.instantiate()
	# Choice buttons own hover/focus; the battle tilt animation is inappropriate here.
	face.get_node("HoverAnim").free()
	button.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.offset_left = 6
	face.offset_top = 6
	face.offset_right = -6
	face.offset_bottom = -6
	var lines := clean.split("\n", false)
	var value := lines[0] if not lines.is_empty() else ""
	var detail := "\n".join(lines.slice(1))
	if mode == "room":
		detail = {"战斗": "迎接下一场战斗", "奇遇": "探索未知的际遇", "Boss": "挑战本层首领"}.get(value, "选择这条路")
		state = "点击进入"
	elif not card_face and detail == "" and value.contains("："):
		detail = value.substr(value.find("：") + 1)
		value = value.get_slice("：", 0)
	var data := face_data.duplicate(true)
	data["presentation"] = "room" if mode == "room" else ("card" if card_face and data.has("card_kind") else "text")
	data["value_text"] = str(data.get("value_text", value))
	data["mark_text"] = detail
	var flags := str(data.get("state_text", ""))
	data["state_text"] = state + (" · " if state != "" and flags != "" else "") + flags
	data["tooltip"] = text
	face.bind_face(data)
	face.set_choice_presentation(dimensions - Vector2(12, 12), card_face and mode != "room")
	button.custom_minimum_size.y = face.custom_minimum_size.y + 12
	_ignore_mouse(face)
	if picked:
		face.set_highlight("equation")
	return button


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _add_choice(button: Button, key: String) -> void:
	button.set_meta("focus_key", key)
	var mode := str(button.get_meta("mode"))
	var group: CenterContainer = null
	if _body.get_child_count() > 0:
		var last := _body.get_child(-1)
		if last is CenterContainer and str(last.get_meta("mode", "")) == mode:
			group = last
	if group == null:
		group = CenterContainer.new()
		group.set_meta("mode", mode)
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var grid := GridContainer.new()
		grid.add_theme_constant_override("h_separation", 40)
		grid.add_theme_constant_override("v_separation", 28)
		group.add_child(grid)
		_body.add_child(group)
	var grid := group.get_child(0) as GridContainer
	grid.add_child(button)
	grid.columns = mini(grid.get_child_count(), 5 if mode == "grid" else 3)


func _show_notice() -> void:
	_set_battle_visible(false)
	_clear_body()
	_title.text = str(_notice.get("title", "结果"))
	_set_status("")
	_summary(_notice.get("lines", []))
	var onward := _button("继续")
	onward.pressed.connect(_dismiss_notice)
	_actions.add_child(onward)


func _dismiss_notice() -> void:
	_notice = {}
	_show()


func _event_result_lines(result: Dictionary) -> PackedStringArray:
	if bool(result.get("skipped", false)):
		return PackedStringArray()
	var lines := PackedStringArray()
	var removed: Array = result.get("removed", [])
	if not removed.is_empty():
		lines.append("交出了这些牌：")
		for card_uid in removed:
			lines.append(_face_block(str(card_uid)))
	var marks: Array = result.get("marks", [])
	if not marks.is_empty():
		lines.append("给剩下的牌加上了：")
		for grant in marks:
			if grant is not Dictionary:
				continue
			var card_uid := str(grant.get("target_uid", ""))
			lines.append("%s\n加上 %s" % [_brief(card_uid), TowerDeck.mark_line(str(grant.get("enh_id", "")))])
	if str(result.get("enh_id", "")) != "" and marks.is_empty():
		lines.append("给 %s 加上了 %s" % [_brief(str(result.get("target_uid", ""))), TowerDeck.mark_line(str(result.get("enh_id", "")))])
		if bool(result.get("converted", false)):
			lines.append("这张牌收进了收藏。")
	var granted: Array = result.get("granted_card_uids", [])
	if not granted.is_empty():
		lines.append("得到了：")
		for card_uid in granted:
			lines.append(_face_block(str(card_uid)))
	if str(result.get("def_id", "")) != "" and str(result.get("enh_id", "")) == "" and granted.is_empty() and marks.is_empty() and removed.is_empty():
		lines.append("这张牌变成了：")
		lines.append(_face_block(str(result.get("target_uid", ""))))
	if int(result.get("target_depth", 0)) > 0:
		lines.append("披萨会在第 %d 层的 Boss 之后送到。现在看不到里面有什么。" % int(result.get("target_depth", 0)))
	return lines


func _multi_status() -> String:
	if _selected_cards.is_empty():
		return "点选 1 到 3 张要交出的牌。"
	var names := PackedStringArray()
	for card_uid in _selected_cards:
		names.append(_brief(str(card_uid)))
	return "已选 %d 张：%s" % [_selected_cards.size(), "、".join(names)]


func _face_block(card_uid: String) -> String:
	var card := run.find_card(card_uid)
	if card == null:
		return card_uid
	return TowerDeck.describe_card(card)


func _brief(card_uid: String) -> String:
	var text := _face_block(card_uid)
	var parts := text.split("\n")
	return str(parts[0]) if not parts.is_empty() else card_uid


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.72))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.09, 0.14, 0.88)
	panel.set_corner_radius_all(10)
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 12
	panel.content_margin_bottom = 12
	label.add_theme_stylebox_override("normal", panel)
	_queue_fit()
	return label


func _summary(lines: Array) -> void:
	var center := CenterContainer.new()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(960, 240)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.14, 0.94)
	style.border_color = Color(0.5, 0.46, 0.34)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 40
	style.content_margin_bottom = 40
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	panel.add_child(column)
	center.add_child(panel)
	_body.add_child(center)
	for line in lines:
		var text := str(line)
		if text == "":
			continue
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if text.replace("−", "-").is_valid_int() or text in ["+", "×", "÷"]:
			label.add_theme_font_size_override("font_size", 80)
		column.add_child(label)


func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	call_deferred("_fit_text")


func _fit_text() -> void:
	_fit_queued = false
	if _scroll == null:
		return
	for group in _body.get_children():
		if group is CenterContainer and group.has_meta("mode"):
			var grid := group.get_child(0) as GridContainer
			if grid.get_child_count() == 0:
				continue
			var card := grid.get_child(0) as Control
			var available := _scroll.size.x - 24.0
			var columns := maxi(1, int((available + 40.0) / (card.custom_minimum_size.x + 40.0)))
			grid.columns = mini(grid.get_child_count(), mini(columns, 5))
	# Containers settle on the following frame; restore only within the current page.
	call_deferred("_restore_page_position", _page_key, _restore_scroll, _restore_focus)


func _restore_page_position(key: String, scroll: int, focus_key: String) -> void:
	if key != _page_key:
		return
	_scroll.scroll_vertical = scroll
	if focus_key != "":
		for button in _body.find_children("*", "Button", true, false):
			if str(button.get_meta("focus_key", "")) == focus_key:
				button.grab_focus()
				break
