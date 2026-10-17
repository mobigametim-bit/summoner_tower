extends Node2D

var _points: PackedVector2Array
var _goal: Vector2
var _duration: float = 1.2
var _elapsed: float = 0.0
var _caster: WeakRef


func initialize(points: PackedVector2Array, goal: Vector2, duration: float, caster: ApproachingEnemy) -> void:
	_points = points
	_goal = goal
	_duration = duration
	_caster = weakref(caster)
	for i: int in 3:
		var bone: Node2D = get_node("Bone%d"%i) as Node2D
		bone.visible = i < points.size()
		if bone.visible:
			bone.global_position = points[i]


func _process(delta: float) -> void:
	var caster: ApproachingEnemy = _caster.get_ref() as ApproachingEnemy if _caster != null else null
	if caster == null or not caster.is_targetable():
		queue_free()
		return
	if caster._freeze_remaining > 0.0:
		return
	_elapsed += delta
	if _elapsed > _duration:
		queue_free()
		return
	if caster._route != null:
		var spacing: float = (caster.abilities as GraveyardAbilities).undead_config.summon_spacing
		_goal = caster._route_transform*caster._route.sample_baked(maxf(caster._distance-spacing,0.0))
	var t: float = clampf((_elapsed-0.2)/maxf(_duration-0.2,0.001),0.0,1.0)
	for i: int in mini(_points.size(),3):
		var bone: Node2D = get_node("Bone%d"%i) as Node2D
		bone.global_position = _points[i].lerp(_goal,t*t)
		bone.rotation = TAU*t
