extends Node

signal volumes_changed
signal settings_save_failed(error: int)
signal settings_saved

@export var config: AudioConfig

@onready var _music_players: Array[AudioStreamPlayer] = [$MusicA, $MusicB]
@onready var _actions: Array[AudioStreamPlayer] = [$SFX/Action0, $SFX/Action1, $SFX/Action2, $SFX/Action3]
@onready var _combat: Array[AudioStreamPlayer] = [$SFX/Combat0, $SFX/Combat1, $SFX/Combat2]
@onready var _save_timer: Timer = $SaveTimer

var music_volume: float = AudioSettingsStore.DEFAULT_MUSIC
var effects_volume: float = AudioSettingsStore.DEFAULT_EFFECTS
var settings_store: AudioSettingsStore = AudioSettingsStore.new()
var last_save_error: Error = OK
var _music_name: StringName = &""
var _music_index: int = 0
var _music_tween: Tween
var _unlocked: bool = false
var _last_combat_time: Dictionary[StringName, int] = {}
var _backgrounded: bool = false
var _visibility_callback: JavaScriptObject
var _web_window: JavaScriptObject
var _web_document: JavaScriptObject


func _ready() -> void:
	_unlocked = not OS.has_feature("web")
	var review: bool = str(ProjectSettings.get_setting("application/run/main_scene", "")).begins_with("res://scenes/debug/")
	for argument: String in OS.get_cmdline_args():
		review = review or argument.begins_with("res://scenes/debug/") or argument.begins_with("res://tests/")
	if review:
		settings_store = AudioSettingsStore.new("")
	var saved: Dictionary = settings_store.load_settings()
	music_volume = saved.music
	effects_volume = saved.effects
	_apply_volumes()
	get_tree().node_added.connect(_on_node_added)
	get_tree().scene_changed.connect(_bind_scene_buttons)
	_bind_scene_buttons.call_deferred()
	_save_timer.timeout.connect(save_settings)
	if OS.has_feature("web"):
		_bind_web_visibility()


func _bind_web_visibility() -> void:
	_web_window = JavaScriptBridge.get_interface("window")
	_web_document = JavaScriptBridge.get_interface("document")
	_visibility_callback = JavaScriptBridge.create_callback(_on_web_presence_changed)
	for event_name: String in ["blur", "focus", "pagehide", "pageshow"]:
		_web_window.addEventListener(event_name, _visibility_callback)
	for event_name: String in ["visibilitychange", "freeze", "resume"]:
		_web_document.addEventListener(event_name, _visibility_callback)
	_refresh_web_presence()


func _on_web_presence_changed(arguments: Array) -> void:
	var event_type: String = str(arguments[0].type) if not arguments.is_empty() else ""
	if event_type in ["pagehide", "freeze"]:
		_set_backgrounded(true)
	else:
		_refresh_web_presence()


func _refresh_web_presence() -> void:
	_set_backgrounded(bool(_web_document.hidden) or not bool(_web_document.hasFocus()))


func _set_backgrounded(backgrounded: bool) -> void:
	if _backgrounded == backgrounded:
		return
	_backgrounded = backgrounded
	# Это временная блокировка звука: пользовательские уровни громкости не меняются.
	_apply_volumes()
	for player: AudioStreamPlayer in _music_players:
		player.stream_paused = backgrounded
	if _music_tween != null and _music_tween.is_valid():
		if backgrounded:
			_music_tween.pause()
		else:
			_music_tween.play()
	if backgrounded:
		stop_effects()
		$SFX/UI.stop()
	elif _unlocked:
		_start_music()


func _exit_tree() -> void:
	if _visibility_callback == null:
		return
	for event_name: String in ["blur", "focus", "pagehide", "pageshow"]:
		_web_window.removeEventListener(event_name, _visibility_callback)
	for event_name: String in ["visibilitychange", "freeze", "resume"]:
		_web_document.removeEventListener(event_name, _visibility_callback)
	_visibility_callback = null


func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	var activated: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed and not event.echo)
	if activated:
		_unlocked = true
		_start_music()


func set_music_volume(value: float) -> void:
	if not AudioSettingsStore.valid_volume(value):
		return
	music_volume = value
	_volume_changed()


func set_effects_volume(value: float) -> void:
	if not AudioSettingsStore.valid_volume(value):
		return
	effects_volume = value
	_volume_changed()


func _volume_changed() -> void:
	_apply_volumes()
	volumes_changed.emit()
	_save_timer.start()


func _apply_volumes() -> void:
	for pair: Array in [[&"Music", music_volume], [&"SFX", effects_volume]]:
		var index: int = AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_linear(index, pair[1])
		AudioServer.set_bus_mute(index, _backgrounded or pair[1] <= 0.0)


func save_settings() -> void:
	_save_timer.stop()
	last_save_error = settings_store.save_settings(music_volume, effects_volume)
	if last_save_error != OK:
		settings_save_failed.emit(last_save_error)
	else:
		settings_saved.emit()


func play_music(kind: StringName) -> void:
	if kind != &"menu" and kind != &"battle":
		return
	if kind == _music_name and _music_players[_music_index].playing:
		return
	if _music_name != kind:
		stop_effects()
	_music_name = kind
	if _unlocked:
		_start_music()


func _start_music() -> void:
	if _backgrounded or _music_name.is_empty():
		return
	var stream: AudioStream = config.menu if _music_name == &"menu" else config.battle
	var outgoing: AudioStreamPlayer = _music_players[_music_index]
	if outgoing.stream == stream and outgoing.playing:
		return
	if _music_tween != null:
		_music_tween.kill()
	_music_index = 1 - _music_index
	var incoming: AudioStreamPlayer = _music_players[_music_index]
	incoming.stop()
	incoming.stream = stream
	incoming.volume_db = -60.0
	incoming.play()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", 0.0, config.music_transition)
	_music_tween.tween_property(outgoing, "volume_db", -60.0, config.music_transition)
	_music_tween.chain().tween_callback(outgoing.stop)


func play_sfx(event: StringName) -> void:
	if _backgrounded or not _unlocked or effects_volume <= 0.0 or not config.effects.has(event):
		return
	var player: AudioStreamPlayer
	if event in [&"archer", &"fire_cast", &"frost_cast", &"priest_cast"]:
		if get_tree().paused:
			return
		var now: int = Time.get_ticks_msec()
		if now - _last_combat_time.get(event, -10000) < config.combat_spacing * 1000.0:
			return
		player = _free_player(_combat)
		if player != null:
			_last_combat_time[event] = now
	elif event == &"ui_click":
		player = $SFX/UI
	elif event == &"tower_hit":
		player = $SFX/TowerHit
	elif event in [&"tower_destroyed", &"revive"]:
		player = $SFX/TowerState
	elif event == &"boss":
		player = $SFX/Boss
	else:
		player = _free_player(_actions)
	if player == null:
		return
	player.stop()
	player.stream = config.effects[event]
	player.volume_db = config.effect_volume_db.get(event, 0.0)
	player.play()


func _free_player(players: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for player: AudioStreamPlayer in players:
		if not player.playing:
			return player
	return null


func stop_combat() -> void:
	for player: AudioStreamPlayer in _combat:
		player.stop()


func stop_effects() -> void:
	for player: AudioStreamPlayer in $SFX.get_children():
		if player.name != &"UI":
			player.stop()
	_last_combat_time.clear()


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_bind_button.call_deferred(node)


func _bind_scene_buttons() -> void:
	# Начальная сцена может войти в дерево до _ready Autoload.
	for button: Node in get_tree().root.find_children("*", "BaseButton", true, false):
		_bind_button(button as BaseButton)


func _bind_button(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	var callback: Callable = _on_button_pressed.bind(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _on_button_pressed(button: BaseButton) -> void:
	if is_instance_valid(button) and not button.has_meta(&"skip_ui_sound"):
		play_sfx(&"ui_click")
