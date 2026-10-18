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
@onready var shop_button: Button = %ShopButton
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
	crystal_wallet.resized.connect(_position_crystal_wallet)
	SessionProgress.biomes_changed.connect(_update_biome)
	_update_biome()
	_layout_menu.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_biome()
	elif what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_menu.call_deferred()


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
	_layout_menu.call_deferred()


func _align_biome_navigation() -> void:
	if ScreenLayout.landscape():
		var center: Vector2 = biome_title.position+biome_title.size*0.5
		var font: Font = biome_title.get_theme_font("font")
		var text_width: float = font.get_string_size(biome_title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,biome_title.get_theme_font_size("font_size")).x
		biome_navigation.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		biome_navigation.position = Vector2(0,center.y-55)
		biome_navigation.size = Vector2(size.x-142.0,110)
		for button: Button in [previous_biome,next_biome]:
			button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			button.custom_minimum_size = Vector2(110,110)
			var x: float = center.x-text_width*0.5-134.0 if button==previous_biome else center.x+text_width*0.5+24.0
			button.position = Vector2(x,0)
			button.size = Vector2(110,110)
		return
	# Контейнер сначала размещает кошелёк; стрелки привязаны к его фактическому центру.
	var wallet_center: Vector2 = get_global_transform().affine_inverse() * crystal_wallet.get_global_rect().get_center()
	biome_navigation.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	biome_navigation.position = Vector2(0,wallet_center.y-44)
	biome_navigation.size = Vector2(size.x,88)
	for button: Button in [previous_biome,next_biome]:
		button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		button.custom_minimum_size = Vector2(96,88)
		button.size = Vector2(96,88)
		button.position = Vector2(24 if button == previous_biome else size.x-120,0)


func _layout_menu() -> void:
	var horizontal: bool = ScreenLayout.landscape()
	var layout: Control = $Center/VBox
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var actions: GridContainer = layout.get_node("Actions")
	for name: String in ["WalletTopSpacer","WalletBottomSpacer"]:
		layout.get_node(name).hide()
	actions.columns = 1 if horizontal else 4
	actions.add_theme_constant_override("h_separation",24)
	actions.add_theme_constant_override("v_separation",16)
	var tablet: bool = horizontal and size.x / size.y < 1.6
	var tablet_factor: float = size.y / 768.0
	var button_side: float = 100.0 * tablet_factor if tablet else 110.0 if horizontal else 128.0
	for button: Button in [play_button,upgrades_button,shop_button,settings_button]:
		button.custom_minimum_size = Vector2.ONE * button_side
	if tablet:
		actions.add_theme_constant_override("v_separation", roundi(20 * tablet_factor))
	actions.reset_size()
	biome_title.add_theme_font_size_override("font_size",58 if horizontal else 72)
	biome_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if horizontal else VERTICAL_ALIGNMENT_TOP
	var wallet_factor: float = size.y / 390.0 if horizontal else size.x / 390.0
	crystal_balance.add_theme_font_size_override("font_size", roundi((34 if horizontal else 43) * wallet_factor))
	crystal_wallet.get_node("Icon").custom_minimum_size = (Vector2(30,35) if horizontal else Vector2(39,45)) * wallet_factor
	crystal_wallet.add_theme_constant_override("separation", roundi(10 * (tablet_factor if tablet else wallet_factor)))
	if tablet:
		crystal_balance.add_theme_font_size_override("font_size", roundi(68 * tablet_factor))
		crystal_wallet.get_node("Icon").custom_minimum_size = Vector2(60,70) * tablet_factor
	crystal_wallet.reset_size()
	if horizontal:
		biome_title.position = Vector2(0,56)
		biome_title.size = Vector2(size.x-142.0,80)
		actions.position = Vector2(size.x - size.x * 0.05 - button_side, size.y * (0.35 if tablet else 0.24))
	else:
		# Та же вертикальная композиция: название, центрированный кошелёк, ряд действий.
		var center_y: float = size.y*0.5
		biome_title.position = Vector2(24,center_y-184)
		biome_title.size = Vector2(size.x-48,96)
		actions.position = Vector2((size.x-actions.size.x)*0.5,center_y+124)
	_position_crystal_wallet.call_deferred()
	_align_biome_navigation.call_deferred()


func _position_crystal_wallet() -> void:
	if not is_node_ready():
		return
	if ScreenLayout.landscape():
		var actions: Control = $Center/VBox/Actions
		var center: Vector2 = Vector2(actions.position.x + play_button.custom_minimum_size.x * 0.5, biome_title.position.y + biome_title.size.y * 0.5)
		crystal_wallet.position = center - crystal_wallet.size * 0.5
	else:
		crystal_wallet.position = Vector2((size.x-crystal_wallet.size.x)*0.5, size.y*0.44)
		_align_biome_navigation.call_deferred()


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
	_position_crystal_wallet.call_deferred()


func _on_play_button_pressed() -> void:
	if SessionProgress.selected_biome().is_playable():
		_open_scene(game_scene_path)


func _on_upgrades_button_pressed() -> void:
	_open_scene(upgrades_scene_path)


func _on_shop_button_pressed() -> void:
	_open_scene("res://scenes/shop.tscn")


func _on_settings_button_pressed() -> void:
	if _is_starting:
		return
	play_button.disabled = true
	upgrades_button.disabled = true
	settings_button.disabled = true
	shop_button.disabled = true
	settings_overlay.open()
	_update_biome()


func _on_settings_closed() -> void:
	upgrades_button.disabled = false
	settings_button.disabled = false
	shop_button.disabled = false
	_update_biome()
	settings_button.grab_focus()


func _open_scene(path: String) -> void:
	if _is_starting:
		return

	_is_starting = true
	play_button.disabled = true
	upgrades_button.disabled = true
	settings_button.disabled = true
	shop_button.disabled = true
	previous_biome.disabled = true
	next_biome.disabled = true
	var error: Error = get_tree().change_scene_to_file(path)
	if error != OK:
		_is_starting = false
		upgrades_button.disabled = false
		settings_button.disabled = false
		shop_button.disabled = false
		_update_biome()
		push_error("Cannot open scene: %s (error %s)" % [path, error])
