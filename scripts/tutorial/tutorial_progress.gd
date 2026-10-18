class_name TutorialProgress
extends RefCounted

const SAVE_PATH: String = "user://tutorial.json"
const VERSION: int = 1

var path: String
var started: bool = false
var completed: bool = false
var skipped: bool = false
var seen: Array[String] = []
var last_error: Error = OK
var writable: bool = true


func _init(save_path: String = SAVE_PATH) -> void:
	path = save_path
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		writable = false
		last_error = FileAccess.get_open_error()
		return
	if file.get_length() > 32768:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return
	if data.get("version") is float or data.get("version") is int:
		if data.version > VERSION:
			writable = false
			last_error = ERR_UNAVAILABLE
			return
	if data.get("version") != VERSION or not data.get("started") is bool or not data.get("completed") is bool or not data.get("skipped") is bool:
		return
	var entries: Variant = data.get("seen")
	if not entries is Array or entries.size() > 256:
		return
	for entry: Variant in entries:
		if not entry is String or entry.length() > 64 or not entry.is_valid_identifier():
			return
	started = data.started
	# Просмотр меню сам по себе не завершает обучение. Старую/неполную отметку
	# восстанавливаем как незавершённый core, сохраняя уже прочитанные подсказки.
	completed = data.completed and entries.has("merge") and entries.has("combat")
	# Старый случайный пропуск больше не выключает обучение.
	skipped = false
	for entry: String in entries:
		if not seen.has(entry):
			seen.append(entry)


func save() -> bool:
	last_error = OK
	if not writable:
		last_error = ERR_UNAVAILABLE
		return false
	if path.is_empty():
		return true
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return false
	file.store_string(JSON.stringify({"version": VERSION, "started": started,
		"completed": completed, "skipped": skipped, "seen": seen}))
	file.flush()
	last_error = file.get_error()
	file.close()
	if last_error == OK:
		last_error = DirAccess.rename_absolute(temporary, path)
	if last_error != OK:
		DirAccess.remove_absolute(temporary)
	return last_error == OK


func mark(id: String) -> void:
	if not seen.has(id):
		seen.append(id)
		save()


func replay() -> void:
	started = false
	completed = false
	skipped = false
	seen.clear()
	save()
