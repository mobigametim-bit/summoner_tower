extends "res://scripts/game/game_manager.gd"

const TYPES: Array[String] = ["skeleton","zombie","ghoul","necromancer","flesh_golem","lich"]
@export var review_type: String = "necromancer"
@export var review_level: int = 5
var subject: ApproachingEnemy
var _callback: JavaScriptObject
var outcomes: Array[Dictionary] = []
var events: Array[String] = []
var _is_fixture: bool = true


func _ready() -> void:
	SessionProgress.use_test_save()
	SessionProgress.unlocked_biomes.assign(["forest","graveyard"])
	SessionProgress.selected_biome_id = &"graveyard"
	AudioService.settings_store = AudioSettingsStore.new("")
	super._ready()
	var start_run: bool = bool(SessionProgress.get_meta("graveyard_review_run",false))
	SessionProgress.remove_meta("graveyard_review_run")
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(_web_command)
		JavaScriptBridge.get_interface("window").graveyardCombat = _callback
		start_run = start_run or str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('mode') || ''")) == "run"
	if start_run:
		_is_fixture = false
		$ArmyReview/Panel.hide()
	else:
		$Interface/Hud/BottomDock.hide()
		reset_fixture()


func reset_fixture() -> void:
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
	wave_manager.wave_number = review_level*5 if review_type == "lich" else 1
	hud._last_announced_boss_wave = wave_manager.wave_number
	wave_manager.phase = WaveManager.Phase.FIGHTING
	wave_manager.suspend_completion(true)
	outcomes.clear()
	events.clear()
	$ArmyReview/Panel/Type.select(TYPES.find(review_type))
	for tier: int in range(1,6):
		var button: Button = get_node("ArmyReview/Panel/Level%d"%tier)
		button.disabled = review_type == "flesh_golem" and tier < 4
		button.set_pressed_no_signal(tier == review_level)
	subject = spawn_subject(review_type,review_level,battlefield.route.curve.get_baked_length()*0.3)


func spawn_subject(kind: String, tier: int, distance: float) -> ApproachingEnemy:
	var enemy: ApproachingEnemy = load("res://scenes/%s.tscn"%kind).instantiate() as ApproachingEnemy
	if kind == "flesh_golem":
		enemy.set_meta("visual_level",5 if tier == 5 else 4)
	wave_manager._active.append(enemy)
	enemy.resolved.connect(_record_outcome)
	enemy.resolved.connect(wave_manager._on_enemy_resolved)
	enemies.add_child(enemy)
	var health_tier: int = (2 if tier == 5 else 1) if kind == "flesh_golem" else tier
	enemy.configure(spawn_point.global_position,contact_point.global_position.y,enemy.stats.base_health*(1<<(health_tier-1)),tier)
	if kind == "flesh_golem" and tier == 5:
		enemy.move_speed = wave_manager.graveyard_army.config.flesh_fast_speed
	enemy.follow_route(battlefield.route.curve,battlefield.route.global_transform,float(battlefield.route.get_meta("cell_size",140.0)))
	enemy._distance = clampf(distance,0.0,enemy._route_length)
	enemy.global_position = enemy._route_transform*enemy._route.sample_baked(enemy._distance)
	wave_manager.graveyard_army.register(enemy)
	enemy.abilities.started.connect(_record_event)
	return enemy


func _record_outcome(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void:
	outcomes.append({"type":str(enemy.stats.enemy_type),"outcome":outcome,"mana":enemy.stats.kill_mana_for(enemy.max_health,enemy.difficulty_tier),"summoned":enemy.get_meta("summoned",false)})


func _record_event(event: StringName) -> void:
	events.append(str(event))


func select_type(index: int) -> void:
	review_type = TYPES[clampi(index,0,5)]
	if review_type == "flesh_golem":
		review_level = maxi(review_level,4)
	reset_fixture()


func select_level(value: int) -> void:
	review_level = clampi(value,4 if review_type == "flesh_golem" else 1,5)
	reset_fixture()


func hit() -> void:
	if is_instance_valid(subject) and subject.is_targetable():
		subject.take_damage(subject.max_health*0.25)


func demonstrate() -> void:
	if not is_instance_valid(subject) or not subject.is_targetable():
		reset_fixture()
	match review_type:
		"skeleton": subject.take_damage(subject.max_health*0.5)
		"zombie": subject.take_damage(subject.max_health*0.65)
		"ghoul": subject.abilities._dash_clock = 0.0
		"necromancer":
			var ally: ApproachingEnemy = spawn_subject("zombie",review_level,subject._distance+55)
			ally.take_damage(ally.max_health*0.5)
			for i: int in wave_manager.graveyard_army.config.corpse_count:
				var victim: ApproachingEnemy = spawn_subject("skeleton",1,subject._distance+20*(i-1))
				victim.take_damage(10000)
			subject.abilities.set("_heal_clock",0.0)
			subject.abilities.set("_summon_clock",0.6)
			subject.abilities.set("_flesh_clock",1.1)
		"lich":
			spawn_subject("skeleton",review_level,subject._distance+60)
			spawn_subject("zombie",review_level,subject._distance-60)
			subject.take_damage(subject.max_health*0.8)
		"flesh_golem": subject._distance = subject._route_length-60
	# The fixture inspects skills; the ordinary run keeps the accepted BOSS warning.
	hud.boss_warning.stop_warning()


func battle() -> void:
	reset_fixture()
	# Place the demo army near the subject, rather than on arbitrary distant branches.
	var point: Vector2 = subject.global_position
	summon_manager._slots.sort_custom(func(a: SummonSlot, b: SummonSlot) -> bool:
		return a.global_position.distance_squared_to(point) < b.global_position.distance_squared_to(point))
	for kind: String in ["archer","mage","frost_mage"]:
		summon_manager.grant_unit(load("res://scenes/%s.tscn"%kind),load("res://resources/balance/%s_lv3.tres"%kind))


func start_run() -> void:
	SessionProgress.set_meta("graveyard_review_run",true)
	restart()


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func snapshot() -> Dictionary:
	var active: Array[Dictionary] = []
	for enemy: ApproachingEnemy in wave_manager._active:
		if not is_instance_valid(enemy) or not enemy.is_targetable():
			continue
		var row: Dictionary = {"type":str(enemy.stats.enemy_type),"tier":enemy.difficulty_tier,"hp":enemy.current_health,"max":enemy.max_health,"speed":enemy.current_move_speed(),"damage":enemy.tower_damage,"mana":enemy.stats.kill_mana_for(enemy.max_health,enemy.difficulty_tier),"summoned":enemy.get_meta("summoned",false),"owner":enemy.get_meta("summoner_id",0),"shield":enemy.abilities.shield_health,"haste":enemy.abilities.haste_bonus,"x":enemy.global_position.x,"y":enemy.global_position.y}
		if enemy.abilities is GraveyardAbilities:
			row["cast"] = str((enemy.abilities as GraveyardAbilities)._cast)
		active.append(row)
	return {"active":active,"subject":review_type,"level":review_level,"wave":wave_manager.wave_number,"phase":wave_manager.phase,"state":state,"map_changes":map_changes,"mana":summon_manager.mana,"tower_health":tower.current_health,"events":events,"outcomes":outcomes,"corpses":wave_manager.graveyard_army._corpses.size(),"tails":get_tree().get_nodes_in_group(&"enemy_visual_tails").size(),"projectiles":projectiles.get_child_count(),"occupied":summon_manager.occupied_count(),"biome":str(biome.biome_id),"test_save":SessionProgress._test_session,"fixture":_is_fixture,"fps":Engine.get_frames_per_second(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"nodes":get_tree().get_node_count()}


func _process(_delta: float) -> void:
	if _is_fixture:
		$ArmyReview/Panel/Readout.text = "ОЗ %d · Щит %d · Мана %d"%[subject.current_health if is_instance_valid(subject) else 0,int(subject.abilities.shield_health) if is_instance_valid(subject) else 0,summon_manager.mana]


func _web_command(args: Array) -> void:
	var action: String = str(args[0]) if not args.is_empty() else "snapshot"
	match action:
		"type": select_type(int(args[1]))
		"level": select_level(int(args[1]))
		"hit": hit()
		"demo": demonstrate()
		"battle": battle()
		"run":
			start_run()
			return
		"restart":
			restart()
			return
		"pause": get_tree().paused = not get_tree().paused
		"wave":
			wave_manager.stop()
			wave_manager.wave_number = int(args[1])
			wave_manager.phase = WaveManager.Phase.FIGHTING
			wave_manager._begin_wave()
		"clear":
			while wave_manager._spawn_remaining > 0 and wave_manager.phase == WaveManager.Phase.FIGHTING:
				wave_manager._spawn_enemy()
			for enemy: ApproachingEnemy in wave_manager._active.duplicate():
				enemy.take_damage(10000000)
		"choose": _on_upgrade_chosen(0)
		"summon":
			summon_manager.add_mana(100)
			summon_manager.try_summon()
		"load":
			reset_fixture()
			for i: int in clampi(int(args[1]),1,60)-1:
				var enemy: ApproachingEnemy = spawn_subject(TYPES[i%4],5,float(i%10)*30.0)
				if enemy.stats.enemy_type in [&"skeleton",&"zombie"]:
					enemy.take_damage(enemy.max_health*0.65)
				elif enemy.stats.enemy_type == &"ghoul":
					enemy.abilities._dash_clock = 0.0
				else:
					enemy.abilities.set("_summon_clock",0.0)
	JavaScriptBridge.get_interface("window").graveyardCombatJSON = JSON.stringify(snapshot())


func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").graveyardCombat = null
	super._exit_tree()
