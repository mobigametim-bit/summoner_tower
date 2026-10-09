class_name GameHud
extends Control

signal restart_requested
signal menu_requested
signal settings_requested
signal resume_requested

@onready var health_label: Label = %HealthLabel
@onready var game_over_overlay: Control = %GameOverOverlay
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton
@onready var mana_label: Label = %ManaLabel
@onready var mana_feedback: ManaFeedback = $BottomDock/Margin/Row/Counters/ManaIcon
@onready var wave_label: Label = %WaveLabel
@onready var bottom_dock: PanelContainer = $BottomDock
@onready var settings_button: Button = %SettingsButton
@onready var settings_overlay: Control = %SettingsOverlay
@onready var resume_button: Button = %ResumeButton
@onready var boss_warning: BossWarning = $BossWarning
@export var wave_config: WaveConfig

var _displayed_mana: int = -1
var _last_announced_boss_wave: int = 0


func update_wave(wave: int, phase: WaveManager.Phase, _seconds: int, _alive: int, _pending: int) -> void:
	var boss_wave: bool = wave_config != null and wave_config.is_boss_wave(wave)
	var title: String = "BOSS" if boss_wave else "WAVE"
	wave_label.modulate = Color("ffb968") if boss_wave else Color.WHITE
	UiNumbers.show_value(wave_label, wave, title + " ")
	if phase != WaveManager.Phase.FIGHTING:
		boss_warning.stop_warning()
	elif boss_wave and phase == WaveManager.Phase.FIGHTING and wave != _last_announced_boss_wave:
		# state_changed приходит также при каждом спавне и убийстве; показываем один раз за волну.
		_last_announced_boss_wave = wave
		boss_warning.play_warning()


func update_health(current: int, _maximum: int) -> void:
	UiNumbers.show_value(health_label, current)
	_fit_counter(health_label)


func set_field_bottom(bottom: float) -> void:
	# Строки целые: HUD примыкает к последней клетке, остаток высоты принадлежит панели.
	bottom_dock.offset_top = bottom - size.y


func _fit_counter(label: Label) -> void:
	var font: Font = label.get_theme_font("font")
	var font_size: int = 48
	var width: float = label.custom_minimum_size.x
	# Реальная ширина цифр зависит от шрифта, а не только от их количества.
	while font_size > 36 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > width:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


func set_settings_available(available: bool) -> void:
	settings_button.disabled = not available


func show_settings() -> void:
	boss_warning.stop_warning()
	settings_overlay.show()
	resume_button.grab_focus()


func close_settings() -> void:
	settings_overlay.hide()
	resume_button.release_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if settings_overlay.visible and event.is_action_pressed(&"ui_cancel"):
		resume_requested.emit()
		get_viewport().set_input_as_handled()


func _on_settings_button_pressed() -> void:
	settings_requested.emit()


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func show_game_over(stats: RunStatistics) -> void:
	close_settings()
	set_settings_available(false)
	var stack: VBoxContainer = game_over_overlay.get_node("Center/Panel/Stack")
	UiNumbers.show_value(stack.get_node("Stats/Wave/Value"), stats.reached_wave)
	UiNumbers.show_value(stack.get_node("Stats/Enemies/Value"), stats.killed_enemies)
	UiNumbers.show_value(stack.get_node("Stats/Bosses/Value"), stats.killed_bosses)
	UiNumbers.show_value(stack.get_node("Stats/Merges/Value"), stats.merges)
	UiNumbers.show_value(stack.get_node("Reward/Amount"), stats.earned_crystals, "+")
	game_over_overlay.show()
	restart_button.grab_focus()


func update_summon(mana: int, _cost: int, _occupied: int, _capacity: int, _available: bool) -> void:
	UiNumbers.show_value(mana_label, mana)
	_fit_counter(mana_label)
	if _displayed_mana >= 0:
		if mana > _displayed_mana:
			mana_feedback.play_gain()
		elif mana < _displayed_mana:
			mana_feedback.stop_feedback()
	_displayed_mana = mana


func set_actions_enabled(enabled: bool) -> void:
	restart_button.disabled = not enabled
	menu_button.disabled = not enabled


func _on_restart_button_pressed() -> void:
	restart_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()
