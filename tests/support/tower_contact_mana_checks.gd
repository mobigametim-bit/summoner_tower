extends RefCounted


func run(game: Node2D) -> Dictionary:
	# Tests switch to an in-memory save before changing progression or entering defeat.
	game.get_node("/root/SessionProgress").use_test_save()
	game.run_bonuses.reset()
	game.wave_manager.stop()
	game.wave_manager.phase = WaveManager.Phase.FIGHTING
	game.wave_manager._spawn_remaining = 1
	game.tower.initialize(10000)
	game.run_statistics.reset()
	var cases: Array[Dictionary] = []
	for entry: Array in [["enemy", 1], ["orc", 3], ["golem", 2], ["boss", 5]]:
		var enemy: ApproachingEnemy = _spawn(game, entry[0], entry[1])
		var before: int = game.summon_manager.mana
		var health: int = game.tower.current_health
		var expected: int = enemy.stats.kill_mana * (1 << (int(entry[1]) - 1))
		enemy._resolve_at_tower()
		assert(game.summon_manager.mana == before + expected)
		assert(game.tower.current_health == health - enemy.tower_damage)
		# A repeated contact, lethal projectile, or old wave callback cannot pay twice.
		enemy._resolve_at_tower()
		enemy.take_damage(100000)
		game.wave_manager._on_enemy_resolved(enemy, ApproachingEnemy.Outcome.KILLED)
		assert(game.summon_manager.mana == before + expected)
		assert(game.tower.current_health == health - enemy.tower_damage)
		assert(game.run_statistics.killed_enemies == 0 and game.run_statistics.killed_bosses == 0)
		cases.append({"type": entry[0], "level": entry[1], "mana": expected})
	var killed: ApproachingEnemy = _spawn(game, "enemy", 2)
	var before_kill: int = game.summon_manager.mana
	var before_health: int = game.tower.current_health
	killed.take_damage(killed.current_health)
	assert(game.summon_manager.mana == before_kill + 6)
	assert(game.tower.current_health == before_health and game.run_statistics.killed_enemies == 1)
	game.run_bonuses.apply((load("res://resources/balance/mana_flow.tres") as RunUpgrade).variant_for(4))
	var before_bonus: int = game.summon_manager.mana
	for index: int in 4:
		_spawn(game, "enemy", 1)._resolve_at_tower()
	assert(game.summon_manager.mana == before_bonus + 14)
	# Verify fixed dimensions on regenerated maps with all three portal counts.
	var dimensions: Array[String] = []
	game.battlefield_seed = 72
	for portal_count: int in range(1, 4):
		game.battlefield_portal_count = portal_count
		game._renew_battlefield()
		var layout: BattlefieldLayout = game.battlefield.layout
		assert(layout.grid_size == Vector2i(6, 9) and is_equal_approx(layout.cell_size, 120.0))
		assert(layout.paths.size() == portal_count and layout.slots.size() >= 10 and layout.slots.size() <= 15)
		assert(BattlefieldGenerator.new(game.battlefield.config).is_valid(layout))
		dimensions.append(str(layout.grid_size))
	# Reward must arrive before a lethal hit can suspend/stop the economy.
	game.run_bonuses.reset()
	game.tower.initialize(10)
	var lethal: ApproachingEnemy = _spawn(game, "enemy", 1)
	var before_lethal: int = game.summon_manager.mana
	lethal._resolve_at_tower()
	assert(game.summon_manager.mana == before_lethal + 3)
	assert(game.state == game.State.REVIVE_OFFER and game.tower.current_health == 0)
	lethal._resolve_at_tower()
	assert(game.summon_manager.mana == before_lethal + 3)
	return {"passed": true, "contacts": cases, "kill_reward_unchanged": true,
		"bonus_with_fractional_carry": 14, "map_sizes": dimensions,
		"lethal_contact_paid_once": true, "duplicates_ignored": true}


func _spawn(game: Node2D, type: String, level: int) -> ApproachingEnemy:
	var enemy: ApproachingEnemy = (load("res://scenes/%s.tscn" % type) as PackedScene).instantiate() as ApproachingEnemy
	game.wave_manager._active.append(enemy)
	enemy.resolved.connect(game.wave_manager._on_enemy_resolved)
	game.enemies.add_child(enemy)
	enemy.configure(game.tower.global_position, game.tower.global_position.y,
		enemy.stats.base_health * (1 << (level - 1)), level)
	enemy.set_physics_process(false)
	return enemy
