class_name Archer
extends Node2D

const TARGET_SEARCH_INTERVAL: float = 0.1

@export var stats: ArcherStats
@export var projectile_scene: PackedScene
@export var attack_enabled: bool = true

@onready var muzzle: Marker2D = $Muzzle

var _enemies: Node2D
var _projectiles: Node2D
var _target: ApproachingEnemy
var _cooldown: float = 0.0
var _search_remaining: float = 0.0
var _running: bool = false


func _ready() -> void:
	refresh_visual()


func refresh_visual() -> void:
	if stats.visual_texture != null:
		$Visual.texture = stats.visual_texture


func can_merge_with(other: Archer) -> bool:
	return (
		is_instance_valid(other) and other != self
		and stats.unit_type == other.stats.unit_type and stats.level == other.stats.level
		and stats.level < 3 and other.stats.next_level != null
		and other.stats.next_level.level == stats.level + 1
		and other.stats.next_level.unit_type == stats.unit_type
	)


func promote() -> void:
	stats = stats.next_level
	refresh_visual()
	refresh_target()
	_cooldown = stats.attack_interval


func retire_into(successor: Archer) -> void:
	stop()
	# Стрелы сохраняют снимок урона, но больше не зависят от удаляемого участника merge.
	for child: Node in _projectiles.get_children():
		var arrow: ArrowProjectile = child as ArrowProjectile
		if arrow != null:
			arrow.reassign_attacker(self, successor)


func configure(enemies: Node2D, projectiles: Node2D) -> void:
	_enemies = enemies
	_projectiles = projectiles
	_running = true


func set_facing_left(faces_left: bool) -> void:
	$Visual.flip_h = faces_left
	muzzle.position.x = -absf(muzzle.position.x) if faces_left else absf(muzzle.position.x)


func refresh_target() -> void:
	_target = null
	_search_remaining = 0.0


func _physics_process(delta: float) -> void:
	if not _running or not attack_enabled:
		return

	_cooldown = maxf(_cooldown - delta, 0.0)
	_search_remaining -= delta
	if _search_remaining <= 0.0:
		_target = _find_nearest_target()
		_search_remaining = TARGET_SEARCH_INTERVAL
	if _cooldown > 0.0 or not is_instance_valid(_target):
		return
	if not _target.is_targetable():
		_target = null
		return
	if global_position.distance_squared_to(_target.global_position) > stats.attack_range ** 2:
		return

	_fire()
	_cooldown = stats.attack_interval


func _find_nearest_target() -> ApproachingEnemy:
	var nearest: ApproachingEnemy
	var nearest_distance: float = stats.attack_range ** 2
	for child: Node in _enemies.get_children():
		var enemy: ApproachingEnemy = child as ApproachingEnemy
		if not is_instance_valid(enemy) or not enemy.is_targetable():
			continue
		var distance: float = global_position.distance_squared_to(enemy.global_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func _fire() -> void:
	var arrow: ArrowProjectile = projectile_scene.instantiate() as ArrowProjectile
	_projectiles.add_child(arrow)
	arrow.launch(muzzle.global_position, _target, stats, self)


func stop() -> void:
	_running = false
	_target = null
	set_physics_process(false)
