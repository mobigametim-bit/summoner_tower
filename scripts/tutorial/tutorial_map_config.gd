class_name TutorialMapConfig
extends Resource

@export var seed_value: int = 146
@export var landscape_seed: int = 0
@export_range(6, 8, 1) var columns: int = 6
@export_range(10, 15, 1) var slot_count: int = 12
@export_range(1, 3, 1) var portal_count: int = 1
@export var move_cell: Vector2i = Vector2i(2, 2)
