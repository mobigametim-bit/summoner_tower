extends Control

const PLAY_ICON: Texture2D = preload("res://assets/ui/play.svg")
const LOCK_ICON: Texture2D = preload("res://assets/ui/locked.svg")

@export_file("*.tscn") var game_scene_path: String = "res://scenes/game.tscn"
@export_file("*.tscn") var upgrades_scene_path: String = "res://scenes/meta_upgrades.tscn"

@onready var play_button: Button = %PlayButton
@onready var biome_title: Label = $Center/VBox/Title
@onready var crystal_balance: Label = $Center/VBox/CrystalWallet/CrystalBalance
@onready var upgrades_button: Button = %UpgradesButton
@onready var settings_button: Button = %SettingsButton
@onready var settings_overlay: Control = $AudioSettingsOverlay
@onready var crystal_wallet: HBoxContainer = $Center/VBox/CrystalWallet
@onready var biome_navigation: Control = $BiomeNavigation
@onready var previous_biome: Button = $BiomeNavigation/PreviousBiome
@onready var next_biome: Button = $BiomeNavigation/NextBiome
@onready var backdrop: Node2D = $Backdrop
@onready var biome_placeholder: Control = $BiomePlaceholder

var _is_starting: bool = false


func _ready() -> void:
	AudioService.play_music(&"menu")
	_update_crystals(SessionProgress.crystals)
	SessionProgress.crystals_changed.connect(_update_crystals)
	SessionProgress.biomes_changed.connect(_update_biome)
	_update_biome()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_biome()
	elif what == NOTIFICATION_RESIZED and is_node_ready():
		_align_biome_navigation.call_deferred()


func _update_biome() -> void:
	var biome: BiomeDefinition = SessionProgress.selected_biome()
	biome_title.text = tr(biome.title)
	previous_biome.visible = SessionProgress.biome_catalog.neighbor(biome.biome_id, -1, SessionProgress.unlocked_biomes) != null
	next_biome.visible = SessionProgress.biome_catalog.neighbor(biome.biome_id, 1, SessionProgress.unlocked_biomes) != null
	biome_navigation.visible = previous_biome.visible or next_biome.visible
	_align_biome_navigation.call_deferred()
	previous_biome.disabled = _is_starting or settings_overlay.visible
	next_biome.disabled = previous_biome.disabled
	play_button.disabled = _is_starting or settings_overlay.visible or not biome.is_playable()
	play_button.tooltip_text = tr("Play") if biome.is_playable() else tr("Coming soon")
	var play_visual: ButtonFeedback = play_button.get_node("FeedbackVisual") as ButtonFeedback
	play_visual.icon = PLAY_ICON if biome.is_playable() else LOCK_ICON
	play_visual.queue_redraw()
	# Финальная кладбищенская композиция производится отдельным art-этапом.
	if biome.menu_backdrop != null and backdrop.scene_file_path != biome.menu_backdrop.resource_path:
		remove_child(backdrop)
		backdrop.queue_free()
		backdrop = biome.menu_backdrop.instantiate() as Node2D
		backdrop.name = "Backdrop"
		add_child(backdrop)
		move_child(backdrop, 1)
	backdrop.visible = biome.menu_backdrop != null
	biome_placeholder.visible = biome.menu_backdrop == null
	$BiomePlaceholder/Name.text = tr("Coming soon")


func _align_biome_navigation() -> void:
	# Контейнер сначала размещает кошелёк; стрелки привязаны к его фактическому центру.
	var wallet_center: Vector2 = get_global_transform().affine_inverse() * crystal_wallet.get_global_rect().get_center()
	biome_navigation.position.y = wallet_center.y - biome_navigation.size.y * 0.5


func _on_previous_biome_pressed() -> void:
	_select_neighbor(-1)


func _on_next_biome_pressed() -> void:
	_select_neighbor(1)


func _select_neighbor(direction: int) -> void:
	if _is_starting or settings_overlay.visible:
		return
	var neighbor: BiomeDefinition = SessionProgress.biome_catalog.neighbor(SessionProgress.selected_biome_id, direction, SessionProgress.unlocked_biomes)
	if neighbor != null:
		SessionProgress.select_biome(neighbor.biome_id)


func _update_crystals(total: int) -> void:
	UiNumbers.show_value(crystal_balance, total)


func _on_play_button_pressed() -> void:
	if SessionProgress.selected_biome().is_playable():
		_open_scene(game_scene_path)


func _on_upgrades_button_pressed() -> void:
	_open_scene(upgrades_scene_path)


func _on_settings_button_pressed() -> void:
	if _is_starting:
		return
	play_button.disabled = true
	upgrades_button.disabled = true
	settings_button.disabled = true
	settings_overlay.open()
	_update_biome()


func _on_settings_closed() -> void:
	upgrades_button.disabled = false
	settings_button.disabled = false
	_update_biome()
	settings_button.grab_focus()


func _open_scene(path: String) -> void:
	if _is_starting:
		return

	_is_starting = true
	play_button.disabled = true
	upgrades_button.disabled = true
	settings_button.disabled = true
	previous_biome.disabled = true
	next_biome.disabled = true
	var error: Error = get_tree().change_scene_to_file(path)
	if error != OK:
		_is_starting = false
		upgrades_button.disabled = false
		settings_button.disabled = false
		_update_biome()
		push_error("Cannot open scene: %s (error %s)" % [path, error])
