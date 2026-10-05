class_name GameHud
extends Control

signal restart_requested
signal menu_requested
signal summon_requested

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var game_over_overlay: Control = %GameOverOverlay
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton
@onready var mana_label: Label = %ManaLabel
@onready var summon_button: Button = %SummonButton


func update_health(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "TOWER HP  %d / %d" % [current, maximum]


func show_game_over() -> void:
	game_over_overlay.show()
	restart_button.grab_focus()


func update_summon(mana: int, cost: int, occupied: int, capacity: int, available: bool) -> void:
	mana_label.text = "MANA %d" % mana
	if occupied >= capacity:
		mana_label.text += " / FIELD FULL"
	elif mana < cost:
		mana_label.text += " / NEED %d" % cost
	summon_button.text = "SUMMON · %d MANA" % cost
	summon_button.disabled = not available


func set_actions_enabled(enabled: bool) -> void:
	restart_button.disabled = not enabled
	menu_button.disabled = not enabled


func _on_restart_button_pressed() -> void:
	restart_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()


func _on_summon_button_pressed() -> void:
	summon_requested.emit()
