class_name RunRewardConfig
extends Resource

@export_range(0, 1000, 1) var crystals_per_wave: int = 2
@export_range(0, 1000, 1) var crystals_per_boss: int = 10


func reward_for(completed_waves: int, killed_bosses: int) -> int:
	return maxi(completed_waves, 0) * crystals_per_wave + maxi(killed_bosses, 0) * crystals_per_boss
