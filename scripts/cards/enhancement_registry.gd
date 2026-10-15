class_name EnhancementRegistry
extends RefCounted
## Whitelist of jam_1.0.0 handlers. handler_id must equal enh_id.
## Config selects a handler; it never names a script to execute.

const LEGACY_TYPES: Array[int] = [1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 16]

const SPECS: Dictionary = {
	"EN_NUM1": {
		"legacy_no": 1, "family_id": "VALUE", "valid_card_kinds": ["NUM"],
		"hooks": ["STAT"], "param_types": {"add": "int"}, "slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_NUM2": {
		"legacy_no": 1, "family_id": "VALUE", "valid_card_kinds": ["NUM"],
		"hooks": ["STAT"], "param_types": {"add": "int"}, "slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_NUM3": {
		"legacy_no": 1, "family_id": "VALUE", "valid_card_kinds": ["NUM"],
		"hooks": ["STAT"], "param_types": {"add": "int"}, "slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_ECHO": {
		"legacy_no": 2, "family_id": "ECHO", "valid_card_kinds": ["NUM"],
		"hooks": ["OPERAND"], "param_types": {"repeat": "int"}, "slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_RETURN": {
		"legacy_no": 3, "family_id": "RETURN", "valid_card_kinds": ["NUM", "OP"],
		"hooks": ["AFTER_PLAY"], "param_types": {"uses_per_run": "int"}, "slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_FRAGILE": {
		"legacy_no": 4, "family_id": "FRAGILE", "valid_card_kinds": ["NUM"],
		"hooks": ["STAT", "AFTER_PLAY"], "param_types": {"add": "int", "break_p": "float"},
		"slot_cost": 1, "risk_kind": "RISK",
	},
	"EN_ALCHEMY": {
		"legacy_no": 5, "family_id": "ALCHEMY", "valid_card_kinds": ["NUM", "OP"],
		"hooks": ["ON_APPLY"], "param_types": {"collection_id": "string"},
		"slot_cost": 0, "risk_kind": "CONVERT",
	},
	"EN_MAGNET": {
		"legacy_no": 6, "family_id": "MAGNET", "valid_card_kinds": ["NUM", "OP"],
		"hooks": ["ON_DRAW"], "param_types": {"extra_draw": "int", "chain_depth": "int"},
		"slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_YINYANG": {
		"legacy_no": 7, "family_id": "YINYANG", "valid_card_kinds": ["NUM", "OP"],
		"hooks": ["EQUATION"], "param_types": {"distinct_cards": "int", "damage_mult": "float"},
		"slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_FLAMMABLE": {
		"legacy_no": 10, "family_id": "FLAMMABLE", "valid_card_kinds": ["NUM"],
		"hooks": ["OPERAND"], "param_types": {"mul_add": "int", "add_add": "int"},
		"slot_cost": 1, "risk_kind": "RISK",
	},
	"EN_SMOLDER": {
		"legacy_no": 11, "family_id": "SMOLDER", "valid_card_kinds": ["NUM"],
		"hooks": ["ON_BURN"], "param_types": {"uses_per_run": "int"}, "slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_COMBO": {
		"legacy_no": 12, "family_id": "COMBO", "valid_card_kinds": ["NUM", "OP"],
		"hooks": ["ON_COMBO"], "param_types": {"bonus_s": "float"}, "slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_FROZEN": {
		"legacy_no": 13, "family_id": "FROZEN", "valid_card_kinds": ["NUM", "OP"],
		"hooks": ["ON_DRAW"], "param_types": {"lock_turns": "int"}, "slot_cost": 1, "risk_kind": "CURSE",
	},
	"EN_PRICE": {
		"legacy_no": 14, "family_id": "PRICE", "valid_card_kinds": ["NUM", "OP"],
		"hooks": ["VALUE_SCORE"], "param_types": {"value_mult": "float"}, "slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_GHOST": {
		"legacy_no": 15, "family_id": "GHOST", "valid_card_kinds": ["NUM", "OP"],
		"hooks": ["HAND_WEIGHT"], "param_types": {"slot_cost": "int"}, "slot_cost": 1, "risk_kind": "BOON",
	},
	"EN_VANGUARD": {
		"legacy_no": 16, "family_id": "VANGUARD", "valid_card_kinds": ["NUM", "OP"],
		"hooks": ["BATTLE_START"], "param_types": {"opening": "bool"}, "slot_cost": 1, "risk_kind": "BOON",
	},
}


static func has_id(enh_id: String) -> bool:
	return SPECS.has(enh_id)


static func normal_drop_allowed(enh_id: String) -> bool:
	return enh_id != "EN_ALCHEMY" and enh_id != "EN_FROZEN"
