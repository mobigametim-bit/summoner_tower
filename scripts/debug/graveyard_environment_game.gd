extends "res://scripts/game/game_manager.gd"


func _ready() -> void:
	# Только development: проверяем окружение будущего биома в настоящем старом бою.
	SessionProgress.use_test_save()
	AudioService.settings_store = AudioSettingsStore.new("")
	$World/Battlefield.config = load("res://resources/biomes/graveyard_battlefield.tres")
	super._ready()
