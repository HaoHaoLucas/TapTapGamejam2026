class_name SceneRegistry
extends RefCounted
## scene_key from the tables is not a file path. Battle reuses the card demo.


static func path_for(scene_key: String) -> String:
	match scene_key:
		"battle":
			return "res://scenes/cards/card_demo.tscn"
		"event":
			return ""
		_:
			return ""
