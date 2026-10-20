class_name CardView
extends PanelContainer
## The only card face. Battle, reward, and event screens instantiate this scene.

signal pressed(card_uid: String)

var library: CardLibrary
var card_uid: String = ""

var _art: CardArt
var _value: Label
var _marks: Label
var _state: Label
var _style: StyleBoxFlat
var _highlight: String = ""
var _face: Dictionary = {}
var _use_face: bool = false
var _choice_presentation := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if _choice_presentation else Control.MOUSE_FILTER_STOP
	_ensure()
	refresh()


func bind(p_library: CardLibrary, p_card_uid: String) -> void:
	_use_face = false
	_face = {}
	library = p_library
	card_uid = p_card_uid
	_ensure()
	refresh()


func bind_face(face: Dictionary) -> void:
	_use_face = true
	_face = face.duplicate(true)
	library = null
	card_uid = str(_face.get("card_uid", ""))
	_ensure()
	refresh()


func set_highlight(mode: String) -> void:
	_highlight = mode
	_apply_style()


func set_compact(compact: bool) -> void:
	_ensure()
	custom_minimum_size = Vector2(84, 112) if compact else Vector2(116, 168)
	if _value != null:
		_value.add_theme_font_size_override("font_size", 22 if compact else 32)
	if _marks != null:
		_marks.add_theme_font_size_override("font_size", 11 if compact else 12)


func face_text() -> String:
	_ensure()
	return "" if _value == null else _value.text


## Opt-in presentation used only by the tower's choice buttons.
func set_choice_presentation(dimensions: Vector2, _numeric_face: bool = true) -> void:
	_choice_presentation = true
	_ensure()
	custom_minimum_size = dimensions
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if str(_face.get("presentation", "text")) != "text":
		return
	_value.add_theme_font_size_override("font_size", 40)
	_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_marks.add_theme_font_size_override("font_size", 26)
	_marks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marks.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_state.add_theme_font_size_override("font_size", 24)
	_state.custom_minimum_size.y = 34
	get_node("Margin/Body").add_theme_constant_override("separation", 12)
	var has_icon := CardArt.MARKS.has(str(_face.get("enh_id", "")))
	for side in ["left", "right", "top", "bottom"]:
		get_node("Margin").add_theme_constant_override("margin_" + side, 84 if side == "top" and has_icon else 18)
	var text_height := 0.0
	for label in [_value, _marks, _state]:
		var font: Font = label.get_theme_font("font")
		text_height += maxf(label.custom_minimum_size.y, font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, dimensions.x - 60, label.get_theme_font_size("font_size")).y)
	custom_minimum_size.y = maxf(dimensions.y, text_height + 96 + (66 if has_icon else 0))


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
	if _use_face:
		_refresh_face()
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
	var data := {
		"presentation": "card", "card_kind": str(def.get("card_kind", "")),
		"printed_value": card.printed_value(catalog), "operator_code": str(def.get("operator_code", "NONE")),
		"enhancement_ids": card.enhancement_ids, "state_text": _state.text,
		"frozen": card.is_frozen(library.turn_index),
	}
	_present(data)
	_apply_style()


func _refresh_face() -> void:
	visible = true
	card_uid = str(_face.get("card_uid", ""))
	_value.text = str(_face.get("value_text", ""))
	_marks.text = str(_face.get("mark_text", ""))
	_state.text = str(_face.get("state_text", ""))
	tooltip_text = str(_face.get("tooltip", ""))
	_present(_face)
	_apply_style()


func _present(data: Dictionary) -> void:
	var illustrated := str(data.get("presentation", "text")) != "text"
	_value.visible = not illustrated
	_marks.visible = not illustrated
	_state.visible = not illustrated
	_art.show_face(data)


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
	_art = CardArt.new()
	_art.name = "Art"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	move_child(_art, 0)
	# Text-only options retain readable light ink.
	_value.add_theme_color_override("font_color", Color(0.93, 0.94, 0.97))
	_marks.add_theme_color_override("font_color", Color(0.83, 0.86, 0.93))
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
	var frozen := false
	var ghost := false
	if _use_face:
		frozen = bool(_face.get("frozen", false))
		ghost = bool(_face.get("ghost", false))
	else:
		var card := library.get_card(card_uid) if library != null else null
		frozen = card != null and card.is_frozen(library.turn_index)
		ghost = card != null and card.has_mark("EN_GHOST")
	var illustrated := not _use_face or str(_face.get("presentation", "text")) != "text"
	_style.bg_color = Color(0, 0, 0, 0) if illustrated else Color(0.11, 0.14, 0.2)
	if frozen:
		_style.border_color = Color(0.58, 0.85, 1.0)
	if _highlight == "equation":
		_style.border_color = Color(0.93, 0.78, 0.42)
	elif _highlight == "selected":
		_style.border_color = Color(0.45, 0.78, 0.86)
	elif ghost:
		_style.border_color = Color(0.62, 0.5, 0.78)
	elif not frozen:
		_style.border_color = Color(0.38, 0.42, 0.5)
	modulate = Color(1, 1, 1, 0.78) if ghost else Color(1, 1, 1, 1)


func _format_number(value: int) -> String:
	if value < 0:
		return "−%d" % absi(value)
	return str(value)
