class_name ApproachingEnemy
extends Node2D

enum Outcome { KILLED, REACHED_TOWER }

signal resolved(enemy: ApproachingEnemy, outcome: Outcome)

var tower_damage: int = 0
var move_speed: float = 0.0
var current_health: int = 0
var max_health: int = 0

@onready var health_bar: ProgressBar = $HealthBar

var _target_y: float = 0.0
var _resolved: bool = false


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
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _resolved:
		return

	global_position.y = move_toward(global_position.y, _target_y, move_speed * delta)
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


func _update_health_bar() -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health


func _finish(outcome: Outcome) -> void:
	if _resolved:
		return

	# Обработчик сигнала может вызвать этот метод повторно: сначала фиксируем результат.
	_resolved = true
	set_physics_process(false)
	resolved.emit(self, outcome)
	queue_free()


func stop() -> void:
	_resolved = true
	set_physics_process(false)
