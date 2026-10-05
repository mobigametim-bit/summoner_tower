class_name SummonSlot
extends Node2D

@export_range(1, 6, 1) var slot_index: int = 1
@export var faces_left: bool = false
@export var hit_rect: Rect2 = Rect2(-70.0, -64.0, 140.0, 160.0)

@onready var unit_host: Node2D = $UnitHost
@onready var empty_label: Label = $EmptyLabel
@onready var highlight: Sprite2D = $Highlight

var unit: CombatUnit


func is_empty() -> bool:
	return not is_instance_valid(unit)


func place_unit(creature: CombatUnit) -> bool:
	if not is_empty() or not is_instance_valid(creature):
		return false

	assign_unit(creature)
	unit_host.add_child(unit)
	align_unit()
	return true


func assign_unit(creature: CombatUnit) -> void:
	unit = creature
	empty_label.visible = is_empty()


func align_unit() -> void:
	if not is_empty():
		unit.position = Vector2.ZERO
		unit.set_facing_left(faces_left)


func contains_point(world_position: Vector2) -> bool:
	return hit_rect.has_point(to_local(world_position))


func set_drop_highlight(enabled: bool, merging: bool = false) -> void:
	highlight.visible = enabled
	highlight.modulate = Color("ffc45c") if merging else Color("82e9ed")
