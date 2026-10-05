extends RefCounted


func run(game: Node2D) -> Dictionary:
	var waves: WaveManager = game.wave_manager
	var manager: SummonManager = game.summon_manager
	var initial: ApproachingEnemy = game.enemies.get_child(0)
	assert(waves.wave_number == 1 and waves.phase == WaveManager.Phase.FIGHTING)
	assert(waves.active_count() == 1 and waves._spawn_remaining == 3)
	assert(waves.config.enemy_count_for(1) == 4 and waves.config.enemy_count_for(10) == 13)
	assert(waves.config.enemy_health_for(1, 30) == 30 and waves.config.enemy_health_for(10, 30) == 75)
	assert(not waves.start())
	waves._on_spawn_timeout()
	assert(waves.active_count() == 1 and waves._spawn_remaining == 3)
	var completions: Array[int] = []
	waves.wave_completed.connect(func(number: int) -> void: completions.append(number))
	var reentry: Array[int] = []
	manager.state_changed.connect(func(_mana: int, _cost: int, _occupied: int, _capacity: int, _available: bool) -> void:
		waves._on_enemy_resolved(initial, ApproachingEnemy.Outcome.KILLED)
		reentry.append(manager.mana), CONNECT_ONE_SHOT)
	initial.take_damage(30)
	assert(manager.mana == 103 and reentry == [103])
	initial.take_damage(30)
	initial._resolve_at_tower()
	waves._on_enemy_resolved(initial, ApproachingEnemy.Outcome.KILLED)
	assert(manager.mana == 103 and game.tower.current_health == 100)
	assert(waves.phase == WaveManager.Phase.FIGHTING and completions.is_empty())
	for index: int in 3:
		waves.spawn_timer.stop()
		waves._on_spawn_timeout()
		assert(waves.active_count() == index + 1 and waves._spawn_remaining == 2 - index)
		if index < 2:
			waves._on_spawn_timeout()
			assert(waves.active_count() == index + 1)
	assert(waves.active_count() == 3 and waves._spawn_remaining == 0)
	var escaped: ApproachingEnemy = waves._active[0]
	escaped._resolve_at_tower()
	escaped._resolve_at_tower()
	waves._on_enemy_resolved(escaped, ApproachingEnemy.Outcome.KILLED)
	assert(game.tower.current_health == 80 and manager.mana == 103)
	var surviving: Array[ApproachingEnemy] = waves._active.duplicate()
	for enemy: ApproachingEnemy in surviving:
		enemy.take_damage(30)
	assert(manager.mana == 109 and completions == [1])
	assert(waves.phase == WaveManager.Phase.INTERMISSION and waves.active_count() == 0)
	assert(is_equal_approx(waves.intermission_timer.time_left, 3.0))
	waves._try_finish_wave()
	waves._on_intermission_timeout()
	assert(completions == [1] and waves.wave_number == 1)
	assert(manager.try_summon() and manager.try_summon())
	var slots: Array[Node] = game.get_node("World/Slots").get_children()
	assert(manager.try_transfer(slots[1], slots[0], slots[1].unit))
	assert(slots[0].unit.stats.level == 2 and slots[1].is_empty() and manager.mana == 64)
	# Истёкший intermission переходит ровно один раз и применяет рост HP экземпляру.
	waves.intermission_timer.stop()
	waves._on_intermission_timeout()
	waves._on_intermission_timeout()
	assert(waves.wave_number == 2 and waves.active_count() == 1 and waves._spawn_remaining == 4)
	assert(waves._active[0].max_health == 35 and waves.enemy_config.enemy_max_health == 30)
	game.tower.take_damage(100)
	assert(game.state == 1 and waves.phase == WaveManager.Phase.STOPPED)
	assert(waves.spawn_timer.is_stopped() and waves.intermission_timer.is_stopped())
	var stopped_mana: int = manager.mana
	waves._on_spawn_timeout()
	waves._on_intermission_timeout()
	waves._on_enemy_resolved(escaped, ApproachingEnemy.Outcome.KILLED)
	manager.add_mana(3)
	assert(manager.mana == stopped_mana and waves.active_count() == 0 and waves.wave_number == 2)
	assert(not waves.start() and not manager.try_summon())
	assert(waves.config.kill_mana == 3 and waves.config.spawn_interval == 1.0)
	return {"passed": true, "kills": 3, "escapes": 1, "reward": 9,
		"reentry": reentry, "completed": completions, "intermission_summon_merge": true,
		"duplicate_timeouts": true, "stopped_callbacks": true}
