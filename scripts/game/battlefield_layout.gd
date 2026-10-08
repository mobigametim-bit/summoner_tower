class_name BattlefieldLayout
extends RefCounted

enum Cell { ENVIRONMENT, ROAD, SPAWN, TOWER, SUMMON }
enum PortalSide { TOP, LEFT, RIGHT }

var seed_value: int = 0
var grid_size: Vector2i
var cell_size: float = 0.0
var origin: Vector2
var cells: PackedInt32Array = []
var road_cells: Array[Vector2i] = []
var network_cells: Array[Vector2i] = []
var paths: Array[Array] = []
var branch_cells: Array[Array] = []
var portal_cells: Array[Vector2i] = []
var portal_sides: Array[int] = []
var curves: Array[Curve2D] = []
var slot_cells: Array[Vector2i] = []
var curve: Curve2D
var slots: PackedVector2Array = []
var decorations: Array[Dictionary] = []
var turn_probability: float = 0.0
var target_length: float = 0.0
var used_fallback: bool = false
var search_steps: int = 0


func cell_center(cell: Vector2i) -> Vector2:
	return origin + (Vector2(cell) + Vector2.ONE * 0.5) * cell_size


func cell_type(cell: Vector2i) -> int:
	return cells[cell.y * grid_size.x + cell.x]
