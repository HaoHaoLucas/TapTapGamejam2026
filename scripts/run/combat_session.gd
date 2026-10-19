class_name CombatSession
extends RefCounted
## Copies the tower deck into a jam RunContext, then writes HP and card zones back.

var ctx: RunContext
var projected_uids: Array = []
var monster_id: String = ""
var monster_name: String = ""
var outcome: String = ""
var battle_phase: String = ""
var _closed: bool = false


func start(run: RunState) -> void:
	_closed = false
	outcome = ""
	battle_phase = ""
	projected_uids = []
	monster_id = ""
	monster_name = ""
	var catalog := ConfigCatalog.load_default()
	var combat_seed := run.randi_stream("COMBAT") & 0x7FFFFFFF
	ctx = RunContext.new(catalog, combat_seed, run.run_id)
	ctx.depth = run.depth
	if not catalog.ok():
		push_error("战斗配置无法启动：%s" % "；".join(catalog.errors))
	_copy_deck(run)
	var encounter_id := str(run.current_room.get("content_id", ""))
	monster_id = str(MonsterRules.monster_id_for_encounter(encounter_id))
	var spec := MonsterRules.load_monster(monster_id)
	monster_name = str(spec.get("name", ""))
	if monster_name == "":
		monster_name = monster_id
	var room_kind := str(run.current_room.get("room_kind", ""))
	var mults := MonsterRules.room_multipliers(room_kind, run.normal_used)
	var room_hp := float(mults.get("hp", 1.0))
	var room_atk := float(mults.get("atk", 1.0))
	var player_hp := run.hp
	ctx.battle = CardBattle.new(ctx)
	MonsterRules.attach(ctx.battle, monster_id, run.depth, room_hp, room_atk)
	MonsterRules.detain_opening(ctx, ctx.battle)
	ctx.battle.start(0, 0, true, player_hp)
	ctx.battle.player_max_hp = maxi(1, run.max_hp)
	ctx.battle.player_hp = clampi(player_hp, 0, ctx.battle.player_max_hp)


func is_live() -> bool:
	return not _closed and ctx != null and ctx.library != null


func write_back(run: RunState) -> String:
	if _closed:
		return outcome
	_closed = true
	if ctx == null or ctx.battle == null:
		battle_phase = ""
		outcome = "defeat"
		return outcome
	battle_phase = str(ctx.battle.phase)
	outcome = _room_outcome(battle_phase)
	run.hp = int(ctx.battle.player_hp)
	for card in ctx.library.all_cards():
		_write_card(run, card)
	return outcome


func _copy_deck(run: RunState) -> void:
	var library := ctx.library
	for inst in TowerDeck.deck_cards(run):
		if inst == null or inst.card_uid == "":
			continue
		_install(library, inst)
		projected_uids.append(inst.card_uid)


func _install(library: CardLibrary, source: CardInstance) -> void:
	# create_instance mints a new uid. The tower card has to keep its own.
	var card := CardInstance.new()
	card.card_uid = source.card_uid
	card.def_id = source.def_id
	card.enhancement_ids = source.enhancement_ids.duplicate()
	card.zone = CardInstance.RUN_DECK
	card.acquired_depth = source.acquired_depth
	card.source_uid = source.source_uid
	card.return_used_run = source.return_used_run
	card.smolder_used_run = source.smolder_used_run
	card.drawn_turn = -1
	card.locked_until_turn = -1
	if not source.collection_snapshot.is_empty():
		card.collection_snapshot = source.collection_snapshot.duplicate(true)
	card.refresh_opening_priority()
	library._cards[card.card_uid] = card
	library._order.append(card.card_uid)
	var pile: Array = library._piles[CardInstance.RUN_DECK]
	pile.append(card.card_uid)


func _write_card(run: RunState, card: CardInstance) -> void:
	var inst := run.find_card(card.card_uid)
	if inst == null:
		inst = CardInstance.new()
		inst.card_uid = card.card_uid
		inst.acquired_depth = card.acquired_depth
		inst.source_uid = card.source_uid
		run.card_instances.append(inst)
	inst.def_id = card.def_id
	inst.enhancement_ids = card.enhancement_ids.duplicate()
	inst.return_used_run = card.return_used_run
	inst.smolder_used_run = card.smolder_used_run
	inst.zone = _home_zone(card.zone)
	inst.drawn_turn = -1
	inst.locked_until_turn = -1
	inst.refresh_opening_priority()
	if not card.collection_snapshot.is_empty():
		inst.collection_snapshot = card.collection_snapshot.duplicate(true)


func _home_zone(zone: String) -> String:
	if zone == CardInstance.REMOVED:
		return CardInstance.REMOVED
	if zone == CardInstance.COLLECTION:
		return CardInstance.COLLECTION
	# Draw, hand, discard, resolving, and unreturned stolen cards go back to the run deck.
	return CardInstance.RUN_DECK


func _room_outcome(phase: String) -> String:
	match phase:
		"VICTORY":
			return "victory"
		"DEFEAT", "DECK_EXHAUSTED":
			return "defeat"
		_:
			return phase

