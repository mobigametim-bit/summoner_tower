class_name WaveConfig
extends Resource

@export_range(1, 1000, 1) var first_enemy_count: int = 1
@export_range(0, 100, 1) var enemy_count_growth: int = 0
@export_range(0, 10000, 1) var enemy_health_growth: int = 0
@export_range(0.1, 10.0, 0.1) var spawn_interval: float = 0.1
@export_range(0.1, 30.0, 0.1) var intermission_duration: float = 0.1
@export var goblin_scene: PackedScene
@export var orc_scene: PackedScene
@export var golem_scene: PackedScene
@export var boss_scene: PackedScene
@export_range(1, 1000, 1) var orc_first_wave: int = 3
@export_range(1, 1000, 1) var golem_first_wave: int = 6
@export_range(0.0, 1.0, 0.05) var orc_share: float = 0.30
@export_range(0.0, 1.0, 0.05) var golem_share: float = 0.15
@export_range(1, 100, 1) var boss_interval: int = 5
@export_range(0, 100000, 1) var boss_health_growth: int = 250


func enemy_count_for(wave: int) -> int:
	return first_enemy_count + maxi(wave - 1, 0) * enemy_count_growth


func total_enemy_count_for(wave: int) -> int:
	return enemy_count_for(wave) + (1 if is_boss_wave(wave) else 0)


func enemy_health_for(wave: int, base_health: int) -> int:
	return base_health + maxi(wave - 1, 0) * enemy_health_growth


func is_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % boss_interval == 0


func boss_health_for(wave: int, base_health: int) -> int:
	return base_health + maxi(floori(float(wave) / boss_interval) - 1, 0) * boss_health_growth


func sequence_for(wave: int) -> Array[PackedScene]:
	var count: int = enemy_count_for(wave)
	var orcs: int = mini(maxi(1, floori(count * orc_share)), count) if wave >= orc_first_wave else 0
	var golems: int = mini(maxi(1, floori(count * golem_share)), count - orcs) if wave >= golem_first_wave else 0
	var remaining: Array[int] = [count - orcs - golems, orcs, golems]
	var types: Array[PackedScene] = [goblin_scene, orc_scene, golem_scene]
	var result: Array[PackedScene] = []
	# Квоты гарантируют появление открытых типов, порядок воспроизводим без отдельного RNG.
	while result.size() < count:
		for index: int in remaining.size():
			if remaining[index] > 0:
				result.append(types[index])
				remaining[index] -= 1
	if is_boss_wave(wave):
		result.push_front(boss_scene)
	return result
