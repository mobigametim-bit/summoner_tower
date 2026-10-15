extends Node2D

@onready var back: CPUParticles2D = $BurnBack
@onready var front: CPUParticles2D = $BurnFront
@onready var ice: Sprite2D = $Ice


func show_status(burning: bool, frozen: bool) -> void:
	for emitter: CPUParticles2D in [back, front]:
		if burning and not emitter.visible:
			emitter.restart()
		emitter.visible = burning
		emitter.emitting = burning
	ice.visible = frozen
