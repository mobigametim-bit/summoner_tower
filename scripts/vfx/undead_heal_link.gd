extends Node2D

var _caster: WeakRef
var _target: WeakRef
var _elapsed: float = 0.0


func initialize(caster: ApproachingEnemy, target: ApproachingEnemy) -> void:
	_caster = weakref(caster)
	_target = weakref(target)
	_update_link()
	$Flow.restart()
	$Receiver.restart()


func _update_link() -> bool:
	var caster: ApproachingEnemy = _caster.get_ref() as ApproachingEnemy if _caster != null else null
	var target: ApproachingEnemy = _target.get_ref() as ApproachingEnemy if _target != null else null
	if caster == null or target == null or not caster.is_targetable() or not target.is_targetable():
		return false
	var start: Vector2 = to_local(caster.undead_visual.to_global(Vector2(84,-50)))
	var end: Vector2 = to_local(target.global_position+Vector2(0,-10))
	var points: PackedVector2Array = []
	for i: int in 24:
		var t: float = i/23.0
		points.append(start.lerp(end,t)+Vector2(0,-sin(t*PI)*24))
	$Link.points = points
	$Flow.emission_points = points
	$Source.position = start
	$Target.position = end
	$Receiver.position = end
	return true


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 0.8 or not _update_link():
		queue_free()
	else:
		modulate.a = minf(_elapsed/0.08,1.0)*clampf((0.8-_elapsed)/0.25,0.0,1.0)
