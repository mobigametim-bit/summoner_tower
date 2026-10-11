class_name AttackRangePreview
extends Node2D

@export_range(1.0, 2000.0, 1.0) var radius: float = 300.0
@export var level_color: Color = Color("71913e")


func configure(attack_range: float, color: Color) -> void:
	radius = attack_range
	level_color = color
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(level_color, 0.14))
	draw_circle(Vector2.ZERO, radius, Color(level_color, 0.65), false, 2.0, true)
