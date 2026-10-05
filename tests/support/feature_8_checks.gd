extends RefCounted


func run(game: Node2D) -> Dictionary:
	var waves: WaveManager = game.wave_manager
	var config: WaveConfig = waves.config
	var manager: SummonManager = game.summon_manager
	var ordinary: Array[PackedScene] = [config.goblin_scene, config.orc_scene, config.golem_scene]
	var bases: Array[int] = [30, 60, 120]
	var thresholds: Array[Dictionary] = []
	for index: int in ordinary.size():
		var enemy: ApproachingEnemy = ordinary[index].instantiate() as ApproachingEnemy
		enemy.set_meta("palette_test", true)
		game.enemies.add_child(enemy)
		var original_base: int = enemy.stats.base_health
		assert(original_base == bases[index])
		for health: int in [original_base, original_base * 2 - 1, original_base * 2, original_base * 4 - 1, original_base * 4]:
			enemy.configure(Vector2.ZERO, 100000.0, health)
			var expected: int = 3 if health >= original_base * 4 else (2 if health >= original_base * 2 else 1)
			assert(enemy.difficulty_tier == expected and enemy.visual.modulate == EnemyStats.TIER_COLORS[expected - 1])
			assert(enemy.health_bar.max_value == health and enemy.health_bar.value == health)
			enemy.take_damage(1)
			assert(enemy.difficulty_tier == expected and enemy.visual.modulate == EnemyStats.TIER_COLORS[expected - 1])
			enemy.apply_slow(0.5, 1.5)
			enemy._physics_process(0.5)
			assert(is_equal_approx(enemy.global_position.y, enemy.stats.move_speed * 0.25))
			assert(enemy.difficulty_tier == expected and enemy.slow_indicator.visible)
		thresholds.append({"type": str(enemy.stats.enemy_type), "orange": original_base * 2, "red": original_base * 4})
		assert(enemy.stats.base_health == original_base)
		enemy.free()
	assert(config.enemy_health_for(7, 30) == 60 and config.enemy_health_for(19, 30) == 120)
	assert(config.enemy_health_for(13, 60) == 120 and config.enemy_health_for(37, 60) == 240)
	assert(config.enemy_health_for(25, 120) == 240 and config.enemy_health_for(73, 120) == 480)
	assert(config.boss_health_for(5, 350) == 350 and config.boss_health_for(10, 350) == 600)
	var compositions: Array[Dictionary] = []
	for number: int in range(1, 11):
		assert(waves.wave_number == number and waves.phase == WaveManager.Phase.FIGHTING)
		waves.spawn_timer.stop()
		while waves._spawn_remaining > 0:
			waves._on_spawn_timeout()
			waves.spawn_timer.stop()
		assert(waves.active_count() == number + 3)
		var counts: Dictionary = {"goblin": 0, "orc": 0, "golem": 0, "boss": 0}
		var boss: ApproachingEnemy
		var active: Array[ApproachingEnemy] = waves._active.duplicate()
		for enemy: ApproachingEnemy in active:
			counts[str(enemy.stats.enemy_type)] += 1
			var expected_health: int = config.boss_health_for(number, enemy.stats.base_health) if enemy.stats.is_boss else config.enemy_health_for(number, enemy.stats.base_health)
			assert(enemy.max_health == expected_health and enemy.move_speed == enemy.stats.move_speed)
			assert(enemy.difficulty_tier == enemy.stats.difficulty_tier(expected_health))
			if enemy.stats.is_boss:
				boss = enemy
		assert(counts.orc > 0 if number >= 3 else counts.orc == 0)
		assert(counts.golem > 0 if number >= 6 else counts.golem == 0)
		assert(counts.boss == (1 if number % 5 == 0 else 0))
		assert(game.hud.wave_label.text.begins_with("BOSS WAVE") == (boss != null))
		if boss != null:
			assert(active.back() == boss and boss.difficulty_tier == 0 and boss.visual.modulate == Color.WHITE)
			boss.apply_slow(0.5, 1.5)
			assert(is_equal_approx(boss.current_move_speed(), 35.0) and boss.slow_indicator.visible)
		for enemy: ApproachingEnemy in active:
			if enemy == boss:
				continue
			var before: int = manager.mana
			enemy.take_damage(enemy.max_health)
			enemy.take_damage(enemy.max_health)
			waves._on_enemy_resolved(enemy, ApproachingEnemy.Outcome.KILLED)
			assert(manager.mana == before + enemy.stats.kill_mana)
		if boss != null:
			assert(waves.phase == WaveManager.Phase.FIGHTING and waves.active_count() == 1)
			waves._try_finish_wave()
			assert(waves.phase == WaveManager.Phase.FIGHTING)
			var before: int = manager.mana
			if number == 5:
				boss.take_damage(boss.max_health)
				boss.take_damage(boss.max_health)
				waves._on_enemy_resolved(boss, ApproachingEnemy.Outcome.KILLED)
				assert(manager.mana == before + 30 and game.tower.current_health == 100)
			else:
				boss._resolve_at_tower()
				boss._resolve_at_tower()
				waves._on_enemy_resolved(boss, ApproachingEnemy.Outcome.KILLED)
				assert(manager.mana == before and game.tower.current_health == 50)
		assert(waves.phase == WaveManager.Phase.INTERMISSION and waves.active_count() == 0)
		compositions.append(counts)
		waves.intermission_timer.stop()
		waves._on_intermission_timeout()
		waves._on_intermission_timeout()
	assert(waves.wave_number == 11 and waves.active_count() == 1)
	game.tower.take_damage(50)
	assert(game.state == 1 and waves.phase == WaveManager.Phase.STOPPED and waves.active_count() == 0)
	assert(waves.spawn_timer.is_stopped() and waves.intermission_timer.is_stopped())
	return {"passed": true, "thresholds": thresholds, "compositions": compositions,
		"boss_kill_reward_once": true, "boss_escape_damage_once": true,
		"boss_blocks_wave_completion": true, "slow_preserves_tier": true,
		"resources_unchanged": true, "next_wave_after_boss": true}
