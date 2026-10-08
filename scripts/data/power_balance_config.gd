class_name PowerBalanceConfig
extends Resource

@export var reference_unit: UnitStats
@export var reference_enemy: EnemyStats
@export var enemy_stats: Array[EnemyStats] = []
@export_range(1, 10000, 1) var reference_tower_health: int = 100
@export_range(0.1, 100.0, 0.1) var power_conversion: float = 6.0
@export var saw_coefficients: Array[float] = [0.70, 0.85, 1.0, 1.15, 1.35]
@export_range(1.0, 3.0, 0.01) var stage_growth: float = 1.18
@export_range(1.0, 1000.0, 1.0) var minimum_stage_power: float = 12.0
@export_range(1.0, 3.0, 0.01) var minimum_growth: float = 1.35
@export_range(1, 100, 1) var tier_unlock_interval: int = 5
@export_range(5, 200, 1) var maximum_regular_enemies: int = 80


func unit_power(stats: UnitStats, damage: float, interval: float) -> float:
	var reference_dps: float = float(reference_unit.damage) / reference_unit.attack_interval
	return damage / interval / reference_dps * stats.attack_range / reference_unit.attack_range


func player_power(units_power: float, maximum_health: int) -> float:
	return units_power * float(maximum_health) / reference_tower_health


func enemy_power(stats: EnemyStats, health: int) -> float:
	return float(health) / reference_enemy.base_health * stats.move_speed / reference_enemy.move_speed * float(stats.tower_damage) / reference_enemy.tower_damage


func stage_for(wave: int) -> int:
	return floori(float(maxi(wave - 1, 0)) / saw_coefficients.size())


func coefficient_for(wave: int) -> float:
	return saw_coefficients[maxi(wave - 1, 0) % saw_coefficients.size()]


func maximum_tier_for(wave: int) -> int:
	return mini(1 + floori(float(maxi(wave - 1, 0)) / tier_unlock_interval), EnemyStats.TIER_COLORS.size())


func budget_for(wave: int, power: float) -> float:
	var stage: int = stage_for(wave)
	var adaptive: float = power * power_conversion * pow(stage_growth, stage)
	var minimum: float = minimum_stage_power * pow(minimum_growth, stage)
	return maxf(adaptive, minimum) * coefficient_for(wave)
