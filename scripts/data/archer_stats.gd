class_name ArcherStats
extends Resource

@export var unit_type: StringName = &"archer"
@export_range(1, 3, 1) var level: int = 1
@export var visual_texture: Texture2D
@export var next_level: ArcherStats

@export_range(1, 10000, 1) var damage: int = 1
@export_range(0.05, 10.0, 0.05) var attack_interval: float = 1.0
@export_range(1.0, 2000.0, 1.0) var attack_range: float = 1.0
@export_range(1.0, 3000.0, 1.0) var projectile_speed: float = 1.0
@export_range(0.1, 10.0, 0.1) var projectile_lifetime: float = 3.0
