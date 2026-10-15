class_name MetaUpgradeCard
extends Button

const CRYSTAL: Texture2D = preload("res://assets/soul_crystal.svg")
const CHECK: Texture2D = preload("res://assets/ui/check.svg")

@export var kind: MetaUpgradeConfig.Kind = MetaUpgradeConfig.Kind.TOWER_HEALTH

@onready var level_label: Label = $Margin/Row/Info/Level
@onready var current_effect: Label = $Margin/Row/Info/Effect/Current
@onready var next_effect: Label = $Margin/Row/Info/Effect/Next
@onready var effect_arrow: TextureRect = $Margin/Row/Info/Effect/Arrow
@onready var price_icon: TextureRect = $Margin/Row/Price/Icon
@onready var price_label: Label = $Margin/Row/Price/Amount


func _ready() -> void:
	set_meta(&"skip_ui_sound", true)
	SessionProgress.crystals_changed.connect(_on_crystals_changed)
	SessionProgress.upgrades_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var config: MetaUpgradeConfig = SessionProgress.UPGRADE_CONFIG
	var level: int = SessionProgress.upgrade_level(kind)
	var limit: int = config.maximum_for(kind)
	var maximum: bool = level >= limit
	get_node("Margin/Row/Info/Title").text = tr(config.titles[kind])
	get_node("Margin/Row/Icon").texture = config.icons[kind]
	level_label.text = "%d / %d" % [level, limit]
	current_effect.text = _effect_at(level)
	next_effect.text = _effect_at(level + 1)
	next_effect.visible = not maximum
	effect_arrow.visible = not maximum
	price_icon.texture = CHECK if maximum else CRYSTAL
	if maximum:
		price_label.text = ""
	else:
		UiNumbers.show_value(price_label, config.price_for(level, kind))
	price_label.tooltip_text = ""
	disabled = not SessionProgress.can_buy(kind)
	price_label.modulate = Color("ed939b") if disabled and not maximum else Color("d4b9ff")
	tooltip_text = tr(config.descriptions[kind])
	if kind not in [MetaUpgradeConfig.Kind.LUCKY_CHOICE, MetaUpgradeConfig.Kind.EXPANDED_CHOICE]:
		tooltip_text = tooltip_text % config.description_amount(kind)


func _effect_at(level: int) -> String:
	var config: MetaUpgradeConfig = SessionProgress.UPGRADE_CONFIG
	if kind == MetaUpgradeConfig.Kind.STARTING_MANA:
		return "+%d" % config.starting_mana_bonus(level)
	if kind == MetaUpgradeConfig.Kind.SUMMON_ECONOMY:
		return "−%d%%" % roundi(config.summon_discount_per_level * level * 100.0)
	if kind == MetaUpgradeConfig.Kind.ABILITY_MASTERY:
		return "−%d%%" % roundi(config.ability_reduction_per_level * level * 100.0)
	if kind == MetaUpgradeConfig.Kind.RESTORATION:
		return "+%d" % (config.restoration_per_level * level)
	if kind == MetaUpgradeConfig.Kind.LUCKY_CHOICE:
		return str(level)
	if kind == MetaUpgradeConfig.Kind.EXPANDED_CHOICE:
		return str(3 + level)
	return "+%d%%" % roundi((config.multiplier_for(kind, level) - 1.0) * 100.0)


func _on_crystals_changed(_total: int) -> void:
	refresh()


func _on_pressed() -> void:
	if SessionProgress.try_buy(kind):
		AudioService.play_sfx(&"meta_upgrade")
