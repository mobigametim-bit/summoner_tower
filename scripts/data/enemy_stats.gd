class_name EnemyStats
extends Resource

const TIER_COLORS: Array[Color] = [Color("88b96b"), Color("ec9b49"), Color("df5654")]

@export var enemy_type: StringName = &"goblin"
@export_range(1, 100000, 1) var base_health: int = 30
@export_range(1.0, 1000.0, 1.0) var move_speed: float = 160.0
@export_range(1, 10000, 1) var tower_damage: int = 20
@export_range(0, 10000, 1) var kill_mana: int = 3
@export var is_boss: bool = false


func difficulty_tier(health: int) -> int:
	if is_boss:
		return 0
	if health >= base_health * 4:
		return 3
	if health >= base_health * 2:
		return 2
	return 1


func color_for(health: int) -> Color:
	var tier: int = difficulty_tier(health)
	return Color.WHITE if tier == 0 else TIER_COLORS[tier - 1]
