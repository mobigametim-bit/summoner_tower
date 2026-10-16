extends RefCounted

const SAVE_PATH: String = "user://biome_victory_review.json"


func prepare(game: Node2D, wave: int = 25, boss_only: bool = false) -> Dictionary:
	game._stop_encounter()
	# Начинаем новый изолированный бой, сохраняя уже открытые биомы тестового профиля.
	game.state = game.State.RUNNING
	game.revive_used = false
	game._last_healed_wave = wave - 1
	game.run_statistics.reset()
	for completed: int in range(1, wave):
		game.run_statistics.record_completed_wave(completed)
	game.run_statistics.killed_bosses = floori(float(wave - 1) / 5.0)
	game.tower.initialize(100)
	game.hud.game_over_overlay.hide()
	game.hud.set_settings_available(true)
	game.drag_controller.configure(game.summon_manager, game.get_node("World/Slots"), game.get_node("World/Tower/ReturnZone"))
	game.summon_manager.set_interaction_enabled(true)
	game.summon_manager._running = true
	# Оставляем двух бойцов: по завершении финала они не должны продаваться.
	if game.summon_manager.occupied_count() == 0:
		game.summon_manager.try_summon()
		game.summon_manager.try_summon()
	for slot: SummonSlot in game.summon_manager._slots:
		if not slot.is_empty():
			slot.unit.attack_enabled = false
	var waves: WaveManager = game.wave_manager
	waves.wave_number = wave
	waves.phase = WaveManager.Phase.FIGHTING
	if boss_only:
		waves._boss_killed = false
		waves._boss_wave_revived = false
		waves._sequence.assign([waves.config.boss_scene])
		waves._spawn_remaining = 1
		waves._spawn_enemy()
	else:
		waves._begin_wave()
	waves.spawn_timer.stop()
	freeze_enemies(game)
	game.set_meta("victory_army", game.summon_manager.occupied_count())
	game.set_meta("victory_maps", game.map_changes)
	return snapshot(game)


func freeze_enemies(game: Node2D) -> void:
	for enemy: ApproachingEnemy in game.wave_manager._active:
		enemy.set_physics_process(false)


func kill_boss(game: Node2D) -> void:
	for enemy: ApproachingEnemy in game.wave_manager._active.duplicate():
		if enemy.stats.is_boss:
			enemy.take_damage(1000000000.0, false, false)


func clear_wave(game: Node2D) -> void:
	var waves: WaveManager = game.wave_manager
	while waves._spawn_remaining > 0 and waves.phase == WaveManager.Phase.FIGHTING:
		waves._spawn_enemy()
	waves.spawn_timer.stop()
	for enemy: ApproachingEnemy in waves._active.duplicate():
		enemy.take_damage(1000000000.0, false, false)


func lethal_boss(game: Node2D) -> void:
	prepare(game, 25, true)
	var boss: ApproachingEnemy = game.wave_manager._active[0]
	game.tower.initialize(boss.tower_damage)
	boss._resolve_at_tower()


func snapshot(game: Node2D) -> Dictionary:
	var stack: Node = game.hud.game_over_overlay.get_node("Center/Panel/Stack")
	return {"state": game.state, "wave": game.wave_manager.wave_number,
		"phase": game.wave_manager.phase, "alive": game.wave_manager.active_count(),
		"pending": game.wave_manager._spawn_remaining, "victory": game.run_statistics.victory,
		"saved": game.run_statistics.result_saved, "completed": game.run_statistics.completed_waves,
		"bosses": game.run_statistics.killed_bosses, "reward": game.run_statistics.earned_crystals,
		"crystals": SessionProgress.crystals, "unlocked": SessionProgress.unlocked_biomes.duplicate(),
		"result_visible": game.hud.game_over_overlay.visible, "title": stack.get_node("Title").text,
		"unlock_notice": stack.get_node("BiomeUnlocked").visible,
		"choice_visible": game.upgrade_choice.visible, "maps": game.map_changes,
		"army": game.summon_manager.occupied_count(), "health": game.tower.current_health,
		"revive_visible": game.hud.revive_overlay.visible, "paused": game.get_tree().paused,
		"reward_doubled": game.run_statistics.reward_doubled,
		"menu_position": _center(game.hud.menu_button), "restart_position": _center(game.hud.restart_button),
		"double_position": _center(game.hud.double_reward_button),
		"revive_accept": _center(game.hud.revive_overlay.get_node("Center/Panel/Stack/Actions/Accept")),
		"revive_decline": _center(game.hud.revive_overlay.get_node("Center/Panel/Stack/Actions/Decline"))}


func _center(control: Control) -> Array[float]:
	var point: Vector2 = control.get_global_rect().get_center()
	return [point.x, point.y]
