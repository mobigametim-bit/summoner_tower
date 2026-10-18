class_name GameHud
extends Control

signal restart_requested
signal menu_requested
signal settings_requested
signal resume_requested
signal revive_accepted
signal revive_declined
signal double_reward_requested
signal rewarded_view_canceled
signal save_result_requested

@onready var health_label: Label = %HealthLabel
@onready var game_over_overlay: Control = %GameOverOverlay
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton
@onready var mana_label: Label = %ManaLabel
@onready var mana_feedback: ManaFeedback = %ManaLabel.get_parent().get_node("ManaIcon")
@onready var wave_label: Label = %WaveLabel
@onready var bottom_dock: PanelContainer = $BottomDock
@onready var settings_button: Button = %SettingsButton
@onready var settings_overlay: Control = %SettingsOverlay
@onready var resume_button: Button = %ResumeButton
@onready var boss_warning: BossWarning = $BossWarning
@onready var revive_overlay: Control = $ReviveOverlay
@onready var ad_overlay: Control = $RewardedOverlay
@onready var double_reward_button: Button = $GameOverOverlay/Center/Panel/Stack/Actions/DoubleRewardButton
@export var wave_config: WaveConfig
@export var mana_reward_scene: PackedScene
@export_range(1, 64) var maximum_mana_popups: int = 32
@export_range(16, 96, 1) var counter_font_size: int = 64
@export_range(16, 96, 1) var counter_minimum_font_size: int = 40

@onready var mana_rewards: Node2D = $ManaRewards

var _displayed_mana: int = -1
var _last_announced_boss_wave: int = 0
var field_rect: Rect2 = Rect2(0,0,720,1080)
var _side_hud: bool = false
var _wave_number: int = 1
var _wave_title: String = ""


func _ready() -> void:
	# MarginContainer завершает раскладку после смены размера dock, позднее камеры.
	$BottomDock/Margin/Row.resized.connect(_place_controls)


func configure_layout(field: Rect2, dock: Rect2, side: bool) -> void:
	field_rect = field
	_side_hud = side
	bottom_dock.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	bottom_dock.position = dock.position
	bottom_dock.size = dock.size
	var row: Control = $BottomDock/Margin/Row
	var counters: GridContainer = row.get_node("Counters")
	counters.columns = 1 if side else 2
	counters.add_theme_constant_override("v_separation",36 if side else 0)
	var compact: bool = ScreenLayout.landscape()
	for label: Label in [health_label,mana_label]:
		label.custom_minimum_size = Vector2(100,70) if compact else Vector2(112,80)
		label.add_theme_font_size_override("font_size",44 if compact else counter_font_size)
	for icon: Control in [health_label.get_parent().get_node("HealthIcon"),mana_feedback]:
		icon.custom_minimum_size = Vector2(44,54) if compact else Vector2(54,65)
	settings_button.custom_minimum_size = Vector2(84,84) if side else (Vector2(64,64) if compact else Vector2(104,104))
	wave_label.custom_minimum_size = Vector2.ZERO
	wave_label.add_theme_font_size_override("font_size",38 if side else (32 if compact else 42))
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if side else HORIZONTAL_ALIGNMENT_LEFT
	_format_wave()
	_place_controls.call_deferred()


func _place_controls() -> void:
	var row: Control = $BottomDock/Margin/Row
	var counters: Control = row.get_node("Counters")
	counters.reset_size()
	settings_button.size = settings_button.custom_minimum_size
	if _side_hud:
		wave_label.position = Vector2(0,24)
		wave_label.size = Vector2(row.size.x,120)
		counters.position = Vector2((row.size.x-counters.size.x)*0.5,row.size.y*0.31)
		settings_button.position = Vector2((row.size.x-settings_button.size.x)*0.5,row.size.y-settings_button.size.y-32)
	else:
		wave_label.position = Vector2.ZERO
		wave_label.size = Vector2(192,row.size.y)
		counters.position = Vector2(maxf(198.0,(row.size.x-counters.size.x)*0.5),(row.size.y-counters.size.y)*0.5)
		settings_button.position = Vector2(row.size.x-settings_button.size.x,(row.size.y-settings_button.size.y)*0.5)


func _format_wave() -> void:
	UiNumbers.show_value(wave_label,_wave_number,_wave_title+("\n" if _side_hud else " "))


func update_wave(wave: int, phase: WaveManager.Phase, _seconds: int, _alive: int, _pending: int) -> void:
	var boss_wave: bool = wave_config != null and wave_config.is_boss_wave(wave)
	var title: String = tr("BOSS") if boss_wave else tr("WAVE")
	_wave_title = title
	_wave_number = wave
	wave_label.modulate = Color("ffb968") if boss_wave else Color.WHITE
	_format_wave()
	if phase != WaveManager.Phase.FIGHTING:
		boss_warning.stop_warning()
	elif boss_wave and phase == WaveManager.Phase.FIGHTING and wave != _last_announced_boss_wave:
		# state_changed приходит также при каждом спавне и убийстве; показываем один раз за волну.
		_last_announced_boss_wave = wave
		AudioService.play_sfx(&"boss")
		boss_warning.play_warning()


func update_health(current: int, _maximum: int) -> void:
	UiNumbers.show_value(health_label, current)
	_fit_counter(health_label)


func set_field_bottom(bottom: float) -> void:
	# Строки целые: HUD примыкает к последней клетке, остаток высоты принадлежит панели.
	bottom_dock.offset_top = bottom - size.y


func _fit_counter(label: Label) -> void:
	var font: Font = label.get_theme_font("font")
	var font_size: int = 44 if ScreenLayout.landscape() else counter_font_size
	var width: float = label.custom_minimum_size.x
	# Реальная ширина цифр зависит от шрифта, а не только от их количества.
	while font_size > mini(counter_minimum_font_size, counter_font_size) and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > width:
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
	stack.get_node("Title").text = tr("VICTORY") if stats.victory else tr("RUN RESULT")
	var unlock_notice: Label = stack.get_node("BiomeUnlocked")
	unlock_notice.visible = not stats.newly_unlocked_biome.is_empty()
	if unlock_notice.visible:
		var unlocked: BiomeDefinition = SessionProgress.biome_catalog.find(stats.newly_unlocked_biome)
		unlock_notice.text = tr("BIOME UNLOCKED: %s") % tr(unlocked.title)
	stack.get_node("SaveResult").visible = not stats.result_saved
	UiNumbers.show_value(stack.get_node("Stats/Wave/Value"), stats.reached_wave)
	UiNumbers.show_value(stack.get_node("Stats/Enemies/Value"), stats.killed_enemies)
	UiNumbers.show_value(stack.get_node("Stats/Bosses/Value"), stats.killed_bosses)
	UiNumbers.show_value(stack.get_node("Stats/Merges/Value"), stats.merges)
	UiNumbers.show_value(stack.get_node("Reward/Amount"), stats.earned_crystals, "+")
	game_over_overlay.show()
	set_actions_enabled(true)
	set_double_reward_available(stats.can_double_reward())
	show_reward_error(false)
	restart_button.grab_focus()


func update_summon(mana: int, _cost: int, _occupied: int, _capacity: int, _available: bool) -> void:
	UiNumbers.show_value(mana_label, mana)
	_fit_counter(mana_label)
	if _displayed_mana >= 0 and mana != _displayed_mana:
		mana_feedback.play_change(mana > _displayed_mana)
	_displayed_mana = mana


func show_mana_reward(canvas_position: Vector2, amount: int) -> void:
	if amount <= 0 or mana_reward_scene == null:
		return
	# Ограничиваем одновременно видимые подписи при массовом убийстве области.
	while mana_rewards.get_child_count() >= maximum_mana_popups:
		var oldest: Node = mana_rewards.get_child(0)
		mana_rewards.remove_child(oldest)
		oldest.queue_free()
	var popup: ManaRewardPopup = mana_reward_scene.instantiate() as ManaRewardPopup
	mana_rewards.add_child(popup)
	var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * canvas_position
	popup.position = Vector2(clampf(local_position.x, field_rect.position.x+60.0, field_rect.end.x-60.0), clampf(local_position.y-32.0,field_rect.position.y+40.0,field_rect.end.y-24.0))
	popup.play_reward(amount)


func set_actions_enabled(enabled: bool) -> void:
	restart_button.disabled = not enabled
	menu_button.disabled = not enabled
	double_reward_button.disabled = not enabled or double_reward_button.has_meta("unavailable")


func set_double_reward_available(available: bool) -> void:
	if available:
		double_reward_button.remove_meta("unavailable")
	else:
		double_reward_button.set_meta("unavailable", true)
	double_reward_button.disabled = not available


func show_revive_offer(health: int, failed: bool = false) -> void:
	boss_warning.stop_warning()
	UiNumbers.show_value(revive_overlay.get_node("Center/Panel/Stack/Reward/Amount"), health, "+")
	revive_overlay.get_node("Center/Panel/Stack/Error").visible = failed
	revive_overlay.show()
	revive_overlay.get_node("Center/Panel/Stack/Actions/Accept").grab_focus()


func close_revive_offer() -> void:
	revive_overlay.hide()


func show_rewarded_view() -> void:
	update_ad_progress(0.0)
	ad_overlay.show()
	ad_overlay.get_node("Center/Panel/Stack/Cancel").grab_focus()


func close_rewarded_view() -> void:
	ad_overlay.hide()


func update_ad_progress(value: float) -> void:
	ad_overlay.get_node("Center/Panel/Stack/Progress").value = value


func show_reward_error(failed: bool) -> void:
	game_over_overlay.get_node("Center/Panel/Stack/RewardError").visible = failed


func _on_revive_accepted() -> void:
	revive_accepted.emit()


func _on_revive_declined() -> void:
	revive_declined.emit()


func _on_double_reward_pressed() -> void:
	double_reward_requested.emit()


func _on_save_result_pressed() -> void:
	save_result_requested.emit()


func _on_rewarded_cancel_pressed() -> void:
	rewarded_view_canceled.emit()


func _on_restart_button_pressed() -> void:
	restart_requested.emit()


func _on_menu_button_pressed() -> void:
	menu_requested.emit()
