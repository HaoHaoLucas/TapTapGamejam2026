class_name CardView
extends PanelContainer
## The only card face. Battle, reward, and event screens instantiate this scene.

signal pressed(card_uid: String)

var library: CardLibrary
var card_uid: String = ""

var _value: Label
var _marks: Label
var _state: Label
var _style: StyleBoxFlat
var _highlight: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure()
	refresh()


func bind(p_library: CardLibrary, p_card_uid: String) -> void:
	library = p_library
	card_uid = p_card_uid
	_ensure()
	refresh()


func set_highlight(mode: String) -> void:
	_highlight = mode
	_apply_style()


func face_text() -> String:
	_ensure()
	return "" if _value == null else _value.text


func mark_text() -> String:
	_ensure()
	return "" if _marks == null else _marks.text


func state_text() -> String:
	_ensure()
	return "" if _state == null else _state.text


func refresh() -> void:
	_ensure()
	if _value == null:
		return
	if library == null or card_uid == "":
		visible = false
		return
	var card := library.get_card(card_uid)
	if card == null:
		visible = false
		return
	visible = true
	var catalog := library.catalog
	var def := catalog.card(card.def_id)
	if str(def.get("card_kind", "")) == "NUM":
		_value.text = _format_number(card.printed_value(catalog))
	else:
		_value.text = str(def.get("name", ""))
	var mark_lines := PackedStringArray()
	for enh_id in card.enhancement_ids:
		mark_lines.append(str(catalog.enh(enh_id).get("name", enh_id)))
	_marks.text = "\n".join(mark_lines)
	var tips := PackedStringArray()
	for enh_id in card.enhancement_ids:
		tips.append(TowerDeck.mark_line_from(catalog.enh(str(enh_id)), str(enh_id)))
	tooltip_text = "\n".join(tips)
	var flags := PackedStringArray()
	if card.has_mark("EN_GHOST"):
		flags.append("幽灵")
	if card.is_frozen(library.turn_index):
		flags.append("冻结")
	if card.zone == CardInstance.COLLECTION and not card.collection_snapshot.is_empty():
		flags.append("估价 %s" % card.collection_value())
	_state.text = " ".join(flags)
	_apply_style()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(card_uid)
		accept_event()


func _ensure() -> void:
	if _value != null:
		return
	_value = get_node_or_null("Margin/Body/Value") as Label
	_marks = get_node_or_null("Margin/Body/Marks") as Label
	_state = get_node_or_null("Margin/Body/State") as Label
	if _style == null:
		_style = StyleBoxFlat.new()
		_style.set_corner_radius_all(8)
		_style.set_border_width_all(2)
		_style.content_margin_left = 6
		_style.content_margin_right = 6
		_style.content_margin_top = 6
		_style.content_margin_bottom = 6
		add_theme_stylebox_override("panel", _style)


func _apply_style() -> void:
	if _style == null:
		return
	var card := library.get_card(card_uid) if library != null else null
	var frozen := card != null and card.is_frozen(library.turn_index)
	var ghost := card != null and card.has_mark("EN_GHOST")
	_style.bg_color = Color(0.11, 0.14, 0.2) if not frozen else Color(0.1, 0.16, 0.24)
	if _highlight == "equation":
		_style.border_color = Color(0.93, 0.78, 0.42)
	elif _highlight == "selected":
		_style.border_color = Color(0.45, 0.78, 0.86)
	elif ghost:
		_style.border_color = Color(0.62, 0.5, 0.78)
	else:
		_style.border_color = Color(0.38, 0.42, 0.5)
	modulate = Color(1, 1, 1, 0.78) if ghost else Color(1, 1, 1, 1)


func _format_number(value: int) -> String:
	if value < 0:
		return "−%d" % absi(value)
	return str(value)
