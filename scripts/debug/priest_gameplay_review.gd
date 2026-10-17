extends "res://scripts/debug/graveyard_combat_review.gd"

var priest_level: int = 5


func _ready() -> void:
	super._ready()
	$ArmyReview/Panel.hide()
	if _is_fixture:
		select_priest_level(priest_level)
	else:
		$PriestReview/Panel.hide()
	if OS.has_feature("web") and str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('biome') || ''")) == "forest":
		use_forest()


func select_priest_level(value: int) -> void:
	priest_level = clampi(value,1,5)
	get_tree().paused = false
	reset_fixture()
	summon_manager._running = true
	summon_manager.set_interaction_enabled(true)
	wave_manager.stop()
	wave_manager.phase = WaveManager.Phase.FIGHTING
	wave_manager.suspend_completion(true)
	var route: Curve2D = battlefield.route.curve
	var distance: float = route.get_baked_length()*0.4
	var point: Vector2 = battlefield.route.global_transform*route.sample_baked(distance)
	summon_manager._slots.sort_custom(func(a: SummonSlot,b: SummonSlot) -> bool:
		return a.global_position.distance_squared_to(point) < b.global_position.distance_squared_to(point))
	var slot: SummonSlot = summon_manager._slots[0]
	distance = route.get_closest_offset(battlefield.route.to_local(slot.global_position))
	for offset: float in [-45.0,0.0,45.0]:
		var enemy: ApproachingEnemy = spawn_subject("zombie",1,distance+offset)
		enemy.max_health = 12000
		enemy.current_health = 12000
		enemy.move_speed = 0.0
		enemy._update_health_bar()
		subject = enemy
	summon_manager.grant_unit(load("res://scenes/priest.tscn"),load("res://resources/balance/priest_lv%d.tres"%priest_level))
	for tier: int in range(1,6):
		get_node("PriestReview/Panel/Level%d"%tier).set_pressed_no_signal(tier == priest_level)
	hud.boss_warning.stop_warning()


func add_support() -> void:
	summon_manager.grant_unit(load("res://scenes/archer.tscn"),load("res://resources/balance/archer_lv3.tres"))


func add_priest() -> void:
	summon_manager.grant_unit(load("res://scenes/priest.tscn"),load("res://resources/balance/priest_lv%d.tres"%priest_level))


func use_forest() -> void:
	var initial_mana: int = summon_manager.mana
	wave_manager.stop()
	biome = SessionProgress.biome_catalog.find(&"forest")
	SessionProgress.selected_biome_id = &"forest"
	wave_manager.config = biome.wave_config
	battlefield.config = biome.battlefield_config
	_renew_battlefield()
	summon_manager.mana = initial_mana
	summon_manager._emit_state()
	if _is_fixture:
		select_priest_level(priest_level)
	else:
		wave_manager.wave_number = 0
		wave_manager.start()


func snapshot() -> Dictionary:
	var result: Dictionary = super.snapshot()
	var units: Array[Dictionary] = []
	var slots: Array[Dictionary] = []
	for slot: SummonSlot in summon_manager._slots:
		var row: Dictionary = {"x":slot.global_position.x,"y":slot.global_position.y,"empty":slot.is_empty()}
		if not slot.is_empty():
			var unit: CombatUnit = slot.unit
			row["type"] = str(unit.stats.unit_type)
			row["lv"] = unit.stats.level
			units.append({"type":str(unit.stats.unit_type),"lv":unit.stats.level,"paid":unit.paid_mana,"range":unit.effective_attack_range(),"x":unit.global_position.x,"y":unit.global_position.y})
		slots.append(row)
	var marks: Array[Dictionary] = []
	for enemy: ApproachingEnemy in wave_manager._active:
		if is_instance_valid(enemy) and enemy.is_targetable():
			marks.append({"ratio":enemy.light_mark_ratio,"remaining":enemy.light_mark_remaining,"visual":is_instance_valid(enemy._light_mark_visual)})
	result.merge({"units":units,"slots":slots,"marks":marks,"priest_level":priest_level,"power":_player_power(),"pool_weights":summon_manager.pool.weights,"tower_x":tower.global_position.x,"tower_y":tower.global_position.y,"drag":drag_controller._dragging,"range_visible":drag_controller.attack_range_preview.visible,"range_radius":drag_controller.attack_range_preview.radius,"merge_visible":drag_controller.merge_range_preview.visible,"merge_radius":drag_controller.merge_range_preview.radius},true)
	return result


func _web_command(args: Array) -> void:
	var action: String = str(args[0]) if not args.is_empty() else "snapshot"
	match action:
		"priest": select_priest_level(int(args[1]))
		"support": add_support()
		"add_priest": add_priest()
		"forest": use_forest()
		_:
			super._web_command(args)
			return
	JavaScriptBridge.get_interface("window").graveyardCombatJSON = JSON.stringify(snapshot())
