extends Control

@export_file("*.tscn") var menu_scene_path: String = "res://scenes/main_menu.tscn"

@onready var crystal_balance: Label = $Center/Stack/Wallet/Amount
@onready var back_button: Button = $Center/Stack/Header/BackButton

var _leaving: bool = false


func _ready() -> void:
	_update_crystals(SessionProgress.crystals)
	SessionProgress.crystals_changed.connect(_update_crystals)
	back_button.grab_focus()


func _update_crystals(total: int) -> void:
	crystal_balance.text = str(total)


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	back_button.disabled = true
	var error: Error = get_tree().change_scene_to_file(menu_scene_path)
	if error != OK:
		_leaving = false
		back_button.disabled = false
		push_error("Cannot open menu: %s (error %s)" % [menu_scene_path, error])
