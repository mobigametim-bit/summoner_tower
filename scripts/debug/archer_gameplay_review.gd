extends "res://scripts/game/game_manager.gd"

@export var review_summon_seed: int = 7

@onready var animated_button: CheckButton = $Interface/ArcherReview/Animated

var _animated: bool = true
var _web_snapshot_callback: JavaScriptObject


func _ready() -> void:
	super._ready()
	# Первые два призыва — Archer для воспроизводимой ручной проверки; веса пула прежние.
	summon_manager.set_random_seed(review_summon_seed)
	summon_manager.state_changed.connect(_on_review_state_changed)
	animated_button.set_pressed_no_signal(_animated)
	if OS.has_feature("web"):
		# Только чтение development preview: не добавляет команд в обычную игру.
		_web_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getArcherReview = _web_snapshot_callback


func _on_animated_toggled(enabled: bool) -> void:
	_animated = enabled
	animated_button.text = "ANIMATED" if enabled else "STATIC"
	drag_controller.cancel_drag()
	_refresh_archers()


func _on_review_state_changed(_mana: int, _cost: int, _occupied: int, _capacity: int, _available: bool) -> void:
	_refresh_archers()


func _refresh_archers() -> void:
	for slot: SummonSlot in summon_manager._slots:
		if slot.is_empty() or slot.unit.stats.unit_type != &"archer":
			continue
		if slot.unit.animated_visual_enabled != _animated:
			slot.unit.set_animated_visual(_animated)


func _publish_snapshot(_arguments: Array) -> void:
	var slots: Array[Dictionary] = []
	for slot: SummonSlot in summon_manager._slots:
		var row: Dictionary = {
			"position": [slot.global_position.x, slot.global_position.y],
			"type": "", "level": 0, "animated": false
		}
		if not slot.is_empty():
			row["type"] = str(slot.unit.stats.unit_type)
			row["level"] = slot.unit.stats.level
			row["animated"] = slot.unit.animated_visual_enabled
			row["paid_mana"] = slot.unit.paid_mana
		slots.append(row)
	var snapshot: Dictionary = {
		"slots": slots, "mana": summon_manager.mana, "cost": summon_manager.current_cost(),
		"state": state, "merges": run_statistics.merges, "kills": run_statistics.killed_enemies,
		"wave": wave_manager.wave_number, "projectiles": projectiles.get_child_count(),
		"tower": [tower.global_position.x, tower.global_position.y],
		"drag_visible": drag_controller.preview.visible, "animated": _animated
	}
	JavaScriptBridge.eval("window.archerReview = %s;" % JSON.stringify(snapshot), true)


func _exit_tree() -> void:
	if _web_snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getArcherReview = null
		JavaScriptBridge.get_interface("window").archerReview = null
	super._exit_tree()
