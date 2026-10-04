class_name TowerHealth
extends Node2D

signal health_changed(current: int, maximum: int)
signal destroyed

var current_health: int = 0
var max_health: int = 0
var _is_destroyed: bool = false


func initialize(health: int) -> void:
	max_health = maxi(health, 1)
	current_health = max_health
	_is_destroyed = false
	modulate = Color.WHITE
	health_changed.emit(current_health, max_health)


func take_damage(amount: int) -> void:
	if _is_destroyed or amount <= 0:
		return

	current_health = maxi(current_health - amount, 0)
	_is_destroyed = current_health == 0
	if _is_destroyed:
		modulate = Color(0.45, 0.45, 0.45)
	health_changed.emit(current_health, max_health)
	if _is_destroyed:
		destroyed.emit()
