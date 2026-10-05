extends RefCounted


func run(game: Node2D) -> Dictionary:
	var manager: SummonManager = game.summon_manager
	var pool: SummonPool = manager.pool
	assert(pool.is_valid() and pool.weights == [40, 35, 25])
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var repeat_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026
	repeat_rng.seed = 2026
	var counts: Array[int] = [0, 0, 0]
	for index: int in 10000:
		var chosen: PackedScene = pool.roll(rng)
		assert(chosen == pool.roll(repeat_rng))
		counts[pool.scenes.find(chosen)] += 1
	assert(absi(counts[0] - 4000) < 200 and absi(counts[1] - 3500) < 200 and absi(counts[2] - 2500) < 200)
	var random_state: int = manager._rng.state
	manager.mana = 0
	assert(not manager.try_summon() and manager._rng.state == random_state and manager.successful_summons == 0)
	var invalid_pool: SummonPool = SummonPool.new()
	manager.pool = invalid_pool
	manager.mana = 10000
	assert(not manager.try_summon() and manager._rng.state == random_state)
	var empty_node: Node2D = Node2D.new()
	var invalid_scene: PackedScene = PackedScene.new()
	assert(invalid_scene.pack(empty_node) == OK)
	empty_node.free()
	invalid_pool.scenes = [invalid_scene]
	invalid_pool.weights = [1]
	assert(not manager.try_summon() and manager._rng.state == random_state and manager.mana == 10000)
	manager.pool = pool
	game.wave_manager.spawn_timer.stop()
	var enemy: ApproachingEnemy = game.enemies.get_child(0)
	enemy.set_physics_process(false)
	enemy.max_health = 10000
	enemy.current_health = 10000
	enemy._target_y = 100000.0
	enemy.global_position = Vector2.ZERO
	enemy.apply_slow(0.3, 1.5)
	enemy._physics_process(0.5)
	assert(is_equal_approx(enemy.global_position.y, 56.0) and is_equal_approx(enemy._slow_remaining, 1.0))
	enemy.apply_slow(0.2, 10.0)
	assert(is_equal_approx(enemy._slow_ratio, 0.3) and is_equal_approx(enemy._slow_remaining, 1.0))
	enemy.apply_slow(0.5, 1.5)
	assert(is_equal_approx(enemy.current_move_speed(), 80.0))
	enemy._physics_process(0.5)
	enemy.apply_slow(0.5, 1.5)
	assert(is_equal_approx(enemy._slow_remaining, 1.5))
	var previous_y: float = enemy.global_position.y
	enemy._physics_process(2.0)
	assert(is_equal_approx(enemy.global_position.y - previous_y, 200.0))
	assert(enemy.current_move_speed() == 160.0 and not enemy.slow_indicator.visible)
	# Завершение забега во время спавна происходит до _ready нового врага.
	var interrupted: Node2D = load("res://scenes/game.tscn").instantiate() as Node2D
	game.get_parent().add_child(interrupted)
	interrupted.wave_manager.spawn_timer.stop()
	interrupted.enemies.child_entered_tree.connect(func(_child: Node) -> void: interrupted.tower.take_damage(100), CONNECT_ONE_SHOT)
	interrupted.wave_manager._on_spawn_timeout()
	assert(interrupted.state == 1 and interrupted.wave_manager.active_count() == 0)
	assert(interrupted.wave_manager.spawn_timer.is_stopped() and interrupted.summon_manager.mana == 100)
	interrupted.free()
	var slots: Array[Node] = game.get_node("World/Slots").get_children()
	var checked_types: Array[String] = []
	for scene_index: int in pool.scenes.size():
		var single: SummonPool = SummonPool.new()
		single.scenes = [pool.scenes[scene_index]]
		single.weights = [1]
		manager.pool = single
		var before_mana: int = manager.mana
		var before_count: int = manager.successful_summons
		for index: int in 4:
			assert(manager.try_summon())
			slots[index].unit.set_physics_process(false)
		var first: CombatUnit = slots[0].unit
		var base: UnitStats = first.stats
		assert(first.get_node("NameLabel").text == base.display_name)
		var survivor: CombatUnit = slots[1].unit
		var bolt: CombatProjectile = first.projectile_scene.instantiate() as CombatProjectile
		game.projectiles.add_child(bolt)
		bolt.launch(enemy.global_position, enemy, base, first)
		assert(manager.try_transfer(slots[0], slots[1], first))
		assert(slots[0].is_empty() and survivor.stats == base.next_level and bolt._attacker == survivor)
		assert(bolt._damage == base.damage and is_equal_approx(bolt._slow_ratio, base.slow_ratio))
		enemy._clear_slow()
		var previous_health: int = enemy.current_health
		bolt._physics_process(0.001)
		bolt._hit_target()
		assert(previous_health - enemy.current_health == base.damage)
		assert(is_equal_approx(enemy._slow_ratio, base.slow_ratio))
		assert(manager.try_transfer(slots[2], slots[3], slots[2].unit))
		assert(manager.try_transfer(slots[1], slots[3], survivor))
		assert(slots[3].unit.stats == base.next_level.next_level and slots[3].unit.stats.level == 3)
		assert(slots[3].unit.get_node("Visual").texture == slots[3].unit.stats.visual_texture)
		assert(base.level == 1 and base.next_level.level == 2)
		var spent: int = 0
		for index: int in range(before_count, before_count + 4):
			spent += manager.config.cost_after(index)
		assert(manager.mana == before_mana - spent and manager.successful_summons == before_count + 4)
		checked_types.append(str(base.unit_type))
		_clear_field(slots, game.projectiles)
	# Разные типы одинакового уровня меняются местами, не объединяются.
	manager.pool = pool
	for index: int in 2:
		var creature: CombatUnit = pool.scenes[index].instantiate() as CombatUnit
		assert(slots[index].place_unit(creature))
		creature.configure(game.enemies, game.projectiles)
		creature.set_physics_process(false)
	var left: CombatUnit = slots[0].unit
	var right: CombatUnit = slots[1].unit
	var unchanged_mana: int = manager.mana
	assert(not left.can_merge_with(right) and manager.try_transfer(slots[0], slots[1], left))
	assert(slots[0].unit == right and slots[1].unit == left and manager.mana == unchanged_mana)
	var touch_checks: RefCounted = load("res://tests/support/feature_4_checks.gd").new()
	touch_checks._touch(game.get_viewport(), 7, Vector2(180, 360), true)
	touch_checks._motion_touch(game.get_viewport(), 7, Vector2(180, 840))
	assert(game.drag_controller.preview.visible and game.drag_controller.preview_visual.texture == right.stats.visual_texture)
	touch_checks._touch(game.get_viewport(), 7, Vector2(180, 840), false, true)
	assert(slots[0].unit == right and slots[4].is_empty() and not game.drag_controller.preview.visible)
	# Завершение забега из add_child откатывает призыв без расхода и повторного RNG.
	random_state = manager._rng.state
	var summons: int = manager.successful_summons
	slots[2].unit_host.child_entered_tree.connect(func(_child: Node) -> void: game.tower.take_damage(100), CONNECT_ONE_SHOT)
	enemy.apply_slow(0.5, 1.5)
	assert(not manager.try_summon())
	assert(game.state == 1 and manager.mana == unchanged_mana and manager.successful_summons == summons)
	assert(manager._rng.state == random_state and slots[2].is_empty())
	assert(enemy._slow_ratio == 0.0 and not enemy.slow_indicator.visible)
	return {"passed": true, "types": checked_types, "rolls": counts, "slow_expiry": true,
		"strongest_only": true, "in_flight_snapshot": true, "mixed_swap": true,
		"touch_cancel": true, "failed_summon_rng": true, "stopped_during_summon": true,
		"stopped_during_spawn": true}


func _clear_field(slots: Array[Node], projectiles: Node2D) -> void:
	for child: Node in projectiles.get_children():
		child.free()
	for slot: SummonSlot in slots:
		if slot.is_empty():
			continue
		var creature: CombatUnit = slot.unit
		slot.assign_unit(null)
		creature.stop()
		slot.unit_host.remove_child(creature)
		creature.free()
