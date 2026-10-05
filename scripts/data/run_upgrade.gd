class_name RunUpgrade
extends Resource

enum Kind { RAPID_FIRE, POWER, MANA_FLOW, TOWER_ARMOR, FROST_POWER, CHEAP_SUMMONS }

@export var kind: Kind = Kind.POWER
@export var title: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export_range(0.0, 1.0, 0.01) var strength: float = 0.2
