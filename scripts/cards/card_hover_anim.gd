extends Node
## 悬停时放大、旋转并上抬父节点，离开时收回。
## 挂在卡面（PanelContainer）下面当子节点用，不参与排版。

const HOVER_SCALE := 1.15
const HOVER_ROTATION_DEG := 15.0
const HOVER_LIFT := 10.0
const DURATION := 0.55

var _face: Control
var _tween: Tween
var _home := Vector2.ZERO


func _ready() -> void:
	_face = get_parent() as Control
	if _face == null:
		push_warning("HoverAnim: 父节点不是 Control，悬停动画不生效")
		return
	_face.resized.connect(_center_pivot)
	_center_pivot()
	_face.mouse_entered.connect(_on_mouse_entered)
	_face.mouse_exited.connect(_on_mouse_exited)


## 旋转与缩放绕节点中心，否则 15° 会让卡牌绕左上角甩出去。
func _center_pivot() -> void:
	_face.pivot_offset = _face.size * 0.5


func _on_mouse_entered() -> void:
	_home = _face.position
	_face.z_index = 1
	_run(Vector2.ONE * HOVER_SCALE, deg_to_rad(HOVER_ROTATION_DEG), _home - Vector2(0.0, HOVER_LIFT),
		Tween.TRANS_BACK, Tween.EASE_OUT)


func _on_mouse_exited() -> void:
	_face.z_index = 0
	_run(Vector2.ONE, 0.0, _home, Tween.TRANS_BACK, Tween.EASE_OUT)


## 上抬单独用 EXPO：起步极快、迅速衰减停住，跟缩放旋转同一时长同时跑。
func _run(scale_to: Vector2, rotation_to: float, position_to: Vector2,
		trans: Tween.TransitionType, ease: Tween.EaseType) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_face, "scale", scale_to, DURATION).set_trans(trans).set_ease(ease)
	_tween.tween_property(_face, "rotation", rotation_to, DURATION).set_trans(trans).set_ease(ease)
	_tween.tween_property(_face, "position", position_to, DURATION).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
