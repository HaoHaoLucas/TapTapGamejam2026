extends RefCounted
## Shared paper chrome, scoped to the battle and its hosted overlays.

const PAPER := preload("res://assets/battle/imported/battle_hud_.png")
const INK := Color(0.16, 0.18, 0.28)
const LIGHT := Color(0.9, 0.91, 0.96)


static func paper(tint: Color = Color.WHITE, margin: float = 18.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = PAPER
	style.texture_margin_left = 22.0
	style.texture_margin_right = 22.0
	style.texture_margin_top = 22.0
	style.texture_margin_bottom = 22.0
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	style.modulate_color = tint
	return style


static var _font: SystemFont


static func button_paper(tint: Color, margin: float) -> StyleBoxTexture:
	var style := paper(tint, margin)
	# Small controls need borders thinner than half their height.
	style.texture_margin_left = 12.0
	style.texture_margin_right = 12.0
	style.texture_margin_top = 6.0
	style.texture_margin_bottom = 6.0
	return style


static func make_theme(font_size: int = 20, button_margin: float = 12.0) -> Theme:
	var ui := Theme.new()
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	ui.default_font = _font
	ui.default_font_size = font_size
	ui.set_color("font_color", "Label", INK)
	for type in ["Button", "OptionButton"]:
		ui.set_stylebox("normal", type, button_paper(Color.WHITE, button_margin))
		ui.set_stylebox("hover", type, button_paper(Color(1.12, 1.12, 1.16), button_margin))
		ui.set_stylebox("pressed", type, button_paper(Color(0.78, 0.8, 0.9), button_margin))
		ui.set_stylebox("disabled", type, button_paper(Color(0.64, 0.65, 0.72), button_margin))
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color.TRANSPARENT
		focus.border_color = INK
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(6)
		ui.set_stylebox("focus", type, focus)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			ui.set_color(state, type, INK)
		ui.set_color("font_disabled_color", type, Color(0.3, 0.31, 0.38))
	ui.set_stylebox("panel", "PanelContainer", paper())
	ui.set_stylebox("panel", "TooltipPanel", paper(Color.WHITE, 20.0))
	ui.set_color("font_color", "TooltipLabel", INK)
	ui.set_font_size("font_size", "TooltipLabel", 20)
	ui.set_stylebox("panel", "PopupMenu", paper())
	ui.set_color("font_color", "PopupMenu", INK)
	ui.set_color("font_hover_color", "PopupMenu", INK)
	return ui


static func ink_labels(node: Node) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", INK)
	for child in node.get_children():
		ink_labels(child)
