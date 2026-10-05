extends Control

@export_file("*.tscn") var game_scene_path: String = "res://scenes/game.tscn"
@export_file("*.tscn") var upgrades_scene_path: String = "res://scenes/meta_upgrades.tscn"

@onready var play_button: Button = %PlayButton
@onready var crystal_balance: Label = $Center/VBox/CrystalWallet/CrystalBalance
@onready var upgrades_button: Button = %UpgradesButton

var _is_starting: bool = false


func _ready() -> void:
	_update_crystals(SessionProgress.crystals)
	SessionProgress.crystals_changed.connect(_update_crystals)


func _update_crystals(total: int) -> void:
	crystal_balance.text = str(total)


func _on_play_button_pressed() -> void:
	_open_scene(game_scene_path)


func _on_upgrades_button_pressed() -> void:
	_open_scene(upgrades_scene_path)


func _open_scene(path: String) -> void:
	if _is_starting:
		return

	_is_starting = true
	play_button.disabled = true
	upgrades_button.disabled = true
	var error: Error = get_tree().change_scene_to_file(path)
	if error != OK:
		_is_starting = false
		play_button.disabled = false
		upgrades_button.disabled = false
		push_error("Cannot open scene: %s (error %s)" % [path, error])
