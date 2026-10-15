class_name RunUpgrade
extends Resource

enum Kind {
	RAPID_FIRE, POWER, MANA_FLOW, TOWER_ARMOR, FROST_POWER, CHEAP_SUMMONS,
	MEDKIT, MANA_RESERVE, LONG_SIGHT, ARCHER_TRAINING, PYROMANCY, ICE_POWER,
	HOT_FLAMES, WIDE_BLAST, DEEP_FREEZE, REGENERATION, BETTER_SALE,
	ARCHER_LV5, MAGE_LV5, FROST_MAGE_LV5
}

@export var kind: Kind = Kind.POWER
@export var title: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export_range(0.0, 1000.0, 0.01) var strength: float = 0.2
@export var unit_scene: PackedScene
@export var unit_stats: UnitStats
