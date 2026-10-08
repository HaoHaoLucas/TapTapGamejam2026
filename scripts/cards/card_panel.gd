class_name CardPanel
extends VBoxContainer
## Battle owns timing and HP. This panel owns the current hand, expression, and formula.

signal preview_changed(result: float)
signal card_burned(instance_id: int, heal: int)

@export var burn_heal_multiplier: int = 10

const CardView = preload("res://scripts/cards/card_view.gd")
const DropZone = preload("res://scripts/cards/expression_drop_zone.gd")

var _hand: Array[CardData] = []
var _expression: Array[CardData] = []
var _constraint: Array[FormulaSlot] = []
var _active: bool = false
var _generation: int = 0
var _settled_result: float = 0.0
var _settled_exact: Rational
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
	_constraint.clear()
	_generation += 1
	_settled_result = 0.0
	_settled_exact = Rational.from_int(0)
	_active = true
	_refresh()
	preview_changed.emit(0)

func finish_player_turn() -> float:
	if _active:
		_settled_exact = _current_outcome().result
		_settled_result = _settled_exact.to_float()
		_active = false
		_refresh()
	return _settled_result

func get_exact_result() -> Rational:
	if _active:
		return _current_outcome().result
	return _settled_exact if _settled_exact != null else Rational.from_int(0)

func is_turn_active() -> bool:
	return _active

func get_pending_heal() -> int:
	return _pending_heal

func reset_battle() -> void:
	_active = false
	_generation += 1
	_hand.clear()
	_expression.clear()
	_constraint.clear()
	_burned_ids.clear()
	_pending_heal = 0
	_settled_result = 0.0
	_settled_exact = Rational.from_int(0)
	_refresh()
	preview_changed.emit(0)

func has_formula_constraint() -> bool:
	return not _constraint.is_empty()

func apply_formula_constraint(slots: Array[FormulaSlot]) -> bool:
	if not _active or not FormulaSlot.is_valid_template(slots):
		return false
	var installed := FormulaSlot.clone_all(slots)
	_release_expression_cards()
	_constraint = installed
	_expression.clear()
	_expression_changed()
	return true

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
		return _find_expression_card(data["card_id"]) >= 0
	if target == &"burn" and data.get("source") == &"hand":
		var index := _find_card(_hand, data["card_id"])
		return index >= 0 and _hand[index].kind == CardData.Kind.NUMBER
	return false

func is_special_drop(instance_id: int) -> bool:
	var index := _find_card(_hand, instance_id)
	if index < 0 or _hand[index].kind != CardData.Kind.SPECIAL:
		return false
	return FormulaSlot.is_valid_template(_hand[index].slots)

func can_fill_slot(instance_id: int, slot_index: int) -> bool:
	if not _active or _constraint.is_empty():
		return false
	if slot_index < 0 or slot_index >= _constraint.size():
		return false
	var hand_index := _find_card(_hand, instance_id)
	if hand_index < 0:
		return false
	return _slot_accepts(_constraint[slot_index], _hand[hand_index])

func accept_drop(data: Variant, target: StringName = &"expression", insertion_index: int = -1) -> bool:
	if not can_accept_drop(data, target):
		return false
	if target == &"hand":
		return return_card(data["card_id"])
	if target == &"burn":
		return burn_card(data["card_id"])
	var hand_index := _find_card(_hand, data["card_id"])
	if hand_index >= 0 and _hand[hand_index].kind == CardData.Kind.SPECIAL:
		return _play_special(_hand[hand_index])
	if not _constraint.is_empty():
		return insert_card(data["card_id"], insertion_index)
	var index := _expression.size() if insertion_index == -1 else insertion_index
	return insert_card(data["card_id"], index)

func insert_card(instance_id: int, insertion_index: int) -> bool:
	var index := _find_card(_hand, instance_id)
	if not _active or index < 0 or _hand[index].kind == CardData.Kind.SPECIAL:
		return false
	if not _constraint.is_empty():
		if not can_fill_slot(instance_id, insertion_index):
			return false
		_constraint[insertion_index].card = _hand[index]
		_hand.remove_at(index)
		_expression_changed()
		return true
	if insertion_index < 0 or insertion_index > _expression.size():
		return false
	_expression.insert(insertion_index, _hand[index])
	_hand.remove_at(index)
	_expression_changed()
	return true

func return_card(instance_id: int) -> bool:
	if not _active:
		return false
	if not _constraint.is_empty():
		for slot in _constraint:
			if slot.card != null and slot.card.instance_id == instance_id:
				_hand.append(slot.card)
				slot.card = null
				_expression_changed()
				return true
		return false
	var index := _find_card(_expression, instance_id)
	if index < 0:
		return false
	_hand.append(_expression[index])
	_expression.remove_at(index)
	_expression_changed()
	return true

func _play_special(card: CardData) -> bool:
	if not FormulaSlot.is_valid_template(card.slots):
		return false
	var installed := FormulaSlot.clone_all(card.slots)
	_release_expression_cards()
	var index := _find_card(_hand, card.instance_id)
	if index < 0:
		return false
	_hand.remove_at(index)
	_constraint = installed
	_expression.clear()
	_expression_changed()
	return true

func _release_expression_cards() -> void:
	if _constraint.is_empty():
		for card in _expression:
			_hand.append(card)
		_expression.clear()
		return
	for slot in _constraint:
		if slot.card != null:
			_hand.append(slot.card)
			slot.card = null
	_constraint.clear()
	_expression.clear()

func _slot_accepts(slot: FormulaSlot, card: CardData) -> bool:
	if slot.locked or slot.card != null:
		return false
	if card.kind == CardData.Kind.NUMBER:
		return slot.kind == FormulaSlot.Kind.NUMBER
	if card.kind == CardData.Kind.OPERATOR:
		return slot.kind == FormulaSlot.Kind.OPERATOR
	return false

func _expression_changed() -> void:
	_refresh()
	preview_changed.emit(_current_outcome().result.to_float())

func get_hand_cards() -> Array[CardData]:
	return _hand.duplicate()

func get_expression_cards() -> Array[CardData]:
	if not _constraint.is_empty():
		var filled: Array[CardData] = []
		for slot in _constraint:
			if slot.card != null:
				filled.append(slot.card)
		return filled
	return _expression.duplicate()

func _find_card(cards: Array[CardData], instance_id: int) -> int:
	for index in range(cards.size()):
		if cards[index].instance_id == instance_id:
			return index
	return -1

func _find_expression_card(instance_id: int) -> int:
	if not _constraint.is_empty():
		var ordinal := 0
		for slot in _constraint:
			if slot.card != null:
				if slot.card.instance_id == instance_id:
					return ordinal
				ordinal += 1
		return -1
	return _find_card(_expression, instance_id)

func _current_outcome() -> ExpressionEvaluator.Outcome:
	if not _constraint.is_empty():
		return ExpressionEvaluator.inspect_slots(_constraint)
	return ExpressionEvaluator.inspect_cards(_expression)

func _formula_text() -> String:
	var parts: PackedStringArray = []
	for slot in _constraint:
		parts.append(slot.display_text())
	return " ".join(parts)

func _result_text() -> String:
	var outcome := _current_outcome()
	var text := ""
	if not _constraint.is_empty():
		text = "定式 %s · " % _formula_text()
	text += "结果 %s" % outcome.result.display_text()
	if not _constraint.is_empty():
		if not outcome.complete:
			text += " · 未完成"
		elif outcome.divided_by_zero:
			text += " · 除以零"
	elif not outcome.valid:
		text += " · 未完成"
	elif outcome.divided_by_zero:
		text += " · 除以零"
	return text

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
	if _constraint.is_empty():
		_rebuild_cards(_expression_row, _expression, &"expression", _expression_zone)
		if _expression.is_empty():
			_add_placeholder(_expression_row, "算式")
	else:
		_rebuild_slots()
	if _hand.is_empty():
		_add_placeholder(_hand_row, "空")
	_result_label.text = _result_text()
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

func _rebuild_slots() -> void:
	for child in _expression_row.get_children():
		_expression_row.remove_child(child)
		child.queue_free()
	for slot in _constraint:
		var view := CardView.new()
		view.card_panel = self
		view.drop_zone = _expression_zone
		view.source_region = &"expression"
		if slot.card != null:
			view.card = slot.card
			view.draggable = _active
		else:
			view.locked_face = slot.locked
			view.face_text = slot.display_text()
			view.draggable = false
		_expression_row.add_child(view)
