class_name BossWarning
extends Control

@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	hide()


func play_warning() -> void:
	animation_player.stop()
	show()
	animation_player.play(&"warning")
	animation_player.advance(0.0)


func stop_warning() -> void:
	animation_player.stop()
	hide()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"warning":
		hide()
