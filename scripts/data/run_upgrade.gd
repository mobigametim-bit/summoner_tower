class_name RunUpgrade
extends Resource

enum Kind {
	RAPID_FIRE, POWER, MANA_FLOW, TOWER_ARMOR, FROST_POWER, CHEAP_SUMMONS,
	MEDKIT, MANA_RESERVE, LONG_SIGHT, ARCHER_TRAINING, PYROMANCY, ICE_POWER,
	HOT_FLAMES, WIDE_BLAST, DEEP_FREEZE, REGENERATION, BETTER_SALE,
	ARCHER_LV5, MAGE_LV5, FROST_MAGE_LV5,
	PRIEST_SUMMON, LIGHT_POWER, LONG_PRAYER, SACRED_RADIANCE
}

@export var kind: Kind = Kind.POWER
@export var title: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export_range(0.0, 1000.0, 0.01) var strength: float = 0.2
@export var unit_scene: PackedScene
@export var unit_stats: UnitStats
@export_range(1, 5, 1) var tier: int = 2
@export var tier_strengths: Array[float] = []
@export var unit_levels: Array[UnitStats] = []


func variant_for(for_tier: int) -> RunUpgrade:
	# Предложение — отдельный Resource: смена цвета не меняет исходный баланс.
	var variant: RunUpgrade = duplicate() as RunUpgrade
	variant.tier = clampi(for_tier, 1, 5)
	if tier_strengths.size() == 5:
		variant.strength = tier_strengths[variant.tier - 1]
	if unit_levels.size() == 5:
		variant.unit_stats = unit_levels[variant.tier - 1]
	return variant


func description_text() -> String:
	var value: float = strength
	if unit_scene != null:
		value = float(unit_stats.level)
	elif kind == Kind.DEEP_FREEZE:
		value *= 1000.0
	elif kind not in [Kind.MEDKIT, Kind.MANA_RESERVE, Kind.LONG_PRAYER, Kind.REGENERATION]:
		value *= 100.0
	var formatted: String = String.num(value, 2)
	if formatted.contains("."):
		formatted = formatted.rstrip("0").rstrip(".")
	if TranslationServer.get_locale().begins_with("ru"):
		formatted = formatted.replace(".", ",")
	return tr(description).replace("{value}", formatted)
