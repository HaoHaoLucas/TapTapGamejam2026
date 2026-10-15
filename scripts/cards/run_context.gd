class_name RunContext
extends RefCounted
## One run: config version, card library, and five independent RNG streams.

signal equation_committed(equation_uid: String, ordered_uids: Array, motif_ids: Array, primary_op: String, effective_result: int, damage: int, damage_kind: String)
signal card_zone_changed(card_uid: String, from_zone: String, to_zone: String, reason: String, txn_id: String)
signal mark_applied(card_uid: String, enh_id: String, source: String, txn_id: String)
signal card_removed(card_uid: String, reason: String)

const STREAMS: PackedStringArray = ["MAP", "REWARD", "ENHANCE", "COMBAT", "QUEST"]

var run_id: String = ""
var run_seed: int = 1
var config_version: String = ""
var depth: int = 1
var catalog: ConfigCatalog
var library: CardLibrary
var rngs: Dictionary = {}
var card_service: CardService
var equation_service: EquationService
var draw_service: DrawService
var battle: CardBattle
var _actions: Dictionary = {}


func _init(p_catalog: ConfigCatalog, p_run_seed: int = 1, p_run_id: String = "") -> void:
	catalog = p_catalog
	run_seed = p_run_seed
	config_version = p_catalog.config_version
	run_id = p_run_id if p_run_id != "" else "run_%s" % str(p_run_seed)
	depth = 1
	for stream_name in STREAMS:
		rngs[stream_name] = CardRng.new(p_run_seed, stream_name)
	library = CardLibrary.new(p_catalog, run_id)
	card_service = CardService.new(self)
	equation_service = EquationService.new(self)
	draw_service = DrawService.new(self)
	if not p_catalog.ok():
		for message in p_catalog.errors:
			push_error(message)


func rng_of(stream_name: String) -> CardRng:
	return rngs[stream_name]


func start_battle(enemy_hp: int = 120, intent_damage: int = 8, auto_deal: bool = true, player_hp: int = -1) -> CardBattle:
	battle = CardBattle.new(self)
	battle.start(enemy_hp, intent_damage, auto_deal, player_hp)
	return battle


func replay(action_uid: String) -> Dictionary:
	if action_uid == "" or not _actions.has(action_uid):
		return {}
	var copy: Dictionary = (_actions[action_uid] as Dictionary).duplicate(true)
	copy["replayed"] = true
	return copy


func remember(action_uid: String, result: Dictionary) -> void:
	if action_uid == "":
		return
	_actions[action_uid] = result.duplicate(true)
