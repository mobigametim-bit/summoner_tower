class_name PowerBalanceConfig
extends Resource

@export var reference_unit: UnitStats
@export var reference_enemy: EnemyStats
@export var enemy_stats: Array[EnemyStats] = []
@export_range(1, 10000, 1) var reference_tower_health: int = 100
@export_range(0.1, 100.0, 0.1) var power_conversion: float = 6.0
@export_range(0.1, 2.0, 0.05) var wave_budget_multiplier: float = 1.0
@export var saw_coefficients: Array[float] = [0.70, 0.85, 1.0, 1.15, 1.35]
@export_range(1.0, 3.0, 0.01) var stage_growth: float = 1.18
@export_range(1.0, 1000.0, 1.0) var minimum_stage_power: float = 12.0
@export_range(1.0, 3.0, 0.01) var minimum_growth: float = 1.35
@export var tier_unlock_waves: Array[int] = [1, 3, 6, 8, 11]
@export_range(5, 200, 1) var maximum_regular_enemies: int = 80
@export_range(0.0, 2.0, 0.05) var control_power_weight: float = 0.5


func unit_power(stats: UnitStats, damage: float, interval: float, slow_ratio: float = -1.0) -> float:
	var reference_dps: float = float(reference_unit.damage) / reference_unit.attack_interval
	var dps: float = damage / interval
	if stats.burn_duration > 0.0:
		dps += damage * stats.burn_damage_ratio / stats.burn_duration
	if stats.ability != UnitStats.Ability.NONE:
		dps += damage * stats.ability_damage_ratio / stats.ability_cooldown
	var control: float = 1.0
	var slow: float = stats.slow_ratio if slow_ratio < 0.0 else slow_ratio
	if slow > 0.0:
		control += control_power_weight * slow
	if stats.ability == UnitStats.Ability.FROST_WAVE:
		control += control_power_weight * stats.freeze_duration / stats.ability_cooldown
	return dps / reference_dps * stats.attack_range / reference_unit.attack_range * stats.area_power_multiplier * control


func player_power(units_power: float, maximum_health: int) -> float:
	return units_power * float(maximum_health) / reference_tower_health


func enemy_power(stats: EnemyStats, health: int) -> float:
	return float(health) / reference_enemy.base_health * stats.move_speed / reference_enemy.move_speed * float(stats.tower_damage) / reference_enemy.tower_damage


func stage_for(wave: int) -> int:
	return floori(float(maxi(wave - 1, 0)) / saw_coefficients.size())


func coefficient_for(wave: int) -> float:
	return saw_coefficients[maxi(wave - 1, 0) % saw_coefficients.size()]


func maximum_tier_for(wave: int) -> int:
	var highest: int = 1
	for index: int in mini(tier_unlock_waves.size(), EnemyStats.TIER_COLORS.size()):
		if wave >= tier_unlock_waves[index]:
			highest = index + 1
	return highest


func budget_for(wave: int, power: float) -> float:
	var stage: int = stage_for(wave)
	var adaptive: float = power * power_conversion * pow(stage_growth, stage)
	var minimum: float = minimum_stage_power * pow(minimum_growth, stage)
	return maxf(adaptive, minimum) * coefficient_for(wave) * wave_budget_multiplier
