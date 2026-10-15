extends RefCounted

var _checks: int = 0
var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _spawn(game: Node, kind: String, tier: int) -> ApproachingEnemy:
	var path: String = "res://scenes/%s.tscn" % ("enemy" if kind == "goblin" else kind)
	var enemy: ApproachingEnemy = load(path).instantiate() as ApproachingEnemy
	game.enemies.add_child(enemy)
	enemy.configure(Vector2(200, 350), 100000, enemy.stats.base_health * (1 << (tier - 1)), tier)
	enemy.set_physics_process(false)
	return enemy


func run(game: Node) -> Dictionary:
	game.wave_manager.stop()
	game.get_tree().paused = false
	# Ни один тест не пишет в сохранение и не выдаёт результат забега.
	var golem: ApproachingEnemy = _spawn(game, "golem", 5)
	var start: int = golem.current_health
	_check(golem.abilities.effects.armor_y + 21.6 <= golem.health_bar.position.y - 8.0 + 0.001, "armor icons above HP")
	golem.take_damage(11)
	golem.take_damage(11)
	golem.take_damage(11)
	_check(golem.current_health == start - 16 and is_equal_approx(golem._damage_remainder, 0.5), "armor fractional accumulation")
	_check(golem.abilities.armor_remaining == 0, "exactly three protected hits")
	golem.take_damage(11)
	_check(golem.current_health == start - 27, "fourth hit full damage")
	golem.configure(Vector2.ZERO, 100000, start)
	golem.set_physics_process(false)
	golem.take_damage(11, false, false)
	_check(golem.current_health == start - 11 and golem.abilities.armor_remaining == 3, "burn bypasses plates")
	golem.stop()
	golem.queue_free()
	for kind: String in ["goblin", "orc", "golem"]:
		for tier: int in range(1, 5):
			var regular: ApproachingEnemy = _spawn(game, kind, tier)
			regular.take_damage(regular.max_health * 0.6)
			_check(not regular.abilities._enabled and regular.abilities.armor_remaining == 0 and is_equal_approx(regular.abilities.advance(10.0), 10.0), "%s Lv%d unchanged" % [kind, tier])
			regular.stop()
			regular.queue_free()
	var orc: ApproachingEnemy = _spawn(game, "orc", 5)
	orc.take_damage(orc.max_health * 0.5)
	_check(orc.abilities.raging and is_equal_approx(orc.current_move_speed(), orc.move_speed * 1.3), "orc rage at half HP")
	_check(is_equal_approx(orc._time_to_contact(), (100000.0 - orc.global_position.y) / (orc.move_speed * 1.3)), "contact animation uses boosted speed")
	orc.apply_slow(0.5, 3.0)
	_check(is_equal_approx(orc.current_move_speed(), orc.move_speed * 0.65), "rage preserves slow")
	orc.take_damage(1)
	_check(is_equal_approx(orc.abilities.speed_multiplier(), 1.3), "rage does not stack")
	orc.stop()
	orc.queue_free()
	var goblin: ApproachingEnemy = _spawn(game, "goblin", 5)
	_check(is_equal_approx(goblin.abilities.advance(5.0), 5.0) and goblin.abilities._dash_preparing, "dash windup after five seconds")
	_check(is_zero_approx(goblin.abilities.advance(0.3)), "dash crouch stationary")
	_check(is_equal_approx(goblin.abilities.advance(0.8), 1.28), "dash exact boost interval")
	goblin.abilities.effects.set_aura(&"dash")
	goblin.abilities.effects.set_motion(Vector2.DOWN)
	_check(is_equal_approx(goblin.abilities.effects.aura_particles.rotation, PI / 2.0), "dash trail follows vertical road")
	goblin.abilities.effects.set_motion(Vector2.LEFT)
	_check(is_equal_approx(absf(goblin.abilities.effects.aura_particles.rotation), PI), "dash trail follows left turn")
	goblin.abilities.configure(&"goblin", 5, goblin.max_health)
	var integrated: float = 0.0
	for frame: int in 660:
		integrated += goblin.abilities.advance(1.0 / 60.0)
	var single_step: float = 0.0
	goblin.abilities.configure(&"goblin", 5, goblin.max_health)
	single_step = goblin.abilities.advance(11.0)
	_check(absf(integrated - single_step) < 0.001, "dash independent of frame splitting")
	goblin.apply_freeze(1.0)
	var clock: float = goblin.abilities._dash_clock
	var old_position: Vector2 = goblin.global_position
	goblin._physics_process(0.5)
	_check(goblin.global_position == old_position and is_equal_approx(clock, goblin.abilities._dash_clock), "freeze suspends dash and movement")
	_check(is_inf(goblin._time_to_contact()), "frozen enemy cannot begin tower attack")
	goblin.stop()
	goblin.queue_free()
	for tier: int in range(1, 6):
		var boss: ApproachingEnemy = _spawn(game, "boss", tier)
		if tier >= 3:
			var intro_radius: Vector2 = boss.abilities.effects.shield_radius
			boss.boss_visual.play_animation(&"walk_loop")
			EnemyAbilityVisual._boss_bounds.clear()
			boss.abilities.effects.fit_to_enemy(boss)
			_check(intro_radius.is_equal_approx(boss.abilities.effects.shield_radius), "shield size independent of intro Lv%d" % tier)
		boss.take_damage(boss.max_health * 0.5)
		var shield: float = float(boss.max_health) * 0.15 if tier >= 3 else 0.0
		_check(is_equal_approx(boss.abilities.shield_health, shield), "boss Lv%d shield gate" % tier)
		_check(boss.abilities.effects.shield_sparks.emitting == (tier >= 3), "shield particles follow shield state Lv%d" % tier)
		if tier >= 3:
			var health: int = boss.current_health
			boss.take_damage(shield + 10.0, false, false)
			_check(boss.current_health == health - 10 and is_zero_approx(boss.abilities.shield_health), "shield overflow / DOT Lv%d" % tier)
			_check(not boss.abilities.effects.shield_sparks.emitting and not boss.abilities.effects.shield_bolts.emitting, "shield particles stop when broken Lv%d" % tier)
			boss.take_damage(1)
			_check(is_zero_approx(boss.abilities.shield_health), "shield cannot reactivate Lv%d" % tier)
		boss.stop()
		boss.queue_free()
	# Настоящий WaveManager: призыв, та же дорога, награда, ожидание свиты.
	var manager: WaveManager = game.wave_manager
	manager.phase = WaveManager.Phase.FIGHTING
	manager.wave_number = 20
	var caster: ApproachingEnemy = _spawn(game, "boss", 4)
	caster.follow_route(game.battlefield.route.curve, game.battlefield.route.global_transform, float(game.battlefield.route.get_meta("cell_size", 140.0)))
	caster._distance = 200.0
	manager._active.append(caster)
	caster.resolved.connect(manager._on_enemy_resolved)
	caster.retinue_requested.connect(manager._on_retinue_requested)
	caster.take_damage(caster.max_health * 0.5)
	caster.abilities.advance(1.0)
	_check(manager.active_count() == 1, "retinue waits for cast animation")
	caster.abilities.advance(0.6)
	_check(manager.active_count() == 3, "exactly two retinue enemies")
	for enemy: ApproachingEnemy in manager._active:
		enemy.set_physics_process(false)
		if enemy != caster:
			_check(enemy.stats.enemy_type == &"orc" and enemy.difficulty_tier == 2 and enemy._route == caster._route and enemy._distance < caster._distance, "retinue Lv2 / caster route")
			_check(enemy.get_node_or_null("EnemyRetinueArrival") != null and is_zero_approx(enemy._animated_visual.modulate.a), "retinue appears inside summon flash")
	var starting_mana: int = game.summon_manager.mana
	caster.take_damage(100000)
	_check(manager.phase == WaveManager.Phase.FIGHTING and manager.active_count() == 2, "boss death waits for retinue")
	var remaining: Array[ApproachingEnemy] = manager._active.duplicate()
	for enemy: ApproachingEnemy in remaining:
		enemy.take_damage(100000)
	_check(manager.phase == WaveManager.Phase.UPGRADE_CHOICE and manager.active_count() == 0, "upgrade only after full wave")
	_check(game.summon_manager.mana == starting_mana + 260, "one boss reward plus 2x10 retinue mana")
	manager.stop()
	game.get_tree().paused = false
	# Если пороги пересечены одним ударом: щит, призыв, затем натиск.
	var final_boss: ApproachingEnemy = _spawn(game, "boss", 5)
	var order: Array[StringName] = []
	final_boss.abilities.started.connect(func(ability: StringName) -> void: order.append(ability))
	final_boss.take_damage(final_boss.max_health * 0.8)
	_check(order == [&"shield"], "shield first on combined thresholds")
	final_boss.abilities.advance(1.0)
	_check(order == [&"shield", &"summon"], "summon second")
	final_boss.abilities.advance(1.0)
	_check(order == [&"shield", &"summon", &"rush"] and not final_boss.abilities.rushing, "rush third, telegraph first")
	final_boss.abilities.advance(0.35)
	_check(final_boss.abilities.rushing and is_equal_approx(final_boss.current_move_speed(), final_boss.move_speed * 1.4), "final rush boost")
	final_boss.stop()
	final_boss.abilities.advance(10.0)
	_check(not final_boss.abilities.rushing and final_boss.abilities._queue.is_empty(), "stop cancels pending abilities")
	final_boss.queue_free()
	game.get_tree().call_group(&"enemy_visual_tails", &"queue_free")
	return {"checks":_checks, "failures":_failures, "ok":_failures.is_empty()}
