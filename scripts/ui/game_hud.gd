class_name GameHud
extends Control

signal restart_requested
signal menu_requested

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var game_over_overlay: Control = %GameOverOverlay
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton


func update_health(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "TOWER HP  %d / %d" % [current, maximum]


func show_game_over() -> void:
	game_over_overlay.show()
	restart_button.grab_focus()


func set_actions_enabled(enabled: bool) -> void:
	restart_button.disabled = not enabled
	menu_button.disabled = not enabled


func _on_restart_button_pressed() -> void:
	restart_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()
