extends Control

var focus_rect: Rect2
var allows_action: bool = false
var arrow_from: Vector2
var arrow_to: Vector2


func configure(rect: Rect2, action: bool, start: Vector2 = Vector2.ZERO, finish: Vector2 = Vector2.ZERO) -> void:
	focus_rect = rect
	allows_action = action
	arrow_from = start
	arrow_to = finish
	queue_redraw()


func _has_point(point: Vector2) -> bool:
	# Сквозь отверстие проходят настоящие mouse/touch события, не синтетические клики.
	return not (allows_action and focus_rect.has_area() and focus_rect.has_point(point))


func _draw() -> void:
	var shade: Color = Color(0.025, 0.06, 0.1, 0.73)
	var bounds: Rect2 = Rect2(Vector2.ZERO, size)
	var hole: Rect2 = focus_rect.intersection(bounds)
	if hole.has_area():
		draw_rect(Rect2(0, 0, size.x, hole.position.y), shade)
		draw_rect(Rect2(0, hole.end.y, size.x, size.y - hole.end.y), shade)
		draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), shade)
		draw_rect(Rect2(hole.end.x, hole.position.y, size.x - hole.end.x, hole.size.y), shade)
		draw_style_box(_border(), hole)
	else:
		draw_rect(bounds, shade)
	if arrow_from != arrow_to:
		var end: Vector2 = arrow_to
		var direction: Vector2 = (arrow_to - arrow_from).normalized()
		draw_dashed_line(arrow_from, end, Color("ffe1a0"), 5.0, 12.0, true)
		draw_line(end, end - direction.rotated(0.6) * 24.0, Color("ffe1a0"), 5.0, true)
		draw_line(end, end - direction.rotated(-0.6) * 24.0, Color("ffe1a0"), 5.0, true)


func _border() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color("f4cc77")
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	return style
