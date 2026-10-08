class_name WavePowerPlanner
extends RefCounted

var config: WaveConfig


func _init(wave_config: WaveConfig) -> void:
	config = wave_config


func make_plan(wave: int, player_power: float, rng: RandomNumberGenerator) -> Dictionary:
	var balance: PowerBalanceConfig = config.power_balance
	var sequence: Array[PackedScene] = []
	var healths: Array[int] = []
	var counts: Dictionary = {}
	var actual_power: float = 0.0
	var boss_power: float = 0.0
	if config.is_boss_wave(wave):
		var boss: EnemyStats = balance.enemy_stats[3]
		var health: int = config.boss_health_for(wave, boss.base_health)
		sequence.append(config.boss_scene)
		healths.append(health)
		boss_power = balance.enemy_power(boss, health)
		actual_power = boss_power
		counts["boss"] = 1
	var requested: float = balance.budget_for(wave, player_power)
	# Первая волна — фиксированное обучение; босс всегда дополнительный к обычным врагам.
	if wave == 1:
		for index: int in config.first_enemy_count:
			sequence.append(config.goblin_scene)
			healths.append(balance.enemy_stats[0].base_health)
		actual_power = float(config.first_enemy_count)
		counts["goblin_lv1"] = config.first_enemy_count
		return _result(sequence, healths, player_power, actual_power, actual_power, counts, wave, false)
	var candidates: Array[Dictionary] = _candidates(wave)
	var biggest: float = 0.0
	for candidate: Dictionary in candidates:
		biggest = maxf(biggest, candidate.power)
	var minimum: float = float(config.first_enemy_count) + boss_power
	var desired: float = maxf(requested, minimum)
	# Предел защищает Web от тысяч экземпляров; невместившийся бюджет виден в отчёте.
	var target: float = minf(desired, boss_power + biggest * balance.maximum_regular_enemies)
	var remaining: float = target - boss_power
	var scenes: Array[PackedScene] = [config.goblin_scene, config.orc_scene, config.golem_scene]
	var regular: int = 0
	while remaining >= 1.0 - 0.000001 and regular < balance.maximum_regular_enemies:
		var available: Array[Dictionary] = []
		var minimum_per_slot: float = remaining / (balance.maximum_regular_enemies - regular)
		for candidate: Dictionary in candidates:
			if candidate.power <= remaining + 0.000001 and candidate.power >= minimum_per_slot - 0.000001:
				available.append(candidate)
		if available.is_empty():
			# Дешёвый остаток добирается Lv1: бюджет не теряется из-за дискретных уровней.
			for candidate: Dictionary in candidates:
				if candidate.power <= remaining + 0.000001:
					available.append(candidate)
		if available.is_empty():
			break
		var selected: Dictionary = _roll(available, rng)
		sequence.append(scenes[selected.type_index])
		healths.append(selected.health)
		var key: String = "%s_lv%d" % [balance.enemy_stats[selected.type_index].enemy_type, selected.tier]
		counts[key] = int(counts.get(key, 0)) + 1
		actual_power += selected.power
		remaining = maxf(target - actual_power, 0.0)
		regular += 1
	return _result(sequence, healths, player_power, target, actual_power, counts, wave, desired > target)


func _candidates(wave: int) -> Array[Dictionary]:
	var balance: PowerBalanceConfig = config.power_balance
	var weights: Array[float] = [1.0 - config.orc_share - config.golem_share, config.orc_share, config.golem_share]
	var result: Array[Dictionary] = []
	var highest: int = balance.maximum_tier_for(wave)
	for index: int in 3:
		if (index == 1 and wave < config.orc_first_wave) or (index == 2 and wave < config.golem_first_wave):
			continue
		var stats: EnemyStats = balance.enemy_stats[index]
		for tier: int in range(1, highest + 1):
			var health: int = stats.base_health * (1 << (tier - 1))
			# Старшие цвета постепенно преобладают, но лёгкие враги остаются в смеси.
			var weight: float = weights[index] * pow(2.0, tier - 1)
			result.append({"type_index": index, "tier": tier, "health": health,
				"power": balance.enemy_power(stats, health), "weight": weight})
	return result


func _roll(candidates: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	var total: float = 0.0
	for candidate: Dictionary in candidates:
		total += candidate.weight
	var pick: float = rng.randf() * total
	for candidate: Dictionary in candidates:
		pick -= candidate.weight
		if pick <= 0.0:
			return candidate
	return candidates.back()


func _result(sequence: Array[PackedScene], healths: Array[int], player: float, target: float, actual: float, counts: Dictionary, wave: int, capped: bool) -> Dictionary:
	return {"sequence": sequence, "healths": healths,
		"summary": {"wave": wave, "player_power": player, "target_power": target,
			"wave_power": actual, "unspent_power": maxf(target - actual, 0.0),
			"coefficient": config.power_balance.coefficient_for(wave), "counts": counts,
			"count": sequence.size(), "capped": capped}}
