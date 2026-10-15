class_name EnemyAbilityVisual
extends Node2D

const PURPLE_PLATE: Texture2D = preload("res://assets/vfx/enemy_abilities/particles/purple_plate.svg")
const WIND: Texture2D = preload("res://assets/vfx/enemy_abilities/particles/wind_streak.svg")
const EMBER: Texture2D = preload("res://assets/vfx/enemy_abilities/particles/ember.svg")

@onready var windup: CPUParticles2D = $Windup
@onready var shield_sparks: CPUParticles2D = $ShieldSparks
@onready var shield_bolts: CPUParticles2D = $ShieldBolts
@onready var rush_sparks: CPUParticles2D = $RushSparks

var shield_center: Vector2 = Vector2.ZERO
var shield_radius: Vector2 = Vector2(96.0, 102.0)
var armor_y: float = -108.0

static var _boss_bounds: Dictionary = {}
@onready var sparks: CPUParticles2D = $Sparks
@onready var aura_particles: CPUParticles2D = $AuraParticles

var _type: StringName
var _aura: StringName
var _plates: int = 0
var _shield: float = 0.0
var _time: float = 0.0
var _warning: StringName
var _warning_time: float = 0.0
var _warning_length: float = 1.0
var _fragments: float = 0.0
var _broken_plate: int = 0



func configure(enemy_type: StringName, plates: int) -> void:
	clear()
	_type = enemy_type
	_plates = plates
	_refresh_processing()


func fit_to_enemy(enemy: ApproachingEnemy) -> void:
	armor_y = enemy.health_bar.position.y - 21.6 - 8.0
	queue_redraw()
	if not enemy.stats.is_boss or enemy.difficulty_tier < 3:
		return
	var cache_key: Vector2i = Vector2i(enemy.difficulty_tier, int(enemy.animated_visual_enabled))
	if _boss_bounds.has(cache_key):
		_apply_shield_bounds(_boss_bounds[cache_key])
		return
	var bounds: Rect2
	var first: bool = true
	var sprites: Array[Node] = []
	if enemy.animated_visual_enabled:
		sprites.assign(enemy._animated_visual.find_children("*", "Sprite2D", true, false))
	else:
		sprites.append(enemy.visual)
	for sprite: Sprite2D in sprites:
		if not sprite.is_visible_in_tree() or sprite.texture == null:
			continue
		var used: Rect2i = sprite.texture.get_image().get_used_rect()
		var origin: Vector2 = sprite.get_rect().position + Vector2(used.position)
		var end: Vector2 = origin + Vector2(used.size)
		# Размер берётся из rest-позы: intro временно уменьшает Skeleton2D/Root.
		var part_transform: Transform2D = sprite.transform
		var ancestor: Node = sprite.get_parent()
		while ancestor != enemy and ancestor is Node2D:
			var ancestor_transform: Transform2D = (ancestor as Bone2D).rest if ancestor is Bone2D else (ancestor as Node2D).transform
			part_transform = ancestor_transform * part_transform
			ancestor = ancestor.get_parent()
		for point: Vector2 in [origin, end, Vector2(origin.x, end.y), Vector2(end.x, origin.y)]:
			var local: Vector2 = to_local(enemy.to_global(part_transform * point))
			bounds = Rect2(local, Vector2.ZERO) if first else bounds.expand(local)
			first = false
	if not first:
		_boss_bounds[cache_key] = bounds
		_apply_shield_bounds(bounds)


func _apply_shield_bounds(bounds: Rect2) -> void:
	shield_center = bounds.get_center()
	shield_radius = (bounds.size * 0.5 + Vector2(16.0, 16.0)) * 1.15
	for emitter: CPUParticles2D in [shield_sparks, shield_bolts]:
		emitter.position = shield_center
		emitter.scale = shield_radius / 60.0


func set_aura(kind: StringName) -> void:
	_aura = kind
	aura_particles.emitting = false
	rush_sparks.emitting = kind == &"rush"
	if kind.is_empty():
		return
	aura_particles.rotation = 0.0
	aura_particles.local_coords = kind != &"dash"
	aura_particles.texture = WIND if kind == &"dash" else EMBER
	if kind == &"dash":
		aura_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		aura_particles.position = Vector2(-23.0, -5.0)
		aura_particles.amount = 12
		aura_particles.lifetime = 0.35
		aura_particles.emission_rect_extents = Vector2(5.0, 26.0)
		aura_particles.direction = Vector2.LEFT
		aura_particles.spread = 20.0
		aura_particles.gravity = Vector2.ZERO
		aura_particles.initial_velocity_min = 55.0
		aura_particles.initial_velocity_max = 100.0
		aura_particles.scale_amount_min = 0.6
		aura_particles.scale_amount_max = 1.0
		aura_particles.self_modulate = Color("bdefff")
	else:
		var rush: bool = kind == &"rush"
		var edge: float = 71.0 if rush else 47.0
		aura_particles.position = Vector2(0.0, 24.0)
		aura_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
		aura_particles.emission_points = PackedVector2Array([Vector2(-edge, 0.0), Vector2(edge, 0.0), Vector2(-edge - 5.0, -14.0), Vector2(edge + 5.0, -14.0), Vector2(-edge + 3.0, 8.0), Vector2(edge - 3.0, 8.0)])
		aura_particles.amount = 20 if rush else 14
		aura_particles.lifetime = 0.65 if rush else 0.85
		aura_particles.emission_rect_extents = Vector2(50.0 if rush else 37.0, 6.0)
		aura_particles.direction = Vector2.UP
		aura_particles.spread = 15.0
		aura_particles.gravity = Vector2(0.0, -35.0)
		aura_particles.initial_velocity_min = 90.0 if rush else 52.0
		aura_particles.initial_velocity_max = 140.0 if rush else 85.0
		aura_particles.scale_amount_min = 0.65
		aura_particles.scale_amount_max = 1.2 if rush else 1.0
		aura_particles.self_modulate = Color(1.0, 0.34 if rush else 0.08, 0.05, 0.85)
	aura_particles.restart()
	aura_particles.emitting = not kind.is_empty()
	_refresh_processing()


func set_shield(ratio: float) -> void:
	var was_active: bool = _shield > 0.0
	_shield = ratio
	for emitter: CPUParticles2D in [shield_sparks, shield_bolts]:
		emitter.emitting = ratio > 0.0
		if ratio > 0.0 and not was_active:
			emitter.restart()
			emitter.emitting = true
	shield_sparks.self_modulate = Color(0.78, 0.48, 1.0, 0.55 + 0.45 * ratio)
	if was_active and ratio < 1.0:
		sparks.position = shield_center
		burst(Color("ddbcff"))
	_refresh_processing()


func break_plate(remaining: int) -> void:
	_broken_plate = _plates - 1
	_plates = remaining
	_fragments = 0.45
	sparks.position = Vector2((float(_broken_plate) - 1.0) * 38.0, armor_y)
	burst(Color("cb8fff"))
	_refresh_processing()


func telegraph(kind: StringName, duration: float) -> void:
	_warning = kind
	_warning_time = duration
	_warning_length = duration
	windup.position = Vector2(0.0, 14.0)
	windup.self_modulate = Color("c5f1ff") if kind == &"dash" else (Color("dfb9ff") if kind == &"summon" else Color("ff6948"))
	windup.restart()
	windup.emitting = true
	_refresh_processing()


func burst(tint: Color) -> void:
	sparks.self_modulate = Color(tint, 0.8)
	sparks.restart()
	sparks.emitting = true


func clear() -> void:
	_aura = &""
	_plates = 0
	_shield = 0.0
	_warning = &""
	_warning_time = 0.0
	_fragments = 0.0
	_time = 0.0
	for emitter: CPUParticles2D in [sparks, aura_particles, windup, shield_sparks, shield_bolts, rush_sparks]:
		if is_instance_valid(emitter):
			emitter.emitting = false
	_refresh_processing()


func _refresh_processing() -> void:
	# Частицы обновляются движком; redraw нужен только для отлетающего значка.
	set_process(_fragments > 0.0)
	queue_redraw()


func _process(delta: float) -> void:
	_fragments = maxf(_fragments - delta, 0.0)
	_refresh_processing()


func _draw() -> void:
	# Ауры и подготовка полностью состоят из частиц, прежняя SVG-аура не рисуется.
	if _shield > 0.0:
		draw_set_transform(shield_center, 0.0, shield_radius / 60.0)
		draw_circle(Vector2.ZERO, 60.0, Color(0.55, 0.3, 0.95, 0.055))
		draw_arc(Vector2.ZERO, 60.0, 0.0, TAU, 48, Color(0.8, 0.6, 1.0, 0.18), 1.0, true)
		draw_set_transform(Vector2.ZERO)
	for index: int in _plates:
		_draw_plate(index, Vector2.ZERO, 1.0)
	if _fragments > 0.0:
		var progress: float = 1.0 - _fragments / 0.45
		_draw_plate(_broken_plate, Vector2(10.0 * progress, 22.0 * progress), 1.0 - progress)


func _draw_plate(index: int, offset: Vector2, alpha: float) -> void:
	var size: Vector2 = Vector2(28.0, 36.0) * 1.2
	var center: Vector2 = Vector2((float(index) - 1.0) * 38.0, armor_y) + offset
	draw_texture_rect(PURPLE_PLATE, Rect2(center - size * 0.5, size), false, Color(1.0, 1.0, 1.0, alpha))


func set_motion(direction: Vector2) -> void:
	if direction.length_squared() < 0.000001 or _aura not in [&"dash", &"rush"]:
		return
	var local: Vector2 = global_transform.basis_xform_inv(direction).normalized()
	if _aura == &"dash":
		aura_particles.rotation = local.angle()
		aura_particles.position = -local * 23.0 + Vector2(0.0, -5.0)
	else:
		rush_sparks.rotation = local.angle()
		rush_sparks.position = -local * 22.0
