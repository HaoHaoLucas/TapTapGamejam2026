extends Node
## 悬停时放大并旋转父节点，离开时沿同一条曲线走回来。
## 挂在卡面（PanelContainer）下面当子节点用，不参与排版。

const HOVER_SCALE := 1.15
const HOVER_ROTATION_DEG := 15.0
const DURATION := 0.55

var _face: Control
var _tween: Tween


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
	_face.z_index = 1
	_run(Vector2.ONE * HOVER_SCALE, deg_to_rad(HOVER_ROTATION_DEG), Tween.EASE_OUT)


## EASE_IN 是 EASE_OUT 的时间反演，所以这一程就是上一程的原路返回。
func _on_mouse_exited() -> void:
	_face.z_index = 0
	_run(Vector2.ONE, 0.0, Tween.EASE_IN)


func _run(scale_to: Vector2, rotation_to: float, ease: Tween.EaseType) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.set_ease(ease)
	_tween.tween_property(_face, "scale", scale_to, DURATION)
	_tween.tween_property(_face, "rotation", rotation_to, DURATION)
