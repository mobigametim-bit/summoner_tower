extends Node2D

const DESIGN_WIDTH: float = 720.0

@onready var tower: Node2D = $Tower


func _ready() -> void:
	var menu: Control = get_parent() as Control
	if menu != null:
		menu.resized.connect(_center_in_menu)
		_center_in_menu()


func _center_in_menu() -> void:
	var menu: Control = get_parent() as Control
	position.x = (menu.size.x - DESIGN_WIDTH) * 0.5


func _on_energy_pulse() -> void:
	tower.call("show_tap")
