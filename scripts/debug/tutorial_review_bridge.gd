extends RefCounted

var tree: SceneTree
var callback: JavaScriptObject


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree
	callback = JavaScriptBridge.create_callback(_web_command)
	JavaScriptBridge.get_interface("window").tutorialReview = callback


func _web_command(arguments: Array) -> void:
	var command: String = str(arguments[0]) if not arguments.is_empty() else "snapshot"
	var current: Node = tree.current_scene
	var result: Dictionary = {}
	if command == "reset":
		Tutorial.progress.replay()
		tree.change_scene_to_file("res://scenes/debug/TutorialReview.tscn")
	elif command == "snapshot":
		result = snapshot(current)
	JavaScriptBridge.get_interface("window").tutorialSnapshot = JSON.stringify(result)


static func snapshot(current: Node) -> Dictionary:
	if not current.is_node_ready():
		return {"loading":true,"scene":current.scene_file_path}
	var result: Dictionary = {"lesson":Tutorial.active_id,"completed":Tutorial.progress.completed,
		"viewport":[current.get_viewport().get_visible_rect().size.x,current.get_viewport().get_visible_rect().size.y],
		"skipped":Tutorial.progress.skipped,"seen":Tutorial.progress.seen,
		"paused":current.get_tree().paused,"scene":current.scene_file_path,
		"next":_rect(Tutorial.overlay.next_button),"skip_button_exists":Tutorial.overlay.has_node("Panel/Margin/Stack/Actions/Skip"),
		"panel":_rect(Tutorial.overlay.panel)}
	if current.has_node("SummonManager"):
		var units: Array = []
		for slot: SummonSlot in current.summon_manager._slots:
			if not slot.is_empty():
				units.append({"type":String(slot.unit.stats.unit_type),"level":slot.unit.stats.level,
					"range":slot.unit.effective_attack_range(),"interval":slot.unit.effective_attack_interval(),"damage":slot.unit.stats.damage,
					"screen":[slot.unit.get_global_transform_with_canvas().origin.x,slot.unit.get_global_transform_with_canvas().origin.y],
					"paid":slot.unit.paid_mana,"position":[slot.global_position.x,slot.global_position.y]})
		result.merge({"mana":current.summon_manager.mana,"units":units,
			"grid":[current.battlefield.layout.grid_size.x,current.battlefield.layout.grid_size.y],
			"tower":_rect(current.tower.summon_button),"health":_rect(current.hud.health_label),"settings":_rect(current.hud.settings_button),
			"hud":_rect(current.hud.bottom_dock),
			"settings_open":current.hud.settings_overlay.visible,"settings_menu":_rect(current.get_node("%SettingsMenuButton")),
			"resume":_rect(current.hud.resume_button),
			"map_seed":current.battlefield.layout.seed_value,"slot_cells":str(current.battlefield.layout.slot_cells),
			"phase":current.wave_manager.phase,"wave":current.wave_manager.wave_number,
			"forced":current.summon_manager.tutorial_archers_remaining,
			"source":[Tutorial._first.get_global_transform_with_canvas().origin.x,Tutorial._first.get_global_transform_with_canvas().origin.y] if is_instance_valid(Tutorial._first) else [],
			"destination":[Tutorial._destination.get_global_transform_with_canvas().origin.x,Tutorial._destination.get_global_transform_with_canvas().origin.y] if is_instance_valid(Tutorial._destination) else [],
			"focus":[Tutorial.overlay.shade.focus_rect.position.x,Tutorial.overlay.shade.focus_rect.position.y,Tutorial.overlay.shade.focus_rect.size.x,Tutorial.overlay.shade.focus_rect.size.y]})
	elif current.has_method("_on_play_button_pressed"):
		result.merge({"play":_rect(current.play_button),"upgrades":_rect(current.upgrades_button),"settings":_rect(current.settings_button),"settings_open":current.settings_overlay.visible})
	elif current.has_node("Center/Stack/Scroll"):
		result.merge({"scroll":_rect(current.get_node("Center/Stack/Scroll")),"scroll_y":current.get_node("Center/Stack/Scroll").scroll_vertical,"back":_rect(current.back_button)})
	return result


static func _rect(control: Control) -> Array:
	var rect: Rect2 = control.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,control.size)
	return [rect.get_center().x,rect.get_center().y,rect.size.x,rect.size.y]
