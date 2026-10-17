class_name BiomeCatalog
extends Resource

@export var biomes: Array[BiomeDefinition] = []


func find(biome_id: StringName) -> BiomeDefinition:
	for biome: BiomeDefinition in biomes:
		if biome.biome_id == biome_id:
			return biome
	return null


func neighbor(biome_id: StringName, direction: int, unlocked: Array[String]) -> BiomeDefinition:
	for index: int in biomes.size():
		if biomes[index].biome_id != biome_id:
			continue
		var next_index: int = index + signi(direction)
		if next_index >= 0 and next_index < biomes.size() and unlocked.has(String(biomes[next_index].biome_id)):
			return biomes[next_index]
		return null
	return null


func summon_pool_for(base: SummonPool, unlocked: Array[String]) -> SummonPool:
	# Результат принадлежит забегу: общие .tres и базовые шансы не мутируют.
	var result: SummonPool = SummonPool.new()
	if base != null:
		_append_pool(result, base)
	for biome: BiomeDefinition in biomes:
		if unlocked.has(String(biome.biome_id)) and biome.summon_additions != null:
			_append_pool(result, biome.summon_additions)
	return result


func upgrade_pool_for(base: RunUpgradePool, unlocked: Array[String]) -> RunUpgradePool:
	# Состав текущего забега не изменяет общий ресурс и не зависит от выбранного биома.
	var result: RunUpgradePool = base.duplicate() as RunUpgradePool
	result.upgrades = base.upgrades.duplicate()
	for biome: BiomeDefinition in biomes:
		if not unlocked.has(String(biome.biome_id)):
			continue
		for upgrade: RunUpgrade in biome.additional_upgrades:
			if result.get_upgrade(upgrade.kind) == null:
				result.upgrades.append(upgrade)
	return result


func _append_pool(destination: SummonPool, source: SummonPool) -> void:
	if not source.is_valid():
		return
	for index: int in source.scenes.size():
		var addition: PackedScene = source.scenes[index]
		var present: bool = false
		for existing: PackedScene in destination.scenes:
			if existing == addition or (not addition.resource_path.is_empty() and existing.resource_path == addition.resource_path):
				present = true
				break
		if not present:
			destination.scenes.append(addition)
			destination.weights.append(source.weights[index])
