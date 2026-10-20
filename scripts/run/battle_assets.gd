class_name BattleAssets
extends RefCounted
## Shared animation registry. No gameplay RNG, timers or async callbacks.

const ROOT := "res://assets/battle/imported/"
static var _frames: SpriteFrames
static var _textures: Dictionary = {}


static func texture(stem: String) -> Texture2D:
	# Canvas draw commands need the texture RID to outlive _draw().
	if not _textures.has(stem):
		_textures[stem] = load(ROOT + stem + ".png") as Texture2D
	return _textures[stem]


static func tier(depth: int) -> int:
	return 1 if depth <= 3 else (2 if depth <= 6 else 3)


static func background(depth: int, battle: bool) -> Texture2D:
	return texture(("battle_bg" if battle else "map_bg_") + str(tier(depth)))


static func animations() -> SpriteFrames:
	if _frames == null:
		_frames = SpriteFrames.new()
		_frames.remove_animation("default")
		var clips: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "animations.json"))
		for key in clips:
			_frames.add_animation(key)
			_frames.set_animation_loop(key, false)
			_frames.set_animation_speed(key, 1.0)
			for i in clips[key].frames.size():
				_frames.add_frame(key, load(clips[key].frames[i]), float(clips[key].durations[i]))
	return _frames


static func clip_texture(key: StringName, elapsed: float) -> Texture2D:
	var frames := animations()
	if not frames.has_animation(key):
		return null
	var count := frames.get_frame_count(key)
	for i in count:
		elapsed -= frames.get_frame_duration(key, i) / frames.get_animation_speed(key)
		if elapsed < 0.0 or i == count - 1:
			return frames.get_frame_texture(key, i)
	return null


static func clip_seconds(key: StringName) -> float:
	var frames := animations()
	if not frames.has_animation(key):
		return 0.0
	var seconds := 0.0
	for i in frames.get_frame_count(key):
		seconds += frames.get_frame_duration(key, i) / frames.get_animation_speed(key)
	return seconds
