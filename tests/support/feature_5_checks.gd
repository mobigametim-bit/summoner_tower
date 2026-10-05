extends RefCounted


func run(scene: Node) -> Dictionary:
	var manager: SummonManager = scene.get_node("SummonManager")
	var slots: Array[Node] = scene.get_node("World/Slots").get_children()
	var drag: UnitDragController = scene.get_node("World/DragController")
	var enemy: ApproachingEnemy = scene.get_node("World/Enemies").get_child(0)
	var projectiles: Node2D = scene.get_node("World/Projectiles")
	var base: UnitStats = load("res://resources/balance/archer_lv1.tres")
	var second_level: UnitStats = base.next_level
	var third_level: UnitStats = second_level.next_level
	assert(base.level == 1 and base.damage == 10)
	assert(second_level.level == 2 and second_level.damage == 22)
	assert(third_level.level == 3 and third_level.damage == 50 and third_level.next_level.level == 4)
	check_extended_levels(scene)
	assert(base.attack_interval == second_level.attack_interval and base.attack_interval == third_level.attack_interval)
	assert(base.attack_range == second_level.attack_range and base.attack_range == third_level.attack_range)
	enemy.set_physics_process(false)
	enemy.current_health = 10000
	enemy.max_health = 10000
	manager.mana = 1000
	for index: int in 6:
		assert(manager.try_summon())
		slots[index].unit.set_physics_process(false)
	assert(manager.occupied_count() == 6 and not manager.can_summon())
	assert(manager.mana == 805 and manager.current_cost() == 50)
	_assert_field(slots, 6)

	var source: CombatUnit = slots[0].unit
	var survivor: CombatUnit = slots[1].unit
	var survivor_id: int = survivor.get_instance_id()
	var old_source_arrow: CombatProjectile = _arrow(projectiles, enemy, source)
	var old_target_arrow: CombatProjectile = _arrow(projectiles, enemy, survivor)
	var reentry: Array[bool] = []
	slots[0].unit_host.child_exiting_tree.connect(func(_child: Node) -> void:
		assert(slots[0].is_empty() and slots[1].unit.stats.level == 2)
		reentry.append(manager.try_transfer(slots[1], slots[2], survivor))
		reentry.append(manager.try_summon()), CONNECT_ONE_SHOT)
	assert(manager.try_transfer(slots[0], slots[1], source))
	assert(reentry == [false, false])
	assert(slots[0].is_empty() and slots[1].unit.get_instance_id() == survivor_id)
	assert(source.is_queued_for_deletion() and source.get_parent() == null)
	assert(not manager.try_transfer(slots[0], slots[1], source))
	assert(manager.occupied_count() == 5 and manager.can_summon())
	assert(manager.mana == 805 and manager.current_cost() == 50 and manager.successful_summons == 6)
	assert(survivor.stats == second_level and is_equal_approx(survivor._cooldown, 0.6))
	assert(old_source_arrow._attacker == survivor and old_source_arrow._damage == 10)
	old_source_arrow._physics_process(0.001)
	old_target_arrow._physics_process(0.001)
	assert(enemy.current_health == 9980)
	_assert_field(slots, 5)

	# Отмена touch над совместимым юнитом сохраняет обе стороны и экономику.
	var input_checks: RefCounted = load("res://tests/support/feature_4_checks.gd").new()
	var viewport: Viewport = scene.get_viewport()
	input_checks._touch(viewport, 7, Vector2(180, 600), true)
	input_checks._motion_touch(viewport, 7, Vector2(540, 600))
	assert(drag.preview.visible and slots[3].highlight.modulate == Color("ffc45c"))
	input_checks._touch(viewport, 7, Vector2(540, 600), false, true)
	assert(manager.occupied_count() == 5 and slots[2].unit.stats.level == 1 and slots[3].unit.stats.level == 1)
	assert(not drag.preview.visible and drag._pointer == UnitDragController.Pointer.NONE)
	input_checks._touch(viewport, 7, Vector2(180, 600), true)
	input_checks._motion_touch(viewport, 7, Vector2(540, 600))
	input_checks._touch(viewport, 9, Vector2(360, 1040), true)
	input_checks._touch(viewport, 9, Vector2(360, 1040), false)
	assert(manager.successful_summons == 6 and drag._touch_index == 7)
	input_checks._touch(viewport, 7, Vector2(540, 600), false)
	assert(slots[2].is_empty() and slots[3].unit.stats == second_level)
	assert(manager.occupied_count() == 4)
	assert(manager.try_transfer(slots[4], slots[5], slots[4].unit))
	_assert_field(slots, 3)

	var old_level_two_arrow: CombatProjectile = _arrow(projectiles, enemy, survivor)
	assert(manager.try_transfer(slots[1], slots[3], survivor))
	assert(slots[1].is_empty() and slots[3].unit.stats == third_level)
	assert(old_level_two_arrow._attacker == slots[3].unit and old_level_two_arrow._damage == 22)
	old_level_two_arrow._physics_process(0.001)
	assert(enemy.current_health == 9958)
	_assert_field(slots, 2)
	assert(manager.mana == 805 and manager.current_cost() == 50)

	# Заполняем освобождённые слоты и получаем вторую максимальную пару.
	assert(manager.try_summon() and manager.try_summon())
	assert(slots[0].unit.stats == base and slots[1].unit.stats == base)
	assert(manager.try_transfer(slots[0], slots[1], slots[0].unit))
	assert(manager.try_transfer(slots[1], slots[5], slots[1].unit))
	_assert_field(slots, 2)
	var red_left: CombatUnit = slots[3].unit
	var red_right: CombatUnit = slots[5].unit
	for unit: CombatUnit in [red_left, red_right]:
		unit.promote()
		unit.promote()
	red_left._cooldown = 0.42
	red_right._cooldown = 0.37
	assert(not red_left.can_merge_with(red_right))
	assert(manager.try_transfer(slots[3], slots[5], red_left))
	assert(slots[5].unit == red_left and slots[3].unit == red_right)
	assert(is_equal_approx(red_left._cooldown, 0.42) and is_equal_approx(red_right._cooldown, 0.37))
	assert(manager.mana == 700 and manager.current_cost() == 60 and manager.successful_summons == 8)
	_assert_field(slots, 2)

	assert(manager.try_summon())
	var green: CombatUnit = slots[0].unit
	assert(not green.can_merge_with(red_left))
	assert(manager.try_transfer(slots[0], slots[5], green))
	assert(slots[0].unit == red_left and slots[5].unit == green)
	assert(manager.try_transfer(slots[5], slots[1], green))
	var orange: CombatUnit = load("res://scenes/archer.tscn").instantiate() as CombatUnit
	assert(slots[2].place_unit(orange))
	orange.configure(scene.get_node("World/Enemies"), projectiles)
	orange.promote()
	assert(not orange.can_merge_with(green) and not orange.can_merge_with(red_left))
	assert(manager.try_transfer(slots[2], slots[1], orange))
	assert(slots[1].unit == orange and slots[2].unit == green)
	_assert_field(slots, 4)

	# Отличающийся тип использует тот же swap-контракт без добавления игрового контента.
	var alternate: UnitStats = base.duplicate() as UnitStats
	alternate.unit_type = &"test_only"
	orange.stats = alternate
	orange.refresh_visual()
	assert(not orange.can_merge_with(green))
	assert(manager.try_transfer(slots[1], slots[2], orange))
	assert(slots[2].unit == orange and slots[1].unit == green)
	orange.stats = second_level
	orange.refresh_visual()
	_assert_field(slots, 4)

	var damage_by_level: Array[int] = []
	for unit: CombatUnit in [green, orange, red_left]:
		var previous_health: int = enemy.current_health
		_arrow(projectiles, enemy, unit)._physics_process(0.001)
		damage_by_level.append(previous_health - enemy.current_health)
	assert(damage_by_level == [10, 22, 250])
	assert(base.level == 1 and base.damage == 10 and base.next_level == second_level)
	assert(second_level.level == 2 and second_level.damage == 22)
	assert(third_level.level == 3 and third_level.damage == 50)
	var final_mana: int = manager.mana
	var final_cost: int = manager.current_cost()
	scene.get_node("World/Tower").take_damage(100)
	assert(not manager.try_transfer(slots[1], slots[2], green))
	assert(manager.mana == final_mana and manager.current_cost() == final_cost)
	return {"passed": true, "levels": 5, "damage": damage_by_level, "in_flight_damage": [10, 10, 22], "reentry": reentry, "touch_merge": true, "capacity": true, "lv5_swap": true}


func check_extended_levels(scene: Node) -> void:
	var manager: SummonManager = scene.get_node("SummonManager")
	var slots: Array[Node] = scene.get_node("World/Slots").get_children()
	var enemies: Node2D = scene.get_node("World/Enemies")
	var projectiles: Node2D = scene.get_node("World/Projectiles")
	var starting_mana: int = manager.mana
	var starting_cost: int = manager.current_cost()
	var expected_damage: Array[Array] = [[10, 22, 50, 110, 250], [24, 53, 120, 264, 600], [6, 13, 30, 66, 150]]
	var types: Array[String] = ["archer", "mage", "frost_mage"]
	var bonuses: RunBonuses = RunBonuses.new()
	bonuses.pool = load("res://resources/balance/run_upgrade_pool.tres")
	for index: int in types.size():
		var stats: UnitStats = load("res://resources/balance/%s_lv1.tres" % types[index])
		var interval: float = stats.attack_interval
		var reach: float = stats.attack_range
		for level: int in range(1, 6):
			assert(stats.level == level and stats.damage == expected_damage[index][level - 1])
			assert(stats.attack_interval == interval and stats.attack_range == reach)
			if index == 2:
				assert(is_equal_approx(stats.slow_ratio, 0.2 + 0.1 * level) and stats.slow_duration == 1.5)
				assert(bonuses.slow_ratio_for(stats) <= 0.7)
			stats = stats.next_level
		assert(stats == null)
		var unit_scene: PackedScene = load("res://scenes/%s.tscn" % types[index])
		var target: CombatUnit = _place_level(unit_scene, slots[1], 3, enemies, projectiles, 160)
		var source: CombatUnit = _place_level(unit_scene, slots[0], 3, enemies, projectiles, 140)
		assert(manager.try_transfer(slots[0], slots[1], source))
		assert(slots[0].is_empty() and slots[1].unit == target and target.stats.level == 4)
		assert(target.paid_mana == 300 and target.get_node("Visual").texture == target.stats.visual_texture)
		source = _place_level(unit_scene, slots[0], 4, enemies, projectiles, 340)
		assert(manager.try_transfer(slots[0], slots[1], source))
		assert(slots[0].is_empty() and target.stats.level == 5 and target.paid_mana == 640)
		assert(is_equal_approx(target._cooldown, interval))
		source = _place_level(unit_scene, slots[0], 5, enemies, projectiles, 680)
		assert(not source.can_merge_with(target))
		assert(manager.try_transfer(slots[0], slots[1], source))
		assert(slots[0].unit == target and slots[1].unit == source and manager.occupied_count() == 2)
		assert(manager.refund_amount(target) == 320 and manager.refund_amount(source) == 340)
		assert(manager.try_refund(slots[0], target) and not manager.try_refund(slots[0], target))
		assert(manager.try_refund(slots[1], source))
		assert(manager.mana == starting_mana + 660 and manager.current_cost() == starting_cost)
		manager.mana = starting_mana
	bonuses.apply(bonuses.pool.get_upgrade(RunUpgrade.Kind.FROST_POWER))
	bonuses.apply(bonuses.pool.get_upgrade(RunUpgrade.Kind.FROST_POWER))
	for level: int in [4, 5]:
		var frost: UnitStats = load("res://resources/balance/frost_mage_lv%d.tres" % level)
		assert(is_equal_approx(bonuses.slow_ratio_for(frost), 0.7))
	bonuses.free()
	assert(manager.occupied_count() == 0 and manager.mana == starting_mana)


func _place_level(packed: PackedScene, slot: SummonSlot, level: int, enemies: Node2D, projectiles: Node2D, cost: int) -> CombatUnit:
	var unit: CombatUnit = packed.instantiate() as CombatUnit
	var placed: bool = slot.place_unit(unit)
	assert(placed)
	unit.configure(enemies, projectiles)
	unit.attack_enabled = false
	for step: int in level - 1:
		unit.promote()
	unit.paid_mana = cost
	return unit


func _arrow(projectiles: Node2D, enemy: ApproachingEnemy, attacker: CombatUnit) -> CombatProjectile:
	var arrow: CombatProjectile = attacker.projectile_scene.instantiate() as CombatProjectile
	projectiles.add_child(arrow)
	arrow.launch(enemy.global_position, enemy, attacker.stats, attacker)
	return arrow


func _assert_field(slots: Array[Node], count: int) -> void:
	var ids: Array[int] = []
	for slot: SummonSlot in slots:
		assert(slot.unit_host.get_child_count() == (0 if slot.is_empty() else 1))
		if slot.is_empty():
			continue
		assert(not slot.unit.is_queued_for_deletion())
		assert(slot.unit.get_parent() == slot.unit_host and slot.unit.position == Vector2.ZERO)
		assert(slot.unit.get_node("Visual").flip_h == slot.faces_left)
		assert(slot.unit.get_node("Visual").texture == slot.unit.stats.visual_texture)
		assert(not slot.unit.has_node("NameLabel"))
		assert(not ids.has(slot.unit.get_instance_id()))
		ids.append(slot.unit.get_instance_id())
	assert(ids.size() == count)
