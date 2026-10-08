class_name SaveManager
extends RefCounted

const SAVE_PATH: String = "user://progress.json"
const FORMAT_VERSION: int = 1
# JSON хранит числа как double; ограничение оставляет целые значения точными.
const MAX_CRYSTALS: int = 9007199254740991
const MAX_FILE_BYTES: int = 65536

var path: String
var maximum_level: int
var last_error: Error = OK
var load_status: String = "missing"
var writable: bool = true


func _init(save_path: String = SAVE_PATH, level_limit: int = 10) -> void:
	path = save_path
	maximum_level = level_limit


func load_progress() -> Dictionary:
	last_error = OK
	writable = true
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
	var levels: Array[int] = []
	for level: Variant in data.upgrade_levels:
		levels.append(int(level))
	return {"crystals": int(data.crystals), "upgrade_levels": levels}


func save_progress(crystals: int, levels: Array[int]) -> Error:
	last_error = OK
	if not writable:
		last_error = ERR_UNAVAILABLE
		return last_error
	var data: Dictionary = {"version": FORMAT_VERSION, "crystals": crystals, "upgrade_levels": levels}
	if not _valid(data):
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


func _valid(data: Dictionary) -> bool:
	if not _integer_in_range(data.get("version"), FORMAT_VERSION, FORMAT_VERSION):
		return false
	if not _integer_in_range(data.get("crystals"), 0, MAX_CRYSTALS):
		return false
	var levels: Variant = data.get("upgrade_levels")
	if not levels is Array or levels.size() != 4:
		return false
	for level: Variant in levels:
		if not _integer_in_range(level, 0, maximum_level):
			return false
	return true


func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floor(float(value))


func _defaults() -> Dictionary:
	var levels: Array[int] = [0, 0, 0, 0]
	return {"crystals": 0, "upgrade_levels": levels}
