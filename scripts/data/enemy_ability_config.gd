class_name EnemyAbilityConfig
extends Resource

@export_group("Goblin Lv5")
@export var dash_interval: float = 5.0
@export var dash_windup: float = 0.3
@export var dash_duration: float = 0.8
@export var dash_speed_bonus: float = 0.6
@export_group("Orc Lv5")
@export var rage_health_ratio: float = 0.5
@export var rage_speed_bonus: float = 0.3
@export_group("Golem Lv5")
@export var armor_hits: int = 3
@export var armor_damage_ratio: float = 0.5
@export_group("Boss")
@export var shield_minimum_level: int = 3
@export var shield_health_trigger: float = 0.5
@export var shield_health_ratio: float = 0.15
@export var retinue_minimum_level: int = 4
@export var retinue_count: int = 2
@export var retinue_level: int = 2
@export var retinue_spacing: float = 42.0
@export var summon_windup: float = 0.6
@export var ability_spacing: float = 1.0
@export var rush_minimum_level: int = 5
@export var rush_health_trigger: float = 0.25
@export var rush_windup: float = 0.35
@export var rush_speed_bonus: float = 0.4
