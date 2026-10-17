extends "res://scripts/ui/main_menu_backdrop.gd"

@export_range(1, 5, 1) var mage_level: int = 2


func _ready() -> void:
	super._ready()
	($FireMage as MageVisual).set_level(mage_level)
