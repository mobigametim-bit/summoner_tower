extends "res://scripts/game/game_manager.gd"

@export var review_summon_seed: int = 10
@export var review_battlefield_seed: int = 101

@onready var animated_button: CheckButton = $Interface/MageReview/Animated
@onready var pause_button: Button = $Interface/MageReview/Pause

var _animated: bool = true
var _web_snapshot_callback: JavaScriptObject
var _seen_mages: Dictionary = {}


func _ready() -> void:
	# Review работает и с классической ареной, где такого свойства нет.
	for property: Dictionary in get_property_list():
		if property.name == &"battlefield_seed":
			set("battlefield_seed", review_battlefield_seed)
			break
	super._ready()
	# Первые два призыва — Mage; production pool и его веса остаются прежними.
	summon_manager.set_random_seed(review_summon_seed)
	summon_manager.state_changed.connect(_on_review_state_changed)
	animated_button.set_pressed_no_signal(_animated)
	if OS.has_feature("web"):
		_web_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getMageReview = _web_snapshot_callback


func _on_review_state_changed(_mana: int, _cost: int, _occupied: int, _capacity: int, _available: bool) -> void:
	_refresh_mages()


func _refresh_mages() -> void:
	for slot: SummonSlot in summon_manager._slots:
		if slot.is_empty() or slot.unit.stats.unit_type != &"mage":
			continue
		var id: int = slot.unit.get_instance_id()
		if slot.unit.animated_visual_enabled != _animated:
			slot.unit.set_animated_visual(_animated, not _seen_mages.has(id))
		_seen_mages[id] = true


func _on_animated_toggled(enabled: bool) -> void:
	_animated = enabled
	animated_button.text = "ANIMATED" if enabled else "STATIC"
	drag_controller.cancel_drag()
	_refresh_mages()


func _on_review_pause() -> void:
	if state != State.RUNNING:
		return
	get_tree().paused = not get_tree().paused
	pause_button.icon = load("res://assets/debug/animation_controls/play.svg" if get_tree().paused else "res://assets/debug/animation_controls/pause.svg")


func _on_review_restart() -> void:
	_stop_encounter()
	get_tree().reload_current_scene()


func _publish_snapshot(_arguments: Array) -> void:
	var slots: Array[Dictionary] = []
	for slot: SummonSlot in summon_manager._slots:
		var row: Dictionary = {"position":[slot.global_position.x,slot.global_position.y],"type":"","level":0,"animated":false}
		if not slot.is_empty():
			var unit: CombatUnit = slot.unit
			row.merge({"type":str(unit.stats.unit_type),"level":unit.stats.level,"paid_mana":unit.paid_mana,"animated":unit.animated_visual_enabled},true)
			if unit.mage_visual != null:
				row["animation"] = str(unit.mage_visual.animation_player.current_animation)
				row["frame"] = unit.mage_visual.animation_player.current_animation_position
				row["glow"] = unit.mage_visual.release_point.get_node("Energy").modulate.a
		slots.append(row)
	var snapshot: Dictionary = {
		"slots":slots,"mana":summon_manager.mana,"cost":summon_manager.current_cost(),
		"state":state,"merges":run_statistics.merges,"kills":run_statistics.killed_enemies,
		"wave":wave_manager.wave_number,"projectiles":projectiles.get_child_count(),
		"tower":[tower.global_position.x,tower.global_position.y],
		"drag_visible":drag_controller.preview.visible,"animated":_animated,"paused":get_tree().paused,
		"fps":Engine.get_frames_per_second()
	}
	JavaScriptBridge.eval("window.mageReview = %s;" % JSON.stringify(snapshot),true)


func _exit_tree() -> void:
	if _web_snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getMageReview = null
		JavaScriptBridge.get_interface("window").mageReview = null
	super._exit_tree()
