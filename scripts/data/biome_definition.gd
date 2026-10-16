class_name BiomeDefinition
extends Resource

@export var biome_id: StringName
@export var title: String
@export_range(1, 20, 1) var biome_number: int = 1
@export var enemy_growth_per_biome: float = 0.2
@export var regular_enemy_types: Array[StringName] = []
@export var boss_type: StringName
@export var wave_config: WaveConfig
@export var battlefield_config: BattlefieldConfig
@export var menu_backdrop: PackedScene
@export var unlocked_unit_type: StringName
@export var summon_additions: SummonPool
@export var additional_upgrades: Array[RunUpgrade] = []


func enemy_stat_multiplier() -> float:
	return pow(1.0 + enemy_growth_per_biome, biome_number - 1)


func is_playable() -> bool:
	# Объявление будущего биома не разрешает запуск со старой армией врагов.
	return wave_config != null and battlefield_config != null
