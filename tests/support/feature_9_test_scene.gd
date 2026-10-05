extends "res://tests/support/feature_8_test_scene.gd"

var _checks: RefCounted = preload("res://tests/support/feature_9_checks.gd").new()
var _web_stage: int = 0
var _saw_wave_six: bool = false


func _ready() -> void:
	super._ready()
	if OS.has_feature("web"):
		prepare_first_choice.call_deferred()


func run_bonus_checks() -> void:
	set_meta("bonus_checks", _checks.run_bonuses(game))


func prepare_first_choice() -> void:
	_checks.prepare_first_choice(game)
	_web_stage = 1


func prepare_second_choice() -> void:
	_checks.prepare_second_choice(game)


func check_escape_and_shutdown() -> void:
	set_meta("choice_checks", _checks.check_escape_and_shutdown(game))


func _process(delta: float) -> void:
	if OS.has_feature("web") and _web_stage == 1 and game.wave_manager.wave_number == 6:
		_saw_wave_six = true
		prepare_second_choice()
		_web_stage = 2
	super._process(delta)


func snapshot() -> Dictionary:
	var result: Dictionary = super.snapshot()
	var offers: Array[Dictionary] = []
	for index: int in game._offered_upgrades.size():
		var upgrade: RunUpgrade = game._offered_upgrades[index]
		var rect: Rect2 = game.upgrade_choice.cards[index].get_global_rect()
		offers.append({"kind": upgrade.kind, "title": upgrade.title, "x": rect.get_center().x, "y": rect.get_center().y})
	result.offers = offers
	result.paused = get_tree().paused
	result.max_health = game.tower.max_health
	result.bonuses = game.run_bonuses._counts
	result.saw_wave_six = _saw_wave_six
	result.choice_visible = game.upgrade_choice.visible
	return result
