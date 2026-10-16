class_name SaveManager
extends RefCounted

const SAVE_PATH: String = "user://progress.json"
const FORMAT_VERSION: int = 3
# JSON хранит числа как double; ограничение оставляет целые значения точными.
const MAX_CRYSTALS: int = 9007199254740991
const MAX_FILE_BYTES: int = 65536

var path: String
var maximum_level: int
var last_error: Error = OK
var load_status: String = "missing"
var writable: bool = true
var needs_migration: bool = false


func _init(save_path: String = SAVE_PATH, level_limit: int = 10) -> void:
	path = save_path
	maximum_level = level_limit


func load_progress() -> Dictionary:
	last_error = OK
	writable = true
	needs_migration = false
	load_status = "missing"
	if path.is_empty() or not FileAccess.file_exists(path):
		return _defaults()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = FileAccess.get_open_error()
		writable = false
		load_status = "unreadable"
		return _defaults()
	if file.get_length() > MAX_FILE_BYTES:
		load_status = "invalid"
		return _defaults()
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		load_status = "invalid"
		return _defaults()
	var data: Dictionary = json.data
	if _integer_in_range(data.get("version"), FORMAT_VERSION + 1, MAX_CRYSTALS):
		# Старый клиент не должен затирать сохранение более новой версии.
		writable = false
		load_status = "future_version"
		return _defaults()
	if not _valid(data):
		load_status = "invalid"
		return _defaults()
	load_status = "loaded"
	needs_migration = int(data.version) < FORMAT_VERSION
	var levels: Array[int] = []
	for level: Variant in data.upgrade_levels:
		levels.append(int(level))
	# V1 содержал ровно четыре вида улучшений; их индексы сохраняются.
	while levels.size() < MetaUpgradeConfig.Kind.COUNT:
		levels.append(0)
	var result: Dictionary = {"crystals": int(data.crystals), "upgrade_levels": levels}
	result.merge(_biomes_from(data))
	return result


func save_progress(crystals: int, levels: Array[int], unlocked_biomes: Array[String] = ["forest"], selected_biome: String = "forest") -> Error:
	last_error = OK
	if not writable:
		last_error = ERR_UNAVAILABLE
		return last_error
	var data: Dictionary = {"version": FORMAT_VERSION, "crystals": crystals, "upgrade_levels": levels,
		"unlocked_biomes": unlocked_biomes, "selected_biome": selected_biome}
	if not _valid(data) or not _valid_biomes(data):
		last_error = ERR_INVALID_DATA
		return last_error
	# Пустой путь — изолированная тестовая сессия без записи на диск.
	if path.is_empty():
		return OK
	var temporary_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return last_error
	file.store_string(JSON.stringify(data))
	file.flush()
	last_error = file.get_error()
	file.close()
	if last_error == OK:
		# Старый файл остаётся целым, пока новый полностью не записан.
		last_error = DirAccess.rename_absolute(temporary_path, path)
	if last_error != OK:
		DirAccess.remove_absolute(temporary_path)
	return last_error


func _valid_biomes(data: Dictionary) -> bool:
	var unlocked: Variant = data.get("unlocked_biomes")
	var selected: Variant = data.get("selected_biome")
	if not unlocked is Array or unlocked.is_empty() or unlocked.size() > 64 or not selected is String:
		return false
	var seen: Array[String] = []
	for value: Variant in unlocked:
		if not value is String or value.is_empty() or value.length() > 48 or not value.is_valid_identifier() or seen.has(value):
			return false
		seen.append(value)
	return seen.has("forest") and seen.has(selected)


func _biomes_from(data: Dictionary) -> Dictionary:
	# Повреждение нового раздела не должно уничтожать ранее заработанные кристаллы/мету.
	if int(data.version) >= 3 and _valid_biomes(data):
		var unlocked: Array[String] = []
		for biome: String in data.unlocked_biomes:
			unlocked.append(biome)
		return {"unlocked_biomes": unlocked, "selected_biome": String(data.selected_biome)}
	return {"unlocked_biomes": ["forest"], "selected_biome": "forest"}


func _valid(data: Dictionary) -> bool:
	if not _integer_in_range(data.get("version"), 1, FORMAT_VERSION):
		return false
	if not _integer_in_range(data.get("crystals"), 0, MAX_CRYSTALS):
		return false
	var levels: Variant = data.get("upgrade_levels")
	var expected_count: int = 4 if int(data.version) == 1 else MetaUpgradeConfig.Kind.COUNT
	if not levels is Array or levels.size() != expected_count:
		return false
	var limits: MetaUpgradeConfig = MetaUpgradeConfig.new()
	for index: int in levels.size():
		if not _integer_in_range(levels[index], 0, mini(maximum_level, limits.maximum_for(index))):
			return false
	return true


func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floor(float(value))


func _defaults() -> Dictionary:
	var levels: Array[int] = []
	levels.resize(MetaUpgradeConfig.Kind.COUNT)
	levels.fill(0)
	return {"crystals": 0, "upgrade_levels": levels, "unlocked_biomes": ["forest"], "selected_biome": "forest"}
