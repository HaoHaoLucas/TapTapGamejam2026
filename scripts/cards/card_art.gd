class_name CardArt
extends Control
## One raster composition for live cards and read-only offer/inventory snapshots.

const ROOT := "res://assets/cards/"
const MARKS := {
	"EN_NUM1": "num1", "EN_NUM2": "num2", "EN_NUM3": "num3",
	"EN_ECHO": "echo", "EN_RETURN": "return", "EN_FRAGILE": "fragile",
	"EN_ALCHEMY": "alchemy", "EN_MAGNET": "magnet", "EN_YINYANG": "yinyang",
	"EN_FLAMMABLE": "flammable", "EN_SMOLDER": "smolder", "EN_COMBO": "combo",
	"EN_FROZEN": "frozen", "EN_PRICE": "price", "EN_GHOST": "ghost", "EN_VANGUARD": "vanguard",
}
static var _textures: Dictionary = {}
var face: Dictionary = {}


static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(ROOT + path) as Texture2D
	return _textures[path] as Texture2D


static func from_parts(def_id: String, ids: Array, uid: String = "") -> Dictionary:
	var def := GameData.card(def_id)
	var kind := str(def.get("card_kind", ""))
	var printed := TowerDeck.printed_value_of({"def_id": def_id, "enhancement_ids": ids})
	var lines := PackedStringArray()
	var names := PackedStringArray()
	for id in ids:
		lines.append(TowerDeck.mark_line(str(id)))
		names.append(str(GameData.enh(str(id)).get("name", id)))
	return {
		"presentation": "card", "card_uid": uid, "def_id": def_id, "card_kind": kind,
		"printed_value": printed, "operator_code": str(def.get("operator_code", "NONE")),
		"enhancement_ids": ids.duplicate(),
		"value_text": ("−%d" % absi(printed) if printed < 0 else str(printed)) if kind == "NUM" else str(def.get("name", "")),
		"mark_text": "\n".join(names), "tooltip": "\n".join(lines),
		"ghost": ids.has("EN_GHOST"), "state_text": "幽灵" if ids.has("EN_GHOST") else "",
	}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func show_face(data: Dictionary) -> void:
	face = data.duplicate(true)
	queue_redraw()


func _fit(tex: Texture2D, area: Rect2, tint: Color = Color.WHITE) -> void:
	if tex == null or area.size.x <= 0 or area.size.y <= 0:
		return
	var extent := tex.get_size() * minf(area.size.x / tex.get_width(), area.size.y / tex.get_height())
	draw_texture_rect(tex, Rect2(area.get_center() - extent * 0.5, extent), false, tint)


func _box(path: String, rect: Rect2, margin: float = 80.0) -> void:
	var tex := texture(path)
	if path != "faces/neutral.png":
		draw_texture_rect(tex, rect, false)
		return
	# The square operator plate stretches only between its decorative corners.
	# Scale source margins with the card width, rather than keeping 80 screen pixels.
	var extent := tex.get_size()
	var edge := margin * rect.size.x / extent.x
	var src_x := [0.0, margin, extent.x - margin, extent.x]
	var src_y := [0.0, margin, extent.y - margin, extent.y]
	var dst_x := [0.0, edge, rect.size.x - edge, rect.size.x]
	var dst_y := [0.0, edge, rect.size.y - edge, rect.size.y]
	for y in 3:
		for x in 3:
			var source := Rect2(Vector2(src_x[x], src_y[y]), Vector2(src_x[x + 1] - src_x[x], src_y[y + 1] - src_y[y]))
			var target := Rect2(rect.position + Vector2(dst_x[x], dst_y[y]), Vector2(dst_x[x + 1] - dst_x[x], dst_y[y + 1] - dst_y[y]))
			draw_texture_rect_region(tex, target, source)


func _caption(text: String, area: Rect2, font_size: int, color: Color) -> void:
	if text == "":
		return
	var font := get_theme_default_font()
	var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	if measured.x > area.size.x:
		font_size = maxi(10, int(font_size * area.size.x / measured.x))
	var baseline := area.get_center().y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	draw_string(font, Vector2(area.position.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, area.size.x, font_size, color)


func _number(number: int, tone: String, area: Rect2) -> void:
	var glyphs: Array[Texture2D] = []
	# Positive and negative plates already carry their sign in the top-left corner.
	var ratio := 0.0
	for digit in str(absi(number)):
		var glyph := texture("glyphs/%s_%s.png" % [tone, digit])
		glyphs.append(glyph)
		ratio += float(glyph.get_width()) / glyph.get_height()
	var gap := 0.045
	ratio += gap * (glyphs.size() - 1)
	var height := minf(area.size.y, area.size.x / ratio)
	var cursor := area.get_center().x - ratio * height * 0.5
	for glyph in glyphs:
		var width := height * glyph.get_width() / glyph.get_height()
		draw_texture_rect(glyph, Rect2(Vector2(cursor, area.get_center().y - height * 0.5), Vector2(width, height)), false)
		cursor += width + gap * height


func _draw() -> void:
	if face.is_empty():
		return
	var mode := str(face.get("presentation", "text"))
	var area := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	if area.size.x <= 0 or area.size.y <= 0:
		return
	if mode == "text":
		var mark := str(face.get("enh_id", ""))
		if MARKS.has(mark):
			var extent := minf(64, area.size.y * 0.25)
			_fit(texture("marks/" + str(MARKS[mark]) + ".png"), Rect2(Vector2(area.get_center().x - extent * 0.5, 12), Vector2.ONE * extent))
		return
	# Keep the portrait silhouette, even when an outer layout allocates extra space.
	var width := minf(area.size.x, area.size.y * 0.75)
	var card := Rect2(area.get_center() - Vector2(width, width / 0.75) * 0.5, Vector2(width, width / 0.75))
	if mode == "room":
		_fit(texture("faces/room.png"), card)
		var ink := Color(0.16, 0.2, 0.25)
		_caption(str(face.get("value_text", "")), Rect2(card.position + card.size * Vector2(0.08, 0.08), card.size * Vector2(0.84, 0.17)), int(width * 0.12), ink)
		_caption(str(face.get("mark_text", "")), Rect2(card.position + card.size * Vector2(0.08, 0.72), card.size * Vector2(0.84, 0.08)), int(width * 0.065), ink)
		_caption(str(face.get("state_text", "")), Rect2(card.position + card.size * Vector2(0.08, 0.84), card.size * Vector2(0.84, 0.08)), int(width * 0.065), ink)
		return
	var number := int(face.get("printed_value", 0))
	var numeric := str(face.get("card_kind", "")) == "NUM"
	var tone := "positive" if number > 0 else "negative"
	var base := tone if numeric and number != 0 else "neutral"
	var frozen := bool(face.get("frozen", false))
	if numeric and number == 0:
		_box("faces/zero.png", card)
	else:
		_box("faces/" + base + ".png", card)
		var glyph_area := Rect2(card.position + card.size * Vector2(0.19, 0.22), card.size * Vector2(0.62, 0.46))
		if numeric:
			_number(number, tone, glyph_area)
		else:
			var op := "mul" if str(face.get("operator_code", "")) == "MUL" else "add"
			_fit(texture("glyphs/" + op + ".png"), glyph_area)
	if frozen:
		draw_rect(card.grow(-5), Color(0.55, 0.85, 1, 0.18))
	var ids: Array = face.get("enhancement_ids", [])
	var slot_size := width * 0.19
	for i in 2:
		var center := card.position + card.size * Vector2(0.36 + i * 0.28, 0.82)
		var slot := Rect2(center - Vector2.ONE * slot_size * 0.5, Vector2.ONE * slot_size)
		_fit(texture("marks/slot_occupied.png" if i < ids.size() else "marks/slot_available.png"), slot)
		if i < ids.size() and MARKS.has(str(ids[i])):
			_fit(texture("marks/" + str(MARKS[str(ids[i])]) + ".png"), slot.grow(-slot_size * 0.13))
	var state := str(face.get("state_text", ""))
	if state != "":
		var strip := Rect2(card.position + card.size * Vector2(0.12, 0.91), card.size * Vector2(0.76, 0.065))
		draw_style_box(_badge(), strip.grow(2))
		_caption(state, strip, maxi(10, int(width * 0.065)), Color(1, 0.95, 0.74))


func _badge() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.13, 0.18, 0.9)
	box.set_corner_radius_all(3)
	return box
