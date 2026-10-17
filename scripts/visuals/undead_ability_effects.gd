extends Node2D

@export var effect_scenes: Dictionary[StringName, PackedScene] = {}

var _current: Node2D
var _speed: float = 1.0
var _paused: bool = false


func play_effect(effect_name: StringName) -> void:
	stop_effects()
	if not effect_scenes.has(effect_name):
		return
	_current = effect_scenes[effect_name].instantiate() as Node2D
	add_child(_current)
	_current.call("start", _speed)
	_current.call("set_paused", _paused)


func stop_effects() -> void:
	if is_instance_valid(_current):
		_current.queue_free()
	_current = null


func set_speed(value: float) -> void:
	_speed = value
	if is_instance_valid(_current):
		_current.call("set_speed", value)


func set_paused(value: bool) -> void:
	_paused = value
	if is_instance_valid(_current):
		_current.call("set_paused", value)
