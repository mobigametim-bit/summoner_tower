class_name CombatProjectile
extends Node2D

@export var impact_scene: PackedScene
@export var impact_scale: float = 0.4
@export var consecration_scene: PackedScene
@export var embedded_arrow_scene: PackedScene

var _target: ApproachingEnemy
var _attacker: Node2D
var _damage: float = 0.0
var _slow_ratio: float = 0.0
var _slow_duration: float = 0.0
var _speed: float = 0.0
var _remaining_lifetime: float = 0.0
var _resolved: bool = false
var _stats: UnitStats
var _enemies: Node2D
var _meteor: bool = false
var _consecration: bool = false
var _ground_target: Vector2
const AREA_SCENE: PackedScene = preload("res://scenes/vfx/CombatArea.tscn")


func _ready() -> void:
	set_physics_process(false)


func launch(origin: Vector2, target: ApproachingEnemy, stats: UnitStats, attacker: Node2D, bonuses: RunBonuses = null, damage_override: float = -1.0) -> void:
	global_position = origin
	_target = target
	_stats = bonuses.combat_stats_for(stats) if bonuses != null else stats
	_attacker = attacker
	_damage = bonuses.damage_amount_for(stats) if bonuses != null else float(stats.damage)
	if damage_override >= 0:
		_damage = damage_override
	_slow_ratio = bonuses.slow_ratio_for(stats) if bonuses != null else stats.slow_ratio
	_slow_duration = stats.slow_duration
	_speed = stats.projectile_speed
	_remaining_lifetime = stats.projectile_lifetime
	set_physics_process(true)


func configure_attack(enemies: Node2D, meteor: bool = false, consecration: bool = false) -> void:
	_enemies = enemies
	_meteor = meteor
	_consecration = consecration
	var trail: CPUParticles2D = get_node_or_null("Trail") as CPUParticles2D
	if meteor:
		_ground_target = _target.global_position
		_speed = global_position.distance_to(_ground_target) / 0.45
		$Visual.scale = Vector2(1.8, 1.8)
	if trail != null:
		trail.visible = meteor or (_stats.unit_type == &"archer" and _stats.level >= 2)
		trail.emitting = trail.visible


func reassign_attacker(previous: Node2D, successor: Node2D) -> void:
	if not _resolved and _attacker == previous:
		_attacker = successor


func cancel_from(attacker: CombatUnit) -> void:
	if not _resolved and _attacker == attacker:
		_dispose()


func _physics_process(delta: float) -> void:
	if _resolved:
		return
	_remaining_lifetime -= delta
	if _remaining_lifetime <= 0.0 or not _has_valid_participants():
		_dispose()
		return

	var destination: Vector2 = _ground_target if _meteor else _target.global_position
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
		(_meteor or (is_instance_valid(_target) and _target.is_targetable()))
		and is_instance_valid(_attacker) and _attacker.is_inside_tree()
		and not _attacker.is_queued_for_deletion()
	)


func _hit_target() -> void:
	if _resolved:
		return
	_resolved = true
	set_physics_process(false)
	if _has_valid_participants():
		if _consecration:
			var victims: Array[ApproachingEnemy] = CombatHit.targets_in_area(_enemies,global_position,_stats.ability_radius)
			var effect: Node2D = consecration_scene.instantiate() as Node2D
			get_parent().add_child(effect)
			effect.global_position = global_position
			effect.scale = Vector2.ONE*(_stats.ability_radius/85.0)
			effect.call("start",1.0)
			for enemy: ApproachingEnemy in victims:
				CombatHit.apply(enemy,_damage,0.0,0.0,0.0,0.0,0.0,_stats.light_mark_ratio,_stats.light_mark_duration)
		elif _meteor:
			_show_area(_stats.ability_radius)
			for enemy: ApproachingEnemy in CombatHit.targets_in_area(_enemies, global_position, _stats.ability_radius):
				CombatHit.apply(enemy, _damage, 0.0, 0.0, 0.0, 0.0)
		else:
			_show_impact()
			var center: Vector2 = _target.global_position
			# Снимок списка делается до первого урона: смерть может закончить волну.
			var neighbors: Array[ApproachingEnemy] = []
			if _stats.splash_radius > 0.0:
				neighbors = CombatHit.targets_in_area(_enemies, center, _stats.splash_radius)
			CombatHit.apply(_target, _damage, _slow_ratio, _slow_duration, _stats.burn_damage_ratio, _stats.burn_duration,0.0,_stats.light_mark_ratio,_stats.light_mark_duration)
			if _stats.splash_radius > 0.0:
				_show_area(_stats.splash_radius)
				for enemy: ApproachingEnemy in neighbors:
					if enemy != _target:
						CombatHit.apply(enemy, _damage * _stats.splash_damage_ratio, _slow_ratio, _slow_duration, _stats.burn_damage_ratio, _stats.burn_duration)
	queue_free()


func _show_area(radius: float) -> void:
	var effect: Node2D = AREA_SCENE.instantiate()
	get_parent().add_child(effect)
	effect.global_position = global_position
	effect.configure(1 if _stats.unit_type == &"mage" else 2, radius)


func _show_impact() -> void:
	if embedded_arrow_scene != null:
		_target.embed_arrow(embedded_arrow_scene, Vector2.RIGHT.rotated(global_rotation))
	if impact_scene == null or _stats.splash_radius > 0.0:
		return
	# Соседний узел переживёт снаряд и цель; смена сцены удалит незавершённый эффект.
	var effect: Node2D = impact_scene.instantiate() as Node2D
	get_parent().add_child(effect)
	effect.global_position = global_position
	effect.global_scale = Vector2.ONE * impact_scale
	if effect.has_method("start"):
		effect.call("start",1.0)


func _dispose() -> void:
	_resolved = true
	set_physics_process(false)
	queue_free()
