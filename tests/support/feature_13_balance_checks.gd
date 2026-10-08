extends RefCounted


func run() -> Dictionary:
	var config: WaveConfig = load("res://resources/balance/wave_config.tres")
	var balance: PowerBalanceConfig = config.power_balance
	var failures: Array[String] = []
	var cases: int = 0
	if not is_equal_approx(balance.unit_power(balance.reference_unit, balance.reference_unit.damage, balance.reference_unit.attack_interval), 1.0):
		failures.append("Archer Lv1 must have Power 1")
	if not is_equal_approx(balance.enemy_power(balance.enemy_stats[0], 30), 1.0):
		failures.append("Goblin Lv1 must have Power 1")
	if not is_equal_approx(balance.enemy_power(balance.enemy_stats[1], 60), 3.0):
		failures.append("Orc Lv1 must have Power 3")
	if not is_equal_approx(balance.enemy_power(balance.enemy_stats[2], 120), 6.0):
		failures.append("Golem Lv1 must have Power 6")
	if not is_equal_approx(balance.player_power(4.0, 150), 6.0):
		failures.append("Tower maximum HP multiplier")
	var planner: WavePowerPlanner = WavePowerPlanner.new(config)
	for army: float in [0.0, 3.46, 10.0, 30.0, 200.0]:
		for wave: int in range(1, 41):
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = 1300 + wave
			var plan: Dictionary = planner.make_plan(wave, army, rng)
			var summary: Dictionary = plan.summary
			cases += 1
			if plan.sequence.size() != plan.healths.size() or summary.unspent_power >= 1.000001:
				failures.append("Unfilled budget: wave %d army %s remainder %s" % [wave, army, summary.unspent_power])
			if plan.sequence.size() > balance.maximum_regular_enemies + int(config.is_boss_wave(wave)):
				failures.append("Web population cap")
			if wave == 1 and (summary.count != 5 or summary.counts != {"goblin_lv1": 5}):
				failures.append("First wave contract")
			if config.is_boss_wave(wave) and (plan.sequence[0] != config.boss_scene or summary.count < 2):
				failures.append("Boss must be additional and spawn first")
			for index: int in plan.sequence.size():
				var type_index: int = [config.goblin_scene, config.orc_scene, config.golem_scene, config.boss_scene].find(plan.sequence[index])
				if type_index == 3:
					continue
				var ratio: int = plan.healths[index] / balance.enemy_stats[type_index].base_health
				if ratio not in [1, 2, 4, 8, 16] or ratio > (1 << (balance.maximum_tier_for(wave) - 1)):
					failures.append("Discrete HP tiers")
			var repeat_rng: RandomNumberGenerator = RandomNumberGenerator.new()
			repeat_rng.seed = 1300 + wave
			var repeated: Dictionary = planner.make_plan(wave, army, repeat_rng)
			if plan.healths != repeated.healths or plan.sequence != repeated.sequence:
				failures.append("Seed reproducibility")
	return {"cases": cases, "failures": failures, "ok": failures.is_empty()}
