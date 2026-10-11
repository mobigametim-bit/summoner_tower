extends RefCounted


func run() -> Dictionary:
	var path: String = "user://audio_settings_check_%d.json" % Time.get_ticks_usec()
	var store: AudioSettingsStore = AudioSettingsStore.new(path)
	assert(store.load_settings() == {"music": 0.1, "effects": 0.6})
	assert(store.save_settings(0.0, 1.0) == OK)
	assert(AudioSettingsStore.new(path).load_settings() == {"music": 0.0, "effects": 1.0})
	assert(store.save_settings(0.37, 0.24) == OK)
	assert(AudioSettingsStore.new(path).load_settings() == {"music": 0.37, "effects": 0.24})
	assert(store.save_settings(NAN, 0.5) == ERR_INVALID_DATA)
	_write(path, '{"version": 1, "music": "loud", "effects": -1}')
	assert(store.load_settings() == {"music": 0.1, "effects": 0.6})
	_write(path, '{"version": true, "music": 0.0, "effects": 0.0}')
	assert(store.load_settings() == {"music": 0.1, "effects": 0.6})
	_write(path, '{broken')
	assert(store.load_settings() == {"music": 0.1, "effects": 0.6})
	var future: String = '{"version": 2, "music": 0.3, "effects": 0.4}'
	_write(path, future)
	assert(store.load_settings() == {"music": 0.1, "effects": 0.6})
	assert(store.save_settings(0.1, 0.6) == ERR_UNAVAILABLE)
	assert(FileAccess.get_file_as_string(path) == future)
	assert(AudioSettingsStore.new(path + "/missing.json").save_settings(0.1, 0.6) != OK)
	DirAccess.remove_absolute(path)
	return {"defaults": true, "roundtrip_and_zero": true, "corrupt_values": true, "future_version_preserved": true, "failed_write": true}


func _write(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(content)
	file.close()
