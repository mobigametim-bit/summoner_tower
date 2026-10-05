extends Control

@export_file("*.tscn") var game_scene_path: String = "res://scenes/game.tscn"

@onready var play_button: Button = %PlayButton
@onready var crystal_balance: Label = $Center/VBox/CrystalWallet/CrystalBalance

var _is_starting: bool = false


func _ready() -> void:
	_update_crystals(SessionProgress.crystals)
	SessionProgress.crystals_changed.connect(_update_crystals)


func _update_crystals(total: int) -> void:
	crystal_balance.text = str(total)


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
