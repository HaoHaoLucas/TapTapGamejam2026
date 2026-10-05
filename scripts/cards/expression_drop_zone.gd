extends PanelContainer

var card_panel: Control
var region: StringName = &"expression"
var card_row: HFlowContainer
var insertion_index: int = -1
var _hovering: bool = false

func _process(_delta: float) -> void:
	if not _hovering:
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if not get_viewport().gui_is_dragging() or not card_panel.is_turn_active() or hovered == null or (hovered != self and not is_ancestor_of(hovered)):
		clear_hint()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		clear_hint()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return can_accept_at(global_position + at_position, data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	accept_at(global_position + at_position, data)

func can_accept_at(global_point: Vector2, data: Variant) -> bool:
	if not card_panel.can_accept_drop(data, region):
		clear_hint()
		return false
	_hovering = true
	insertion_index = insertion_at(global_point) if region == &"expression" else -1
	queue_redraw()
	return true

func accept_at(global_point: Vector2, data: Variant) -> void:
	var index := insertion_at(global_point) if region == &"expression" else -1
	card_panel.accept_drop(data, region, index)
	clear_hint()

func insertion_at(global_point: Vector2) -> int:
	var count: int = card_panel.get_expression_cards().size()
	for index in range(count):
		var rect: Rect2 = card_row.get_child(index).get_global_rect()
		if rect.has_point(global_point):
			return index if global_point.x < rect.get_center().x else index + 1
		if index > 0:
			var previous: Rect2 = card_row.get_child(index - 1).get_global_rect()
			# Only gaps in the same visual row belong to an interior boundary.
			if is_equal_approx(previous.position.y, rect.position.y) and global_point.y >= rect.position.y and global_point.y < rect.end.y:
				if global_point.x >= previous.end.x and global_point.x < rect.position.x:
					return index
	return count

func clear_hint() -> void:
	_hovering = false
	insertion_index = -1
	queue_redraw()

func _draw() -> void:
	if not _hovering:
		return
	var accent := Color("72dfcb")
	if region != &"expression":
		if region == &"burn":
			accent = Color("ffb375")
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), accent, false, 2.0)
		return
	var count: int = card_panel.get_expression_cards().size()
	var marker := Rect2(Vector2(10, 16), Vector2(3, 116))
	if count > 0 and insertion_index >= 0:
		var anchor: Control = card_row.get_child(mini(insertion_index, count - 1))
		var rect := anchor.get_global_rect()
		var x := rect.position.x - 6 if insertion_index < count else rect.end.x + 3
		marker.position = Vector2(x, rect.position.y) - global_position
		marker.size.y = rect.size.y
	draw_rect(marker, accent)
