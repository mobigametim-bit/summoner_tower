extends Node2D

@onready var player: AnimationPlayer = $AnimationPlayer
var _particles: Array[CPUParticles2D] = []
var _speed: float = 1.0
var _paused: bool = false
var _elapsed: float = 0.0
var _pending: Array[CPUParticles2D] = []


func _ready() -> void:
	for child: Node in find_children("*", "CPUParticles2D", true, false):
		_particles.append(child as CPUParticles2D)
	player.animation_finished.connect(_on_finished)


func start(speed: float) -> void:
	_elapsed = 0.0
	_pending.clear()
	set_speed(speed)
	player.play(&"effect")
	player.advance(0.0)
	for particles: CPUParticles2D in _particles:
		if float(particles.get_meta("start_delay",0.0)) > 0.0:
			particles.emitting = false
			_pending.append(particles)
		else:
			particles.restart()
			particles.emitting = true


func set_speed(value: float) -> void:
	_speed = value
	player.speed_scale = value
	for particles: CPUParticles2D in _particles:
		particles.speed_scale = 0.0 if _paused else value


func set_paused(value: bool) -> void:
	_paused = value
	for particles: CPUParticles2D in _particles:
		particles.speed_scale = 0.0 if value else _speed
	if value:
		player.pause()
	else:
		player.play()


func _process(delta: float) -> void:
	if not _paused:
		_elapsed += delta * _speed
		for i: int in range(_pending.size()-1,-1,-1):
			var particles: CPUParticles2D = _pending[i]
			if _elapsed >= float(particles.get_meta("start_delay",0.0)):
				particles.restart()
				particles.emitting = true
				_pending.remove_at(i)
		if _elapsed > 5.0:
			queue_free()


func _on_finished(_animation_name: StringName) -> void:
	queue_free()
