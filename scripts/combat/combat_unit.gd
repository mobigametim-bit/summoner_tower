class_name CombatUnit
extends Node2D

const TARGET_SEARCH_INTERVAL: float = 0.1

@export var stats: UnitStats
@export var projectile_scene: PackedScene
@export var attack_enabled: bool = true
@export var animated_visual_enabled: bool = false

var paid_mana: int = 0

@onready var muzzle: Marker2D = $Muzzle
@onready var archer_visual: ArcherVisual = get_node_or_null("ArcherVisual") as ArcherVisual
@onready var mage_visual: MageVisual = get_node_or_null("MageVisual") as MageVisual
# Godot не поддерживает union types; оба визуала реализуют один небольшой контракт.
@onready var _animated_visual: Variant = archer_visual if archer_visual != null else mage_visual

var _enemies: Node2D
var _projectiles: Node2D
var _target: ApproachingEnemy
var _cooldown: float = 0.0
var _search_remaining: float = 0.0
var _running: bool = false
var _run_bonuses: RunBonuses
var _damage_remainder: float = 0.0
var _visual_release_pending: bool = false


func _ready() -> void:
	refresh_visual()
	if _animated_visual != null:
		_animated_visual.release.connect(_on_visual_release)
		_animated_visual.enable_gameplay(animated_visual_enabled)
		_apply_visual_mode()


func refresh_visual() -> void:
	if stats.visual_texture != null:
		$Visual.texture = stats.visual_texture
	if _animated_visual != null:
		_animated_visual.set_level(stats.level)


func set_animated_visual(enabled: bool, play_spawn: bool = false) -> void:
	animated_visual_enabled = enabled and _animated_visual != null
	if _animated_visual != null:
		_animated_visual.cancel_preparation()
		_animated_visual.enable_gameplay(animated_visual_enabled and play_spawn)
		_apply_visual_mode()


func _apply_visual_mode() -> void:
	$Visual.visible = not animated_visual_enabled
	_animated_visual.visible = animated_visual_enabled
	if not animated_visual_enabled:
		_animated_visual.stop_gameplay()


func drag_texture() -> Texture2D:
	return _animated_visual.DRAG_TEXTURE if animated_visual_enabled else $Visual.texture


func drag_material() -> Material:
	return _animated_visual.cloth_material if animated_visual_enabled else null


func drag_scale() -> Vector2:
	return global_scale * absf(_animated_visual.scale.x) if animated_visual_enabled else global_scale


func can_merge_with(other: CombatUnit) -> bool:
	return (
		is_instance_valid(other) and other != self
		and stats.unit_type == other.stats.unit_type and stats.level == other.stats.level
		and stats.level < UnitStats.MAX_LEVEL and other.stats.next_level != null
		and other.stats.next_level.level == stats.level + 1
		and other.stats.next_level.unit_type == stats.unit_type
	)


func promote() -> void:
	stats = stats.next_level
	refresh_visual()
	refresh_target()
	_cooldown = effective_attack_interval()


func retire_into(successor: CombatUnit) -> void:
	stop()
	# Стрелы сохраняют снимок урона, но больше не зависят от удаляемого участника merge.
	for child: Node in _projectiles.get_children():
		var arrow: CombatProjectile = child as CombatProjectile
		if arrow != null:
			arrow.reassign_attacker(self, successor)


func configure(enemies: Node2D, projectiles: Node2D, bonuses: RunBonuses = null) -> void:
	_enemies = enemies
	_projectiles = projectiles
	_run_bonuses = bonuses
	_damage_remainder = 0.0
	_running = true


func effective_attack_interval() -> float:
	return _run_bonuses.attack_interval_for(stats) if _run_bonuses != null else stats.attack_interval


func set_facing_left(faces_left: bool) -> void:
	$Visual.flip_h = faces_left
	muzzle.position.x = -absf(muzzle.position.x) if faces_left else absf(muzzle.position.x)
	if _animated_visual != null:
		_animated_visual.scale.x = -absf(_animated_visual.scale.x) if faces_left else absf(_animated_visual.scale.x)


func refresh_target() -> void:
	_target = null
	_search_remaining = 0.0
	if _animated_visual != null:
		_animated_visual.cancel_preparation()


func _physics_process(delta: float) -> void:
	if not _running or not attack_enabled:
		return

	_cooldown = maxf(_cooldown - delta, 0.0)
	_search_remaining -= delta
	if _search_remaining <= 0.0:
		_target = _find_nearest_target()
		_search_remaining = TARGET_SEARCH_INTERVAL
	if animated_visual_enabled:
		var has_target: bool = (
			is_instance_valid(_target) and _target.is_targetable()
			and global_position.distance_squared_to(_target.global_position) <= stats.attack_range ** 2
		)
		_animated_visual.advance_gameplay(delta, _cooldown, effective_attack_interval(), has_target)
	if _cooldown > 0.0 or not is_instance_valid(_target):
		return
	if not _target.is_targetable():
		_target = null
		return
	if global_position.distance_squared_to(_target.global_position) > stats.attack_range ** 2:
		return

	if animated_visual_enabled:
		_visual_release_pending = true
		_animated_visual.release_now()
	else:
		_fire()
	_cooldown = effective_attack_interval()


func _on_visual_release() -> void:
	if not _visual_release_pending or not _running:
		return
	_visual_release_pending = false
	_fire()


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
	var arrow: CombatProjectile = projectile_scene.instantiate() as CombatProjectile
	_projectiles.add_child(arrow)
	arrow.launch(muzzle.global_position, _target, stats, self, _run_bonuses, _next_damage())


func _next_damage() -> int:
	# Дробь переносится между выстрелами конкретного бойца: +5% полезны уже на Lv1.
	var amount: float = _run_bonuses.damage_amount_for(stats) if _run_bonuses != null else float(stats.damage)
	amount += _damage_remainder
	var damage: int = maxi(floori(amount + RunBonuses.ROUNDING_EPSILON), 1)
	_damage_remainder = maxf(amount - damage, 0.0)
	return damage


func stop() -> void:
	_running = false
	_target = null
	_visual_release_pending = false
	if _animated_visual != null:
		_animated_visual.stop_gameplay()
	set_physics_process(false)
