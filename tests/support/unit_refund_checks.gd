extends RefCounted


func run(game: Node2D) -> Dictionary:
	var manager: SummonManager = game.summon_manager
	var slots: Array[Node] = game.get_node("World/Slots").get_children()
	var drag: UnitDragController = game.drag_controller
	var viewport: Viewport = game.get_viewport()
	var input_checks: RefCounted = load("res://tests/support/feature_4_checks.gd").new()
	game.wave_manager.spawn_timer.stop()
	var enemy: ApproachingEnemy = game.wave_manager._active[0]
	enemy.set_physics_process(false)
	enemy.current_health = 10000
	manager.pool = load("res://tests/resources/archer_only_pool.tres")
	assert(manager.try_summon() and manager.try_summon())
	var first: CombatUnit = slots[0].unit
	var second: CombatUnit = slots[1].unit
	assert(first.paid_mana == 20 and second.paid_mana == 25)
	assert(manager.refund_amount(first) == 10 and manager.refund_amount(second) == 12)
	assert(not manager.try_refund(null, first) and not manager.try_refund(slots[0], second))
	# Несовместимые уровни проходят через swap, а затем обычный перенос в пустой слот.
	second.promote()
	assert(manager.try_transfer(slots[0], slots[1], first))
	assert(first.paid_mana == 20 and second.paid_mana == 25)
	assert(manager.try_transfer(slots[0], slots[2], second))
	var before: int = manager.mana
	assert(manager.try_refund(slots[2], second) and manager.mana == before + 12)
	assert(not manager.try_refund(slots[2], second) and slots[2].is_empty())
	assert(manager.try_transfer(slots[1], slots[0], first))
	# Отмена touch над башней сохраняет и бойца, и стоимость, и ману.
	input_checks._touch(viewport, 7, Vector2(180, 360), true)
	input_checks._motion_touch(viewport, 7, Vector2(360, 1040))
	assert(drag._return_zone.highlight.visible and drag._return_zone.refund_label.text == "RETURN · +10 MANA")
	before = manager.mana
	input_checks._touch(viewport, 7, Vector2(360, 1040), false, true)
	assert(slots[0].unit == first and manager.mana == before and not drag._return_zone.highlight.visible)
	input_checks._touch(viewport, 7, Vector2(180, 360), true)
	input_checks._motion_touch(viewport, 7, Vector2(360, 700))
	input_checks._touch(viewport, 7, Vector2(360, 700), false)
	assert(slots[0].unit == first and manager.mana == before)
	# Снаряд возвращённого бойца не может нанести отложенный урон или применить Frost.
	var projectile: CombatProjectile = first.projectile_scene.instantiate() as CombatProjectile
	game.projectiles.add_child(projectile)
	projectile.launch(enemy.global_position, enemy, first.stats, first)
	var reentry: Array[bool] = []
	slots[0].unit_host.child_exiting_tree.connect(func(_child: Node) -> void:
		reentry.append(manager.try_refund(slots[0], first))
		reentry.append(manager.try_summon()), CONNECT_ONE_SHOT)
	input_checks._touch(viewport, 7, Vector2(180, 360), true)
	input_checks._motion_touch(viewport, 7, Vector2(360, 1040))
	input_checks._touch(viewport, 9, Vector2(360, 1040), true)
	input_checks._touch(viewport, 9, Vector2(360, 1040), false)
	assert(slots[0].unit == first)
	input_checks._touch(viewport, 7, Vector2(360, 1040), false)
	assert(manager.mana == before + 10 and slots[0].is_empty() and reentry == [false, false])
	assert(projectile._resolved and projectile.is_queued_for_deletion() and not first._running)
	var health: int = enemy.current_health
	projectile._hit_target()
	assert(enemy.current_health == health and manager.current_cost() == 30)
	# Четыре следующих оплаченных призыва собираются в Lv3 без потери стоимости.
	manager.add_mana(1000)
	for index: int in 4:
		assert(manager.try_summon())
	assert(slots[0].unit.paid_mana == 30 and slots[1].unit.paid_mana == 35)
	assert(manager.try_transfer(slots[0], slots[1], slots[0].unit))
	assert(slots[1].unit.paid_mana == 65 and manager.refund_amount(slots[1].unit) == 32)
	assert(manager.try_transfer(slots[2], slots[3], slots[2].unit))
	assert(slots[3].unit.paid_mana == 85)
	assert(manager.try_transfer(slots[1], slots[3], slots[1].unit))
	var merged: CombatUnit = slots[3].unit
	assert(merged.stats.level == 3 and merged.paid_mana == 150 and manager.refund_amount(merged) == 75)
	assert(manager.try_refund(slots[3], merged) and manager.current_cost() == 50)
	assert(manager.try_summon() and slots[0].unit.paid_mana == 50)
	# Полное поле после возврата снова допускает призыв, цена продолжает расти.
	while manager.occupied_count() < 6:
		assert(manager.try_summon())
	assert(not manager.can_summon())
	var full_cost: int = manager.current_cost()
	assert(manager.try_refund(slots[5], slots[5].unit) and manager.can_summon())
	assert(manager.current_cost() == full_cost and manager.try_summon())
	var stopped: CombatUnit = slots[0].unit
	input_checks._touch(viewport, 7, Vector2(180, 360), true)
	input_checks._motion_touch(viewport, 7, Vector2(360, 1040))
	game.tower.take_damage(100)
	before = manager.mana
	input_checks._touch(viewport, 7, Vector2(360, 1040), false)
	assert(not manager.try_refund(slots[0], stopped) and manager.mana == before)
	assert(not drag._return_zone.highlight.visible and not drag.preview.visible)
	return {"passed": true, "odd_cost_floor": 12, "lv2_refund": 32, "lv3_refund": 75,
		"swap_preserves_cost": true, "touch_cancel": true, "extra_pointer": true,
		"duplicate_blocked": true, "reentry_blocked": true, "projectile_cancelled": true,
		"full_field_reopens": true, "game_over_blocks_refund": true}
