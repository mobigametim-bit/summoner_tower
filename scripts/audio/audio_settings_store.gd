class_name AudioSettingsStore
extends RefCounted

const DEFAULT_MUSIC: float = 0.1
const DEFAULT_EFFECTS: float = 0.6
const FORMAT_VERSION: int = 1
const MAX_BYTES: int = 4096

var path: String
var writable: bool = true
var last_error: Error = OK


func _init(file_path: String = "user://audio_settings.json") -> void:
	path = file_path


func load_settings() -> Dictionary:
	writable = true
	last_error = OK
	var result: Dictionary = {"music": DEFAULT_MUSIC, "effects": DEFAULT_EFFECTS}
	if path.is_empty() or not FileAccess.file_exists(path):
		return result
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = FileAccess.get_open_error()
		writable = false
		return result
	if file.get_length() > MAX_BYTES:
		return result
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return result
	var data: Variant = json.data
	if not data is Dictionary:
		return result
	var version: Variant = data.get("version")
	if typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return result
	if not is_finite(float(version)) or float(version) != floor(float(version)):
		return result
	if float(version) > FORMAT_VERSION:
		writable = false
		return result
	if version != FORMAT_VERSION:
		return result
	for key: String in ["music", "effects"]:
		var value: Variant = data.get(key)
		if valid_volume(value):
			result[key] = float(value)
	return result


func save_settings(music: float, effects: float) -> Error:
	last_error = OK
	if not writable:
		last_error = ERR_UNAVAILABLE
		return last_error
	if not valid_volume(music) or not valid_volume(effects):
		last_error = ERR_INVALID_DATA
		return last_error
	if path.is_empty():
		return OK
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return last_error
	file.store_string(JSON.stringify({"version": FORMAT_VERSION, "music": music, "effects": effects}))
	file.flush()
	last_error = file.get_error()
	file.close()
	if last_error == OK:
		last_error = DirAccess.rename_absolute(temporary, path)
	if last_error != OK:
		DirAccess.remove_absolute(temporary)
	return last_error


static func valid_volume(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and value >= 0.0 and value <= 1.0
