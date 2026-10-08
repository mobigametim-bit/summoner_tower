extends RefCounted

const PATH: String = "user://feature12-checks.json"


func run_checks() -> Dictionary:
	SessionProgress.use_test_save()
	DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(PATH + ".tmp")
	var store: SaveManager = SaveManager.new(PATH, SessionProgress.UPGRADE_CONFIG.maximum_level)
	assert(store.load_progress().crystals == 0 and store.load_status == "missing")
	var levels: Array[int] = [1, 2, 3, 4]
	assert(store.save_progress(321, levels) == OK)
	var restored: Dictionary = SaveManager.new(PATH).load_progress()
	assert(restored.crystals == 321 and restored.upgrade_levels == levels)
	assert(store.save_progress(221, [2, 2, 3, 4]) == OK)
	assert(store.load_progress().crystals == 221)
	assert(not FileAccess.file_exists(PATH + ".tmp"))
	var invalid_cases: Array[String] = [
		"{broken", "[]", "{}",
		'{"version":1,"crystals":-1,"upgrade_levels":[0,0,0,0]}',
		'{"version":1,"crystals":1.5,"upgrade_levels":[0,0,0,0]}',
		'{"version":1,"crystals":"5","upgrade_levels":[0,0,0,0]}',
		'{"version":1,"crystals":true,"upgrade_levels":[0,0,0,0]}',
		'{"version":1,"crystals":9007199254740992,"upgrade_levels":[0,0,0,0]}',
		'{"version":1,"crystals":5,"upgrade_levels":[0,0,0]}',
		'{"version":1,"crystals":5,"upgrade_levels":[0,0,0,11]}',
		'{"version":1,"crystals":5,"upgrade_levels":[0,0,0,-1]}',
		'{"version":1,"crystals":5,"upgrade_levels":[0,0,0,0.5]}'
	]
	for source: String in invalid_cases:
		_write(source)
		var reset: Dictionary = store.load_progress()
		assert(reset.crystals == 0 and reset.upgrade_levels == [0, 0, 0, 0] and store.load_status == "invalid")
	_write('{"version":2,"crystals":321,"upgrade_levels":[1,2,3,4]}')
	store.load_progress()
	assert(not store.writable and store.load_status == "future_version")
	var future_source: String = FileAccess.get_file_as_string(PATH)
	assert(store.save_progress(0, [0, 0, 0, 0]) == ERR_UNAVAILABLE)
	assert(FileAccess.get_file_as_string(PATH) == future_source)
	_write("x".repeat(SaveManager.MAX_FILE_BYTES + 1))
	assert(store.load_progress().crystals == 0 and store.load_status == "invalid")
	assert(store.save_progress(0, [0, 0, 0, 0]) == OK)
	SessionProgress.use_test_save(PATH)
	SessionProgress.add_crystals(200)
	assert(SessionProgress.try_buy(0))
	assert(SaveManager.new(PATH).load_progress().crystals == 175)
	assert(SaveManager.new(PATH).load_progress().upgrade_levels == [1, 0, 0, 0])
	# Существующая выдача результата остаётся однократной и сохраняет весь баланс.
	var statistics: RunStatistics = RunStatistics.new()
	statistics.config = load("res://resources/balance/run_reward_config.tres")
	statistics.completed_waves = 10
	assert(statistics.finish() and not statistics.finish())
	statistics.free()
	assert(SaveManager.new(PATH).load_progress().crystals == 195)
	SessionProgress.save_manager = SaveManager.new("user://feature12-no-such-directory/progress.json")
	var failure_state: Dictionary = {}
	var on_failure: Callable = func(_error: int) -> void:
		failure_state.crystals = SessionProgress.crystals
		failure_state.levels = SessionProgress.upgrade_levels.duplicate()
		failure_state.reentrant_purchase = SessionProgress.try_buy(1)
	SessionProgress.save_failed.connect(on_failure)
	assert(not SessionProgress.try_buy(1))
	SessionProgress.save_failed.disconnect(on_failure)
	assert(SessionProgress.crystals == 195 and SessionProgress.upgrade_levels == [1, 0, 0, 0])
	assert(failure_state.crystals == 195 and failure_state.levels == [1, 0, 0, 0] and not failure_state.reentrant_purchase)
	SessionProgress.use_test_save()
	DirAccess.remove_absolute(PATH)
	return {"passed": true, "invalid_cases": invalid_cases.size(), "atomic_overwrite": true,
		"future_version_preserved": true, "award_once": true, "purchase_failure_rollback": true}


func _write(source: String) -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(source)
	file.close()
