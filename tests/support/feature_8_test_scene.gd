extends "res://tests/support/feature_7_test_scene.gd"

var spawned: Array[Dictionary] = []
var boss_outcomes: Array[Dictionary] = []
var rewards_by_type: Dictionary = {}


func _ready() -> void:
	super._ready()
	for enemy: ApproachingEnemy in game.enemies.get_children():
		_record_spawn(enemy.get_instance_id(), game.wave_manager.wave_number)
	game.enemies.child_entered_tree.connect(_on_child_entered)
	game.wave_manager.enemy_resolved.connect(_record_reward)


func _on_child_entered(child: Node) -> void:
	if child is ApproachingEnemy:
		_record_spawn.call_deferred(child.get_instance_id(), game.wave_manager.wave_number)


func _record_spawn(instance_id: int, wave: int) -> void:
	var enemy: ApproachingEnemy = instance_from_id(instance_id) as ApproachingEnemy
	if not is_instance_valid(enemy) or enemy.max_health <= 0 or enemy.has_meta("palette_test"):
		return
	spawned.append({"wave": wave, "type": str(enemy.stats.enemy_type),
		"hp": enemy.max_health, "speed": enemy.move_speed, "tier": enemy.difficulty_tier,
		"color": enemy.visual.modulate.to_html(), "mana": enemy.stats.kill_mana})


func _record_reward(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome, mana: int) -> void:
	var type: String = str(enemy.stats.enemy_type)
	rewards_by_type[type] = int(rewards_by_type.get(type, 0)) + mana
	if enemy.stats.is_boss:
		boss_outcomes.append({"wave": game.wave_manager.wave_number, "outcome": outcome, "mana": mana})


func run_enemy_checks() -> void:
	set_meta("feature8_checks", load("res://tests/support/feature_8_checks.gd").new().run(game))


func run_refund_checks() -> void:
	set_meta("refund_checks", load("res://tests/support/unit_refund_checks.gd").new().run(game))


func snapshot() -> Dictionary:
	var result: Dictionary = super.snapshot()
	var visible_enemies: Array[Dictionary] = []
	for enemy: ApproachingEnemy in game.enemies.get_children():
		if enemy.is_targetable():
			visible_enemies.append({"type": str(enemy.stats.enemy_type), "hp": enemy.current_health,
				"max_hp": enemy.max_health, "base_hp": enemy.stats.base_health,
				"base_speed": enemy.move_speed, "speed": enemy.current_move_speed(),
				"ratio": enemy._slow_ratio, "tier": enemy.difficulty_tier,
				"color": enemy.visual.modulate.to_html(), "indicator": enemy.slow_indicator.visible,
				"remaining": enemy._slow_remaining, "y": enemy.global_position.y})
	result.enemies = visible_enemies
	result.spawned = spawned
	result.boss_outcomes = boss_outcomes
	result.rewards_by_type = rewards_by_type
	var investments: Array[int] = []
	for slot: SummonSlot in slots:
		investments.append(0 if slot.is_empty() else slot.unit.paid_mana)
	result.investments = investments
	result.return_visible = game.drag_controller._return_zone.highlight.visible
	result.return_label = game.drag_controller._return_zone.refund_label.text
	result.health_text = game.hud.health_label.text
	result.mana_text = game.hud.mana_label.text
	result.price_text = game.tower.cost_label.text
	result.summon_disabled = game.tower.summon_button.disabled
	return result
