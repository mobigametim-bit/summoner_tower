extends "res://scripts/game/game_manager.gd"

@export_enum("goblin", "orc", "golem", "boss") var review_enemy: String = "boss"
@export_range(1, 5, 1) var review_tier: int = 5
var _snapshot_callback: JavaScriptObject
var _command_callback: JavaScriptObject
var _events: Array[Dictionary] = []
var _subject: ApproachingEnemy


func _ready() -> void:
	super._ready()
	wave_manager.stop()
	if OS.has_feature("web"):
		var kind: String = str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('enemy') || 'boss'", true))
		if kind in ["goblin", "orc", "golem", "boss"]:
			review_enemy = kind
		review_tier = clampi(int(JavaScriptBridge.eval("Number(new URL(location.href).searchParams.get('tier')) || 5", true)), 1, 5)
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		_command_callback = JavaScriptBridge.create_callback(_web_command)
		JavaScriptBridge.get_interface("window").getEnemyAbilitiesReview = _snapshot_callback
		JavaScriptBridge.get_interface("window").enemyAbilitiesCommand = _command_callback
	wave_manager.wave_number = review_tier * 5 if review_enemy == "boss" else 11
	wave_manager.phase = WaveManager.Phase.FIGHTING
	var path: String = "res://scenes/%s.tscn" % ("enemy" if review_enemy == "goblin" else review_enemy)
	_subject = load(path).instantiate() as ApproachingEnemy
	wave_manager._active.append(_subject)
	_subject.resolved.connect(wave_manager._on_enemy_resolved)
	_subject.retinue_requested.connect(wave_manager._on_retinue_requested)
	enemies.add_child(_subject)
	_subject.configure(spawn_point.global_position, contact_point.global_position.y, _subject.stats.base_health * (1 << (review_tier - 1)), review_tier)
	_subject.follow_route(battlefield.route.curve, battlefield.route.global_transform, float(battlefield.route.get_meta("cell_size", 140.0)))
	_subject._distance = 160.0
	_subject.global_position = battlefield.route.global_transform * battlefield.route.curve.sample_baked(_subject._distance)
	_subject.abilities.started.connect(_record_ability)
	wave_manager._emit_state()
	$Review/Controls/Title.text = "%s Lv%d" % [review_enemy.capitalize(), review_tier]
	if OS.has_feature("web"):
		var load_count: int = clampi(int(JavaScriptBridge.eval("Number(new URL(location.href).searchParams.get('load')) || 0", true)), 0, 80)
		_setup_load_review(load_count)


func _setup_load_review(count: int) -> void:
	for index: int in count:
		var packed: PackedScene = [wave_manager.config.goblin_scene, wave_manager.config.orc_scene, wave_manager.config.golem_scene][index % 3]
		var enemy: ApproachingEnemy = packed.instantiate() as ApproachingEnemy
		wave_manager._active.append(enemy)
		enemy.resolved.connect(wave_manager._on_enemy_resolved)
		enemies.add_child(enemy)
		enemy.configure(spawn_point.global_position, contact_point.global_position.y, enemy.stats.base_health * 16)
		enemy.follow_route(battlefield.route.curve, battlefield.route.global_transform, float(battlefield.route.get_meta("cell_size", 140.0)))
		enemy._distance = float(index) / maxf(float(count), 1.0) * 500.0
		enemy.global_position = battlefield.route.global_transform * battlefield.route.curve.sample_baked(enemy._distance)
		if enemy.stats.enemy_type == &"orc":
			enemy.take_damage(enemy.max_health * 0.5)


func _record_ability(ability: StringName) -> void:
	_events.append({"ability":str(ability), "time":Time.get_ticks_msec()})


func _on_hit() -> void:
	if is_instance_valid(_subject) and _subject.is_targetable() and state == State.RUNNING:
		_subject.take_damage(float(_subject.max_health) * 0.25)


func _on_burn() -> void:
	if is_instance_valid(_subject) and _subject.is_targetable() and state == State.RUNNING:
		_subject.apply_burn(float(_subject.max_health) * 0.2, 2.0)


func _on_slow() -> void:
	if is_instance_valid(_subject) and _subject.is_targetable() and state == State.RUNNING:
		_subject.apply_slow(0.5, 3.0)


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _web_command(arguments: Array) -> void:
	if arguments.is_empty():
		return
	match str(arguments[0]):
		"hit": _on_hit()
		"burn": _on_burn()
		"slow": _on_slow()
		"restart": _on_restart()
		"quarter":
			if is_instance_valid(_subject) and _subject.is_targetable():
				_subject.take_damage(float(_subject.max_health) * 0.8)
		"kill":
			for enemy: ApproachingEnemy in wave_manager._active.duplicate():
				enemy.take_damage(1000000)
		"effects_off":
			for enemy: ApproachingEnemy in wave_manager._active:
				enemy.abilities.effects.clear()
				enemy.abilities.effects.hide()
		"static":
			for enemy: ApproachingEnemy in wave_manager._active:
				enemy.set_animated_visual(false)


func _publish_snapshot(_arguments: Array) -> void:
	var active: Array[Dictionary] = []
	for enemy: ApproachingEnemy in wave_manager._active:
		if not is_instance_valid(enemy) or not enemy.is_targetable():
			continue
		active.append({"type":str(enemy.stats.enemy_type), "tier":enemy.difficulty_tier,
			"health":enemy.current_health, "max_health":enemy.max_health, "speed":enemy.current_move_speed(),
			"shield":enemy.abilities.shield_health, "armor":enemy.abilities.armor_remaining,
			"rage":enemy.abilities.raging, "rush":enemy.abilities.rushing, "dash":enemy.abilities._dash_remaining,
			"retinue":bool(enemy.get_meta("retinue", false)), "distance":enemy._distance,
			"particles":enemy.abilities.effects.aura_particles.emitting,
			"shield_particles":enemy.abilities.effects.shield_sparks.emitting,
			"lightning":enemy.abilities.effects.shield_bolts.emitting,
			"armor_y":enemy.abilities.effects.armor_y, "hp_top":enemy.health_bar.position.y,
			"arrival":enemy.get_node_or_null("EnemyRetinueArrival") != null,
			"visual_alpha":enemy._animated_visual.modulate.a,
			"animation":str(enemy._animated_visual.animation_player.assigned_animation),
			"position":[enemy.global_position.x, enemy.global_position.y]})
	JavaScriptBridge.eval("window.enemyAbilitiesReview = %s" % JSON.stringify({"active":active,
		"events":_events, "phase":wave_manager.phase, "state":state, "fps":Engine.get_frames_per_second(),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"mana":summon_manager.mana, "wave":wave_manager.wave_number, "kills":run_statistics.killed_enemies}), true)


func _exit_tree() -> void:
	if _snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getEnemyAbilitiesReview = null
		JavaScriptBridge.get_interface("window").enemyAbilitiesCommand = null
	super._exit_tree()
