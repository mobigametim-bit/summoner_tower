class_name ArrowProjectile
extends Node2D

var _target: ApproachingEnemy
var _attacker: Node2D
var _damage: int = 0
var _speed: float = 0.0
var _remaining_lifetime: float = 0.0
var _resolved: bool = false


func _ready() -> void:
	set_physics_process(false)


func launch(origin: Vector2, target: ApproachingEnemy, stats: ArcherStats, attacker: Node2D) -> void:
	global_position = origin
	_target = target
	_attacker = attacker
	_damage = stats.damage
	_speed = stats.projectile_speed
	_remaining_lifetime = stats.projectile_lifetime
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _resolved:
		return
	_remaining_lifetime -= delta
	if _remaining_lifetime <= 0.0 or not _has_valid_participants():
		_dispose()
		return

	var destination: Vector2 = _target.global_position
	var direction: Vector2 = destination - global_position
	global_rotation = direction.angle()
	var distance: float = _speed * delta
	if direction.length_squared() <= distance * distance:
		global_position = destination
		_hit_target()
	else:
		global_position = global_position.move_toward(destination, distance)


func _has_valid_participants() -> bool:
	return (
		is_instance_valid(_target) and _target.is_targetable()
		and is_instance_valid(_attacker) and _attacker.is_inside_tree()
		and not _attacker.is_queued_for_deletion()
	)


func _hit_target() -> void:
	if _resolved:
		return
	# Урон может удалить цель и вызвать очистку всех снарядов: сначала закрываем попадание.
	_resolved = true
	set_physics_process(false)
	if _has_valid_participants():
		_target.take_damage(_damage)
	queue_free()


func _dispose() -> void:
	_resolved = true
	set_physics_process(false)
	queue_free()
