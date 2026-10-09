extends "res://tests/support/feature_8_test_scene.gd"

var _web_boss_preview: bool = false
var _preview_elapsed: float = 0.0


func _ready() -> void:
	super._ready()
	# Этот сценарий проверяет результаты и кошелёк на фиксированных волнах,
	# независимо от адаптивной балансировки обычного забега.
	game.wave_manager.stop()
	var fixed: WaveConfig = game.wave_manager.config.duplicate() as WaveConfig
	fixed.power_balance = null
	fixed.first_enemy_count = 4
	game.wave_manager.config = fixed
	game.wave_manager.wave_number = 0
	game.run_statistics.reset()
	game.wave_manager.start()
	game.summon_manager.pool = load("res://tests/resources/archer_only_pool.tres")
	if OS.has_feature("web") and SessionProgress.crystals == 0:
		prepare_boss_preview.call_deferred()


func prepare_boss_preview() -> void:
	game.wave_manager.stop()
	game.wave_manager.wave_number = 5
	game.wave_manager.phase = WaveManager.Phase.FIGHTING
	game.wave_manager._begin_wave()
	_web_boss_preview = true


func _process(delta: float) -> void:
	if _web_boss_preview:
		_preview_elapsed += delta
		if _preview_elapsed >= 4.0:
			_web_boss_preview = false
			game.wave_manager.stop()
			game.wave_manager.wave_number = 0
			game.run_statistics.reset()
			game.wave_manager.start()
			prepare_result(10)
	super._process(delta)


func prepare_result(wave_count: int) -> void:
	var stats: RunStatistics = game.run_statistics
	var waves: WaveManager = game.wave_manager
	assert(stats.config.reward_for(0, 0) == 0 and stats.config.reward_for(5, 1) == 20)
	assert(stats.config.reward_for(10, 2) == 40 and stats.config.reward_for(20, 4) == 80)
	var before: int = SessionProgress.crystals
	var expected_bosses: int = floori(float(wave_count) / waves.config.boss_interval)
	if wave_count == 0:
		waves._active[0].take_damage(waves._active[0].max_health)
	else:
		var manager: SummonManager = game.summon_manager
		var first: bool = manager.try_summon()
		var second: bool = manager.try_summon()
		var third: bool = manager.try_summon()
		assert(first and second and third)
		var merged: bool = manager.try_transfer(slots[0], slots[1], slots[0].unit)
		var swapped: bool = manager.try_transfer(slots[1], slots[2], slots[1].unit)
		var refunded_unit: bool = manager.try_refund(slots[1], slots[1].unit)
		assert(merged and swapped and refunded_unit and stats.merges == 1)
		for slot: SummonSlot in slots:
			if not slot.is_empty():
				slot.unit.attack_enabled = false
		for wave: int in range(1, wave_count + 1):
			assert(waves.wave_number == wave)
			var ordinary: int = 4 + 2 * (wave - 1)
			assert(waves.config.enemy_count_for(wave) == ordinary)
			if waves.config.is_boss_wave(wave):
				# Первая пачка обычных врагов содержит 1–3 моба, плюс отдельный босс.
				assert(waves.active_count() >= 2 and waves._spawn_remaining + waves.active_count() == ordinary + 1)
				assert(waves._active[0].stats.is_boss and not waves._active[1].stats.is_boss)
				assert(waves._active[0].global_position == waves._active[1].global_position)
				var boss: ApproachingEnemy = waves._active[0]
				boss.take_damage(boss.max_health)
				assert(game.state == 0 and waves.phase == WaveManager.Phase.FIGHTING)
			while waves._spawn_remaining > 0:
				waves.spawn_timer.stop()
				waves._on_spawn_timeout()
			waves.spawn_timer.stop()
			var active: Array[ApproachingEnemy] = waves._active.duplicate()
			for enemy: ApproachingEnemy in active:
				enemy.take_damage(enemy.max_health)
				enemy.take_damage(enemy.max_health)
				waves._on_enemy_resolved(enemy, ApproachingEnemy.Outcome.KILLED)
			assert(stats.completed_waves == wave)
			stats.record_completed_wave(wave)
			assert(stats.completed_waves == wave)
			if waves.config.is_boss_wave(wave):
				assert(game.state == 3 and get_tree().paused)
				for index: int in game._offered_upgrades.size():
					if game._offered_upgrades[index].kind != RunUpgrade.Kind.TOWER_ARMOR:
						game._on_upgrade_chosen(index)
						break
			assert(game.state == 0 and waves.phase == WaveManager.Phase.INTERMISSION)
			waves.intermission_timer.stop()
			waves._on_intermission_timeout()
		assert(stats.killed_enemies == wave_count * (wave_count + 3) + expected_bosses)
		assert(stats.killed_bosses == expected_bosses and stats.reached_wave == wave_count + 1)
	game.tower.take_damage(game.tower.max_health)
	game._on_revive_declined()
	var expected: int = stats.config.reward_for(wave_count, expected_bosses)
	assert(game.state == 1 and stats.finished and stats.earned_crystals == expected)
	assert(SessionProgress.crystals == before + expected and stats.total_crystals == SessionProgress.crystals)
	game._on_tower_destroyed()
	var repeated: bool = stats.finish()
	stats.record_merge()
	assert(not repeated and SessionProgress.crystals == before + expected)
	var stack: Node = game.hud.game_over_overlay.get_node("Center/Panel/Stack")
	assert(stack.get_node("Stats/Wave/Value").text == str(stats.reached_wave))
	assert(stack.get_node("Stats/Enemies/Value").text == str(stats.killed_enemies))
	assert(stack.get_node("Reward/Amount").text == "+%d" % expected)
	set_meta("result_checks", {"passed": true, "wave_count": wave_count, "reward": expected})


func snapshot() -> Dictionary:
	var result: Dictionary = super.snapshot()
	var stats: RunStatistics = game.run_statistics
	var stack: Node = game.hud.game_over_overlay.get_node("Center/Panel/Stack")
	var restart_rect: Rect2 = game.hud.restart_button.get_global_rect()
	result.crystals = SessionProgress.crystals
	result.stats = {"reached": stats.reached_wave, "completed": stats.completed_waves,
		"enemies": stats.killed_enemies, "bosses": stats.killed_bosses, "merges": stats.merges,
		"earned": stats.earned_crystals, "total": stats.total_crystals, "finished": stats.finished}
	result.reward_text = stack.get_node("Reward/Amount").text
	result.restart = {"x": restart_rect.get_center().x, "y": restart_rect.get_center().y}
	result.bonuses = game.run_bonuses._counts
	return result
