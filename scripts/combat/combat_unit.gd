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
@onready var frost_mage_visual: FrostMageVisual = get_node_or_null("FrostMageVisual") as FrostMageVisual
# Godot не поддерживает union types; визуалы реализуют один небольшой контракт.
@onready var _animated_visual: Variant = archer_visual if archer_visual != null else (
	mage_visual if mage_visual != null else frost_mage_visual
)

var _enemies: Node2D
var _projectiles: Node2D
var _target: ApproachingEnemy
var _cooldown: float = 0.0
var _search_remaining: float = 0.0
var _running: bool = false
var _run_bonuses: RunBonuses
var _damage_remainder: float = 0.0
var _visual_release_pending: bool = false
var _normal_pending: bool = false
var _skill_pending: bool = false
var _skill_cooldown: float = 3.0
var _shots: Array[Dictionary] = []
const AREA_SCENE: PackedScene = preload("res://scenes/vfx/CombatArea.tscn")


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
	_skill_cooldown = effective_ability_cooldown()
	_shots.clear()
	_normal_pending = false
	_skill_pending = false


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
	_skill_cooldown = effective_ability_cooldown()
	_running = true


func effective_attack_interval() -> float:
	return _run_bonuses.attack_interval_for(stats) if _run_bonuses != null else stats.attack_interval


func effective_attack_range(for_stats: UnitStats = null) -> float:
	var source: UnitStats = for_stats if for_stats != null else stats
	return _run_bonuses.attack_range_for(source) if _run_bonuses != null else source.attack_range


func effective_ability_cooldown() -> float:
	return _run_bonuses.ability_cooldown_for(stats) if _run_bonuses != null else stats.ability_cooldown


func set_facing_left(faces_left: bool) -> void:
	$Visual.flip_h = faces_left
	muzzle.position.x = -absf(muzzle.position.x) if faces_left else absf(muzzle.position.x)
	if _animated_visual != null:
		_animated_visual.scale.x = -absf(_animated_visual.scale.x) if faces_left else absf(_animated_visual.scale.x)


func refresh_target() -> void:
	_target = null
	_search_remaining = 0.0
	_shots.clear()
	_visual_release_pending = false
	_normal_pending = false
	_skill_pending = false
	if _animated_visual != null:
		_animated_visual.cancel_preparation()


func _physics_process(delta: float) -> void:
	if not _running or not attack_enabled:
		return
	_advance_shots(delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	_skill_cooldown = maxf(_skill_cooldown - delta, 0.0)
	_search_remaining -= delta
	if _search_remaining <= 0.0:
		_target = _find_nearest_target()
		_search_remaining = TARGET_SEARCH_INTERVAL
	var has_target: bool = _in_range(_target)
	var ability_ready: bool = stats.ability != UnitStats.Ability.NONE and _skill_cooldown <= 0.0
	if animated_visual_enabled:
		var next_release: float = minf(_cooldown, _skill_cooldown) if stats.ability != UnitStats.Ability.NONE else _cooldown
		_animated_visual.advance_gameplay(delta, next_release, effective_attack_interval(), has_target)
	if not has_target or (_cooldown > 0.0 and not ability_ready):
		return
	_normal_pending = _cooldown <= 0.0
	_skill_pending = ability_ready
	if _normal_pending:
		_cooldown = effective_attack_interval()
	if _skill_pending:
		_skill_cooldown = effective_ability_cooldown()
	_visual_release_pending = true
	if animated_visual_enabled:
		_animated_visual.release_now()
	else:
		_on_visual_release()


func _on_visual_release() -> void:
	if not _visual_release_pending or not _running:
		return
	_visual_release_pending = false
	var normal: bool = _normal_pending
	var special: bool = _skill_pending
	_normal_pending = false
	_skill_pending = false
	if not _in_range(_target):
		return
	if normal:
		_fire()
	if special:
		_fire_skill()


# Variant допускает освобождённую цель: проверка valid должна произойти до приведения типа.
func _in_range(target: Variant) -> bool:
	return is_instance_valid(target) and target.is_targetable() and global_position.distance_squared_to(target.global_position) <= effective_attack_range() ** 2


func _advance_shots(delta: float) -> void:
	for index: int in range(_shots.size() - 1, -1, -1):
		var shot: Dictionary = _shots[index]
		shot.delay -= delta
		if shot.delay > 0.000001:
			continue
		_shots.remove_at(index)
		var victim: ApproachingEnemy = shot.target if is_instance_valid(shot.target) else null
		var allowed: bool = _in_range(victim)
		if shot.has("center"):
			allowed = is_instance_valid(victim) and victim.is_targetable() and victim.global_position.distance_squared_to(shot.center) <= shot.radius * shot.radius
			if not allowed:
				var replacements: Array[ApproachingEnemy] = CombatHit.targets_in_area(_enemies, shot.center, shot.radius)
				victim = replacements[0] if not replacements.is_empty() else null
				allowed = is_instance_valid(victim)
		elif not allowed:
			victim = _find_nearest_target()
			allowed = _in_range(victim)
		if allowed:
			_spawn_projectile(victim, shot.stats, shot.damage)


func _find_nearest_target() -> ApproachingEnemy:
	var nearest: ApproachingEnemy
	var nearest_distance: float = effective_attack_range() ** 2
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
	var shot_damage: float = float(_next_damage()) / stats.burst_count
	_spawn_projectile(_target, stats, shot_damage)
	for index: int in range(1, stats.burst_count):
		_shots.append({"target": _target, "stats": stats, "damage": shot_damage, "delay": stats.burst_delay * index})
	var sound: StringName = &"archer"
	if stats.unit_type == &"mage":
		sound = &"fire_cast"
	elif stats.unit_type == &"frost_mage":
		sound = &"frost_cast"
	AudioService.play_sfx(sound)


func _spawn_projectile(victim: ApproachingEnemy, shot_stats: UnitStats, damage: float, meteor: bool = false) -> void:
	var projectile: CombatProjectile = projectile_scene.instantiate() as CombatProjectile
	_projectiles.add_child(projectile)
	var origin: Vector2 = victim.global_position + Vector2(0.0, -210.0) if meteor else muzzle.global_position
	projectile.launch(origin, victim, shot_stats, self, _run_bonuses, damage)
	projectile.configure_attack(_enemies, meteor)


func _fire_skill() -> void:
	var effective: UnitStats = _run_bonuses.combat_stats_for(stats) if _run_bonuses != null else stats
	var damage: float = _run_bonuses.damage_amount_for(stats) if _run_bonuses != null else float(stats.damage)
	damage *= stats.ability_damage_ratio
	var center: Vector2 = _target.global_position
	match stats.ability:
		UnitStats.Ability.HAIL:
			var victims: Array[ApproachingEnemy] = CombatHit.targets_in_area(_enemies, center, effective.ability_radius)
			if victims.is_empty():
				return
			_show_area(center, 0, effective.ability_radius)
			for index: int in stats.ability_projectiles:
				var victim: ApproachingEnemy = victims[index % victims.size()]
				var amount: float = damage / stats.ability_projectiles
				if index == 0:
					_spawn_projectile(victim, stats, amount)
				else:
					_shots.append({"target": victim, "stats": stats, "damage": amount, "delay": index * stats.burst_delay, "center": center, "radius": effective.ability_radius})
		UnitStats.Ability.METEOR:
			_spawn_projectile(_target, stats, damage, true)
		UnitStats.Ability.FROST_WAVE:
			_show_area(center, 2, effective.ability_radius)
			var slow: float = _run_bonuses.slow_ratio_for(stats) if _run_bonuses != null else stats.slow_ratio
			for victim: ApproachingEnemy in CombatHit.targets_in_area(_enemies, center, effective.ability_radius):
				CombatHit.apply(victim, damage, slow, stats.slow_duration, 0.0, 0.0, effective.freeze_duration)


func _show_area(center: Vector2, kind: int, radius: float) -> void:
	var effect: Node2D = AREA_SCENE.instantiate()
	_projectiles.add_child(effect)
	effect.global_position = center
	effect.configure(kind, radius)


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
	_normal_pending = false
	_skill_pending = false
	_shots.clear()
	if _animated_visual != null:
		_animated_visual.stop_gameplay()
	set_physics_process(false)
