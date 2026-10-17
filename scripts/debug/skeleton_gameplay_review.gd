extends "res://scripts/game/game_manager.gd"

@export var skeleton_scene: PackedScene
@export_range(1,5,1) var review_level: int = 5
var subject: ApproachingEnemy
var outcomes: Array[Dictionary] = []
var _callback: JavaScriptObject


func _ready() -> void:
	SessionProgress.use_test_save()
	AudioService.settings_store = AudioSettingsStore.new("")
	$World/Battlefield.config = load("res://resources/biomes/graveyard_battlefield.tres")
	super._ready()
	reset_review()
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(_web_command)
		JavaScriptBridge.get_interface("window").skeletonReview = _callback


func reset_review() -> void:
	wave_manager.stop()
	get_tree().call_group(&"enemy_visual_tails",&"queue_free")
	for projectile: Node in projectiles.get_children():
		projectile.queue_free()
	for slot: SummonSlot in summon_manager._slots:
		if not slot.is_empty():
			var unit: CombatUnit = slot.unit
			slot.assign_unit(null)
			unit.stop()
			unit.queue_free()
	state = State.RUNNING
	tower.initialize(100)
	summon_manager.mana = 100
	summon_manager._emit_state()
	wave_manager.wave_number = 1
	wave_manager.phase = WaveManager.Phase.FIGHTING
	wave_manager.suspend_completion(true)
	outcomes.clear()
	spawn_skeleton()


func spawn_skeleton(at_start: bool = false) -> void:
	subject = skeleton_scene.instantiate() as ApproachingEnemy
	wave_manager._active.append(subject)
	subject.resolved.connect(_record_outcome)
	subject.resolved.connect(wave_manager._on_enemy_resolved)
	enemies.add_child(subject)
	subject.configure(spawn_point.global_position,contact_point.global_position.y,subject.stats.base_health*(1<<(review_level-1)))
	subject.follow_route(battlefield.route.curve,battlefield.route.global_transform,float(battlefield.route.get_meta("cell_size",140.0)))
	if not at_start:
		subject._distance = battlefield.route.curve.get_baked_length()*0.43
		subject.global_position = battlefield.route.to_global(battlefield.route.curve.sample_baked(subject._distance))


func _record_outcome(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void:
	outcomes.append({"outcome":outcome,"tier":enemy.difficulty_tier,"mana":enemy.stats.kill_mana_for(enemy.max_health),"impact":enemy.undead_visual.get("_impact_emitted"),"targetable":enemy.is_targetable()})


func select_level(value: int) -> void:
	review_level = clampi(value,1,5)
	reset_review()


func hit() -> void:
	if is_instance_valid(subject):
		subject.take_damage(subject.max_health*0.25)


func freeze() -> void:
	if is_instance_valid(subject):
		subject.apply_freeze(4.0)


func battle() -> void:
	reset_review()
	# The real summon, targeting and projectile systems run on an isolated save.
	for kind: String in ["archer","mage","frost_mage"]:
		summon_manager.grant_unit(load("res://scenes/%s.tscn"%kind),load("res://resources/balance/%s_lv3.tres"%kind))


func next_skeleton() -> void:
	spawn_skeleton(true)


func restart_review() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func snapshot() -> Dictionary:
	var result: Dictionary = {"tier":review_level,"mana":summon_manager.mana,"tower_health":tower.current_health,"active":wave_manager.active_count(),"outcomes":outcomes,"tails":get_tree().get_nodes_in_group(&"enemy_visual_tails").size(),"projectiles":projectiles.get_child_count(),"occupied":summon_manager.occupied_count(),"fps":Engine.get_frames_per_second(),"test_save":SessionProgress._test_session}
	if is_instance_valid(subject) and subject.is_targetable():
		var shield: SkeletonAbilities = subject.abilities as SkeletonAbilities
		result.merge({"health":subject.current_health,"max_health":subject.max_health,"speed":subject.current_move_speed(),"damage":subject.tower_damage,"shield":shield.shield_health,"shield_time":shield.shield_remaining,"shield_used":shield._half_triggered,"shield_vfx":is_instance_valid(subject.undead_visual.get("_shield")),"animation":str(subject.undead_visual.get_node("AnimationPlayer").assigned_animation),"position":[subject.global_position.x,subject.global_position.y],"distance":subject._distance,"head_rotation":subject.undead_visual.get_node("Skeleton2D/Root/Body/Head").rotation,"health_z":subject.health_bar.z_index})
	return result


func _process(_delta: float) -> void:
	var info: Dictionary = snapshot()
	$SkeletonReview/Panel/Readout.text = "Скелет Lv%d · ОЗ %d · Щит %d · Мана %d · Башня %d"%[review_level,info.get("health",0),int(info.get("shield",0)),info.mana,info.tower_health]


func _web_command(args: Array) -> void:
	var action: String = str(args[0]) if not args.is_empty() else "snapshot"
	match action:
		"level": select_level(int(args[1]))
		"hit": hit()
		"freeze": freeze()
		"battle": battle()
		"spawn": next_skeleton()
		"reset": reset_review()
		"kill":
			if is_instance_valid(subject):
				subject.take_damage(1000000)
		"contact":
			if is_instance_valid(subject) and subject.is_targetable():
				subject._distance = subject._route_length-25.0
		"pause": get_tree().paused = not get_tree().paused
	JavaScriptBridge.get_interface("window").skeletonReviewJSON = JSON.stringify(snapshot())


func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").skeletonReview = null
	super._exit_tree()
