class_name RunInventory
extends Control
## Read-only run bag. It lists cards and collections; it does not move, destroy, or spend them.

const CARD_SCENE := preload("res://scenes/cards/card_view.tscn")

@export var battle_anchor_top := 0.42
@export var battle_bottom_reserve := 230.0
@export var roam_anchor_top := 0.16
@export_range(0.55, 0.85, 0.01) var card_column_ratio := 0.75
@export var slide_seconds := 0.45
@export var tab_hover_seconds := 0.12
@export var tab_hover_lift := 8.0
@export var bag_texture: Texture2D

var _host: Node
var _use_fixed := false
var _fixed_run: RunState
var _fixed_library: CardLibrary
var _fixed_battle: CardBattle
var _input_view: RunBattle
var _meta: MetaResourceProvider = MetaResourceProvider.new()
var _snapshot: Dictionary = {}
var _signature_text := ""
var _kind := RunInventoryPresenter.KIND_ALL
var _marks := RunInventoryPresenter.MARKS_ALL
var _sort_mode := RunInventoryPresenter.SORT_ACQUIRED
var _selected_uid := ""
var _target_open := false
var _sliding := false
var _open_ratio := 0.0
var _hover_lift := 0.0
var _pending_scroll := 0
var _pause_claim := false
var _pause_was_set := false
var _claimed_battle_id := 0
var _battle_clearance := false
var _slide_tween: Tween
var _hover_tween: Tween
var _split_pending := false
var _applying_anchors := false

@onready var _blocker: ColorRect = $InputBlocker
@onready var _drawer_host: Control = $DrawerHost
@onready var _slide: Control = $DrawerHost/Slide
@onready var _panel: PanelContainer = $DrawerHost/Slide/BagPanel
@onready var _title: Label = $DrawerHost/Slide/BagPanel/Margin/Body/Header/Title
@onready var _pause_badge: Label = $DrawerHost/Slide/BagPanel/Margin/Body/Header/PauseBadge
@onready var _close: Button = $DrawerHost/Slide/BagPanel/Margin/Body/Header/CloseButton
@onready var _split: HSplitContainer = $DrawerHost/Slide/BagPanel/Margin/Body/Split
@onready var _stats: Label = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/Stats
@onready var _kind_all: Button = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/Filters/KindAll
@onready var _kind_num: Button = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/Filters/KindNum
@onready var _kind_op: Button = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/Filters/KindOp
@onready var _mark_all: Button = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/Filters/MarkAll
@onready var _mark_yes: Button = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/Filters/MarkYes
@onready var _mark_no: Button = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/Filters/MarkNo
@onready var _sort_option: OptionButton = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/Filters/SortOption
@onready var _card_scroll: ScrollContainer = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/CardScroll
@onready var _empty: Label = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/CardScroll/CardBox/EmptyLabel
@onready var _grid: GridContainer = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/CardScroll/CardBox/Grid
@onready var _detail_scroll: ScrollContainer = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/DetailScroll
@onready var _detail: Label = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Cards/DetailScroll/Detail
@onready var _run_hint: Label = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Resources/RunHint
@onready var _collection_empty: Label = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Resources/CollectionScroll/CollectionBox/CollectionEmpty
@onready var _collection_list: VBoxContainer = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Resources/CollectionScroll/CollectionBox/CollectionList
@onready var _meta_header: Label = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Resources/MetaHeader
@onready var _meta_empty: Label = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Resources/MetaScroll/MetaBox/MetaEmpty
@onready var _meta_list: VBoxContainer = $DrawerHost/Slide/BagPanel/Margin/Body/Split/Resources/MetaScroll/MetaBox/MetaList
@onready var _tab: Button = $DrawerHost/Slide/TabButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	_drawer_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_host.clip_contents = true
	_panel.clip_contents = true
	_slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unlock(_slide)
	_unlock(_panel)
	_unlock(_tab)
	_apply_chrome()
	_configure_filters()
	_tab.pressed.connect(_on_tab_pressed)
	_tab.mouse_entered.connect(_on_tab_entered)
	_tab.mouse_exited.connect(_on_tab_exited)
	_tab.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(request_close)
	_close.focus_mode = Control.FOCUS_NONE
	resized.connect(_apply_host_anchors)
	_drawer_host.resized.connect(_on_drawer_resized)
	_split.resized.connect(_apply_split)
	_card_scroll.resized.connect(_update_columns)
	_pause_badge.visible = false
	_detail.text = "选择一张牌查看详情"
	_run_hint.text = RunInventoryPresenter.RUN_RECORD_NOTE
	_meta_empty.text = MetaResourceProvider.DISCONNECTED_TEXT
	_apply_host_anchors()
	_apply_panel_visibility()
	_apply_blocker()


func _exit_tree() -> void:
	abandon_pause_claim()
	_target_open = false
	_sliding = false
	_open_ratio = 0.0
	_apply_input_lock()


func _process(_delta: float) -> void:
	if not _target_open:
		return
	var snapshot := _present()
	var signature := _signature(snapshot)
	if signature == _signature_text:
		return
	_snapshot = snapshot
	_signature_text = signature
	_rebuild(true)


func _input(event: InputEvent) -> void:
	if not blocks_input():
		return
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			request_close()
			get_viewport().set_input_as_handled()
		KEY_P, KEY_B, KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			get_viewport().set_input_as_handled()


func bind_host(host: Node) -> void:
	_host = host
	_use_fixed = false


func set_sources(run_state: RunState, library: CardLibrary = null, battle: CardBattle = null) -> void:
	_use_fixed = true
	_fixed_run = run_state
	_fixed_library = library
	_fixed_battle = battle


func set_input_view(view: RunBattle) -> void:
	_input_view = view


func set_meta_provider(provider: MetaResourceProvider) -> void:
	_meta = provider if provider != null else MetaResourceProvider.new()
	if _meta_list != null:
		_paint_meta()


func set_battle_clearance(enabled: bool) -> void:
	_battle_clearance = enabled
	_apply_host_anchors()


func blocks_input() -> bool:
	return _target_open or _sliding or _open_ratio > 0.001


func request_open() -> void:
	if _target_open and not _sliding:
		return
	_target_open = true
	_claim_pause()
	_reload(true)
	_start_slide(1.0)


func request_close() -> void:
	if not blocks_input():
		return
	if not _target_open and _sliding:
		return
	_target_open = false
	_start_slide(0.0)


func reset_run() -> void:
	abandon_pause_claim()
	_kind = RunInventoryPresenter.KIND_ALL
	_marks = RunInventoryPresenter.MARKS_ALL
	_sort_mode = RunInventoryPresenter.SORT_ACQUIRED
	_selected_uid = ""
	_snapshot = RunInventoryPresenter.present(null)
	_signature_text = ""
	_pending_scroll = 0
	_stop_slide()
	_target_open = false
	_sliding = false
	_open_ratio = 0.0
	_hover_lift = 0.0
	if _card_scroll != null:
		_card_scroll.scroll_vertical = 0
	_sync_filters()
	_apply_panel_visibility()
	_apply_blocker()
	_apply_input_lock()
	_layout_slide()
	if _grid != null:
		_rebuild(false)


func detach_combat() -> void:
	abandon_pause_claim()
	if _target_open or _open_ratio > 0.0:
		_reload(true)


func abandon_pause_claim() -> void:
	_pause_claim = false
	_pause_was_set = false
	_claimed_battle_id = 0
	_show_pause_badge(false)


func _configure_filters() -> void:
	var kind_group := ButtonGroup.new()
	kind_group.allow_unpress = false
	var mark_group := ButtonGroup.new()
	mark_group.allow_unpress = false
	_bind_filter(_kind_all, kind_group, _on_kind_all)
	_bind_filter(_kind_num, kind_group, _on_kind_num)
	_bind_filter(_kind_op, kind_group, _on_kind_op)
	_bind_filter(_mark_all, mark_group, _on_marks_all)
	_bind_filter(_mark_yes, mark_group, _on_marks_yes)
	_bind_filter(_mark_no, mark_group, _on_marks_no)
	_sort_option.clear()
	_sort_option.add_item("获得顺序")
	_sort_option.add_item("牌面数值")
	if not _sort_option.item_selected.is_connected(_on_sort_selected):
		_sort_option.item_selected.connect(_on_sort_selected)
	_sync_filters()


func _bind_filter(button: Button, group: ButtonGroup, handler: Callable) -> void:
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	if not button.pressed.is_connected(handler):
		button.pressed.connect(handler)


func _on_tab_pressed() -> void:
	if _target_open:
		request_close()
	else:
		request_open()


func _on_tab_entered() -> void:
	_tween_hover(tab_hover_lift)


func _on_tab_exited() -> void:
	_tween_hover(0.0)


func _on_kind_all() -> void:
	_set_kind(RunInventoryPresenter.KIND_ALL)


func _on_kind_num() -> void:
	_set_kind(RunInventoryPresenter.KIND_NUM)


func _on_kind_op() -> void:
	_set_kind(RunInventoryPresenter.KIND_OP)


func _on_marks_all() -> void:
	_set_marks(RunInventoryPresenter.MARKS_ALL)


func _on_marks_yes() -> void:
	_set_marks(RunInventoryPresenter.MARKS_PRESENT)


func _on_marks_no() -> void:
	_set_marks(RunInventoryPresenter.MARKS_PLAIN)


func _on_sort_selected(index: int) -> void:
	var mode := RunInventoryPresenter.SORT_VALUE if index == 1 else RunInventoryPresenter.SORT_ACQUIRED
	if _sort_mode == mode:
		return
	_sort_mode = mode
	_rebuild(true)


func _on_card_pressed(card_uid: String) -> void:
	_selected_uid = card_uid
	_paint_selection()
	_paint_detail()
	if _detail_scroll != null:
		_detail_scroll.scroll_vertical = 0


func _on_drawer_resized() -> void:
	_layout_slide()
	_queue_split()


func _apply_split() -> void:
	_queue_split()


func _queue_split() -> void:
	if _split_pending or _split == null:
		return
	_split_pending = true
	call_deferred("_apply_split_now")


func _apply_split_now() -> void:
	_split_pending = false
	if _split == null or _split.get_child_count() < 2:
		return
	var cards_pane := _split.get_child(0) as Control
	var resource_pane := _split.get_child(1) as Control
	if cards_pane != null:
		cards_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards_pane.size_flags_stretch_ratio = card_column_ratio
	if resource_pane != null:
		resource_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resource_pane.size_flags_stretch_ratio = maxf(0.05, 1.0 - card_column_ratio)
	if _split.split_offset != 0:
		_split.split_offset = 0


func _set_kind(kind: String) -> void:
	if _kind == kind:
		_sync_filters()
		return
	_kind = kind
	_sync_filters()
	_rebuild(true)


func _set_marks(marks: String) -> void:
	if _marks == marks:
		_sync_filters()
		return
	_marks = marks
	_sync_filters()
	_rebuild(true)


func _sync_filters() -> void:
	if _kind_all == null:
		return
	_kind_all.set_pressed_no_signal(_kind == RunInventoryPresenter.KIND_ALL)
	_kind_num.set_pressed_no_signal(_kind == RunInventoryPresenter.KIND_NUM)
	_kind_op.set_pressed_no_signal(_kind == RunInventoryPresenter.KIND_OP)
	_mark_all.set_pressed_no_signal(_marks == RunInventoryPresenter.MARKS_ALL)
	_mark_yes.set_pressed_no_signal(_marks == RunInventoryPresenter.MARKS_PRESENT)
	_mark_no.set_pressed_no_signal(_marks == RunInventoryPresenter.MARKS_PLAIN)
	if _sort_option == null:
		return
	_sort_option.set_block_signals(true)
	_sort_option.select(1 if _sort_mode == RunInventoryPresenter.SORT_VALUE else 0)
	_sort_option.set_block_signals(false)


func _reload(keep_scroll: bool) -> void:
	_snapshot = _present()
	_signature_text = _signature(_snapshot)
	_rebuild(keep_scroll)


func _rebuild(keep_scroll: bool) -> void:
	if _grid == null:
		return
	var scroll_y := 0
	if keep_scroll and _card_scroll != null:
		scroll_y = _card_scroll.scroll_vertical
	var cards: Array = _snapshot.get("cards", [])
	var alive := false
	for card in cards:
		if str(card.get("card_uid", "")) == _selected_uid:
			alive = true
			break
	if not alive:
		_selected_uid = ""
	var shown := RunInventoryPresenter.filter_sort(cards, _kind, _marks, _sort_mode)
	_wipe(_grid)
	if cards.is_empty():
		_empty.visible = true
		_empty.text = "本局还没有可查看的卡牌"
	elif shown.is_empty():
		_empty.visible = true
		_empty.text = "没有符合筛选的卡牌"
	else:
		_empty.visible = false
	for card in shown:
		var view := CARD_SCENE.instantiate() as CardView
		view.set_compact(true)
		view.focus_mode = Control.FOCUS_NONE
		var face = card.get("face", {})
		if face is Dictionary:
			view.bind_face(face)
		view.set_highlight("selected" if str(card.get("card_uid", "")) == _selected_uid else "")
		view.pressed.connect(_on_card_pressed)
		_grid.add_child(view)
	_paint_stats()
	_paint_detail()
	_paint_collections()
	_paint_meta()
	_update_columns()
	_pending_scroll = scroll_y if keep_scroll else 0
	call_deferred("_restore_scroll")


func _restore_scroll() -> void:
	if _card_scroll == null:
		return
	_card_scroll.scroll_vertical = _pending_scroll


func _paint_stats() -> void:
	var counts: Dictionary = _snapshot.get("counts", {})
	_stats.text = "共 %d 张    数字 %d    符号 %d    有强化 %d    无强化 %d" % [
		int(counts.get("total", 0)),
		int(counts.get("num", 0)),
		int(counts.get("op", 0)),
		int(counts.get("enhanced", 0)),
		int(counts.get("plain", 0)),
	]


func _paint_selection() -> void:
	for child in _grid.get_children():
		var view := child as CardView
		if view == null:
			continue
		view.set_highlight("selected" if view.card_uid == _selected_uid else "")


func _paint_detail() -> void:
	if _selected_uid == "":
		_detail.text = "选择一张牌查看详情"
		return
	for card in _snapshot.get("cards", []):
		if str(card.get("card_uid", "")) == _selected_uid:
			_detail.text = _detail_text(card)
			return
	_detail.text = "选择一张牌查看详情"


func _detail_text(card: Dictionary) -> String:
	var lines := PackedStringArray()
	var head := str(card.get("value_text", ""))
	var card_name := str(card.get("name", ""))
	if card_name != "" and card_name != head:
		head = "%s    %s" % [head, card_name]
	lines.append(head)
	lines.append("所在区域：%s" % str(card.get("zone_label", "")))
	lines.append("获取层数：%d" % int(card.get("acquired_depth", 0)))
	lines.append(_usage("回手", bool(card.get("has_return", false)), bool(card.get("return_used", false))))
	lines.append(_usage("焖烧", bool(card.get("has_smolder", false)), bool(card.get("smolder_used", false))))
	var mark_lines: Array = card.get("mark_lines", [])
	if mark_lines.is_empty():
		lines.append("强化：无")
	else:
		lines.append("强化：")
		for line in mark_lines:
			lines.append(str(line))
	return "\n".join(lines)


func _usage(title: String, has_mark: bool, used: bool) -> String:
	if not has_mark:
		return "%s：无此强化" % title
	if used:
		return "%s：已消耗" % title
	return "%s：未消耗" % title


func _paint_collections() -> void:
	_wipe(_collection_list)
	var items: Array = _snapshot.get("collections", [])
	_collection_empty.visible = items.is_empty()
	_collection_empty.text = "本局尚未获得收藏品"
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s\n来源：%s\n估值 %d\n%s" % [
			item.get("name", ""),
			item.get("source_name", ""),
			int(item.get("value_score", 0)),
			item.get("note", RunInventoryPresenter.RUN_RECORD_NOTE),
		]
		_collection_list.add_child(label)


func _paint_meta() -> void:
	if _meta_list == null:
		return
	_wipe(_meta_list)
	var provider := _meta if _meta != null else MetaResourceProvider.new()
	if not provider.is_available():
		if _meta_header != null:
			_meta_header.text = MetaResourceProvider.DISCONNECTED_TEXT
		_meta_empty.visible = false
		return
	if _meta_header != null:
		_meta_header.text = "局外资源"
	var rows: Array = provider.list_resources()
	_meta_empty.visible = rows.is_empty()
	if rows.is_empty():
		_meta_empty.text = "没有局外资源"
		return
	for item in rows:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		_meta_list.add_child(_resource_row(item))


func _resource_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon = item.get("icon", null)
	if icon is Texture2D:
		var rect := TextureRect.new()
		rect.texture = icon
		rect.custom_minimum_size = Vector2(28, 28)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(rect)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text := "%s × %d" % [str(item.get("name", item.get("id", ""))), int(item.get("count", 0))]
	var description := str(item.get("description", ""))
	if description != "":
		text += "\n" + description
	label.text = text
	row.add_child(label)
	return row


func _present() -> Dictionary:
	var sources := _sources()
	return RunInventoryPresenter.present(sources.get("run", null), sources.get("library", null))


func _sources() -> Dictionary:
	if _use_fixed:
		return {"run": _fixed_run, "library": _fixed_library, "battle": _fixed_battle}
	if _host != null and is_instance_valid(_host) and _host.has_method("inventory_sources"):
		var sources = _host.inventory_sources()
		if sources is Dictionary:
			return sources
	return {}


func _signature(snapshot: Dictionary) -> String:
	var parts := PackedStringArray()
	for card in snapshot.get("cards", []):
		var ids := PackedStringArray()
		for enh_id in card.get("enhancement_ids", []):
			ids.append(str(enh_id))
		parts.append("%s/%s/%s/%s/%s/%s/%s/%s/%s" % [
			card.get("card_uid", ""),
			card.get("zone", ""),
			card.get("def_id", ""),
			card.get("printed_value", 0),
			"|".join(ids),
			card.get("return_used", false),
			card.get("smolder_used", false),
			card.get("frozen", false),
			card.get("acquired_depth", 0),
		])
	parts.append("#")
	for item in snapshot.get("collections", []):
		parts.append("%s/%s/%s/%s" % [
			item.get("card_uid", ""),
			item.get("collection_id", ""),
			item.get("value_score", 0),
			item.get("source_def_id", ""),
		])
	return "|".join(parts)


func _claim_pause() -> void:
	if _pause_claim:
		_show_pause_badge(true)
		return
	var battle := _current_battle()
	if battle == null:
		_show_pause_badge(false)
		return
	_pause_claim = true
	_pause_was_set = battle.paused
	_claimed_battle_id = battle.get_instance_id()
	battle.paused = true
	_show_pause_badge(true)


func _release_pause() -> void:
	if not _pause_claim:
		_show_pause_badge(false)
		return
	var claimed := _claimed_battle_id
	var was_set := _pause_was_set
	_pause_claim = false
	_pause_was_set = false
	_claimed_battle_id = 0
	var battle := _current_battle()
	if battle != null and battle.get_instance_id() == claimed and not was_set:
		battle.paused = false
	_show_pause_badge(false)


func _current_battle() -> CardBattle:
	var battle = _sources().get("battle", null)
	if battle == null or not is_instance_valid(battle):
		return null
	return battle


func _show_pause_badge(show: bool) -> void:
	if _pause_badge == null:
		return
	_pause_badge.visible = show


func _start_slide(target_ratio: float) -> void:
	_stop_slide()
	_sliding = true
	_apply_panel_visibility()
	_apply_blocker()
	_apply_input_lock()
	if slide_seconds <= 0.0:
		_set_open_ratio(target_ratio)
		_finish_slide()
		return
	_slide_tween = create_tween()
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.set_ease(Tween.EASE_IN_OUT)
	_slide_tween.tween_method(_set_open_ratio, _open_ratio, target_ratio, slide_seconds)
	_slide_tween.finished.connect(_finish_slide)


func _finish_slide() -> void:
	_sliding = false
	_slide_tween = null
	if not _target_open:
		_open_ratio = 0.0
		_release_pause()
	_apply_panel_visibility()
	_apply_blocker()
	_apply_input_lock()
	_layout_slide()


func _stop_slide() -> void:
	if _slide_tween != null:
		_slide_tween.kill()
		_slide_tween = null


func _set_open_ratio(value: float) -> void:
	_open_ratio = clampf(value, 0.0, 1.0)
	_layout_slide()


func _tween_hover(target: float) -> void:
	if not is_inside_tree():
		return
	if _hover_tween != null:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_method(_set_hover_lift, _hover_lift, target, tab_hover_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_hover_lift(value: float) -> void:
	_hover_lift = value
	_layout_slide()


func _apply_host_anchors() -> void:
	if _drawer_host == null or _applying_anchors:
		return
	_applying_anchors = true
	_drawer_host.anchor_left = 0.0
	_drawer_host.anchor_right = 1.0
	_drawer_host.anchor_bottom = 1.0
	_drawer_host.offset_left = 16.0
	_drawer_host.offset_right = -16.0
	if _battle_clearance:
		var height := size.y
		var top := clampf(battle_anchor_top * height, 0.0, maxf(0.0, height - 48.0))
		var bottom := clampf(height - battle_bottom_reserve, top + 48.0, height)
		_drawer_host.anchor_top = 0.0
		_drawer_host.offset_top = top
		_drawer_host.offset_bottom = bottom - height
	else:
		_drawer_host.anchor_top = roam_anchor_top
		_drawer_host.offset_top = 0.0
		_drawer_host.offset_bottom = 0.0
	_layout_slide()
	_applying_anchors = false


func _layout_slide() -> void:
	if _drawer_host == null or _slide == null or _tab == null or _panel == null:
		return
	var host_size := _drawer_host.size
	var tab_size := _tab.custom_minimum_size
	if tab_size.x < 1.0:
		tab_size.x = 132.0
	if tab_size.y < 1.0:
		tab_size.y = 40.0
	_tab.size = tab_size
	_tab.position = Vector2((host_size.x - tab_size.x) * 0.5, -_hover_lift)
	_slide.size = host_size
	_slide.position = Vector2(0, maxf(0.0, host_size.y - tab_size.y) * (1.0 - _open_ratio))
	_panel.position = Vector2(0, tab_size.y)
	var panel_height := maxf(0.0, host_size.y - tab_size.y)
	_panel.custom_minimum_size = Vector2(0, 0)
	_reserve_detail_height(panel_height)
	_panel.size = Vector2(host_size.x, panel_height)


func _reserve_detail_height(panel_height: float) -> void:
	if _detail_scroll == null or _panel == null or panel_height < 1.0:
		return
	var current := _detail_scroll.custom_minimum_size.y
	var base := _panel.get_combined_minimum_size().y - current
	var room := panel_height - base
	var want := 0.0
	if room >= 128.0:
		want = minf(clampf(room * 0.42, 72.0, 168.0), room - 56.0)
	elif room > 48.0:
		want = room * 0.45
	if absf(current - want) <= 1.0:
		return
	_detail_scroll.custom_minimum_size.y = want


func _update_columns() -> void:
	if _grid == null or _card_scroll == null:
		return
	var separation := _grid.get_theme_constant("h_separation")
	var card_w := 92.0
	var width := _card_scroll.size.x
	if _split != null and _split.size.x > 1.0:
		width = _split.size.x * card_column_ratio - 36.0
	var columns := int((width + separation) / (card_w + separation))
	_grid.columns = maxi(1, columns)
	call_deferred("_apply_split")


func _apply_panel_visibility() -> void:
	if _panel == null:
		return
	var show := _target_open or _sliding or _open_ratio > 0.001
	_panel.visible = show
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if show else Control.MOUSE_FILTER_IGNORE


func _apply_blocker() -> void:
	if _blocker == null:
		return
	var block := blocks_input()
	_blocker.visible = block
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP if block else Control.MOUSE_FILTER_IGNORE


func _apply_input_lock() -> void:
	var locked := blocks_input()
	if _input_view != null and is_instance_valid(_input_view):
		_input_view.set_external_input_blocked(locked)
	if _host != null and is_instance_valid(_host) and _host.has_method("set_inventory_input_locked"):
		_host.set_inventory_input_locked(locked)


func _apply_chrome() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	var ui := Theme.new()
	ui.default_font = font
	ui.default_font_size = 16
	theme = ui
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.93, 0.86, 0.68))
	_pause_badge.add_theme_color_override("font_color", Color(0.95, 0.72, 0.42))
	_stats.add_theme_color_override("font_color", Color(0.78, 0.82, 0.74))
	_detail.add_theme_color_override("font_color", Color(0.9, 0.92, 0.88))
	_run_hint.add_theme_color_override("font_color", Color(0.93, 0.86, 0.68))
	_tab.add_theme_font_size_override("font_size", 18)
	_tab.custom_minimum_size = Vector2(132, 40)
	if bag_texture != null:
		var textured := StyleBoxTexture.new()
		textured.texture = bag_texture
		textured.set_expand_margin_all(12)
		_panel.add_theme_stylebox_override("panel", textured)
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.16, 0.96)
	style.border_color = Color(0.93, 0.78, 0.42, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)


func _unlock(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0


func _wipe(node: Node) -> void:
	var doomed: Array = []
	for child in node.get_children():
		doomed.append(child)
	for child in doomed:
		node.remove_child(child)
		child.queue_free()
