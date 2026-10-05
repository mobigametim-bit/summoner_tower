class_name WaveConfig
extends Resource

@export_range(1, 1000, 1) var first_enemy_count: int = 1
@export_range(0, 100, 1) var enemy_count_growth: int = 0
@export_range(0, 10000, 1) var enemy_health_growth: int = 0
@export_range(0.1, 10.0, 0.1) var spawn_interval: float = 0.1
@export_range(0.1, 30.0, 0.1) var intermission_duration: float = 0.1
@export_range(0, 10000, 1) var kill_mana: int = 0


func enemy_count_for(wave: int) -> int:
	return first_enemy_count + maxi(wave - 1, 0) * enemy_count_growth


func enemy_health_for(wave: int, base_health: int) -> int:
	return base_health + maxi(wave - 1, 0) * enemy_health_growth
