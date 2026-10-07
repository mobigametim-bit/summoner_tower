extends "res://scripts/game/game_manager.gd"

@export var review_summon_seed: int = 23

@onready var animated_button: CheckButton = $Interface/GoblinReview/Animated
@onready var pause_button: Button = $Interface/GoblinReview/Pause

var _animated: bool = true
var _web_snapshot_callback: JavaScriptObject
var _observed: Dictionary = {}
var _outcomes: Array[Dictionary] = []


func _ready() -> void:
	wave_manager.state_changed.connect(_on_review_wave_changed)
	super._ready()
	_start_review_wave()
	summon_manager.set_random_seed(review_summon_seed)
	animated_button.set_pressed_no_signal(_animated)
	if OS.has_feature("web"):
		_web_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getGolemReview = _web_snapshot_callback
		var load_count: int = int(JavaScriptBridge.eval("Number(new URL(window.location.href).searchParams.get('load_test')) || 0", true))
		var palette_test: bool = bool(JavaScriptBridge.eval("new URL(window.location.href).searchParams.get('palette_test') === '1'", true))
		if load_count > 0 or palette_test:
			_setup_load_test(5 if palette_test else clampi(load_count, 1, 80), palette_test)
		if palette_test:
			_on_review_pause()


func _start_review_wave() -> void:
	# Только review: начинаем с существующей шестой волны, где открывается Golem.
	wave_manager.stop()
	wave_manager.wave_number = 6
	wave_manager.phase = WaveManager.Phase.FIGHTING
	wave_manager._begin_wave()


func _setup_load_test(count: int, palette_test: bool = false) -> void:
	# Development-only fixture: existing enemy stats and route, no saved player data.
	wave_manager.stop()
	wave_manager.phase = WaveManager.Phase.FIGHTING
	var battlefield_node: Node = get_node_or_null("World/Battlefield")
	var route: Path2D = battlefield_node.get("route") as Path2D if battlefield_node != null else null
	for index: int in count:
		var enemy: ApproachingEnemy = wave_manager.config.golem_scene.instantiate() as ApproachingEnemy
		wave_manager._active.append(enemy)
		enemy.resolved.connect(wave_manager._on_enemy_resolved)
		enemies.add_child(enemy)
		var health: int = enemy.stats.base_health * (1 << index) if palette_test else 0
		enemy.configure(spawn_point.global_position, contact_point.global_position.y, health)
		if route != null and enemy.has_method("follow_route"):
			enemy.call("follow_route", route.curve, route.global_transform, float(route.get_meta("cell_size", 140.0)))
			var span: float = 0.9 if palette_test else 0.25
			var offset: float = route.curve.get_baked_length() * span * float(index) / float(count)
			enemy.set("_distance", offset)
			enemy.global_position = route.global_transform * route.curve.sample_baked(offset)
		else:
			enemy.global_position.y = lerpf(spawn_point.global_position.y, contact_point.global_position.y, 0.25 * float(index) / float(count))
	_refresh_golems()


func _on_animated_toggled(enabled: bool) -> void:
	_animated = enabled
	animated_button.text = "ANIMATED" if enabled else "STATIC"
	_refresh_golems()


func _on_review_pause() -> void:
	if state != State.RUNNING:
		return
	get_tree().paused = not get_tree().paused
	pause_button.icon = load("res://assets/debug/animation_controls/play.svg" if get_tree().paused else "res://assets/debug/animation_controls/pause.svg")


func _on_review_wave_changed(_wave: int, _phase: WaveManager.Phase, _seconds: int, _alive: int, _pending: int) -> void:
	_refresh_golems()


func _refresh_golems() -> void:
	for enemy: ApproachingEnemy in wave_manager._active:
		if enemy.stats.enemy_type != &"golem" or enemy.golem_visual == null:
			continue
		if enemy.animated_visual_enabled != _animated:
			enemy.set_animated_visual(_animated)
		var id: int = enemy.get_instance_id()
		if not _observed.has(id):
			_observed[id] = true
			enemy.resolved.connect(_record_outcome)


func _record_outcome(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void:
	_observed.erase(enemy.get_instance_id())
	var visual: GolemVisual = enemy.golem_visual
	_outcomes.append({
		"outcome": outcome, "animated": enemy.animated_visual_enabled,
		"impact": visual.get("_impact_emitted") if enemy.animated_visual_enabled else false,
		"targetable": enemy.is_targetable(), "health": enemy.current_health,
		"route_remaining": enemy._time_to_contact() * enemy.move_speed,
		"visual_frame": visual.animation_player.current_animation_position if enemy.animated_visual_enabled else -1.0
	})
	if _outcomes.size() > 32:
		_outcomes.pop_front()


func _publish_snapshot(_arguments: Array) -> void:
	var slots: Array[Dictionary] = []
	for slot: SummonSlot in summon_manager._slots:
		slots.append({"position":[slot.global_position.x,slot.global_position.y],"type":"" if slot.is_empty() else str(slot.unit.stats.unit_type),"paid_mana":0 if slot.is_empty() else slot.unit.paid_mana})
	var active: Array[Dictionary] = []
	for enemy: ApproachingEnemy in wave_manager._active:
		if not is_instance_valid(enemy) or not enemy.is_targetable():
			continue
		var row: Dictionary = {
			"type": str(enemy.stats.enemy_type), "position": [enemy.global_position.x, enemy.global_position.y],
			"health": enemy.current_health, "max_health": enemy.max_health,
			"speed": enemy.current_move_speed(), "animated": enemy.animated_visual_enabled,
			"tier": enemy.difficulty_tier, "slow": enemy._slow_ratio
		}
		if enemy.animated_visual_enabled:
			row["animation"] = str(enemy._animated_visual.animation_player.assigned_animation)
			row["visual_frame"] = enemy._animated_visual.animation_player.current_animation_position
		active.append(row)
	var snapshot: Dictionary = {
		"active": active, "outcomes": _outcomes,
		"slots": slots, "projectiles": projectiles.get_child_count(),
		"mana": summon_manager.mana, "wave": wave_manager.wave_number, "state": state,
		"tower_health": tower.current_health, "kills": run_statistics.killed_enemies,
		"animated": _animated, "paused": get_tree().paused,
		"tails": get_tree().get_nodes_in_group("enemy_visual_tails").size(),
		"fps": Engine.get_frames_per_second(),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"tower": [tower.global_position.x,tower.global_position.y]
	}
	JavaScriptBridge.eval("window.golemReview = %s;" % JSON.stringify(snapshot), true)


func _exit_tree() -> void:
	if _web_snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getGolemReview = null
		JavaScriptBridge.get_interface("window").golemReview = null
	super._exit_tree()
