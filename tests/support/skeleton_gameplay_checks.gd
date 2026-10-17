extends RefCounted

const SCENE: PackedScene = preload("res://scenes/skeleton.tscn")


func _spawn(host: Node, tier: int) -> ApproachingEnemy:
	var enemy: ApproachingEnemy = SCENE.instantiate()
	host.add_child(enemy)
	enemy.configure(Vector2.ZERO,100000,enemy.stats.base_health*(1<<(tier-1)))
	enemy.set_physics_process(false)
	return enemy


func run(host: Node) -> Dictionary:
	var checks: int = 0
	for tier: int in range(1,6):
		var enemy: ApproachingEnemy = _spawn(host,tier)
		assert(enemy.max_health == 36*(1<<(tier-1)))
		assert(enemy.difficulty_tier == tier)
		assert(enemy.stats.kill_mana_for(enemy.max_health) == 3*(1<<(tier-1)))
		assert(enemy.tower_damage == 12 and is_equal_approx(enemy.move_speed,172.8))
		if tier < 5:
			enemy.take_damage(enemy.max_health/2.0)
			assert(enemy.abilities.shield_health == 0.0)
		enemy.stop()
		enemy.queue_free()
		checks += 1
	var shielded: ApproachingEnemy = _spawn(host,5)
	shielded.take_damage(287)
	assert(shielded.current_health == 289 and shielded.abilities.shield_health == 0)
	shielded.take_damage(1)
	assert(shielded.current_health == 288 and shielded.abilities.shield_health == 144)
	assert(is_instance_valid(shielded.undead_visual.get("_shield")))
	shielded.take_damage(100)
	assert(shielded.current_health == 288 and shielded.abilities.shield_health == 44)
	shielded.take_damage(50)
	assert(shielded.current_health == 282 and shielded.abilities.shield_health == 0)
	shielded.take_damage(1)
	assert(shielded.current_health == 281 and shielded.abilities.shield_health == 0)
	shielded.stop()
	shielded.queue_free()
	checks += 1
	var timed: ApproachingEnemy = _spawn(host,5)
	timed.take_damage(288)
	timed.apply_freeze(4)
	var before: float = timed.abilities.get("shield_remaining")
	host.get_tree().paused = true
	await host.get_tree().create_timer(0.2,true).timeout
	assert(is_equal_approx(before,timed.abilities.get("shield_remaining")))
	host.get_tree().paused = false
	await host.get_tree().create_timer(3.15).timeout
	assert(timed.abilities.shield_health == 0 and timed.abilities.get("shield_remaining") == 0)
	assert(timed.current_health == 288)
	assert(not is_instance_valid(timed.undead_visual.get("_shield")))
	timed.stop()
	timed.queue_free()
	checks += 1
	var lethal: ApproachingEnemy = _spawn(host,5)
	var count: Array[int] = [0]
	lethal.resolved.connect(func(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void:
		count[0] += 1
		assert(outcome == ApproachingEnemy.Outcome.KILLED and not enemy.is_targetable())
		enemy.take_damage(1000))
	lethal.take_damage(10000)
	assert(count[0] == 1 and lethal.abilities.shield_health == 0)
	checks += 1
	var contact: ApproachingEnemy = _spawn(host,1)
	var contacts: Array[int] = [0]
	contact.resolved.connect(func(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void:
		contacts[0] += 1
		assert(outcome == ApproachingEnemy.Outcome.REACHED_TOWER)
		assert(enemy.undead_visual.get("_impact_emitted")))
	contact._target_y = 1.0
	contact._physics_process(1.0)
	assert(contacts[0] == 1)
	checks += 1
	await host.get_tree().create_timer(0.8).timeout
	assert(host.get_tree().get_nodes_in_group(&"enemy_visual_tails").is_empty())
	var goblin: ApproachingEnemy = load("res://scenes/enemy.tscn").instantiate()
	host.add_child(goblin)
	goblin.configure(Vector2.ZERO,100000)
	goblin.take_damage(1)
	assert(goblin.current_health == 29 and goblin.undead_visual == null and goblin.goblin_visual != null)
	goblin.stop()
	goblin.queue_free()
	return {"passed":true,"groups":checks+1,"tiers":5,"shield_capacity":144,"shield_seconds":3}
