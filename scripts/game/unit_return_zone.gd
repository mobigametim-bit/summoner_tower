class_name UnitReturnZone
extends Node2D

@export var hit_rect: Rect2 = Rect2(-100.0, -120.0, 200.0, 196.0)

@onready var highlight: Sprite2D = $Highlight
@onready var refund_label: Label = $RefundLabel


func contains_point(world_position: Vector2) -> bool:
	return hit_rect.has_point(to_local(world_position))


func set_preview(enabled: bool, hovered: bool = false, refund: int = 0) -> void:
	highlight.visible = enabled
	refund_label.visible = enabled
	highlight.modulate = Color("82e9ed") if hovered else Color(0.85, 0.68, 0.33, 0.55)
	refund_label.modulate = Color("82e9ed") if hovered else Color("ffe0a0")
	refund_label.text = "RETURN · +%d MANA" % refund
