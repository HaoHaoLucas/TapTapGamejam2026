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
var _battle_room := ""
@onready var _body: VBoxContainer = $Layout/Column/Scroll/Body
@onready var _scroll: ScrollContainer = $Layout/Column/Scroll
@onready var _header: Label = $Layout/Column/Header
@onready var _status: Label = $Layout/Column/Status
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
	ui.default_font_size = 18
	theme = ui
	_scroll.resized.connect(_queue_fit)
	_battle.returned_to_tower.connect(_on_return_to_tower)
	move_child(_battle, -1)
	_start_run(str(Time.get_unix_time_from_system()))


func _start_run(seed: String) -> void:
	_battle_room = ""
	_pizza_done = false
	_selected_offer = ""
	_selected_cards = []
	if _battle != null:
		_battle.visible = false
	var created := RunService.new_run(seed)
	if not created.get("ok", false):
		run = null
		_header.text = "无法开局"
		var lines := PackedStringArray()
		for err in created.get("errors", [created.get("error", "")]):
			lines.append(str(err))
		_status.text = "\n".join(lines)
		_clear_body()
		return
	run = created.run
	_show()


func _show() -> void:
	if run == null:
		return
	if not _notice.is_empty():
		_show_notice()
		return
	_header.text = "第 %d 层    生命 %d/%d    牌库 %d" % [run.depth, run.hp, run.max_hp, TowerDeck.deck_cards(run).size()]
	var pizza := _active_pizza()
	_status.text = "" if pizza.is_empty() else "披萨在第 %d 层的 Boss 之后到。" % int(pizza.get("target_depth", 0))
	if run.phase == "ERROR":
		_status.text = run.last_error
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
	_selected_offer = ""
	_selected_cards = []
	if run.current_offers.is_empty():
		_status.text = "前面没有路了。"
		return
	_status.text = "第 %d 间，选一条路。" % run.pending_slot
	for offer in run.current_offers:
		var label := str(DISPLAY.get(str(offer.get("display_key", "")), "房间"))
		var button := _button(label)
		var uid := str(offer.get("offer_uid", ""))
		button.pressed.connect(_choose_offer.bind(uid))
		_body.add_child(button)


func _choose_offer(offer_uid: String) -> void:
	var result := MapService.choose_room(run, offer_uid)
	if not result.get("ok", false):
		_status.text = str(result.get("error", "进不去。"))
		return
	_show()


func _show_battle() -> void:
	_clear_body()
	var room_uid := str(run.current_room.get("room_uid", ""))
	if _battle_room == room_uid and _session != null:
		_set_battle_visible(true)
		return
	_set_battle_visible(false)
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
	_battle_room = ""
	_session = null
	_selected_offer = ""
	_selected_cards = []
	if _is_battle_loss(phase) or _is_battle_loss(outcome) or run.hp <= 0:
		RunService.finish_room(run, "defeat")
	else:
		RunService.finish_room(run, "victory")
	_show()


func _is_battle_loss(phase: String) -> bool:
	return phase == "defeat" or phase == "DEFEAT" or phase == "DECK_EXHAUSTED"


func _show_event() -> void:
	_set_battle_visible(false)
	_clear_body()
	var room_uid := str(run.current_room.get("room_uid", ""))
	var view := EventService.make_view(run, room_uid)
	if not view.get("ok", false):
		_status.text = str(view.get("error", "这个奇遇打不开。"))
		return
	var title := Label.new()
	title.text = str(view.get("name", "奇遇"))
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.93, 0.86, 0.68))
	_body.add_child(title)
	var blurb := str(view.get("text", ""))
	if blurb != "":
		_body.add_child(_hint(blurb))
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
		_body.add_child(leave)


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
		var button := _button(label)
		if picked:
			button.modulate = Color(1, 0.86, 0.55)
		button.pressed.connect(_select_card.bind(str(card_uid), multi, str(view.get("room_uid", ""))))
		_body.add_child(button)
	var confirm := _button("确认")
	confirm.pressed.connect(_confirm_cards.bind(str(view.get("room_uid", "")), str(view.get("handler_id", "")), multi))
	_body.add_child(confirm)


func _select_card(card_uid: String, multi: bool, room_uid: String) -> void:
	if multi:
		if _selected_cards.has(card_uid):
			_selected_cards.erase(card_uid)
		elif _selected_cards.size() < 3:
			_selected_cards.append(card_uid)
		_status.text = _multi_status()
		call_deferred("_show_event")
		return
	_selected_cards = [card_uid]
	var view := EventService.make_view(run, room_uid)
	if str(view.get("handler_id", "")) == "TRANSFORM_CARD":
		var preview := EventService.freeze_preview(run, room_uid, card_uid)
		if preview.get("ok", false):
			_status.text = "会变成 %s" % str(preview.get("label", ""))
		else:
			_status.text = str(preview.get("error", "换不了。"))
	else:
		_status.text = "选好了这张牌。"
	call_deferred("_show_event")


func _confirm_cards(room_uid: String, handler_id: String, multi: bool) -> void:
	var payload := {}
	if multi:
		payload = {"sacrifice_uids": _selected_cards.duplicate()}
	elif handler_id == "TRANSFORM_CARD":
		if _selected_cards.is_empty():
			_status.text = "先选一张牌。"
			return
		var preview: Dictionary = EventService.make_view(run, room_uid).get("previews", {}).get(_selected_cards[0], {})
		if preview.is_empty():
			preview = EventService.freeze_preview(run, room_uid, _selected_cards[0])
		if not preview.get("ok", false):
			_status.text = str(preview.get("error", "换不了。"))
			return
		payload = {"target_uid": _selected_cards[0], "preview_uid": str(preview.get("preview_uid", ""))}
	else:
		if _selected_cards.is_empty():
			_status.text = "先选一张牌。"
			return
		payload = {"target_uid": _selected_cards[0]}
	_commit_event(room_uid, payload)


func _show_offers(view: Dictionary) -> void:
	var handler := str(view.get("handler_id", ""))
	for offer in view.get("offers", []):
		var label := str(offer.get("display_name", ""))
		if str(offer.get("payload_kind", "")) == "CARD":
			label = TowerDeck.describe_parts(str(offer.get("def_id", "")), offer.get("enhancement_ids", []), str(offer.get("display_name", "")))
		var uid := str(offer.get("offer_uid", ""))
		if uid == _selected_offer:
			label = "已选\n" + label
		var button := _button(label)
		if uid == _selected_offer:
			button.modulate = Color(1, 0.86, 0.55)
		button.pressed.connect(_select_offer.bind(uid, handler))
		_body.add_child(button)
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
			var button := _button(label)
			if picked:
				button.modulate = Color(1, 0.86, 0.55)
			button.pressed.connect(_select_card.bind(card_uid, false, str(view.get("room_uid", ""))))
			_body.add_child(button)
	var confirm := _button("确认")
	confirm.pressed.connect(_confirm_offer.bind(str(view.get("room_uid", "")), handler))
	_body.add_child(confirm)


func _select_offer(offer_uid: String, handler: String) -> void:
	_selected_offer = offer_uid
	_selected_cards = []
	if handler == "MARK_OFFER":
		call_deferred("_show_event")
		return
	_status.text = "选好了。"
	call_deferred("_show_event")


func _confirm_offer(room_uid: String, handler: String) -> void:
	if _selected_offer == "":
		_status.text = "先选一项。"
		return
	if handler == "MARK_OFFER":
		if _selected_cards.is_empty():
			_status.text = "再选一张牌。"
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
		_body.add_child(take)
		return
	var accept := _button("收下")
	accept.pressed.connect(_commit_event.bind(str(view.get("room_uid", "")), {"accept": true}))
	_body.add_child(accept)
	var decline := _button("放弃")
	decline.pressed.connect(_commit_event.bind(str(view.get("room_uid", "")), {"accept": false}))
	_body.add_child(decline)


func _skip_event(room_uid: String) -> void:
	_commit_event(room_uid, {"skip": true})


func _commit_event(room_uid: String, payload: Dictionary) -> void:
	var view := EventService.make_view(run, room_uid)
	var title := str(view.get("name", "奇遇"))
	var txn := run.uid("T")
	var result := EventService.commit(run, room_uid, payload, txn)
	if not result.get("ok", false):
		_status.text = str(result.get("error", "没做成。"))
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
	var session := _open_reward_session()
	if session.is_empty():
		_body.add_child(_hint("奖励已经拿完了。"))
		var onward := _button("继续")
		onward.pressed.connect(_finish_reward_step)
		_body.add_child(onward)
		return
	var known := false
	for offer in session.get("offers", []):
		if str(offer.get("offer_uid", "")) == _selected_offer:
			known = true
			break
	if not known:
		_selected_offer = ""
		_selected_cards = []
	if _selected_offer == "" and _selected_cards.is_empty():
		_status.text = "挑一份战利品。"
	elif _selected_cards.is_empty():
		_status.text = "选好了这一项。"
	else:
		_status.text = "选好了这张牌。"
	var plan := GameData.reward(str(session.get("reward_id", "")))
	if str(plan.get("payload_kind", "")) == "MARK":
		_show_mark_reward(session)
	else:
		_show_card_reward(session)


func _show_card_reward(session: Dictionary) -> void:
	_body.add_child(_hint("选一张放进牌库，也可以不要。"))
	var session_uid := str(session.get("reward_session_uid", ""))
	for offer in session.get("offers", []):
		var label := TowerDeck.describe_parts(str(offer.get("def_id", "")), offer.get("enhancement_ids", []), str(offer.get("display_name", "")))
		var uid := str(offer.get("offer_uid", ""))
		if uid == _selected_offer:
			label = "已选\n" + label
		var button := _button(label)
		if uid == _selected_offer:
			button.modulate = Color(1, 0.86, 0.55)
		button.pressed.connect(_select_reward_offer.bind(uid, false))
		_body.add_child(button)
	var confirm := _button("确认")
	confirm.pressed.connect(_confirm_card_reward.bind(session_uid))
	_body.add_child(confirm)
	_add_reward_skip(session)


func _show_mark_reward(session: Dictionary) -> void:
	_body.add_child(_hint("先选一种变化，再选一张牌。也可以不要。"))
	var session_uid := str(session.get("reward_session_uid", ""))
	for offer in session.get("offers", []):
		var label := str(offer.get("display_name", ""))
		var uid := str(offer.get("offer_uid", ""))
		if uid == _selected_offer:
			label = "已选\n" + label
		var button := _button(label)
		if uid == _selected_offer:
			button.modulate = Color(1, 0.86, 0.55)
		button.pressed.connect(_select_reward_offer.bind(uid, true))
		_body.add_child(button)
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
			var button := _button(label)
			if picked:
				button.modulate = Color(1, 0.86, 0.55)
			button.pressed.connect(_select_reward_card.bind(str(card_uid)))
			_body.add_child(button)
	var confirm := _button("确认")
	confirm.pressed.connect(_confirm_mark_reward.bind(session_uid))
	_body.add_child(confirm)
	_add_reward_skip(session)


func _add_reward_skip(session: Dictionary) -> void:
	var plan := GameData.reward(str(session.get("reward_id", "")))
	if not bool(plan.get("can_skip", true)):
		return
	var skip := _button("跳过")
	skip.pressed.connect(_skip_reward.bind(str(session.get("reward_session_uid", ""))))
	_body.add_child(skip)


func _select_reward_offer(offer_uid: String, marks: bool) -> void:
	_selected_offer = offer_uid
	_selected_cards = []
	if marks:
		call_deferred("_show")
		return
	_status.text = "选好了。"
	call_deferred("_show")


func _select_reward_card(card_uid: String) -> void:
	_selected_cards = [card_uid]
	_status.text = "选好了这张牌。"
	call_deferred("_show")


func _confirm_card_reward(session_uid: String) -> void:
	if _selected_offer == "":
		_status.text = "先选一项。"
		return
	var result := RewardService.commit_cards(run, session_uid, _selected_offer, false, run.uid("T"))
	if not result.get("ok", false):
		_status.text = str(result.get("error", "没拿到牌。"))
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
		_status.text = "先选一项。"
		return
	if _selected_cards.is_empty():
		_status.text = "再选一张牌。"
		return
	var target_uid := str(_selected_cards[0])
	var result := RewardService.commit_mark(run, session_uid, _selected_offer, target_uid, run.uid("T"))
	if not result.get("ok", false):
		_status.text = str(result.get("error", "没加上去。"))
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
			_status.text = str(result.get("error", "不能继续"))
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
	var quest := _ready_pizza()
	if not quest.is_empty() and not _pizza_done:
		_show_pizza(quest)
		return
	_body.add_child(_hint("这层的 Boss 倒了。"))
	var onward := _button("继续下一层")
	onward.pressed.connect(_continue_floor.bind(true))
	_body.add_child(onward)
	var stop := _button("结束本局")
	stop.pressed.connect(_continue_floor.bind(false))
	_body.add_child(stop)


func _show_pizza(quest: Dictionary) -> void:
	_body.add_child(_hint("披萨到了。不想要的牌可以丢掉。"))
	for offer in quest.get("reward_snapshot", []):
		var offer_uid := str(offer.get("offer_uid", ""))
		var verb := "丢掉\n" if _selected_cards.has(offer_uid) else "带走\n"
		var button := _button(verb + TowerDeck.describe_parts(str(offer.get("def_id", "")), offer.get("enhancement_ids", []), ""))
		button.pressed.connect(_toggle_discard.bind(offer_uid))
		_body.add_child(button)
	var claim := _button("确认领取")
	claim.pressed.connect(_claim_pizza.bind(str(quest.get("quest_uid", ""))))
	_body.add_child(claim)


func _toggle_discard(offer_uid: String) -> void:
	if _selected_cards.has(offer_uid):
		_selected_cards.erase(offer_uid)
	else:
		_selected_cards.append(offer_uid)
	call_deferred("_show_floor_clear")


func _claim_pizza(quest_uid: String) -> void:
	var result := RewardService.claim_pizza(run, quest_uid, run.uid("T"), _selected_cards.duplicate())
	if not result.get("ok", false):
		_status.text = str(result.get("error", "不能领取"))
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
	_body.add_child(_hint(message))
	var again := _button("新的一局")
	again.pressed.connect(func() -> void: _start_run(str(Time.get_ticks_usec())))
	_body.add_child(again)


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


func _set_battle_visible(show_battle: bool) -> void:
	if _battle == null:
		return
	_battle.visible = show_battle
	_body.visible = not show_battle
	_header.visible = not show_battle
	_status.visible = not show_battle


func _clear_body() -> void:
	# The clicked room button is still emitting. free() is rejected while it is locked.
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.clip_text = false
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 18)
	_queue_fit()
	return button


func _show_notice() -> void:
	_set_battle_visible(false)
	_clear_body()
	_header.text = str(_notice.get("title", "结果"))
	_status.text = ""
	for line in _notice.get("lines", []):
		var text := str(line)
		if text == "":
			continue
		_body.add_child(_hint(text))
	var onward := _button("继续")
	onward.pressed.connect(_dismiss_notice)
	_body.add_child(onward)


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
	_queue_fit()
	return label


func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	call_deferred("_fit_text")


func _fit_text() -> void:
	_fit_queued = false
	if _scroll == null or _body == null or _scroll.size.x < 80.0:
		return
	var width := _scroll.size.x
	var bar := _scroll.get_v_scroll_bar()
	if bar != null and bar.visible:
		width -= bar.size.x
	width = maxf(40.0, width)
	_body.custom_minimum_size.x = width
	_grow_label(_status, width)
	for child in _body.get_children():
		if child is Button:
			_grow_button(child, width)
		elif child is Label:
			_grow_label(child, width)


func _grow_button(button: Button, width: float) -> void:
	var font := button.get_theme_font("font")
	var font_size := button.get_theme_font_size("font_size")
	if font == null:
		return
	var inner := maxf(40.0, width - 24.0)
	var measured := font.get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, inner, font_size)
	var need := measured.y + 22.0
	if absf(button.custom_minimum_size.y - need) > 1.0:
		button.custom_minimum_size.y = need


func _grow_label(label: Label, width: float) -> void:
	if label == null or label.autowrap_mode == TextServer.AUTOWRAP_OFF or label.text == "":
		return
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	if font == null:
		return
	var measured := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, maxf(40.0, width), font_size)
	if absf(label.custom_minimum_size.y - measured.y) > 1.0:
		label.custom_minimum_size.y = measured.y
