class_name ApproachingEnemy
extends Node2D

enum Outcome { KILLED, REACHED_TOWER }

signal resolved(enemy: ApproachingEnemy, outcome: Outcome)

var tower_damage: int = 0
var move_speed: float = 0.0
var current_health: int = 0
var max_health: int = 0

@onready var health_bar: ProgressBar = $HealthBar
@onready var slow_indicator: Sprite2D = $SlowIndicator

var _target_y: float = 0.0
var _resolved: bool = false
var _slow_ratio: float = 0.0
var _slow_remaining: float = 0.0


func _ready() -> void:
	set_physics_process(false)


func configure(config: EncounterConfig, spawn_position: Vector2, target_y: float, health: int = 0) -> void:
	global_position = spawn_position
	tower_damage = config.enemy_tower_damage
	move_speed = config.enemy_move_speed
	max_health = health if health > 0 else config.enemy_max_health
	current_health = max_health
	_update_health_bar()
	_target_y = target_y
	_clear_slow()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _resolved:
		return

	# Последний неполный кадр эффекта учитывается отдельно, чтобы срок не зависел от FPS.
	var slowed_delta: float = minf(delta, _slow_remaining)
	var distance: float = move_speed * (delta - slowed_delta * _slow_ratio)
	global_position.y = move_toward(global_position.y, _target_y, distance)
	_slow_remaining = maxf(_slow_remaining - delta, 0.0)
	if _slow_remaining <= 0.0 and _slow_ratio > 0.0:
		_clear_slow()
	if global_position.y >= _target_y:
		_resolve_at_tower()


func _resolve_at_tower() -> void:
	_finish(Outcome.REACHED_TOWER)


func take_damage(amount: int) -> void:
	if not is_targetable() or amount <= 0:
		return

	current_health = maxi(current_health - amount, 0)
	_update_health_bar()
	if current_health == 0:
		_finish(Outcome.KILLED)


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
	resolved.emit(self, outcome)
	queue_free()


func stop() -> void:
	_resolved = true
	set_physics_process(false)
	_clear_slow()
