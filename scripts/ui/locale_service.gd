extends Node

signal language_changed

const LANGUAGES: Array[String] = ["ru", "en"]
const SETTINGS_PATH: String = "user://language_settings.json"
const FORMAT_VERSION: int = 1

var language: String = "ru"
var last_save_error: Error = OK
var _writable: bool = true


func _ready() -> void:
	_load_language()
	TranslationServer.set_locale(language)


func set_language(value: String) -> void:
	if value not in LANGUAGES:
		return
	language = value
	TranslationServer.set_locale(language)
	_save_language()
	language_changed.emit()


func _load_language() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		_writable = false
		last_save_error = FileAccess.get_open_error()
		return
	if file.get_length() > 4096:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return
	var version: Variant = data.get("version")
	if (typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT) or not is_finite(float(version)):
		return
	if float(version) > FORMAT_VERSION:
		_writable = false
		return
	if float(version) == FORMAT_VERSION and data.get("language") in LANGUAGES:
		language = data.language


func _save_language() -> void:
	last_save_error = OK
	if not _writable:
		last_save_error = ERR_UNAVAILABLE
		return
	# Предпросмотры не должны менять настройки обычного игрока.
	for argument: String in OS.get_cmdline_args():
		if argument.begins_with("res://scenes/debug/") or argument.begins_with("res://tests/"):
			return
	var temporary: String = SETTINGS_PATH + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_save_error = FileAccess.get_open_error()
		return
	file.store_string(JSON.stringify({"version": FORMAT_VERSION, "language": language}))
	file.flush()
	last_save_error = file.get_error()
	file.close()
	if last_save_error == OK:
		last_save_error = DirAccess.rename_absolute(temporary, SETTINGS_PATH)
	if last_save_error != OK:
		DirAccess.remove_absolute(temporary)
