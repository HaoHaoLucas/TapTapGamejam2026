class_name CombatSession
extends RefCounted
## Projects a run deck into CombatEngine and writes zones and HP back.
## Every ENC_* fight is the existing watcher until monster tables exist.

var engine: CombatEngine
var projected_uids: Array = []
var outcome: String = ""
var _closed: bool = false


func start(run: RunState) -> void:
	projected_uids = []
	var cards: Array = []
	for inst in TowerDeck.deck_cards(run):
		cards.append(_project(inst))
		projected_uids.append(inst.card_uid)
	if engine == null:
		engine = CombatEngine.new()
	var combat_seed := run.randi_stream("COMBAT") & 0xFFFFFFFF
	engine.start_with_deck(combat_seed, cards, run.hp, run.max_hp)
	_closed = false
	outcome = ""


func write_back(run: RunState) -> String:
	if _closed:
		return outcome
	_closed = true
	outcome = str(engine.s.get("phase", ""))
	var burned := {}
	for card in engine.s.burned:
		if card != null:
			burned[card.id] = true
	for card_uid in projected_uids:
		var inst := run.find_card(str(card_uid))
		if inst == null:
			continue
		inst.zone = "REMOVED" if burned.has(card_uid) else "RUN_DECK"
		inst.drawn_turn = -1
		inst.locked_until_turn = -1
	run.hp = int(engine.s.hp)
	return outcome


func _project(inst: CardInstance) -> BattleCard:
	var def := GameData.card(inst.def_id)
	var card := BattleCard.new()
	card.id = inst.card_uid
	if str(def.get("card_kind", "")) == "NUM":
		card.type = "number"
		card.value = CardService.printed_value_of(inst)
		card.elem = ["fire", "ice", "spark"][(card.value + 5) % 3]
	else:
		card.type = "operator"
		card.op = "+" if str(def.get("operator_code", "")) == "ADD" else "×"
	card.enhancement_ids = inst.enhancement_ids.duplicate()
	for enh_id in inst.enhancement_ids:
		var enh := GameData.enh(str(enh_id))
		card.marks.append(str(enh.get("name", enh_id)))
	return card
