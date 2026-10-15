class_name MetaUpgradeConfig
extends Resource

enum Kind {
	TOWER_HEALTH, UNIT_DAMAGE, MANA_INCOME, STARTING_MANA,
	ATTACK_SPEED, ATTACK_RANGE, SUMMON_ECONOMY, RESTORATION,
	ABILITY_MASTERY, LUCKY_CHOICE, EXPANDED_CHOICE, COUNT
}

@export_range(1, 100, 1) var maximum_level: int = 10
@export_range(1, 10000, 1) var price_step: int = 25
@export_range(1, 20, 1) var choice_price_multiplier: int = 5
@export var health_per_level: float = 0.1
@export var damage_per_level: float = 0.05
@export var income_per_level: float = 0.05
@export var starting_mana_per_level: int = 10
@export var attack_speed_per_level: float = 0.02
@export var attack_range_per_level: float = 0.02
@export var summon_discount_per_level: float = 0.02
@export var restoration_per_level: int = 1
@export var ability_reduction_per_level: float = 0.02
@export var level_limits: Array[int] = [10, 10, 10, 10, 10, 5, 10, 5, 5, 1, 1]
@export var titles: Array[String] = [
	"TOWER HP", "UNIT DAMAGE", "MANA INCOME", "STARTING MANA",
	"BATTLE TRAINING", "KEEN SIGHT", "ECONOMICAL SUMMONS", "RESTORATION",
	"ABILITY MASTERY", "LUCKY CHOICE", "EXPANDED CHOICE"
]
@export var icons: Array[Texture2D] = []
@export var descriptions: Array[String] = [
	"Max tower HP\n+%d%% per level",
	"Damage of all units\n+%d%% per level",
	"Mana from kills\n+%d%% per level",
	"Starting mana\n+%d per level",
	"Normal attack speed\n+%d%% per level",
	"Attack range\n+%d%% per level",
	"Summon cost\n-%d%% per level",
	"HP restored after a wave\n+%d per level",
	"Lv5 abilities\n-%d%% cooldown per level",
	"Free card reroll\nOnce per run",
	"Boss upgrade choices\nFour instead of three"
]


func description_amount(kind: Kind) -> int:
	match kind:
		Kind.TOWER_HEALTH: return roundi(health_per_level * 100.0)
		Kind.UNIT_DAMAGE: return roundi(damage_per_level * 100.0)
		Kind.MANA_INCOME: return roundi(income_per_level * 100.0)
		Kind.STARTING_MANA: return starting_mana_per_level
		Kind.ATTACK_SPEED: return roundi(attack_speed_per_level * 100.0)
		Kind.ATTACK_RANGE: return roundi(attack_range_per_level * 100.0)
		Kind.SUMMON_ECONOMY: return roundi(summon_discount_per_level * 100.0)
		Kind.RESTORATION: return restoration_per_level
		Kind.ABILITY_MASTERY: return roundi(ability_reduction_per_level * 100.0)
	return 0


func is_valid_kind(kind: int) -> bool:
	return kind >= 0 and kind < Kind.COUNT


func maximum_for(kind: int) -> int:
	return mini(maximum_level, level_limits[kind]) if is_valid_kind(kind) else 0


func price_for(level: int, kind: int = Kind.TOWER_HEALTH) -> int:
	var multiplier: int = choice_price_multiplier if kind in [Kind.LUCKY_CHOICE, Kind.EXPANDED_CHOICE] else 1
	return price_step * (level + 1) * multiplier if level >= 0 and level < maximum_for(kind) else 0


func multiplier_for(kind: Kind, level: int) -> float:
	var strength: float = 0.0
	match kind:
		Kind.TOWER_HEALTH: strength = health_per_level
		Kind.UNIT_DAMAGE: strength = damage_per_level
		Kind.MANA_INCOME: strength = income_per_level
		Kind.ATTACK_SPEED: strength = attack_speed_per_level
		Kind.ATTACK_RANGE: strength = attack_range_per_level
	return 1.0 + strength * clampi(level, 0, maximum_for(kind))


func starting_mana_bonus(level: int) -> int:
	return starting_mana_per_level * clampi(level, 0, maximum_level)
