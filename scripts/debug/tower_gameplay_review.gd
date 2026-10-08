extends "res://scripts/game/game_manager.gd"

@export var review_summon_seed: int = 23

@onready var animated_button: CheckButton = $Interface/TowerReview/Animated
@onready var pause_button: Button = $Interface/TowerReview/Pause

var _web_snapshot_callback: JavaScriptObject
var _events: Array[Dictionary] = []
var _last_health: int = 0


func _ready() -> void:
	if OS.has_feature("web"):
		var columns: int = int(JavaScriptBridge.eval("Number(new URL(window.location.href).searchParams.get('columns')) || 0", true))
		if columns >= 6 and columns <= 8:
			battlefield_columns = columns
	super._ready()
	tower.set_animated_visual(true)
	animated_button.set_pressed_no_signal(true)
	summon_manager.set_random_seed(review_summon_seed)
	_last_health = tower.current_health
	tower.summon_requested.connect(_record_tap)
	tower.health_changed.connect(_record_health)
	summon_manager.unit_refunded.connect(_record_refund)
	if OS.has_feature("web"):
		# Только чтение состояния из development preview; команд в обычной игре нет.
		_web_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getTowerReview = _web_snapshot_callback
		if bool(JavaScriptBridge.eval("new URL(window.location.href).searchParams.get('contact_test') === '1'", true)):
			_setup_contact_test()


func _setup_contact_test() -> void:
	# Только fixture: две существующие Boss entity проходят последние метры дороги.
	wave_manager.stop()
	wave_manager.phase = WaveManager.Phase.FIGHTING
	for index: int in 2:
		var enemy: ApproachingEnemy = wave_manager.config.boss_scene.instantiate() as ApproachingEnemy
		wave_manager._active.append(enemy)
		enemy.resolved.connect(wave_manager._on_enemy_resolved)
		enemies.add_child(enemy)
		enemy.configure(spawn_point.global_position, contact_point.global_position.y)
		enemy.follow_route(battlefield.route.curve, battlefield.route.global_transform, battlefield.layout.cell_size)
		var distance: float = maxf(battlefield.route.curve.get_baked_length() - 90.0 * float(index + 1), 0.0)
		enemy._distance = distance
		enemy.global_position = battlefield.route.global_transform * battlefield.route.curve.sample_baked(distance)


func _on_animated_toggled(enabled: bool) -> void:
	drag_controller.cancel_drag()
	animated_button.text = "ANIMATED" if enabled else "STATIC"
	tower.set_animated_visual(enabled)


func _on_review_pause() -> void:
	if state != State.RUNNING:
		return
	get_tree().paused = not get_tree().paused
	pause_button.icon = load("res://assets/debug/animation_controls/play.svg" if get_tree().paused else "res://assets/debug/animation_controls/pause.svg")


func _record_tap() -> void:
	_record_event("tap")


func _record_refund(amount: int) -> void:
	_record_event("refund", amount)


func _record_health(current: int, _maximum: int) -> void:
	if current < _last_health:
		_record_event("destroyed" if current == 0 else "hit")
	_last_health = current


func _record_event(kind: String, amount: int = 0) -> void:
	_events.append({"kind": kind, "amount": amount, "mana": summon_manager.mana, "health": tower.current_health,
		"active": str(tower.tower_visual.get("_active_animation")), "pending": str(tower.tower_visual.get("_pending_reaction")),
		"frame": Engine.get_physics_frames()})
	if _events.size() > 32:
		_events.pop_front()


func _publish_snapshot(_arguments: Array) -> void:
	var slots: Array[Dictionary] = []
	for slot: SummonSlot in summon_manager._slots:
		slots.append({"position": [slot.global_position.x, slot.global_position.y],
			"type": "" if slot.is_empty() else str(slot.unit.stats.unit_type),
			"paid_mana": 0 if slot.is_empty() else slot.unit.paid_mana})
	var player: AnimationPlayer = tower.tower_visual.animation_player
	var label: Label = tower.cost_label
	var base_bottom: Vector2 = tower.tower_visual.to_global(Vector2(0.0, TowerVisual.BASE_BOTTOM_Y - TowerVisual.CANVAS_SIZE * 0.5))
	var snapshot: Dictionary = {
		"slots": slots, "mana": summon_manager.mana, "cost": summon_manager.current_cost(),
		"summons": summon_manager.successful_summons, "state": state, "wave": wave_manager.wave_number,
		"health": tower.current_health, "max_health": tower.max_health, "kills": run_statistics.killed_enemies,
		"tower": [tower.global_position.x, tower.global_position.y], "base_bottom_y": base_bottom.y,
		"cost_label": [label.global_position.x, label.global_position.y, label.size.x, label.size.y],
		"cost_color": str(label.modulate * tower.modulate), "cost_z": label.z_index, "disabled": tower.summon_button.disabled,
		"animated": tower.animated_visual_enabled, "static_visible": tower.static_visual.visible,
		"animated_visible": tower.tower_visual.visible, "animation": str(tower.tower_visual.get("_active_animation")),
		"visual_frame": player.current_animation_position, "pending": str(tower.tower_visual.get("_pending_reaction")),
		"body_color": str(tower.tower_visual.get_node("BodyPivot/Body").self_modulate),
		"paused": get_tree().paused, "events": _events, "active": wave_manager.active_count(),
		"projectiles": projectiles.get_child_count(), "drag_visible": drag_controller.preview.visible,
		"columns": battlefield.layout.grid_size.x, "canvas_size": tower.tower_visual.scale.y * TowerVisual.CANVAS_SIZE,
		"fps": Engine.get_frames_per_second(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"controls": {"animated": _center(animated_button), "pause": _center(pause_button)}
	}
	JavaScriptBridge.eval("window.towerReview = %s;" % JSON.stringify(snapshot), true)


func _center(control: Control) -> Array[float]:
	var center: Vector2 = control.get_global_rect().get_center()
	return [center.x, center.y]


func _exit_tree() -> void:
	if _web_snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getTowerReview = null
		JavaScriptBridge.get_interface("window").towerReview = null
	super._exit_tree()
