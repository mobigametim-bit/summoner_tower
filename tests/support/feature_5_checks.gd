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
	assert(third_level.level == 3 and third_level.damage == 50 and third_level.next_level == null)
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
	input_checks._touch(viewport, 9, Vector2(360, 1220), true)
	input_checks._touch(viewport, 9, Vector2(360, 1220), false)
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
	assert(damage_by_level == [10, 22, 50])
	assert(base.level == 1 and base.damage == 10 and base.next_level == second_level)
	assert(second_level.level == 2 and second_level.damage == 22)
	assert(third_level.level == 3 and third_level.damage == 50)
	var final_mana: int = manager.mana
	var final_cost: int = manager.current_cost()
	scene.get_node("World/Tower").take_damage(100)
	assert(not manager.try_transfer(slots[1], slots[2], green))
	assert(manager.mana == final_mana and manager.current_cost() == final_cost)
	return {"passed": true, "levels": 3, "damage": damage_by_level, "in_flight_damage": [10, 10, 22], "reentry": reentry, "touch_merge": true, "capacity": true, "lv3_swap": true}


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
		assert(slot.unit.get_node("NameLabel").text == "ARCHER")
		assert(not ids.has(slot.unit.get_instance_id()))
		ids.append(slot.unit.get_instance_id())
	assert(ids.size() == count)
