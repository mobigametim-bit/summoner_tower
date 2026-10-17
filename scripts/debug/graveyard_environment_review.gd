extends Node

var _callback: JavaScriptObject
@onready var game: Node2D = $Game


func _ready() -> void:
	for index: int in 3:
		game.summon_manager.try_summon()
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(_command)
		JavaScriptBridge.get_interface("window").graveyardEnvironment = _callback


func _command(args: Array) -> void:
	var action: String = str(args[0]) if not args.is_empty() else "snapshot"
	match action:
		"map": _on_map_pressed()
		"summon": _on_summon_pressed()
		"boss": _on_boss_pressed()
		"clear":
			while game.wave_manager._spawn_remaining > 0 and game.wave_manager.phase == WaveManager.Phase.FIGHTING:
				game.wave_manager._spawn_enemy()
			for enemy: ApproachingEnemy in game.wave_manager._active.duplicate():
				enemy.take_damage(1000000000.0, false, false)
		"choose": game._on_upgrade_chosen(0)
		"freeze": game.wave_manager.stop()
		"tap": game.tower.tower_visual.show_tap()
		"refund": game.tower.tower_visual.show_refund()
		"hit": game.tower.take_damage(1)
		"destroy": game.tower.take_damage(game.tower.current_health)
	JavaScriptBridge.get_interface("window").graveyardEnvironmentJSON = JSON.stringify(snapshot())


func _on_map_pressed() -> void:
	if game.state != game.State.RUNNING:
		return
	game.wave_manager.stop()
	game._renew_battlefield()
	game.wave_manager.wave_number = 0
	game.wave_manager.start()


func _on_summon_pressed() -> void:
	game.summon_manager.add_mana(100)
	game._on_summon_requested()


func _on_boss_pressed() -> void:
	if game.state != game.State.RUNNING:
		return
	game.wave_manager.stop()
	game.wave_manager.wave_number = 5
	game.wave_manager.phase = WaveManager.Phase.FIGHTING
	game.wave_manager._begin_wave()


func snapshot() -> Dictionary:
	var field: Battlefield = game.battlefield
	var ground: BattlefieldCell = field.cells.get_child(0)
	var slots: Array = []
	for slot: SummonSlot in game.summon_manager._slots:
		slots.append({"position":[slot.global_position.x,slot.global_position.y],"empty":slot.is_empty()})
	return {"grid":[field.layout.grid_size.x,field.layout.grid_size.y],
		"ground":ground.fill.texture.resource_path,"road":field.road_surface.texture.resource_path,
		"portal":field.portal.texture.resource_path,"portals":field.layout.portal_cells.size(),
		"decoration_count":field.decorations.get_child_count(),"decoration_types":field.config.decoration_textures.size(),
		"slots":slots,"wave":game.wave_manager.wave_number,"map_changes":game.map_changes,
		"state":game.state,"health":game.tower.current_health,"mana":game.summon_manager.mana,
		"tower":game.tower.tower_visual.scene_file_path,"tower_instance":game.tower.tower_visual.get_instance_id(),
		"tower_animation":str(game.tower.tower_visual._active_animation),
		"occupied":game.summon_manager.occupied_count(),"choice":game.upgrade_choice.visible}


func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").graveyardEnvironment = null
