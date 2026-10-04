extends Control

@export_file("*.tscn") var game_scene_path: String = "res://scenes/game.tscn"

@onready var play_button: Button = %PlayButton

var _is_starting: bool = false


func _on_play_button_pressed() -> void:
	if _is_starting:
		return

	_is_starting = true
	play_button.disabled = true
	var error: Error = get_tree().change_scene_to_file(game_scene_path)
	if error != OK:
		_is_starting = false
		play_button.disabled = false
		push_error("Cannot open game scene: %s (error %s)" % [game_scene_path, error])
