class_name GameHud
extends Control

signal restart_requested
signal menu_requested

@onready var health_label: Label = %HealthLabel
@onready var game_over_overlay: Control = %GameOverOverlay
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton
@onready var mana_label: Label = %ManaLabel
@onready var wave_label: Label = %WaveLabel
@export var wave_config: WaveConfig


func update_wave(wave: int, _phase: WaveManager.Phase, _seconds: int, _alive: int, _pending: int) -> void:
	var boss_wave: bool = wave_config != null and wave_config.is_boss_wave(wave)
	var title: String = "BOSS WAVE" if boss_wave else "WAVE"
	wave_label.modulate = Color("ffb968") if boss_wave else Color.WHITE
	wave_label.text = "%s %d" % [title, wave]


func update_health(current: int, _maximum: int) -> void:
	health_label.text = str(current)


func show_game_over() -> void:
	game_over_overlay.show()
	restart_button.grab_focus()


func update_summon(mana: int, _cost: int, _occupied: int, _capacity: int, _available: bool) -> void:
	mana_label.text = str(mana)


func set_actions_enabled(enabled: bool) -> void:
	restart_button.disabled = not enabled
	menu_button.disabled = not enabled


func _on_restart_button_pressed() -> void:
	restart_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()
