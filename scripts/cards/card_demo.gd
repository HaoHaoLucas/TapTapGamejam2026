extends Control

const PanelScene = preload("res://scenes/cards/card_panel.tscn")

var card_panel: CardPanel
var _finish_button: Button
var _next_button: Button
var _output: Label
var _turn: int = 0
var hud: BattleHUD
var _cards: Array[CardData] = []
var _health: int = 70
const MAX_HEALTH: int = 100

func _ready() -> void:
	var ui_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	ui_theme.default_font = font
	ui_theme.default_font_size = 18
	theme = ui_theme
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20 if side in ["top", "bottom"] else 32)
	scroll.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	hud = BattleHUD.new()
	layout.add_child(hud)
	hud.set_health(_health, MAX_HEALTH)
	hud.time_expired.connect(_finish_turn)
	card_panel = PanelScene.instantiate()
	layout.add_child(card_panel)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	layout.add_child(actions)
	_finish_button = Button.new()
	_finish_button.text = "结束回合"
	_finish_button.custom_minimum_size = Vector2(150, 44)
	_finish_button.pressed.connect(_finish_turn)
	actions.add_child(_finish_button)
	_next_button = Button.new()
	_next_button.text = "下一回合"
	_next_button.custom_minimum_size = Vector2(150, 44)
	_next_button.pressed.connect(_start_turn)
	actions.add_child(_next_button)
	_output = Label.new()
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(_output)
	_cards = [
		CardData.number_card(3), CardData.number_card(5),
		CardData.operator_card("×"), CardData.operator_card("+"), CardData.number_card(2)
	]
	_start_turn()

func _start_turn() -> void:
	_turn += 1
	card_panel.start_player_turn(_cards)
	_finish_button.disabled = false
	_next_button.disabled = true
	_output.text = "第 %d 回合" % _turn
	hud.start_countdown(30.0)

func _finish_turn() -> void:
	if not card_panel.is_turn_active():
		return
	card_panel.finish_player_turn()
	hud.stop_countdown()
	_health = mini(MAX_HEALTH, _health + card_panel.get_pending_heal())
	hud.set_health(_health, MAX_HEALTH)
	_output.text = "已结束"
	_finish_button.disabled = true
	_next_button.disabled = false
