@tool
extends Node2D

# Polygon2D в Godot 4.7.2 обновляет index buffer через GL_ARRAY_BUFFER,
# что запрещено в WebGL. Для жёсткого VFX достаточно canvas polygon.
@export var polygon: PackedVector2Array = []:
	set(value):
		polygon = value
		queue_redraw()
@export var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()


func _draw() -> void:
	if polygon.size() >= 3:
		draw_colored_polygon(polygon, color)
