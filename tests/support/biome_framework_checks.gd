extends RefCounted

const PATH: String = "user://biome_framework_checks.json"


func run() -> Dictionary:
	var levels: Array[int] = [1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0]
	for version: int in [1, 2]:
		_write({"version":version, "crystals":321, "upgrade_levels":[1,2,3,4] if version == 1 else levels})
		SessionProgress.use_test_save(PATH)
		assert(SessionProgress.crystals == 321 and SessionProgress.upgrade_levels == levels)
		assert(SessionProgress.unlocked_biomes == ["forest"] and SessionProgress.selected_biome_id == &"forest")
		assert(int(JSON.parse_string(FileAccess.get_file_as_string(PATH)).version) == SaveManager.FORMAT_VERSION)
	var events: Array[int] = []
	var on_change: Callable = func() -> void:
		events.append(1)
		assert(not SessionProgress.select_biome(&"forest") or SessionProgress.selected_biome_id == &"forest")
	SessionProgress.biomes_changed.connect(on_change)
	assert(not SessionProgress.select_biome(&"graveyard"))
	assert(SessionProgress.unlock_biome(&"graveyard") and SessionProgress.unlock_biome(&"graveyard"))
	assert(events.size() == 1 and SessionProgress.unlocked_biomes.count("graveyard") == 1)
	assert(SessionProgress.select_biome(&"graveyard"))
	SessionProgress.biomes_changed.disconnect(on_change)
	SessionProgress.use_test_save(PATH)
	assert(SessionProgress.selected_biome_id == &"graveyard" and SessionProgress.crystals == 321)
	assert(SessionProgress.upgrade_levels == levels and not SessionProgress.selected_biome().is_playable())
	SessionProgress.add_crystals(10)
	assert(SessionProgress.try_buy(0))
	var restored: Dictionary = SaveManager.new(PATH).load_progress()
	assert(restored.selected_biome == "graveyard" and restored.unlocked_biomes == ["forest", "graveyard"])
	var forest: BiomeDefinition = SessionProgress.biome_catalog.find(&"forest")
	var graveyard: BiomeDefinition = SessionProgress.biome_catalog.find(&"graveyard")
	assert(forest.is_playable() and is_equal_approx(forest.enemy_stat_multiplier(), 1.0))
	assert(is_equal_approx(graveyard.enemy_stat_multiplier(), 1.2) and graveyard.unlocked_unit_type == &"priest")
	var base: SummonPool = load("res://resources/balance/summon_pool.tres") as SummonPool
	assert(SessionProgress.summon_pool_for(base).weights == base.weights)
	# Подставляем дополнительную сцену только в копию каталога: новый production art не создаётся.
	var fixture: BiomeCatalog = BiomeCatalog.new()
	fixture.biomes.assign([forest.duplicate(), graveyard.duplicate()])
	var extra: SummonPool = SummonPool.new()
	extra.scenes.assign([base.scenes[0], load("res://scenes/boss.tscn")])
	extra.weights.assign([1, 10])
	fixture.biomes[1].summon_additions = extra
	var combined: SummonPool = fixture.summon_pool_for(base, ["forest", "graveyard"])
	assert(combined.scenes.size() == 4 and combined.weights == [40, 35, 25, 10])
	assert(base.scenes.size() == 3 and base.weights == [40, 35, 25])
	assert(fixture.summon_pool_for(base, ["forest"]).scenes.size() == 3)
	SessionProgress.save_manager = SaveManager.new("user://missing_biome_checks_dir/progress.json")
	assert(not SessionProgress.select_biome(&"forest") and SessionProgress.selected_biome_id == &"graveyard")
	SessionProgress.use_test_save()
	SessionProgress.save_manager = SaveManager.new("user://missing_biome_checks_dir/progress.json")
	assert(not SessionProgress.unlock_biome(&"graveyard") and not SessionProgress.is_biome_unlocked(&"graveyard"))
	_write({"version":3,"crystals":100,"upgrade_levels":levels,"unlocked_biomes":["forest"],"selected_biome":"graveyard"})
	var repaired: Dictionary = SaveManager.new(PATH).load_progress()
	assert(repaired.crystals == 100 and repaired.upgrade_levels == levels and repaired.selected_biome == "forest")
	_write({"version":4,"crystals":999,"upgrade_levels":levels})
	var future: SaveManager = SaveManager.new(PATH)
	future.load_progress()
	assert(not future.writable and future.save_progress(0, levels) == ERR_UNAVAILABLE)
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(PATH)).crystals) == 999)
	SessionProgress.use_test_save()
	DirAccess.remove_absolute(PATH)
	return {"passed":true,"migrations":[1,2],"roundtrip":true,"wallet_preserved":true,
		"selection_and_unlock_rollback":true,"future_version_preserved":true,"global_summon_expansion":true}


func _write(data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(data))
	file.close()
