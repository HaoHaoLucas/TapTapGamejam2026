extends Control
## 一只怪一个场景：换怪时释放旧实例；没有专属场景的怪退回共用立绘。

const DEFAULT_SCENE := "res://scenes/run/enemies/mon_default.tscn"
const SCENES := {
	"MON_INK": "res://scenes/run/enemies/mon_ink.tscn",
	"MON_PARITY": "res://scenes/run/enemies/mon_parity.tscn",
	"MON_PRIEST": "res://scenes/run/enemies/mon_priest.tscn",
}

var _shown_id := ""
var _current: Control


func show_monster(monster_id: String) -> void:
	if monster_id == _shown_id and _current != null:
		return
	_shown_id = monster_id
	var path := str(SCENES.get(monster_id, DEFAULT_SCENE))
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("EnemyArt: 载入不了 %s" % path)
		return
	if _current != null:
		remove_child(_current)
		_current.queue_free()
		_current = null
	var instance := packed.instantiate()
	if not (instance is Control):
		push_error("EnemyArt: %s 的根不是 Control" % path)
		instance.queue_free()
		return
	_current = instance as Control
	add_child(_current)
	_current.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
