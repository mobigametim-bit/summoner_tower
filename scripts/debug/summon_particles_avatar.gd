extends Node2D

@onready var unit: ArcherVisual = $Unit
@onready var rays: CPUParticles2D = $Rays

var requests: int = 0
var _reveal: Tween


func summon() -> void:
	requests += 1
	if _reveal != null:
		_reveal.kill()
	unit.visible = true
	unit.modulate.a = 0.0
	unit.play_animation(&"spawn")
	rays.restart()
	_reveal = create_tween()
	_reveal.tween_interval(0.1)
	_reveal.tween_property(unit, "modulate:a", 1.0, 0.3)


func _exit_tree() -> void:
	if _reveal != null:
		_reveal.kill()
