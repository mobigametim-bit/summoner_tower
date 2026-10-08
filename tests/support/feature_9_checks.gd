extends RefCounted


func run_bonuses(game: Node2D) -> Dictionary:
	var bonuses: RunBonuses = game.run_bonuses
	var manager: SummonManager = game.summon_manager
	var slots: Array[Node] = game.get_node("World/Slots").get_children()
	var archer: UnitStats = load("res://resources/balance/archer_lv1.tres")
	var frost: UnitStats = load("res://resources/balance/frost_mage_lv1.tres")
	var frost3: UnitStats = load("res://resources/balance/frost_mage_lv3.tres")
	game.wave_manager.stop()
	manager.pool = load("res://tests/resources/archer_only_pool.tres")
	var first_summon: bool = manager.try_summon()
	var second_summon: bool = manager.try_summon()
	assert(first_summon and second_summon)
	var first: CombatUnit = slots[0].unit
	first.attack_enabled = false
	slots[1].unit.attack_enabled = false
	var target: ApproachingEnemy = load("res://scenes/enemy.tscn").instantiate()
	game.enemies.add_child(target)
	target.configure(Vector2.ZERO, 100000.0, 10000)
	target.set_physics_process(false)
	first._target = target
	first._fire()
	var original: CombatProjectile = game.projectiles.get_child(0)
	assert(original._damage == 10 and manager.current_cost() == 30)
	for kind: RunUpgrade.Kind in [RunUpgrade.Kind.RAPID_FIRE, RunUpgrade.Kind.POWER]:
		bonuses.apply(bonuses.pool.get_upgrade(kind))
		bonuses.apply(bonuses.pool.get_upgrade(kind))
	assert(is_equal_approx(first.effective_attack_interval(), first.stats.attack_interval / pow(1.15, 2)))
	assert(bonuses.damage_for(archer) == 14 and original._damage == 10)
	first._fire()
	var stronger: CombatProjectile = game.projectiles.get_child(1)
	assert(stronger._damage == 14)
	stronger._hit_target()
	assert(target.current_health == 9986)
	assert(manager.try_transfer(slots[0], slots[1], first))
	var merged: CombatUnit = slots[1].unit
	assert(merged.stats.level == 2 and merged.paid_mana == 45)
	assert(bonuses.damage_for(merged.stats) == 31)
	assert(is_equal_approx(merged.effective_attack_interval(), merged.stats.attack_interval / pow(1.15, 2)))
	bonuses.apply(bonuses.pool.get_upgrade(RunUpgrade.Kind.MANA_FLOW))
	var income: Array[int] = []
	for index: int in 5:
		income.append(bonuses.kill_mana_for(3))
	assert(income == [3, 4, 3, 4, 4])
	bonuses.apply(bonuses.pool.get_upgrade(RunUpgrade.Kind.MANA_FLOW))
	assert(bonuses.kill_mana_for(5) == 7 and bonuses.kill_mana_for(3) == 4)
	prepare_wave(game, 1, RunUpgrade.Kind.RAPID_FIRE)
	var mana_before_kill: int = manager.mana
	var rewarded_enemy: ApproachingEnemy = game.wave_manager._active[0]
	rewarded_enemy.take_damage(rewarded_enemy.max_health)
	assert(manager.mana == mana_before_kill + 4)
	game.wave_manager.stop()
	bonuses.apply(bonuses.pool.get_upgrade(RunUpgrade.Kind.CHEAP_SUMMONS))
	assert(manager.current_cost() == 26)
	var before: int = manager.mana
	assert(manager.try_summon() and manager.mana == before - 26 and slots[0].unit.paid_mana == 26)
	assert(slots[0].unit._run_bonuses == bonuses and bonuses.damage_for(slots[0].unit.stats) == 14)
	assert(manager.try_refund(slots[0], slots[0].unit) and manager.mana == before - 13)
	assert(manager.refund_amount(merged) == 22)
	bonuses.apply(bonuses.pool.get_upgrade(RunUpgrade.Kind.CHEAP_SUMMONS))
	assert(bonuses.summon_cost_for(30) == 22 and bonuses.summon_cost_for(1) == 1)
	game.tower.take_damage(20)
	bonuses.apply(bonuses.pool.get_upgrade(RunUpgrade.Kind.TOWER_ARMOR))
	game.tower.increase_max_health(bonuses.tower_health_for(100))
	assert(game.tower.max_health == 125 and game.tower.current_health == 105)
	bonuses.apply(bonuses.pool.get_upgrade(RunUpgrade.Kind.TOWER_ARMOR))
	game.tower.increase_max_health(bonuses.tower_health_for(100))
	assert(game.tower.max_health == 156 and game.tower.current_health == 136 and game.hud.health_label.text == "136")
	for index: int in 4:
		bonuses.apply(bonuses.pool.get_upgrade(RunUpgrade.Kind.FROST_POWER))
	assert(is_equal_approx(bonuses.slow_ratio_for(frost), 0.7))
	assert(is_equal_approx(bonuses.slow_ratio_for(frost3), 0.7) and bonuses.slow_ratio_for(archer) == 0.0)
	var frost_shot: CombatProjectile = load("res://scenes/frost_bolt.tscn").instantiate()
	game.projectiles.add_child(frost_shot)
	frost_shot.launch(target.global_position, target, frost, merged, bonuses)
	frost_shot._hit_target()
	assert(is_equal_approx(target._slow_ratio, 0.7))
	for upgrade: RunUpgrade in bonuses.roll_choices():
		assert(upgrade.kind != RunUpgrade.Kind.FROST_POWER)
	assert(archer.damage == 10 and is_equal_approx(archer.attack_interval, 0.5) and is_equal_approx(frost.slow_ratio, 0.3))
	bonuses.reset()
	bonuses.set_random_seed(23)
	var choices: Array[RunUpgrade] = bonuses.roll_choices()
	bonuses.set_random_seed(23)
	assert(choices == bonuses.roll_choices() and choices.size() == 3)
	assert(choices[0] != choices[1] and choices[0] != choices[2] and choices[1] != choices[2])
	assert(bonuses.damage_for(archer) == 10 and bonuses.summon_cost_for(30) == 30 and bonuses.kill_mana_for(3) == 3)
	return {"passed": true, "effects": 6, "income": income, "snapshot_projectiles": true,
		"merge_and_new_units": true, "actual_cost_refund": 13, "frost_cap": 0.7, "resources_unchanged": true}


func prepare_wave(game: Node2D, number: int, preferred: RunUpgrade.Kind) -> void:
	var waves: WaveManager = game.wave_manager
	waves.stop()
	# Seed выбирается в тестовой сцене; production не получает команды пропуска волн.
	if preferred >= 0:
		for value: int in 100:
			game.run_bonuses.set_random_seed(value)
			if game.run_bonuses.roll_choices()[0].kind == preferred:
				game.run_bonuses.set_random_seed(value)
				break
	waves.wave_number = number
	waves.phase = WaveManager.Phase.FIGHTING
	waves._begin_wave()
	while waves._spawn_remaining > 0:
		waves.spawn_timer.stop()
		waves._on_spawn_timeout()
	waves.spawn_timer.stop()
	for enemy: ApproachingEnemy in waves._active:
		enemy.set_physics_process(false)


func prepare_first_choice(game: Node2D) -> void:
	game.summon_manager.pool = load("res://tests/resources/archer_only_pool.tres")
	# Release export удаляет assert: подготовка объектов должна выполняться отдельно.
	var first_summon: bool = game.summon_manager.try_summon()
	var second_summon: bool = game.summon_manager.try_summon()
	assert(first_summon and second_summon)
	game.tower.take_damage(30)
	prepare_wave(game, 5, RunUpgrade.Kind.TOWER_ARMOR)
	var active: Array[ApproachingEnemy] = game.wave_manager._active.duplicate()
	var boss: ApproachingEnemy = active.front()
	var unit: CombatUnit = game.get_node("World/Slots/Slot1").unit
	unit._target = boss
	unit._fire()
	unit._cooldown = 5.0
	boss.take_damage(boss.max_health)
	assert(game.state == 0 and game.wave_manager.phase == WaveManager.Phase.FIGHTING)
	for enemy: ApproachingEnemy in active:
		if enemy != boss:
			enemy.take_damage(enemy.max_health)
	assert(game.state == 3 and game.get_tree().paused and game.upgrade_choice.visible)
	assert(game._offered_upgrades.size() == 3 and game._offered_upgrades[0].kind == RunUpgrade.Kind.TOWER_ARMOR)
	assert(game.wave_manager.intermission_timer.is_stopped())
	assert(not game.summon_manager.try_summon())
	assert(not game.summon_manager.try_refund(game.get_node("World/Slots/Slot1"), unit))
	assert(not game.summon_manager.try_transfer(game.get_node("World/Slots/Slot1"), game.get_node("World/Slots/Slot2"), unit))
	game._on_upgrade_chosen(-1)
	assert(game.state == 3)
	game.tower.health_changed.connect(func(_hp: int, _max_hp: int) -> void:
		game._on_upgrade_chosen(1), CONNECT_ONE_SHOT)


func prepare_second_choice(game: Node2D) -> void:
	assert(game.run_bonuses.count(RunUpgrade.Kind.TOWER_ARMOR) == 1)
	assert(game.state == 0 and not game.get_tree().paused and game.tower.max_health == 125 and game.tower.current_health == 95)
	assert(game._offered_upgrades.is_empty() and not game.upgrade_choice.visible)
	game._on_upgrade_chosen(0)
	assert(game.run_bonuses.count(RunUpgrade.Kind.TOWER_ARMOR) == 1)
	prepare_wave(game, 10, RunUpgrade.Kind.POWER)
	var active: Array[ApproachingEnemy] = game.wave_manager._active.duplicate()
	for enemy: ApproachingEnemy in active:
		enemy.take_damage(enemy.max_health)
	assert(game.state == 3 and game._offered_upgrades[0].kind == RunUpgrade.Kind.POWER)


func check_escape_and_shutdown(game: Node2D) -> Dictionary:
	assert(game.state == 0 and not game.get_tree().paused and game.run_bonuses.count(RunUpgrade.Kind.POWER) == 1)
	assert(game.tower.max_health == 125 and game.tower.current_health == 95)
	prepare_wave(game, 15, RunUpgrade.Kind.POWER)
	var active: Array[ApproachingEnemy] = game.wave_manager._active.duplicate()
	var boss: ApproachingEnemy = active.front()
	for enemy: ApproachingEnemy in active:
		if enemy != boss:
			enemy.take_damage(enemy.max_health)
	boss._resolve_at_tower()
	assert(game.state == 0 and not game.get_tree().paused and game.tower.current_health == 45)
	assert(game.wave_manager.phase == WaveManager.Phase.INTERMISSION and game._offered_upgrades.is_empty())
	prepare_wave(game, 20, RunUpgrade.Kind.POWER)
	active = game.wave_manager._active.duplicate()
	for enemy: ApproachingEnemy in active:
		enemy.take_damage(enemy.max_health)
	assert(game.state == 3 and game.get_tree().paused)
	game.tower.take_damage(game.tower.max_health)
	assert(game.state == 1 and not game.get_tree().paused and not game.upgrade_choice.visible)
	return {"passed": true, "boss_escape_no_choice": true, "choice_reentry_blocked": true, "shutdown_unpauses": true}
