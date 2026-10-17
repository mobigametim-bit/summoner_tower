class_name BattlefieldConfig
extends Resource

@export var column_range: Vector2i = Vector2i(6, 8)
@export var playable_rect: Rect2 = Rect2(0, 0, 720, 1184)
@export var slot_count_range: Vector2i = Vector2i(10, 15)
@export var portal_count_range: Vector2i = Vector2i(1, 3)
@export var portal_count_weights: Vector3 = Vector3(50, 30, 20)
@export var portal_max_y: float = 640.0
@export var turn_probability_range: Vector2 = Vector2(0.25, 0.75)
@export var horizontal_run_range: Vector2i = Vector2i(2, 5)
@export var vertical_run_range: Vector2i = Vector2i(1, 3)
@export var route_length_range: Vector2 = Vector2(1300, 2500)
@export var minimum_attack_range: float = 260.0
@export var minimum_coverage_length: float = 160.0
@export var generation_attempts: int = 24
@export var search_steps_per_attempt: int = 1200
@export var cell_gap: float = 4.0
@export var decoration_probability: float = 0.40
@export var decoration_textures: Array[Texture2D] = []

@export_group("Environment")
@export var ground_texture: Texture2D = preload("res://assets/environment/ground_cell.svg")
@export var road_texture: Texture2D = preload("res://assets/environment/paved_road.svg")
@export var pedestal_texture: Texture2D = preload("res://assets/environment/pedestal.svg")
@export var tower_visual_scene: PackedScene = preload("res://scenes/visuals/TowerVisual.tscn")
@export var portal_texture: Texture2D = preload("res://assets/environment/portal.svg")
@export var road_edge_color: Color = Color(0.3019608, 0.31764707, 0.2509804, 1)
@export var portal_energy_color: Color = Color("c091ff")
@export var portal_smoke_gradient: Gradient = preload("res://resources/vfx/summon_portal/smoke_fade.tres")


func grid_size(columns: int) -> Vector2i:
	var width: int = clampi(columns, column_range.x, column_range.y)
	return Vector2i(width, floori(playable_rect.size.y / (playable_rect.size.x / width)))


func cell_size(columns: int) -> float:
	return playable_rect.size.x / grid_size(columns).x


func roll_portal_count(rng: RandomNumberGenerator) -> int:
	var roll: float = rng.randf_range(0.0, portal_count_weights.x + portal_count_weights.y + portal_count_weights.z)
	if roll < portal_count_weights.x:
		return 1
	if roll < portal_count_weights.x + portal_count_weights.y:
		return 2
	return 3
