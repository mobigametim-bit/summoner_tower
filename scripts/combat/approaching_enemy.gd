class_name ApproachingEnemy
extends Node2D

signal reached_tower(enemy: ApproachingEnemy)

var tower_damage: int = 0
var move_speed: float = 0.0
var _target_y: float = 0.0
var _resolved: bool = false


func _ready() -> void:
	set_physics_process(false)


func configure(config: EncounterConfig, spawn_position: Vector2, target_y: float) -> void:
	global_position = spawn_position
	tower_damage = config.enemy_tower_damage
	move_speed = config.enemy_move_speed
	_target_y = target_y
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _resolved:
		return

	global_position.y = move_toward(global_position.y, _target_y, move_speed * delta)
	if global_position.y >= _target_y:
		_resolve_at_tower()


func _resolve_at_tower() -> void:
	if _resolved:
		return

	# Обработчик сигнала может вызвать этот метод повторно: сначала фиксируем результат.
	_resolved = true
	set_physics_process(false)
	reached_tower.emit(self)
	queue_free()


func stop() -> void:
	_resolved = true
	set_physics_process(false)
