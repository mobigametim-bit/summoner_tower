extends RefCounted


static func run() -> Dictionary:
	var path: String = "user://tutorial_checks.json"
	var wallet_path: String = "user://tutorial_checks_progress.json"
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(wallet_path)
	var wallet: SaveManager = SaveManager.new(wallet_path,10)
	var levels: Array[int] = [7,6,5,4,3,2,1,0,1,1,1]
	var unlocked: Array[String] = ["forest","graveyard"]
	assert(wallet.save_progress(2468,levels,unlocked,"graveyard") == OK)
	var progress: TutorialProgress = TutorialProgress.new(path)
	assert(not progress.started and not progress.completed and not progress.skipped)
	progress.started = true
	progress.mark("summon_first")
	progress.mark("summon_first")
	progress = TutorialProgress.new(path)
	assert(progress.started and progress.seen == ["summon_first"] and not progress.completed)
	progress.completed = true
	progress.mark("merge")
	progress.mark("combat")
	progress = TutorialProgress.new(path)
	assert(progress.completed and not progress.skipped)
	progress.skipped = true
	assert(progress.save())
	assert(not TutorialProgress.new(path).skipped)
	progress.replay()
	progress = TutorialProgress.new(path)
	assert(not progress.started and not progress.completed and not progress.skipped and progress.seen.is_empty())
	var data: Dictionary = wallet.load_progress()
	assert(data.crystals == 2468 and data.upgrade_levels == levels and data.unlocked_biomes == unlocked and data.selected_biome == "graveyard")
	_write(path,{"version":2,"started":true,"completed":true,"skipped":false,"seen":[]})
	progress = TutorialProgress.new(path)
	assert(not progress.writable and not progress.save())
	var future: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(future.version == 2)
	_write(path,{"version":1,"started":true,"completed":false,"skipped":false,"seen":[17]})
	progress = TutorialProgress.new(path)
	assert(not progress.started and progress.seen.is_empty())
	_write(path,{"version":1,"started":true,"completed":false,"skipped":false,"seen":["../bad"]})
	assert(TutorialProgress.new(path).seen.is_empty())
	_write(path,{"version":1,"started":true,"completed":true,"skipped":false,"seen":["welcome"]})
	progress = TutorialProgress.new(path)
	assert(progress.started and not progress.completed and progress.seen.has("welcome"))
	_write(path,{"version":1,"started":true,"completed":true,"skipped":true,"seen":["welcome"]})
	progress = TutorialProgress.new(path)
	assert(progress.started and not progress.completed and not progress.skipped)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(wallet_path)
	return {"storage":"passed","repeat":"passed","legacy_progress_preserved":true,"future_version_protected":true}


static func _write(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
