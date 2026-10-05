class_name RunBonuses
extends Node

const ROUNDING_EPSILON: float = 0.000001

@export var pool: RunUpgradePool

var _counts: Dictionary = {}
var _mana_remainder: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _meta_levels: Array[int] = [0, 0, 0, 0]


func reset() -> void:
	_counts.clear()
	# Снимок исключает повторное применение и изменение бонусов посреди забега.
	_meta_levels = SessionProgress.upgrade_levels.duplicate()
	_mana_remainder = 0.0
	_rng.randomize()


func set_random_seed(value: int) -> void:
	_rng.seed = value


func count(kind: RunUpgrade.Kind) -> int:
	return int(_counts.get(kind, 0))


func apply(upgrade: RunUpgrade) -> void:
	_counts[upgrade.kind] = count(upgrade.kind) + 1


func multiplier(kind: RunUpgrade.Kind) -> float:
	return pow(1.0 + pool.get_upgrade(kind).strength, count(kind))


func roll_choices() -> Array[RunUpgrade]:
	var candidates: Array[RunUpgrade] = []
	for upgrade: RunUpgrade in pool.upgrades:
		if upgrade.kind == RunUpgrade.Kind.FROST_POWER:
			if slow_ratio_for(pool.frost_base_stats) >= pool.frost_max_ratio - ROUNDING_EPSILON:
				continue
		candidates.append(upgrade)
	var result: Array[RunUpgrade] = []
	while result.size() < 3 and not candidates.is_empty():
		var index: int = _rng.randi_range(0, candidates.size() - 1)
		result.append(candidates[index])
		candidates.remove_at(index)
	return result


func attack_interval_for(stats: UnitStats) -> float:
	return stats.attack_interval / multiplier(RunUpgrade.Kind.RAPID_FIRE)


func damage_for(stats: UnitStats) -> int:
	return maxi(floori(damage_amount_for(stats) + ROUNDING_EPSILON), 1)


func damage_amount_for(stats: UnitStats) -> float:
	return stats.damage * _meta_multiplier(MetaUpgradeConfig.Kind.UNIT_DAMAGE) * multiplier(RunUpgrade.Kind.POWER)


func slow_ratio_for(stats: UnitStats) -> float:
	if stats.slow_ratio <= 0.0:
		return 0.0
	var extra: float = pool.get_upgrade(RunUpgrade.Kind.FROST_POWER).strength * count(RunUpgrade.Kind.FROST_POWER)
	return minf(stats.slow_ratio + extra, pool.frost_max_ratio)


func tower_health_for(base_health: int) -> int:
	return maxi(floori(base_health * _meta_multiplier(MetaUpgradeConfig.Kind.TOWER_HEALTH) * multiplier(RunUpgrade.Kind.TOWER_ARMOR) + ROUNDING_EPSILON), 1)


func starting_mana_for(base_mana: int) -> int:
	return base_mana + SessionProgress.UPGRADE_CONFIG.starting_mana_bonus(_meta_levels[MetaUpgradeConfig.Kind.STARTING_MANA])


func _meta_multiplier(kind: MetaUpgradeConfig.Kind) -> float:
	return SessionProgress.UPGRADE_CONFIG.multiplier_for(kind, _meta_levels[kind])


func summon_cost_for(base_cost: int) -> int:
	var discount: float = pow(1.0 - pool.get_upgrade(RunUpgrade.Kind.CHEAP_SUMMONS).strength, count(RunUpgrade.Kind.CHEAP_SUMMONS))
	return maxi(ceili(base_cost * discount - ROUNDING_EPSILON), pool.minimum_summon_cost)


func kill_mana_for(base_mana: int) -> int:
	# Сохраняем дроби между убийствами: +20% полезны и при награде всего в 3 маны.
	var total: float = base_mana * _meta_multiplier(MetaUpgradeConfig.Kind.MANA_INCOME) * multiplier(RunUpgrade.Kind.MANA_FLOW) + _mana_remainder
	var amount: int = floori(total + ROUNDING_EPSILON)
	_mana_remainder = maxf(total - amount, 0.0)
	return amount
