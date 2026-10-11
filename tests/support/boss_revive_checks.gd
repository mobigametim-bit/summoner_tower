extends RefCounted


func prepare(game: Node2D, wave: int = 5, remaining_creep: bool = false) -> Dictionary:
	game.get_node("/root/SessionProgress").use_test_save()
	game.get_node("/root/AudioService").settings_store = AudioSettingsStore.new("")
	var waves: WaveManager = game.wave_manager
	waves.stop()
	game.battlefield_seed = 1711
	game.summon_manager.pool = load("res://tests/resources/archer_only_pool.tres")
	assert(game.summon_manager.try_summon())
	assert(game.summon_manager.try_summon())
	for slot: SummonSlot in game.summon_manager._slots:
		if not slot.is_empty():
			slot.unit.attack_enabled = false
	var boss: ApproachingEnemy = load("res://scenes/boss.tscn").instantiate()
	game.enemies.add_child(boss)
	boss.configure(Vector2.ZERO, 100000.0)
	boss.set_physics_process(false)
	waves.wave_number = wave
	waves.phase = WaveManager.Phase.FIGHTING
	waves._boss_killed = false
	waves._boss_wave_revived = false
	waves._active.append(boss)
	boss.resolved.connect(waves._on_enemy_resolved)
	if remaining_creep:
		var enemy: ApproachingEnemy = load("res://scenes/enemy.tscn").instantiate()
		game.enemies.add_child(enemy)
		enemy.configure(Vector2.ZERO, 100000.0)
		enemy.set_physics_process(false)
		waves._active.append(enemy)
		enemy.resolved.connect(waves._on_enemy_resolved)
	game.tower.initialize(boss.tower_damage)
	game.set_meta("revive_check_mana", game.summon_manager.mana)
	var refund: int = 0
	for slot: SummonSlot in game.summon_manager._slots:
		if not slot.is_empty():
			refund += game.summon_manager.refund_amount(slot.unit)
	game.set_meta("revive_check_refund", refund)
	boss._resolve_at_tower()
	assert(game.state == game.State.REVIVE_OFFER)
	assert(game.get_tree().paused and game.map_changes == 0)
	assert(waves.phase == WaveManager.Phase.FIGHTING)
	assert(not waves._boss_killed and game.run_statistics.killed_bosses == 0)
	game._on_revive_accepted()
	assert(game.state == game.State.REWARDED_VIEW and game.ad_service.busy)
	return {"offer": true, "watching": true, "wave": wave, "remaining_creep": remaining_creep}


func check_restored(game: Node2D, remaining_creep: bool = false) -> Dictionary:
	assert(game.revive_used and game.tower.current_health == 50)
	assert(game.map_changes == 0 and game.summon_manager.occupied_count() == 2)
	assert(game.run_statistics.killed_bosses == 0)
	if remaining_creep:
		assert(game.state == game.State.RUNNING and not game.get_tree().paused)
		assert(not game.upgrade_choice.visible)
		var enemies: Array[ApproachingEnemy] = game.wave_manager._active.duplicate()
		for enemy: ApproachingEnemy in enemies:
			enemy.take_damage(enemy.max_health)
	assert(game.state == game.State.UPGRADE_CHOICE and game.get_tree().paused)
	assert(game.wave_manager.phase == WaveManager.Phase.UPGRADE_CHOICE)
	assert(game.upgrade_choice.visible and game._offered_upgrades.size() == 3)
	game.wave_manager._try_finish_wave()
	game._on_ad_completed(AdService.Placement.REVIVE, AdService.Outcome.SUCCESS)
	assert(game.map_changes == 0 and game.tower.current_health == 50)
	var mana_before_choice: int = game.summon_manager.mana
	game._on_upgrade_chosen(0)
	assert(game.map_changes == 1 and game.summon_manager.occupied_count() == 0)
	assert(game.summon_manager.mana == mana_before_choice + game.get_meta("revive_check_refund"))
	assert(game.state == game.State.RUNNING and not game.get_tree().paused)
	assert(game.wave_manager.phase == WaveManager.Phase.INTERMISSION)
	game._on_upgrade_chosen(0)
	assert(game.map_changes == 1)
	return {"choice": true, "map_once": true, "sale_once": true, "no_fake_boss_kill": true}
