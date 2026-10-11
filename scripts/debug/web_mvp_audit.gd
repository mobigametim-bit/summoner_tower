extends Node
## Только чтение состояния отдельной проверочной Web-сборки; в production Autoload отсутствует.

var _callback: JavaScriptObject


func _ready() -> void:
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(_snapshot)
		JavaScriptBridge.get_interface("window").getWebMvpAudit = _callback


func _rect(control: Control) -> Array:
	var value: Rect2 = control.get_global_rect()
	return [value.position.x, value.position.y, value.size.x, value.size.y]


func _snapshot(_arguments: Array) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var controls: Dictionary = {}
	var labels: Dictionary = {}
	for node: Node in scene.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree():
			continue
		var path: String = str(scene.get_path_to(control))
		if control is BaseButton:
			controls[path] = {"rect": _rect(control), "disabled": control.disabled}
		elif control is Range:
			controls[path] = {"rect": _rect(control), "value": control.value}
		elif control is Label:
			labels[path] = {"rect": _rect(control), "text": control.text}
	var snapshot: Dictionary = {
		"scene": scene.scene_file_path, "controls": controls, "labels": labels,
		"paused": get_tree().paused, "frame": Engine.get_process_frames(),
		"wallet": SessionProgress.crystals, "meta_levels": SessionProgress.upgrade_levels,
		"save_status": SessionProgress.save_manager.load_status,
		"audio": {"music": AudioService.music_volume, "effects": AudioService.effects_volume,
			"track": str(AudioService._music_name)},
		"perf": {"fps": Engine.get_frames_per_second(),
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"memory": Performance.get_monitor(Performance.MEMORY_STATIC)}
	}
	if scene.has_method("_player_power"):
		var slots: Array = []
		for slot: SummonSlot in scene.summon_manager._slots:
			slots.append({"position": [slot.global_position.x, slot.global_position.y],
				"type": "" if slot.is_empty() else str(slot.unit.stats.unit_type),
				"level": 0 if slot.is_empty() else slot.unit.stats.level,
				"paid": 0 if slot.is_empty() else slot.unit.paid_mana})
		var enemies: Array = []
		for enemy: ApproachingEnemy in scene.wave_manager._active:
			enemies.append({"type": str(enemy.stats.enemy_type), "hp": enemy.current_health,
				"max_hp": enemy.max_health, "portal": enemy.get_meta("portal_index", 0)})
		snapshot.merge({"state": scene.state, "wave": scene.wave_manager.wave_number,
			"drag": {"active": scene.drag_controller._dragging,
				"range_visible": scene.drag_controller.attack_range_preview.visible,
				"radius": scene.drag_controller.attack_range_preview.radius,
				"color": scene.drag_controller.attack_range_preview.level_color.to_html(),
				"position": [scene.drag_controller.attack_range_preview.global_position.x, scene.drag_controller.attack_range_preview.global_position.y]},
			"phase": scene.wave_manager.phase, "power": scene.wave_manager.power_summary,
			"hp": scene.tower.current_health, "max_hp": scene.tower.max_health,
			"mana": scene.summon_manager.mana, "cost": scene.summon_manager.current_cost(),
			"can_summon": scene.summon_manager.can_summon(), "slots": slots, "enemies": enemies,
			"tower": [scene.tower.global_position.x, scene.tower.global_position.y],
			"summons": scene.summon_manager.successful_summons,
			"map_changes": scene.map_changes, "seed": scene.battlefield.layout.seed_value,
			"portals": scene.battlefield.layout.paths.size(),
			"decor_probability": scene.battlefield.config.decoration_probability,
			"revive_used": scene.revive_used, "choice": scene.upgrade_choice.visible,
			"stats": {"killed": scene.run_statistics.killed_enemies,
				"bosses": scene.run_statistics.killed_bosses, "merges": scene.run_statistics.merges,
				"completed": scene.run_statistics.completed_waves, "earned": scene.run_statistics.earned_crystals,
				"doubled": scene.run_statistics.reward_doubled, "finished": scene.run_statistics.finished}})
	JavaScriptBridge.eval("window.webMvpAudit = %s;" % JSON.stringify(snapshot), true)
