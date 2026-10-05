class_name RunUpgradePool
extends Resource

@export var upgrades: Array[RunUpgrade] = []
@export var frost_base_stats: UnitStats
@export_range(0.0, 0.95, 0.01) var frost_max_ratio: float = 0.7
@export_range(1, 100, 1) var minimum_summon_cost: int = 1


func get_upgrade(kind: RunUpgrade.Kind) -> RunUpgrade:
	for upgrade: RunUpgrade in upgrades:
		if upgrade.kind == kind:
			return upgrade
	return null
