class_name SummonConfig
extends Resource

@export_range(0, 100000, 1) var starting_mana: int = 0
@export_range(1, 10000, 1) var initial_cost: int = 1
@export_range(0, 10000, 1) var cost_increase: int = 0


func cost_after(successful_summons: int) -> int:
	return initial_cost + cost_increase * maxi(successful_summons, 0)
