class_name MetaUpgradeConfig
extends Resource

enum Kind { TOWER_HEALTH, UNIT_DAMAGE, MANA_INCOME, STARTING_MANA }

@export_range(1, 100, 1) var maximum_level: int = 10
@export_range(1, 10000, 1) var price_step: int = 25
@export var health_per_level: float = 0.1
@export var damage_per_level: float = 0.05
@export var income_per_level: float = 0.05
@export var starting_mana_per_level: int = 10


func is_valid_kind(kind: int) -> bool:
	return kind >= Kind.TOWER_HEALTH and kind <= Kind.STARTING_MANA


func price_for(level: int) -> int:
	return price_step * (level + 1) if level >= 0 and level < maximum_level else 0


func multiplier_for(kind: Kind, level: int) -> float:
	var strength: float = 0.0
	match kind:
		Kind.TOWER_HEALTH: strength = health_per_level
		Kind.UNIT_DAMAGE: strength = damage_per_level
		Kind.MANA_INCOME: strength = income_per_level
	return 1.0 + strength * clampi(level, 0, maximum_level)


func starting_mana_bonus(level: int) -> int:
	return starting_mana_per_level * clampi(level, 0, maximum_level)
