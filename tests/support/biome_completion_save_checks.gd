extends RefCounted

const PATH: String = "user://biome_completion_checks.json"


func run() -> Dictionary:
	DirAccess.remove_absolute(PATH)
	SessionProgress.use_test_save(PATH)
	SessionProgress.add_crystals(17)
	var stats: RunStatistics = RunStatistics.new()
	stats.config = load("res://resources/balance/run_reward_config.tres")
	stats.completed_waves = 25
	stats.killed_bosses = 5
	SessionProgress.save_manager = SaveManager.new("user://biome-completion-no-directory/progress.json")
	assert(stats.finish(true, &"graveyard"))
	assert(stats.finished and stats.victory and not stats.result_saved)
	assert(SessionProgress.crystals == 17 and not SessionProgress.is_biome_unlocked(&"graveyard"))
	assert(stats.newly_unlocked_biome.is_empty() and not stats.can_double_reward())
	assert(not stats.finish(true, &"graveyard"))
	SessionProgress.save_manager = SaveManager.new(PATH)
	assert(stats.save_result() and stats.save_result())
	assert(SessionProgress.crystals == 117 and stats.newly_unlocked_biome == &"graveyard")
	var saved: Dictionary = SaveManager.new(PATH).load_progress()
	assert(saved.crystals == 117 and saved.unlocked_biomes == ["forest", "graveyard"])
	assert(saved.selected_biome == "forest")
	SessionProgress.use_test_save(PATH)
	assert(SessionProgress.crystals == 117 and SessionProgress.is_biome_unlocked(&"graveyard"))
	stats.reset()
	stats.completed_waves = 25
	stats.killed_bosses = 5
	assert(stats.finish(true, &"graveyard") and stats.result_saved)
	assert(stats.newly_unlocked_biome.is_empty() and SessionProgress.unlocked_biomes.size() == 2)
	assert(SessionProgress.crystals == 217)
	stats.free()
	SessionProgress.use_test_save()
	DirAccess.remove_absolute(PATH)
	return {"passed": true, "atomic_reward_unlock": true, "retry_once": true,
		"reload": true, "repeat_victory": true}
