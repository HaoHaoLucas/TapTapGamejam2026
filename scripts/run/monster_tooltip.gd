extends Label
## Keep long monster rules readable inside the viewport.


func _make_custom_tooltip(for_text: String) -> Object:
	var text := Label.new()
	text.custom_minimum_size.x = 540.0
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = for_text
	text.add_theme_color_override("font_color", Color(0.14, 0.16, 0.23))
	text.add_theme_font_size_override("font_size", 22)
	return text
