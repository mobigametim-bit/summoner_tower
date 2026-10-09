extends "res://scripts/game/game_manager.gd"

@export var review_summon_seed: int = 23

@onready var animated_button: CheckButton = $Interface/TowerReview/Animated
@onready var pause_button: Button = $Interface/TowerReview/Pause

var _web_snapshot_callback: JavaScriptObject
var _events: Array[Dictionary] = []
var _last_health: int = 0
var _shake_started_count: int = 0


func _ready() -> void:
	if OS.has_feature("web"):
		var columns: int = int(JavaScriptBridge.eval("Number(new URL(window.location.href).searchParams.get('columns')) || 0", true))
		if columns >= 6 and columns <= 8:
			battlefield_columns = columns
		var portals: int = int(JavaScriptBridge.eval("Number(new URL(window.location.href).searchParams.get('portals')) || 0", true))
		if portals >= 1 and portals <= 3:
			battlefield_portal_count = portals
		var seed_value: int = int(JavaScriptBridge.eval("Number(new URL(window.location.href).searchParams.get('seed') || -1)", true))
		if seed_value >= 0:
			battlefield_seed = seed_value
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
		get_node("ScreenShake/GFFPlayer").effect_started.connect(_record_shake)
		if bool(JavaScriptBridge.eval("new URL(window.location.href).searchParams.get('contact_test') === '1'", true)):
			_setup_contact_test()
		if bool(JavaScriptBridge.eval("new URL(window.location.href).searchParams.get('merge_test') === '1'", true)):
			_setup_merge_particle_test()
		if bool(JavaScriptBridge.eval("new URL(window.location.href).searchParams.get('arrow_test') === '1'", true)):
			_setup_embedded_arrow_test()
		if bool(JavaScriptBridge.eval("new URL(window.location.href).searchParams.get('shake_test') === '1'", true)):
			_setup_shake_test()


func _setup_shake_test() -> void:
	_setup_boss_warning_test()
	wave_manager.spawn_timer.stop()
	tower.initialize(500)
	var archer_scene: PackedScene = load("res://scenes/archer.tscn")
	for index: int in 2:
		var unit: CombatUnit = archer_scene.instantiate() as CombatUnit
		unit.attack_enabled = false
		unit.paid_mana = 20
		summon_manager._slots[index].place_unit(unit)
		unit.configure(enemies, projectiles, run_bonuses)
	get_node("ShakeTestTimer").start()


func _on_shake_test_tick() -> void:
	if state == State.RUNNING:
		tower.take_damage(20)


func _record_shake(_effect_name: String) -> void:
	_shake_started_count += 1


func _setup_boss_warning_test() -> void:
	# Запускаем настоящую пятую волну, без циклического таймера декоративного превью.
	wave_manager.stop()
	wave_manager.wave_number = 5
	wave_manager.phase = WaveManager.Phase.FIGHTING
	wave_manager._begin_wave()


func _setup_embedded_arrow_test() -> void:
	# Development fixture: настоящие атаки Archer по четырём существующим типам врагов.
	wave_manager.stop()
	for enemy: Node in enemies.get_children():
		enemy.queue_free()
	var paths: Array[String] = ["res://scenes/enemy.tscn", "res://scenes/orc.tscn", "res://scenes/golem.tscn", "res://scenes/boss.tscn"]
	for index: int in paths.size():
		var slot: SummonSlot = summon_manager._slots[index]
		var enemy: ApproachingEnemy = (load(paths[index]) as PackedScene).instantiate() as ApproachingEnemy
		enemies.add_child(enemy)
		enemy.configure(slot.global_position + Vector2(70.0, -35.0), 1400.0, 500)
		enemy.move_speed = 0.0
		var unit: CombatUnit = (load("res://scenes/archer.tscn") as PackedScene).instantiate() as CombatUnit
		slot.place_unit(unit)
		unit.configure(enemies, projectiles, run_bonuses)


func _setup_merge_particle_test() -> void:
	# Четыре пары Lv1–Lv4 для проверки настоящего drag/merge в Web.
	wave_manager.stop()
	for enemy: Node in enemies.get_children():
		enemy.queue_free()
	var archer_scene: PackedScene = load("res://scenes/archer.tscn")
	for index: int in 8:
		var unit: CombatUnit = archer_scene.instantiate() as CombatUnit
		unit.stats = load("res://resources/balance/archer_lv%d.tres" % [1 + (index >> 1)])
		unit.attack_enabled = false
		unit.paid_mana = 20
		summon_manager._slots[index].place_unit(unit)
		unit.configure(enemies, projectiles, run_bonuses)


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
			"level": 0 if slot.is_empty() else slot.unit.stats.level,
			"alpha": 1.0 if slot.is_empty() else slot.unit.modulate.a,
			"rays": slot.summon_rays.emitting,
			"rays_color": [slot.summon_rays.modulate.r, slot.summon_rays.modulate.g, slot.summon_rays.modulate.b],
			"paid_mana": 0 if slot.is_empty() else slot.unit.paid_mana})
	var player: AnimationPlayer = tower.tower_visual.animation_player
	var label: Label = tower.cost_label
	var base_bottom: Vector2 = tower.tower_visual.to_global(Vector2(0.0, TowerVisual.BASE_BOTTOM_Y - TowerVisual.CANVAS_SIZE * 0.5))
	var snapshot: Dictionary = {
		"road_cells": battlefield.layout.road_cells.map(func(cell: Vector2i) -> Array: return [cell.x, cell.y]),
		"paths": battlefield.layout.paths.map(func(path: Array) -> Array: return path.map(func(cell: Vector2i) -> Array: return [cell.x, cell.y])),
		"portal_sides": battlefield.layout.portal_sides,
		"portal_positions": battlefield.layout.portal_cells.map(func(cell: Vector2i) -> Array: var p: Vector2 = battlefield.layout.cell_center(cell); return [p.x, p.y]),
		"route_lengths": battlefield.layout.curves.map(func(curve: Curve2D) -> float: return curve.get_baked_length()),
		"routes": battlefield.routes.size(), "portal_nodes": battlefield.portals.get_child_count() + 1,
		"route_length": battlefield.layout.curve.get_baked_length(), "seed": battlefield.layout.seed_value,
		"used_fallback": battlefield.layout.used_fallback,
		"field_origin": [battlefield.layout.origin.x, battlefield.layout.origin.y], "rows": battlefield.layout.grid_size.y,
		"field_bottom": battlefield.layout.origin.y + battlefield.layout.grid_size.y * battlefield.layout.cell_size,
		"dock": _rect(hud.bottom_dock), "settings_visible": hud.settings_overlay.visible,
		"gear_disabled": hud.settings_button.disabled, "upgrade_visible": upgrade_choice.visible,
		"enemy_distances": enemies.get_children().map(func(enemy: ApproachingEnemy) -> float: return enemy._distance),
		"enemy_portals": enemies.get_children().map(func(enemy: ApproachingEnemy) -> int: return int(enemy.get_meta("portal_index", 0))),
		"enemy_positions": enemies.get_children().map(func(enemy: ApproachingEnemy) -> Array: return [enemy.global_position.x, enemy.global_position.y]),
		"embedded_arrows": enemies.get_children().filter(func(enemy: ApproachingEnemy) -> bool: return not enemy.is_queued_for_deletion()).map(func(enemy: ApproachingEnemy) -> Dictionary: return {"type": enemy.stats.enemy_type, "count": enemy._embedded_arrow_count, "health": enemy.current_health}),
		"spawn_remaining": wave_manager.get_node("SpawnTimer").time_left,
		"slots": slots, "mana": summon_manager.mana, "cost": summon_manager.current_cost(),
		"summons": summon_manager.successful_summons, "state": state, "wave": wave_manager.wave_number,
		"health": tower.current_health, "max_health": tower.max_health, "kills": run_statistics.killed_enemies,
		"tower": [tower.global_position.x, tower.global_position.y], "base_bottom_y": base_bottom.y,
		"tower_screen": [tower.get_global_transform_with_canvas().origin.x, tower.get_global_transform_with_canvas().origin.y],
		"slot_screen_positions": summon_manager._slots.map(func(slot: SummonSlot) -> Array: var p: Vector2 = slot.get_global_transform_with_canvas().origin; return [p.x,p.y]),
		"shake": {"offset":[get_node("ScreenShake").offset.x,get_node("ScreenShake").offset.y],
			"playing":get_node("ScreenShake/GFFPlayer").is_playing(),"started":_shake_started_count},
		"world_position": [$World.position.x,$World.position.y],
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
		"mana_feedback": {"scale": [hud.mana_feedback.visual.scale.x, hud.mana_feedback.visual.scale.y],
			"active": hud.mana_feedback.player.is_playing()},
		"gear_feedback": _feedback(hud.settings_button),
		"restart_feedback": _feedback(hud.restart_button), "menu_feedback": _feedback(hud.menu_button),
		"controls": {"animated": _center(animated_button), "pause": _center(pause_button),
			"settings": _center(hud.settings_button), "resume": _center(hud.resume_button),
			"restart": _center(hud.restart_button), "result_menu": _center(hud.menu_button),
			"menu": _center(hud.get_node("SettingsOverlay/Center/Panel/Stack/SettingsMenuButton"))}
	}
	JavaScriptBridge.eval("window.towerReview = %s;" % JSON.stringify(snapshot), true)


func _feedback(button: Button) -> Dictionary:
	var visual: ButtonFeedback = button.get_node("FeedbackVisual") as ButtonFeedback
	return {"scale": [visual.scale.x, visual.scale.y], "hover": visual.hover_amount,
		"bounds": _rect(button), "active": visual.player.is_playing()}


func _center(control: Control) -> Array[float]:
	var center: Vector2 = control.get_global_rect().get_center()
	return [center.x, center.y]


func _rect(control: Control) -> Array[float]:
	var bounds: Rect2 = control.get_global_rect()
	return [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]


func _exit_tree() -> void:
	if _web_snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getTowerReview = null
		JavaScriptBridge.get_interface("window").towerReview = null
	super._exit_tree()
