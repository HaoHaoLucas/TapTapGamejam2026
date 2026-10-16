class_name SceneRegistry
extends RefCounted
## scene_key from the tables is not a file path. Battle is the jam equation scene.


static func path_for(scene_key: String) -> String:
	match scene_key:
		"battle":
			return "res://scenes/run/run_battle.tscn"
		"event":
			return ""
		_:
			return ""
