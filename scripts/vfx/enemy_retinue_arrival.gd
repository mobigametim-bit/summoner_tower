extends Node2D


func _ready() -> void:
	$Rays.restart()
	$Rays.emitting = true
	$Sparks.restart()
	$Sparks.emitting = true


func _on_animation_finished(_animation: StringName) -> void:
	queue_free()
