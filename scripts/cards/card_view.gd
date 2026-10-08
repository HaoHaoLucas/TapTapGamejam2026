extends PanelContainer
## Dragging only creates a payload; the panel moves the card on accepted drop.

var card: CardData
var card_panel: Control
var draggable: bool = false
var source_region: StringName = &"hand"
var drop_zone: Control
var face_text: String = "□"
var locked_face: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(92, 116)
	var box := StyleBoxFlat.new()
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	var text := ""
	var font_color := Color("f4f7fb")
	if card == null:
		text = face_text
		draggable = false
		if locked_face:
			box.bg_color = Color("3f3620")
			box.border_color = Color("b89a55")
			font_color = Color("d9c79a")
			tooltip_text = "锁定格"
		else:
			box.bg_color = Color("122430")
			box.border_color = Color("68889a")
			font_color = Color("c5d5de")
			tooltip_text = "空格"
	else:
		text = card.display_text()
		match card.kind:
			CardData.Kind.NUMBER:
				box.bg_color = Color("20394b")
				box.border_color = Color("72dfcb")
				tooltip_text = "数字牌"
			CardData.Kind.OPERATOR:
				box.bg_color = Color("4b355a")
				box.border_color = Color("d7a4f3")
				tooltip_text = "运算符牌"
			_:
				box.bg_color = Color("5a3414")
				box.border_color = Color("e8a84a")
				font_color = Color("ffd7a1")
				tooltip_text = "定式牌"
	add_theme_stylebox_override("panel", box)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", font_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	mouse_default_cursor_shape = Control.CURSOR_DRAG if draggable else Control.CURSOR_ARROW
	if not draggable:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not draggable or card == null or not card_panel.is_turn_active():
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
