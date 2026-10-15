class_name SummonConfig
extends Resource

@export_range(0, 100000, 1) var starting_mana: int = 0
@export_range(1, 10000, 1) var initial_cost: int = 1
@export_range(0, 10000, 1) var cost_increase: int = 0
@export_range(0, 100, 1) var refund_percent: int = 50
@export var map_change_refund_percentages: Array[int] = [80, 60, 40]


func cost_after(successful_summons: int) -> int:
	return initial_cost + cost_increase * maxi(successful_summons, 0)


func map_refund_percent_for(boss_number: int) -> int:
	var index: int = clampi(boss_number - 1, 0, map_change_refund_percentages.size() - 1)
	return map_change_refund_percentages[index]


func refund_for(paid_mana: int, map_change: bool = false, boss_number: int = 1) -> int:
	# Целочисленное деление округляет вниз всю стоимость объединённого бойца.
	var percent: int = map_refund_percent_for(boss_number) if map_change else refund_percent
	@warning_ignore("integer_division")
	return maxi(paid_mana, 0) * percent / 100
