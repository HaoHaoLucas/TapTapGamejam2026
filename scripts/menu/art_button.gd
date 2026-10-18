class_name ArtButton
extends Control
## Pre-painted menu button. Hover crossfades; clicks use the normal texture's alpha.


signal pressed

const ALPHA_THRESHOLD := 32.0 / 255.0

@export var normal_texture: Texture2D:
	set(value):
		normal_texture = value
		if is_node_ready():
			apply_textures()

@export var hover_texture: Texture2D:
	set(value):
		hover_texture = value
		if is_node_ready():
			apply_textures()

@export var fade_seconds: float = 0.1

var _normal: TextureRect
var _hover: TextureRect
var _mask: BitMap
var _fade: Tween
var _input_enabled := true
var _pointer_inside := false
var _pressing := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _ready() -> void:
	_normal = get_node_or_null("Normal") as TextureRect
	_hover = get_node_or_null("Hover") as TextureRect
	assert(_normal != null and _hover != null, "ArtButton: 场景里缺 Normal / Hover 两层贴图")
	apply_textures()
	_apply_enabled(true)


func set_hovering(hovering: bool, instant: bool = false) -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hovering else Control.CURSOR_ARROW
	if _fade != null:
		_fade.kill()
		_fade = null
	if _normal == null or _hover == null:
		return
	var hover_alpha := 1.0 if hovering else 0.0
	var normal_alpha := 0.0 if hovering else 1.0
	if instant or fade_seconds <= 0.0 or not is_inside_tree():
		_hover.modulate.a = hover_alpha
		_normal.modulate.a = normal_alpha
		return
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(_hover, "modulate:a", hover_alpha, fade_seconds)
	_fade.tween_property(_normal, "modulate:a", normal_alpha, fade_seconds)


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if _normal == null:
		return
	_apply_enabled(false)


func apply_textures() -> void:
	if _normal != null:
		_normal.texture = normal_texture
	if _hover != null:
		_hover.texture = hover_texture
	_rebuild_mask()


func _gui_input(event: InputEvent) -> void:
	if not _input_enabled:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			_pressing = true
			_pointer_inside = true
			_refresh_hover()
			accept_event()
			return
		# Godot 4.7 already stores this position in the control's local space.
		_pressing = false
		var inside := _has_point(mouse.position)
		_pointer_inside = inside
		if inside:
			pressed.emit()
		if is_inside_tree():
			_refresh_hover()
		accept_event()
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		pressed.emit()
		accept_event()


func _has_point(point: Vector2) -> bool:
	if _mask == null:
		return false
	var mask_size := _mask.get_size()
	if mask_size.x <= 0 or mask_size.y <= 0:
		return false
	if size.x <= 0.0 or size.y <= 0.0:
		return false
	if point.x < 0.0 or point.y < 0.0 or point.x >= size.x or point.y >= size.y:
		return false
	var px := clampi(int(point.x / size.x * float(mask_size.x)), 0, mask_size.x - 1)
	var py := clampi(int(point.y / size.y * float(mask_size.y)), 0, mask_size.y - 1)
	return _mask.get_bit(px, py)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			if not _input_enabled:
				return
			_pointer_inside = true
			_refresh_hover()
		NOTIFICATION_MOUSE_EXIT:
			_pointer_inside = false
			_refresh_hover()
		NOTIFICATION_FOCUS_ENTER:
			if _input_enabled:
				_refresh_hover()
		NOTIFICATION_FOCUS_EXIT:
			_refresh_hover()


func _refresh_hover(instant: bool = false) -> void:
	if not _input_enabled:
		set_hovering(false, true)
		return
	# Pointer and press only. Keyboard focus used to count as hover, which pinned
	# 开始游戏 (and 取消) on the hover art for the whole time they stayed focused.
	set_hovering(_pointer_inside or _pressing, instant)


func _apply_enabled(instant: bool) -> void:
	if _input_enabled:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		if is_inside_tree():
			_pointer_inside = _has_point(get_local_mouse_position())
		_refresh_hover(instant)
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_pressing = false
	_pointer_inside = false
	if is_inside_tree() and has_focus():
		release_focus()
	set_hovering(false, true)


func _rebuild_mask() -> void:
	_mask = null
	if normal_texture == null:
		return
	var image := normal_texture.get_image()
	if image == null or image.is_empty():
		return
	if image.is_compressed():
		image = image.duplicate()
		if image.decompress() != OK:
			return
	var mask := BitMap.new()
	mask.create_from_image_alpha(image, ALPHA_THRESHOLD)
	var mask_size := mask.get_size()
	if mask_size.x <= 0 or mask_size.y <= 0:
		return
	_mask = mask
