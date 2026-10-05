class_name CardPanel
extends VBoxContainer
## Battle owns timing and HP. This panel owns the current hand and expression.

signal preview_changed(result: int)
signal card_burned(instance_id: int, heal: int)

@export var burn_heal_multiplier: int = 10

const CardView = preload("res://scripts/cards/card_view.gd")
const DropZone = preload("res://scripts/cards/expression_drop_zone.gd")

var _hand: Array[CardData] = []
var _expression: Array[CardData] = []
var _active: bool = false
var _generation: int = 0
var _settled_result: int = 0
var _expression_row: HFlowContainer
var _hand_row: HFlowContainer
var _result_label: Label
var _burn_zone: PanelContainer
var _heal_label: Label
var _burned_ids: Dictionary = {}
var _pending_heal: int = 0
var _expression_zone: PanelContainer
var _hand_zone: PanelContainer

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_build_ui()
	_refresh()

func start_player_turn(cards: Array[CardData]) -> void:
	_hand.clear()
	for card in cards:
		if not _burned_ids.has(card.instance_id):
			_hand.append(card)
	_pending_heal = 0
	_expression.clear()
	_generation += 1
	_settled_result = 0
	_active = true
	_refresh()
	preview_changed.emit(0)

func finish_player_turn() -> int:
	if _active:
		_settled_result = ExpressionEvaluator.evaluate(_expression)
		_active = false
		_refresh()
	return _settled_result

func is_turn_active() -> bool:
	return _active

func get_pending_heal() -> int:
	return _pending_heal

func reset_battle() -> void:
	_active = false
	_generation += 1
	_hand.clear()
	_expression.clear()
	_burned_ids.clear()
	_pending_heal = 0
	_settled_result = 0
	_refresh()
	preview_changed.emit(0)

func burn_card(instance_id: int) -> bool:
	var index := _find_card(_hand, instance_id)
	if not _active or index < 0 or _hand[index].kind != CardData.Kind.NUMBER:
		return false
	var heal := absi(_hand[index].number) * maxi(0, burn_heal_multiplier)
	_hand.remove_at(index)
	_burned_ids[instance_id] = true
	_pending_heal += heal
	_refresh()
	card_burned.emit(instance_id, heal)
	return true

func drag_payload(instance_id: int, source: StringName = &"hand") -> Dictionary:
	return {"panel": self, "turn": _generation, "card_id": instance_id, "source": source}

func can_accept_drop(data: Variant, target: StringName = &"expression") -> bool:
	if not _active or not data is Dictionary:
		return false
	if data.get("panel") != self or data.get("turn") != _generation:
		return false
	if not data.get("card_id") is int:
		return false
	if target == &"expression" and data.get("source") == &"hand":
		return _find_card(_hand, data["card_id"]) >= 0
	if target == &"hand" and data.get("source") == &"expression":
		return _find_card(_expression, data["card_id"]) >= 0
	if target == &"burn" and data.get("source") == &"hand":
		var index := _find_card(_hand, data["card_id"])
		return index >= 0 and _hand[index].kind == CardData.Kind.NUMBER
	return false

func accept_drop(data: Variant, target: StringName = &"expression", insertion_index: int = -1) -> bool:
	if not can_accept_drop(data, target):
		return false
	if target == &"hand":
		return return_card(data["card_id"])
	if target == &"burn":
		return burn_card(data["card_id"])
	return insert_card(data["card_id"], _expression.size() if insertion_index == -1 else insertion_index)

func insert_card(instance_id: int, insertion_index: int) -> bool:
	var index := _find_card(_hand, instance_id)
	if not _active or index < 0 or insertion_index < 0 or insertion_index > _expression.size():
		return false
	_expression.insert(insertion_index, _hand[index])
	_hand.remove_at(index)
	_expression_changed()
	return true

func return_card(instance_id: int) -> bool:
	var index := _find_card(_expression, instance_id)
	if not _active or index < 0:
		return false
	_hand.append(_expression[index])
	_expression.remove_at(index)
	_expression_changed()
	return true

func _expression_changed() -> void:
	_refresh()
	preview_changed.emit(ExpressionEvaluator.evaluate(_expression))

func get_hand_cards() -> Array[CardData]:
	return _hand.duplicate()

func get_expression_cards() -> Array[CardData]:
	return _expression.duplicate()

func _find_card(cards: Array[CardData], instance_id: int) -> int:
	for index in range(cards.size()):
		if cards[index].instance_id == instance_id:
			return index
	return -1

func _build_ui() -> void:
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 28)
	add_child(_result_label)
	_expression_zone = _make_zone(&"expression")
	add_child(_expression_zone)
	_expression_row = HFlowContainer.new()
	_expression_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_expression_row.add_theme_constant_override("h_separation", 10)
	_expression_row.add_theme_constant_override("v_separation", 10)
	_expression_zone.add_child(_expression_row)
	_expression_zone.card_row = _expression_row
	var hand_heading := Label.new()
	hand_heading.text = "手牌"
	hand_heading.add_theme_font_size_override("font_size", 22)
	add_child(hand_heading)
	_hand_zone = _make_zone(&"hand")
	add_child(_hand_zone)
	_hand_row = HFlowContainer.new()
	_hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_row.add_theme_constant_override("h_separation", 12)
	_hand_row.add_theme_constant_override("v_separation", 12)
	_hand_zone.add_child(_hand_row)
	_hand_zone.card_row = _hand_row
	_burn_zone = _make_zone(&"burn")
	_burn_zone.custom_minimum_size.y = 64
	_burn_zone.tooltip_text = "数字牌烧毁后本场移除，回合结束回血。"
	add_child(_burn_zone)
	var burn_row := HBoxContainer.new()
	burn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burn_zone.add_child(burn_row)
	var burn_title := Label.new()
	burn_title.text = "烧牌"
	burn_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	burn_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burn_row.add_child(burn_title)
	_heal_label = Label.new()
	_heal_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burn_row.add_child(_heal_label)

func _make_zone(region: StringName) -> PanelContainer:
	var zone := DropZone.new()
	zone.card_panel = self
	zone.region = region
	zone.custom_minimum_size.y = 150
	var style := StyleBoxFlat.new()
	style.bg_color = Color("122633") if region == &"expression" else Color("101f2c")
	style.border_color = Color("385e70")
	if region == &"burn":
		style.bg_color = Color("33251f")
		style.border_color = Color("ad7049")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_top = 16
	style.content_margin_right = 16
	style.content_margin_bottom = 16
	zone.add_theme_stylebox_override("panel", style)
	return zone

func _refresh() -> void:
	if not is_node_ready():
		return
	_expression_zone.clear_hint()
	_hand_zone.clear_hint()
	_burn_zone.clear_hint()
	_rebuild_cards(_hand_row, _hand, &"hand", _hand_zone)
	_rebuild_cards(_expression_row, _expression, &"expression", _expression_zone)
	if _expression.is_empty():
		_add_placeholder(_expression_row, "算式")
	if _hand.is_empty():
		_add_placeholder(_hand_row, "空")
	var valid := ExpressionEvaluator.is_valid(_expression)
	_result_label.text = "结果 %d" % ExpressionEvaluator.evaluate(_expression)
	if not valid:
		_result_label.text += " · 未完成"
	_heal_label.text = "回血 +%d" % _pending_heal

func _add_placeholder(row: Container, text: String) -> void:
	var placeholder := Label.new()
	placeholder.text = text
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placeholder.custom_minimum_size.y = 116
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(placeholder)

func _rebuild_cards(row: Container, cards: Array[CardData], region: StringName, zone: Control) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for card in cards:
		var view := CardView.new()
		view.card = card
		view.card_panel = self
		view.draggable = _active
		view.source_region = region
		view.drop_zone = zone
		row.add_child(view)
