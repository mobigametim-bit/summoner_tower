extends "res://tests/support/feature_6_test_scene.gd"

@export var run_seed: int = 23


func _ready() -> void:
	super._ready()
	game.summon_manager.set_random_seed(run_seed)


func run_unit_checks() -> void:
	set_meta("feature7_checks", load("res://tests/support/feature_7_checks.gd").new().run(game))


func snapshot() -> Dictionary:
	var result: Dictionary = super.snapshot()
	var types: Array[String] = []
	for slot: SummonSlot in slots:
		types.append("" if slot.is_empty() else str(slot.unit.stats.unit_type))
	var slowed: Array[Dictionary] = []
	for enemy: ApproachingEnemy in game.enemies.get_children():
		if enemy.is_targetable():
			slowed.append({"hp": enemy.current_health, "max_hp": enemy.max_health,
				"speed": enemy.current_move_speed(), "ratio": enemy._slow_ratio,
				"remaining": enemy._slow_remaining, "indicator": enemy.slow_indicator.visible})
	result.types = types
	result.enemies = slowed
	result.seed = run_seed
	return result
