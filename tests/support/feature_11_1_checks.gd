extends RefCounted


func run(fixture: Node) -> Dictionary:
	var settings: BattlefieldConfig = load("res://resources/balance/battlefield_config.tres")
	var generator: BattlefieldGenerator = BattlefieldGenerator.new(settings)
	assert(settings.route_length_range == Vector2(1300, 2500))
	assert(settings.turn_probability_range == Vector2(0.25, 0.75))
	assert(settings.horizontal_run_range == Vector2i(2, 5))
	assert(settings.vertical_run_range == Vector2i(1, 3))
	var layouts: int = 0
	var upward: int = 0
	var counts: Array[int] = []
	var lengths: Array[float] = []
	var fallback_count: int = 0
	var portal_counts: Array[int] = []
	var combinations: Dictionary = {}
	var maximum_ms: float = 0.0
	var altered: BattlefieldConfig = settings.duplicate() as BattlefieldConfig
	altered.generation_attempts = 0
	for columns: int in range(6, 9):
		for seed_value: int in 20:
			var started: int = Time.get_ticks_usec()
			var layout: BattlefieldLayout = generator.generate(seed_value, columns)
			maximum_ms = maxf(maximum_ms, (Time.get_ticks_usec() - started) / 1000.0)
			var repeated: BattlefieldLayout = generator.generate(seed_value, columns)
			assert(generator.is_valid(layout))
			assert(layout.cells == repeated.cells and layout.road_cells == repeated.road_cells)
			assert(layout.paths == repeated.paths and layout.portal_sides == repeated.portal_sides)
			if not portal_counts.has(layout.paths.size()):
				portal_counts.append(layout.paths.size())
			var mask: int = 0
			for side: int in layout.portal_sides:
				mask |= 1 << side
			combinations[mask] = true
			assert(layout.slot_cells == repeated.slot_cells and layout.decorations == repeated.decorations)
			assert(layout.target_length == repeated.target_length)
			assert(layout.target_length >= 1300.0 and layout.target_length <= 2500.0)
			for curve: Curve2D in layout.curves:
				lengths.append(curve.get_baked_length())
			fallback_count += int(layout.used_fallback)
			assert(layout.grid_size == settings.grid_size(columns))
			assert(layout.cells.size() == layout.grid_size.x * layout.grid_size.y)
			assert(layout.turn_probability >= settings.turn_probability_range.x and layout.turn_probability <= settings.turn_probability_range.y)
			for path: Array in layout.paths:
				_check_runs(path)
			var fallback: BattlefieldLayout = BattlefieldGenerator.new(altered).generate(seed_value, columns)
			assert(fallback.used_fallback and generator.is_valid(fallback))
			assert(fallback.portal_sides == layout.portal_sides)
			for path: Array in fallback.paths:
				_check_runs(path)
			if not counts.has(layout.slots.size()):
				counts.append(layout.slots.size())
			for index: int in range(1, layout.road_cells.size()):
				if layout.road_cells[index].y < layout.road_cells[index - 1].y:
					upward += 1
					break
			layouts += 1
	assert(upward > 0 and counts.size() == settings.slot_count_range.y - settings.slot_count_range.x + 1)
	assert(portal_counts.size() == 3)
	assert(lengths.max() > 2000.0)
	var forced_counts: int = _check_portal_counts(generator, combinations)
	assert(combinations.size() == 7)
	var random_sizes: Array[int] = []
	for seed_value: int in 20:
		var randomized: BattlefieldLayout = generator.generate(seed_value, 0)
		var repeated: BattlefieldLayout = generator.generate(seed_value, 0)
		assert(generator.is_valid(randomized) and randomized.road_cells == repeated.road_cells)
		assert(randomized.grid_size == repeated.grid_size)
		if not random_sizes.has(randomized.grid_size.x):
			random_sizes.append(randomized.grid_size.x)
	assert(random_sizes.size() == 3)
	var original: BattlefieldLayout = generator.generate(7, 6)
	altered.decoration_probability = 0.0
	altered.generation_attempts = settings.generation_attempts
	var no_decor: BattlefieldLayout = BattlefieldGenerator.new(altered).generate(7, 6)
	assert(original.road_cells == no_decor.road_cells and original.slot_cells == no_decor.slot_cells)
	assert(settings.decoration_probability == 0.55 and no_decor.decorations.is_empty())
	original.road_cells.append(original.road_cells[0])
	assert(not generator.is_valid(original))
	original.road_cells.pop_back()
	_check_movement(fixture, original)
	for count: int in [10, 12, 15]:
		_check_capacity(fixture, count)
	_check_wave_distribution(fixture)
	return {"passed": true, "layouts": layouts, "fallbacks_checked": 60, "fallbacks_used": fallback_count, "forced_portal_counts": forced_counts, "portal_counts": portal_counts, "side_combinations": combinations.size(), "maximum_generation_ms": maximum_ms, "horizontal_first": true, "length_range": [lengths.min(), lengths.max()], "random_sizes": random_sizes, "upward": upward, "deterministic": true, "movement_and_slow": true, "capacities": [10, 12, 15], "refund_once": true, "wave_distribution": true, "boss_additional_same_frame": true}


func _check_portal_counts(generator: BattlefieldGenerator, combinations: Dictionary) -> int:
	var checked: int = 0
	for columns: int in range(6, 9):
		for count: int in range(1, 4):
			for seed_value: int in 5:
				var layout: BattlefieldLayout = generator.generate(seed_value, columns, 10, count)
				assert(generator.is_valid(layout) and layout.paths.size() == count and layout.slots.size() == 10)
				var mask: int = 0
				for side: int in layout.portal_sides:
					mask |= 1 << side
				combinations[mask] = true
				for path: Array in layout.paths:
					_check_runs(path)
				checked += 1
	return checked


func _check_runs(path: Array) -> void:
	assert(path[0].y == path[1].y)
	var previous: Vector2i = path[1] - path[0]
	var length: int = 0
	for index: int in range(1, path.size()):
		var direction: Vector2i = path[index] - path[index - 1]
		if direction != previous:
			assert(length >= (2 if previous.x != 0 else 1) and length <= (5 if previous.x != 0 else 3))
			previous = direction
			length = 0
		length += 1
	assert(length >= (2 if previous.x != 0 else 1) and length <= (5 if previous.x != 0 else 3))


func _check_movement(fixture: Node, layout: BattlefieldLayout) -> void:
	for curve: Curve2D in layout.curves:
		_check_route_movement(fixture, layout, curve)


func _check_route_movement(fixture: Node, layout: BattlefieldLayout, curve: Curve2D) -> void:
	var enemy: ApproachingEnemy = load("res://scenes/enemy.tscn").instantiate()
	fixture.add_child(enemy)
	enemy.configure(curve.get_point_position(0), 920, 1000)
	enemy.follow_route(curve, Transform2D.IDENTITY, layout.cell_size)
	enemy.set_physics_process(false)
	var resolutions: Array[int] = []
	enemy.resolved.connect(func(_enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void: resolutions.append(outcome))
	enemy.apply_slow(0.7, 1.5)
	enemy._physics_process(0.5)
	assert(is_equal_approx(enemy._distance, 24.0))
	assert(enemy.global_position.is_equal_approx(curve.sample_baked(24.0)))
	enemy._physics_process(1.5)
	assert(is_equal_approx(enemy._distance, 152.0) and not enemy.slow_indicator.visible)
	enemy._physics_process(1000.0)
	enemy._physics_process(1000.0)
	assert(resolutions == [ApproachingEnemy.Outcome.REACHED_TOWER])
	assert(enemy.global_position.is_equal_approx(curve.get_point_position(curve.point_count - 1)))


func _check_capacity(fixture: Node, count: int) -> void:
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	game.battlefield_slot_count = count
	game.battlefield_columns = 6 + floori((count - 10) / 2.0)
	game.battlefield_seed = 7
	game.battlefield_portal_count = 3
	fixture.add_child(game)
	game.wave_manager.stop()
	var manager: SummonManager = game.summon_manager
	manager.pool = load("res://tests/resources/archer_only_pool.tres")
	manager.mana = 1000
	var slots: Array[Node] = game.get_node("World/Slots").get_children()
	assert(slots.size() == count and manager._slots.size() == count and game.drag_controller._slots.size() == count)
	assert(game.battlefield.cells.get_child_count() == game.battlefield.layout.cells.size())
	assert(game.battlefield.portal.global_position == game.spawn_point.global_position)
	assert(game.battlefield.routes.size() == 3 and game.battlefield.branches.get_child_count() == 2 and game.battlefield.portals.get_child_count() == 2)
	assert(game.battlefield.road_surface.texture.resource_path == "res://assets/environment/paved_road.svg")
	for cell: Node in game.battlefield.cells.get_children():
		assert(cell.get_node("Fill").texture.resource_path == "res://assets/environment/ground_cell.svg")
	assert(game.spawn_point.global_position.is_equal_approx(game.battlefield.layout.curve.get_point_position(0)))
	assert(game.tower.global_position.is_equal_approx(game.battlefield.layout.curve.get_point_position(game.battlefield.layout.curve.point_count - 1)))
	assert(game.tower.summon_button.get_global_rect().size == Vector2.ONE * (game.battlefield.layout.cell_size - game.battlefield.config.cell_gap))
	for index: int in count:
		var summoned: bool = manager.try_summon()
		assert(summoned)
		slots[index].unit.attack_enabled = false
		assert(slots[index].slot_index == index + 1)
		assert(game.drag_controller._slot_at(slots[index].global_position) == slots[index])
		assert(slots[index].unit.global_scale.x <= 1.0)
	var mana: int = manager.mana
	var cost: int = manager.current_cost()
	var rejected: bool = manager.try_summon()
	assert(not rejected and manager.mana == mana and manager.current_cost() == cost)
	var source: CombatUnit = slots[0].unit
	var target: CombatUnit = slots[1].unit
	var merged: bool = manager.try_transfer(slots[0], slots[1], source)
	assert(merged and target.stats.level == 2 and target.paid_mana == 45 and slots[0].is_empty())
	assert(manager.mana == mana and manager.current_cost() == cost and manager.occupied_count() == count - 1)
	var refunded: bool = manager.try_refund(slots[1], target)
	var repeated: bool = manager.try_refund(slots[1], target)
	assert(refunded and not repeated and manager.mana == mana + 22 and manager.occupied_count() == count - 2)
	game.free()


func _check_wave_distribution(fixture: Node) -> void:
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	game.battlefield_seed = 7
	game.battlefield_portal_count = 3
	fixture.add_child(game)
	var waves: WaveManager = game.wave_manager
	for number: int in [1, 5]:
		waves.stop()
		waves.wave_number = number
		waves.phase = WaveManager.Phase.FIGHTING
		waves._begin_wave()
		if number == 5:
			assert(waves._active.size() == 2 and waves._active[0].stats.is_boss and not waves._active[1].stats.is_boss)
			assert(waves._active[0].get_meta("spawn_frame") == waves._active[1].get_meta("spawn_frame"))
		while waves._spawn_remaining > 0:
			waves._spawn_next()
		waves.spawn_timer.stop()
		assert(waves.active_count() == waves.config.total_enemy_count_for(number))
		var distribution: Array[int] = [0, 0, 0]
		for enemy: ApproachingEnemy in waves._active:
			var index: int = int(enemy.get_meta("portal_index"))
			distribution[index] += 1
			assert(enemy._route == game.battlefield.routes[index].curve)
			assert(enemy.global_position.is_equal_approx(game.battlefield.routes[index].curve.sample_baked(0.0)))
		assert(distribution.max() - distribution.min() <= 1)
		var active: Array[ApproachingEnemy] = waves._active.duplicate()
		for enemy: ApproachingEnemy in active:
			enemy.take_damage(enemy.current_health)
		assert(waves.phase == (WaveManager.Phase.UPGRADE_CHOICE if number == 5 else WaveManager.Phase.INTERMISSION))
		assert(waves.active_count() == 0)
	game.free()
