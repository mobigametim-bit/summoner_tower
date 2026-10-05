class_name EncounterConfig
extends Resource

@export_range(1, 10000, 1) var tower_max_health: int = 1
@export_range(1, 10000, 1) var enemy_tower_damage: int = 1
@export_range(1, 10000, 1) var enemy_max_health: int = 1
@export_range(1.0, 1000.0, 1.0) var enemy_move_speed: float = 1.0
@export_range(0.1, 10.0, 0.1) var next_enemy_delay: float = 1.0
