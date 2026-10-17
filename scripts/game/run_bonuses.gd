class_name RunBonuses
extends Node

const ROUNDING_EPSILON: float = 0.000001

@export var pool: RunUpgradePool

var _counts: Dictionary = {}
var _multipliers: Dictionary = {}
var _additions: Dictionary = {}
var _mana_remainder: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _meta_levels: Array[int] = []
var rerolls_remaining: int = 0


func reset() -> void:
	_counts.clear()
	_multipliers.clear()
	_additions.clear()
	# Снимок исключает повторное применение и изменение бонусов посреди забега.
	_meta_levels = SessionProgress.upgrade_levels.duplicate()
	while _meta_levels.size() < MetaUpgradeConfig.Kind.COUNT:
		_meta_levels.append(0)
	rerolls_remaining = _meta_levels[MetaUpgradeConfig.Kind.LUCKY_CHOICE]
	_mana_remainder = 0.0
	_rng.randomize()


func set_random_seed(value: int) -> void:
	_rng.seed = value


func count(kind: RunUpgrade.Kind) -> int:
	return int(_counts.get(kind, 0))


func apply(upgrade: RunUpgrade) -> void:
	_counts[upgrade.kind] = count(upgrade.kind) + 1
	if upgrade.kind in [RunUpgrade.Kind.FROST_POWER, RunUpgrade.Kind.DEEP_FREEZE, RunUpgrade.Kind.REGENERATION, RunUpgrade.Kind.BETTER_SALE]:
		_additions[upgrade.kind] = added_strength(upgrade.kind) + upgrade.strength
	elif upgrade.kind == RunUpgrade.Kind.CHEAP_SUMMONS:
		_multipliers[upgrade.kind] = multiplier(upgrade.kind) * (1.0 - upgrade.strength)
	elif upgrade.kind not in [RunUpgrade.Kind.MEDKIT, RunUpgrade.Kind.MANA_RESERVE, RunUpgrade.Kind.ARCHER_LV5, RunUpgrade.Kind.MAGE_LV5, RunUpgrade.Kind.FROST_MAGE_LV5]:
		_multipliers[upgrade.kind] = multiplier(upgrade.kind) * (1.0 + upgrade.strength)


func multiplier(kind: RunUpgrade.Kind) -> float:
	return float(_multipliers.get(kind, 1.0))


func added_strength(kind: RunUpgrade.Kind) -> float:
	return float(_additions.get(kind, 0.0))


func roll_choices(current_health: int = -1, maximum_health: int = -1) -> Array[RunUpgrade]:
	var candidates: Array[RunUpgrade] = []
	for upgrade: RunUpgrade in pool.upgrades:
		if upgrade.kind == RunUpgrade.Kind.MEDKIT and maximum_health > 0 and current_health >= maximum_health:
			continue
		if upgrade.kind == RunUpgrade.Kind.BETTER_SALE and manual_refund_percent(50) >= 100:
			continue
		if upgrade.kind == RunUpgrade.Kind.FROST_POWER:
			if slow_ratio_for(pool.frost_base_stats) >= pool.frost_max_ratio - ROUNDING_EPSILON:
				continue
		candidates.append(upgrade)
	var result: Array[RunUpgrade] = []
	var offered_count: int = 3 + _meta_levels[MetaUpgradeConfig.Kind.EXPANDED_CHOICE]
	while result.size() < offered_count and not candidates.is_empty():
		var index: int = _rng.randi_range(0, candidates.size() - 1)
		result.append(candidates[index].variant_for(pool.roll_tier(_rng)))
		candidates.remove_at(index)
	return result


func try_use_reroll() -> bool:
	if rerolls_remaining <= 0:
		return false
	rerolls_remaining -= 1
	return true


func attack_interval_for(stats: UnitStats) -> float:
	return stats.attack_interval / (multiplier(RunUpgrade.Kind.RAPID_FIRE) * _meta_multiplier(MetaUpgradeConfig.Kind.ATTACK_SPEED))


func damage_for(stats: UnitStats) -> int:
	return maxi(floori(damage_amount_for(stats) + ROUNDING_EPSILON), 1)


func damage_amount_for(stats: UnitStats) -> float:
	var specialization: float = 1.0
	match stats.unit_type:
		&"archer": specialization = multiplier(RunUpgrade.Kind.ARCHER_TRAINING)
		&"mage": specialization = multiplier(RunUpgrade.Kind.PYROMANCY)
		&"frost_mage": specialization = multiplier(RunUpgrade.Kind.ICE_POWER)
	return stats.damage * _meta_multiplier(MetaUpgradeConfig.Kind.UNIT_DAMAGE) * multiplier(RunUpgrade.Kind.POWER) * specialization


func attack_range_for(stats: UnitStats) -> float:
	return stats.attack_range * multiplier(RunUpgrade.Kind.LONG_SIGHT) * _meta_multiplier(MetaUpgradeConfig.Kind.ATTACK_RANGE)


func ability_cooldown_for(stats: UnitStats) -> float:
	var config: MetaUpgradeConfig = SessionProgress.UPGRADE_CONFIG
	return stats.ability_cooldown * (1.0 - config.ability_reduction_per_level * _meta_levels[MetaUpgradeConfig.Kind.ABILITY_MASTERY])


func combat_stats_for(stats: UnitStats) -> UnitStats:
	# Снимок для снаряда/расчёта Мощи; общие исходные Resources не меняются.
	var effective: UnitStats = stats.duplicate() as UnitStats
	effective.attack_range = attack_range_for(stats)
	effective.ability_cooldown = ability_cooldown_for(stats)
	effective.burn_damage_ratio = stats.burn_damage_ratio * multiplier(RunUpgrade.Kind.HOT_FLAMES)
	var area_gain: float = multiplier(RunUpgrade.Kind.WIDE_BLAST)
	effective.splash_radius = stats.splash_radius * area_gain
	effective.ability_radius = stats.ability_radius * area_gain
	if stats.splash_radius > 0.0 or stats.ability != UnitStats.Ability.NONE:
		effective.area_power_multiplier = stats.area_power_multiplier * area_gain
	if stats.freeze_duration > 0.0:
		effective.freeze_duration = stats.freeze_duration + added_strength(RunUpgrade.Kind.DEEP_FREEZE)
	return effective


func regeneration_amount() -> float:
	var config: MetaUpgradeConfig = SessionProgress.UPGRADE_CONFIG
	return added_strength(RunUpgrade.Kind.REGENERATION) + config.restoration_per_level * _meta_levels[MetaUpgradeConfig.Kind.RESTORATION]


func manual_refund_percent(base_percent: int) -> float:
	return minf(base_percent + added_strength(RunUpgrade.Kind.BETTER_SALE) * 100.0, 100.0)


func slow_ratio_for(stats: UnitStats) -> float:
	if stats.slow_ratio <= 0.0:
		return 0.0
	var extra: float = added_strength(RunUpgrade.Kind.FROST_POWER)
	return minf(stats.slow_ratio + extra, pool.frost_max_ratio)


func tower_health_for(base_health: int) -> int:
	return maxi(floori(base_health * _meta_multiplier(MetaUpgradeConfig.Kind.TOWER_HEALTH) * multiplier(RunUpgrade.Kind.TOWER_ARMOR) + ROUNDING_EPSILON), 1)


func starting_mana_for(base_mana: int) -> int:
	return base_mana + SessionProgress.UPGRADE_CONFIG.starting_mana_bonus(_meta_levels[MetaUpgradeConfig.Kind.STARTING_MANA])


func _meta_multiplier(kind: MetaUpgradeConfig.Kind) -> float:
	return SessionProgress.UPGRADE_CONFIG.multiplier_for(kind, _meta_levels[kind])


func summon_cost_for(base_cost: int) -> int:
	var discount: float = multiplier(RunUpgrade.Kind.CHEAP_SUMMONS)
	discount *= 1.0 - SessionProgress.UPGRADE_CONFIG.summon_discount_per_level * _meta_levels[MetaUpgradeConfig.Kind.SUMMON_ECONOMY]
	return maxi(ceili(base_cost * discount - ROUNDING_EPSILON), pool.minimum_summon_cost)


func kill_mana_for(base_mana: int) -> int:
	# Сохраняем дроби между убийствами: +20% полезны и при награде всего в 3 маны.
	var total: float = base_mana * _meta_multiplier(MetaUpgradeConfig.Kind.MANA_INCOME) * multiplier(RunUpgrade.Kind.MANA_FLOW) + _mana_remainder
	var amount: int = floori(total + ROUNDING_EPSILON)
	_mana_remainder = maxf(total - amount, 0.0)
	return amount
