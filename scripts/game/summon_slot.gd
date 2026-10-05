class_name SummonSlot
extends Node2D

@export_range(1, 6, 1) var slot_index: int = 1
@export var faces_left: bool = false

@onready var unit_host: Node2D = $UnitHost
@onready var empty_label: Label = $EmptyLabel

var unit: Archer


func is_empty() -> bool:
	return not is_instance_valid(unit)


func place_unit(archer: Archer) -> bool:
	if not is_empty() or not is_instance_valid(archer):
		return false

	unit = archer
	unit_host.add_child(unit)
	unit.position = Vector2.ZERO
	unit.set_facing_left(faces_left)
	empty_label.hide()
	return true
