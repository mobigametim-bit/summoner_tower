class_name BattlefieldConfig
extends Resource

@export var column_range: Vector2i = Vector2i(6, 8)
@export var playable_rect: Rect2 = Rect2(0, 0, 720, 1184)
@export var slot_count_range: Vector2i = Vector2i(6, 10)
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
@export var decoration_probability: float = 0.55
@export var decoration_textures: Array[Texture2D] = []


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
