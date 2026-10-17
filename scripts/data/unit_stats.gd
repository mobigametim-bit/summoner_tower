class_name UnitStats
extends Resource

const MAX_LEVEL: int = 5

@export var unit_type: StringName = &"archer"
@export var display_name: String = "ARCHER"
@export_range(1, MAX_LEVEL, 1) var level: int = 1
@export var visual_texture: Texture2D
@export var next_level: UnitStats

@export_range(1, 10000, 1) var damage: int = 1
@export_range(0.05, 10.0, 0.05) var attack_interval: float = 1.0
@export_range(1.0, 2000.0, 1.0) var attack_range: float = 1.0
@export_range(1.0, 3000.0, 1.0) var projectile_speed: float = 1.0
@export_range(0.1, 10.0, 0.1) var projectile_lifetime: float = 3.0
@export_range(0.0, 0.95, 0.05) var slow_ratio: float = 0.0
@export_range(0.0, 10.0, 0.1) var slow_duration: float = 0.0

# damage — урон всей обычной серии, а не каждой стрелы.
enum Ability { NONE, HAIL, METEOR, FROST_WAVE, CONSECRATION }

@export_range(1, 6, 1) var burst_count: int = 1
@export_range(0.01, 1.0, 0.01) var burst_delay: float = 0.1
@export_range(0.0, 200.0, 1.0) var splash_radius: float = 0.0
@export_range(0.0, 1.0, 0.05) var splash_damage_ratio: float = 0.0
@export_range(0.0, 1.0, 0.05) var burn_damage_ratio: float = 0.0
@export_range(0.0, 10.0, 0.1) var burn_duration: float = 0.0
@export var ability: Ability = Ability.NONE
@export_range(0.1, 30.0, 0.1) var ability_cooldown: float = 3.0
@export_range(0.0, 5.0, 0.05) var ability_damage_ratio: float = 0.0
@export_range(1, 12, 1) var ability_projectiles: int = 1
@export_range(0.0, 200.0, 1.0) var ability_radius: float = 85.0
@export_range(0.0, 5.0, 0.05) var freeze_duration: float = 0.0
@export_range(1.0, 3.0, 0.05) var area_power_multiplier: float = 1.0
@export_range(0.0, 1.0, 0.05) var light_mark_ratio: float = 0.0
@export_range(0.0, 10.0, 0.1) var light_mark_duration: float = 0.0
