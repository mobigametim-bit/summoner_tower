extends Node

const CHECKS: Script = preload("res://scripts/debug/biome_victory_checks.gd")
var checks: RefCounted = CHECKS.new()
var _callback: JavaScriptObject
@onready var game: Node2D = $Game


func _ready() -> void:
	SessionProgress.use_test_save(CHECKS.SAVE_PATH)
	AudioService.settings_store = AudioSettingsStore.new("")
	checks.prepare(game)
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(_command)
		JavaScriptBridge.get_interface("window").biomeVictory = _callback


func _command(args: Array) -> void:
	var action: String = str(args[0]) if not args.is_empty() else "snapshot"
	match action:
		"prepare": checks.prepare(game)
		"boss": checks.kill_boss(game)
		"clear": checks.clear_wave(game)
		"lethal": checks.lethal_boss(game)
		"repeat":
			game.wave_manager._try_finish_wave()
			game._on_encounter_completed()
			game.run_statistics.finish(true, &"graveyard")
		"reset":
			DirAccess.remove_absolute(CHECKS.SAVE_PATH)
			SessionProgress.use_test_save(CHECKS.SAVE_PATH)
			checks.prepare(game)
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	window.biomeVictoryJSON = JSON.stringify(checks.snapshot(game))


func _on_prepare_pressed() -> void:
	checks.prepare(game)


func _on_boss_pressed() -> void:
	checks.kill_boss(game)


func _on_clear_pressed() -> void:
	checks.clear_wave(game)


func _on_lethal_pressed() -> void:
	checks.lethal_boss(game)


func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").biomeVictory = null
