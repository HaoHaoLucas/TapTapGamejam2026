extends Control
## Sampled by RunBattle's clock: pauses and replacement are atomic.
const FALLBACK := preload("res://assets/battle/enemy.png")

var _shown_id := ""
var form := ""
var mode := "idle"
var elapsed := 0.0
var _opening_form := ""
var _death_form := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func form_for(battle: CardBattle) -> String:
	match battle.monster_id:
		MonsterRules.MON_INK:
			return "MON_INK2" if battle.turn_index % 2 == 1 else "MON_INK"
		MonsterRules.MON_PARITY:
			return "MON_PARITY" if battle.turn_index % 2 == 1 else "MON_PARITY2"
		MonsterRules.MON_PRIEST:
			return "MON_PRIEST" if battle.priest_heal_cancelled else "MON_PRIEST2"
		MonsterRules.MON_RUST:
			return "MON_RUST"
	return ""


func adopt_battle(battle: CardBattle) -> void:
	_shown_id = str(battle.monster_id)
	form = form_for(battle)
	_opening_form = form
	_death_form = ""
	mode = "enter"
	elapsed = 0.0
	queue_redraw()


func refresh(battle: CardBattle) -> void:
	if mode != "die":
		form = form_for(battle)
	queue_redraw()


func show_monster(monster_id: String) -> void:
	_shown_id = monster_id
	form = monster_id if monster_id in ["MON_INK", "MON_PARITY", "MON_PRIEST", "MON_RUST"] else ""
	mode = "idle"
	queue_redraw()


func play_death(battle: CardBattle) -> void:
	_death_form = form_for(battle)
	form = _death_form
	mode = "die"
	elapsed = 0.0
	queue_redraw()


func advance(delta: float) -> void:
	elapsed += delta
	if mode == "enter" and elapsed >= maxf(1.8, 0.4 + BattleAssets.clip_seconds(_opening_form + "_enter")):
		mode = "idle"
	queue_redraw()


func _draw() -> void:
	var factor := minf(size.x / 720.0, size.y / 600.0)
	var area := Rect2(Vector2((size.x - 720.0 * factor) / 2.0, size.y - 600.0 * factor), Vector2(720, 600) * factor)
	if _shown_id != "":
		draw_texture_rect(BattleAssets.texture("battle_shadow"), Rect2(area.position + Vector2(260, 444) * factor, Vector2(200, 48) * factor), false)
	var art: Texture2D
	if mode == "enter":
		if elapsed < BattleAssets.clip_seconds("rift"):
			draw_texture_rect(BattleAssets.clip_texture("rift", elapsed), area, false)
		if elapsed >= 0.4:
			art = BattleAssets.clip_texture(_opening_form + "_enter", elapsed - 0.4)
	elif mode == "die":
		art = BattleAssets.clip_texture(_death_form + "_die", elapsed)
	elif form != "":
		art = BattleAssets.texture(form)
	if form == "" and _shown_id != "" and (mode != "enter" or elapsed >= 0.4):
		art = FALLBACK
	if art != null:
		draw_texture_rect(art, area, false)


func head_anchor() -> Vector2:
	var factor := minf(size.x / 720.0, size.y / 600.0)
	var origin := Vector2((size.x - 720.0 * factor) / 2.0, size.y - 600.0 * factor)
	return origin + Vector2(360, 160 if form.begins_with("MON_PRIEST") else 80) * factor
