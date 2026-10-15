extends Node2D

@export var duration: float = 0.7

var _age: float = 0.0
var _radius: float = 50.0
var _color: Color = Color("ffad46")


func configure(kind: int, radius: float) -> void:
	_radius = radius
	_color = [Color("ffdc82"), Color("ffad46"), Color("8eeaff")][kind]
	var emitter: CPUParticles2D = [$Streaks, $Fire, $Frost][kind]
	emitter.emission_sphere_radius = radius * 0.55
	emitter.restart()
	emitter.emitting = true


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	var progress: float = clampf(_age / duration, 0.0, 1.0)
	draw_circle(Vector2.ZERO, _radius, Color(_color, 0.14 * (1.0 - progress)))
	draw_circle(Vector2.ZERO, _radius * lerpf(0.18, 1.0, progress), Color(_color, 0.8 * (1.0 - progress)), false, 3.0, true)
