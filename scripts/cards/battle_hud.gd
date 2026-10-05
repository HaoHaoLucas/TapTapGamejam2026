class_name BattleHUD
extends HBoxContainer
## Display adapter. Battle owns HP; the local countdown is optional.

signal time_expired

var _health: int = 100
var _max_health: int = 100
var _remaining: float = 0.0
var _hp_label: Label
var _hp_bar: ProgressBar
var _time_label: Label
var _timer: Timer

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_hp_label = Label.new()
	add_child(_hp_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(160, 18)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.show_percentage = false
	add_child(_hp_bar)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 26)
	add_child(_time_label)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)
	_refresh()

func set_health(current: int, maximum: int) -> void:
	_max_health = maxi(1, maximum)
	_health = clampi(current, 0, _max_health)
	_refresh()

func start_countdown(seconds: float = 30.0) -> void:
	_remaining = maxf(0.0, seconds)
	_timer.stop()
	if _remaining > 0.0:
		_timer.start(_remaining)
		_refresh()
	else:
		_on_timeout()

func stop_countdown() -> void:
	if not _timer.is_stopped():
		_remaining = _timer.time_left
	_timer.stop()
	_refresh()

func set_time_remaining(seconds: float) -> void:
	# External timing takes ownership; displaying zero does not emit timeout.
	if is_instance_valid(_timer):
		_timer.stop()
	_remaining = maxf(0.0, seconds)
	_refresh()

func get_time_remaining() -> float:
	return _timer.time_left if is_instance_valid(_timer) and not _timer.is_stopped() else _remaining

func _process(_delta: float) -> void:
	if not _timer.is_stopped():
		_remaining = _timer.time_left
		_refresh()

func _on_timeout() -> void:
	_remaining = 0.0
	_refresh()
	time_expired.emit()

func _refresh() -> void:
	if not is_node_ready():
		return
	_hp_label.text = "HP %d/%d" % [_health, _max_health]
	_hp_bar.max_value = _max_health
	_hp_bar.value = _health
	_time_label.text = "%02d 秒" % ceili(_remaining)
