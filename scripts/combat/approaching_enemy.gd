class_name ApproachingEnemy
extends Node2D

enum Outcome { KILLED, REACHED_TOWER }

signal resolved(enemy: ApproachingEnemy, outcome: Outcome)

@export var stats: EnemyStats
@export var animated_visual_enabled: bool = false

var tower_damage: int = 0
var move_speed: float = 0.0
var current_health: int = 0
var max_health: int = 0
var difficulty_tier: int = 1

@onready var visual: Sprite2D = $Visual
@onready var health_bar: ProgressBar = $HealthBar
@onready var slow_indicator: Sprite2D = $SlowIndicator
@onready var goblin_visual: GoblinVisual = get_node_or_null("GoblinVisual") as GoblinVisual
@onready var orc_visual: OrcVisual = get_node_or_null("OrcVisual") as OrcVisual
@onready var golem_visual: GolemVisual = get_node_or_null("GolemVisual") as GolemVisual
@onready var boss_visual: BossVisual = get_node_or_null("BossVisual") as BossVisual
# Все visual реализуют один контракт; gameplay сохраняет движение и outcomes.
@onready var _animated_visual: Variant = goblin_visual if goblin_visual != null else (orc_visual if orc_visual != null else (golem_visual if golem_visual != null else boss_visual))

var _target_y: float = 0.0
var _route: Curve2D
var _route_transform: Transform2D = Transform2D.IDENTITY
var _route_length: float = 0.0
var _distance: float = 0.0
var _resolved: bool = false
var _slow_ratio: float = 0.0
var _slow_remaining: float = 0.0


func _ready() -> void:
	set_physics_process(false)
	set_animated_visual(animated_visual_enabled)


func configure(spawn_position: Vector2, target_y: float, health: int = 0) -> void:
	global_position = spawn_position
	tower_damage = stats.tower_damage
	move_speed = stats.move_speed
	max_health = health if health > 0 else stats.base_health
	current_health = max_health
	difficulty_tier = stats.difficulty_tier(max_health)
	visual.modulate = stats.color_for(max_health)
	set_animated_visual(animated_visual_enabled)
	_update_health_bar()
	_target_y = target_y
	_route = null
	_distance = 0.0
	_clear_slow()
	set_physics_process(true)


func follow_route(curve: Curve2D, route_transform: Transform2D, cell_size: float = 140.0) -> void:
	scale = Vector2.ONE * minf((cell_size - 12.0) / 140.0, 1.0)
	_route = curve
	_route_transform = route_transform
	_route_length = curve.get_baked_length()
	_distance = 0.0
	global_position = _route_transform * curve.sample_baked(0.0)


func _physics_process(delta: float) -> void:
	if _resolved:
		return

	# Последний неполный кадр эффекта учитывается отдельно, чтобы срок не зависел от FPS.
	var slowed_delta: float = minf(delta, _slow_remaining)
	var distance: float = move_speed * (delta - slowed_delta * _slow_ratio)
	var previous_position: Vector2 = global_position
	if _route != null:
		_distance = minf(_distance + distance, _route_length)
		global_position = _route_transform * _route.sample_baked(_distance)
	else:
		global_position.y = move_toward(global_position.y, _target_y, distance)
	_slow_remaining = maxf(_slow_remaining - delta, 0.0)
	if _slow_remaining <= 0.0 and _slow_ratio > 0.0:
		_clear_slow()
	if animated_visual_enabled:
		_animated_visual.advance_gameplay(delta, _time_to_contact(), global_position - previous_position)
	if (_route != null and _distance >= _route_length) or (_route == null and global_position.y >= _target_y):
		_resolve_at_tower()


func _resolve_at_tower() -> void:
	if _resolved:
		return
	if animated_visual_enabled:
		_animated_visual.impact_now()
	_finish(Outcome.REACHED_TOWER)


func set_animated_visual(enabled: bool) -> void:
	animated_visual_enabled = enabled and _animated_visual != null
	visual.visible = not animated_visual_enabled
	if _animated_visual == null:
		return
	_animated_visual.visible = animated_visual_enabled
	if animated_visual_enabled:
		_animated_visual.enable_gameplay()
		_animated_visual.set_difficulty(difficulty_tier, stats.color_for(max_health))
	else:
		_animated_visual.stop_gameplay()


func _time_to_contact() -> float:
	var remaining: float = maxf(_route_length - _distance, 0.0) if _route != null else maxf(_target_y - global_position.y, 0.0)
	var speed: float = current_move_speed()
	var slow_distance: float = speed * _slow_remaining
	if remaining <= slow_distance:
		return remaining / maxf(speed, 0.001)
	return _slow_remaining + (remaining - slow_distance) / maxf(move_speed, 0.001)


func take_damage(amount: int) -> void:
	if not is_targetable() or amount <= 0:
		return

	current_health = maxi(current_health - amount, 0)
	_update_health_bar()
	if current_health == 0:
		_finish(Outcome.KILLED)
	elif animated_visual_enabled:
		_animated_visual.show_hit()


func is_targetable() -> bool:
	return is_inside_tree() and not _resolved and not is_queued_for_deletion() and current_health > 0


func apply_slow(ratio: float, duration: float) -> void:
	if not is_targetable() or ratio <= 0.0 or duration <= 0.0:
		return
	var strength: float = clampf(ratio, 0.0, 0.95)
	# Слабое попадание не заменяет и не продлевает сильное замедление.
	if _slow_remaining > 0.0 and strength < _slow_ratio:
		return
	_slow_ratio = strength
	_slow_remaining = duration
	slow_indicator.show()


func current_move_speed() -> float:
	return move_speed * (1.0 - _slow_ratio)


func _clear_slow() -> void:
	_slow_ratio = 0.0
	_slow_remaining = 0.0
	# Game Over из child_entered_tree может остановить врага до его _ready.
	if is_instance_valid(slow_indicator):
		slow_indicator.hide()


func _update_health_bar() -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health


func _finish(outcome: Outcome) -> void:
	if _resolved:
		return

	# Обработчик сигнала может вызвать этот метод повторно: сначала фиксируем результат.
	_resolved = true
	set_physics_process(false)
	_clear_slow()
	if animated_visual_enabled:
		# Only the visual survives; it is neither a target nor an active wave enemy.
		_animated_visual.reparent(get_parent().get_parent(), true)
		_animated_visual.add_to_group("enemy_visual_tails")
		_animated_visual.finish_as_tail(outcome == Outcome.KILLED)
	resolved.emit(self, outcome)
	queue_free()


func stop() -> void:
	_resolved = true
	set_physics_process(false)
	_clear_slow()
	if _animated_visual != null and is_instance_valid(_animated_visual):
		_animated_visual.stop_gameplay()
