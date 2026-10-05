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
	SessionProgress.crystals_changed.connect(_on_crystals_changed)
	SessionProgress.upgrades_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var config: MetaUpgradeConfig = SessionProgress.UPGRADE_CONFIG
	var level: int = SessionProgress.upgrade_level(kind)
	var maximum: bool = level >= config.maximum_level
	level_label.text = "%d / %d" % [level, config.maximum_level]
	current_effect.text = _effect_at(level)
	next_effect.text = _effect_at(level + 1)
	next_effect.visible = not maximum
	effect_arrow.visible = not maximum
	price_icon.texture = CHECK if maximum else CRYSTAL
	price_label.text = "" if maximum else str(config.price_for(level))
	disabled = not SessionProgress.can_buy(kind)
	price_label.modulate = Color("ed939b") if disabled and not maximum else Color("d4b9ff")
	tooltip_text = "Maximum level" if maximum else "Upgrade for %d Soul Crystals" % config.price_for(level)


func _effect_at(level: int) -> String:
	var config: MetaUpgradeConfig = SessionProgress.UPGRADE_CONFIG
	if kind == MetaUpgradeConfig.Kind.STARTING_MANA:
		return "+%d" % config.starting_mana_bonus(level)
	return "+%d%%" % roundi((config.multiplier_for(kind, level) - 1.0) * 100.0)


func _on_crystals_changed(_total: int) -> void:
	refresh()


func _on_pressed() -> void:
	SessionProgress.try_buy(kind)
