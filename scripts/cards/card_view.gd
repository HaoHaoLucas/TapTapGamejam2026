extends PanelContainer
## Dragging only creates a payload; the panel moves the card on accepted drop.

var card: CardData
var card_panel: Control
var draggable: bool = false
var source_region: StringName = &"hand"
var drop_zone: Control

func _ready() -> void:
	custom_minimum_size = Vector2(92, 116)
	mouse_default_cursor_shape = Control.CURSOR_DRAG if draggable else Control.CURSOR_ARROW
	var box := StyleBoxFlat.new()
	box.bg_color = Color("20394b") if card.kind == CardData.Kind.NUMBER else Color("4b355a")
	box.border_color = Color("72dfcb") if card.kind == CardData.Kind.NUMBER else Color("d7a4f3")
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = card.display_text()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	tooltip_text = "数字牌" if card.kind == CardData.Kind.NUMBER else "运算符牌"
	if not draggable:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not draggable or not card_panel.is_turn_active():
		return null
	var preview := Label.new()
	preview.text = "  " + card.display_text() + "  "
	preview.add_theme_font_size_override("font_size", 40)
	preview.modulate = Color("72dfcb")
	set_drag_preview(preview)
	return card_panel.drag_payload(card.instance_id, source_region)

# Card faces accept drops through their containing zone while remaining draggable.
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return drop_zone.can_accept_at(global_position + at_position, data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	drop_zone.accept_at(global_position + at_position, data)
