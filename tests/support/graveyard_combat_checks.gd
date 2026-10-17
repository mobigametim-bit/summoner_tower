extends RefCounted

var groups: Array[String] = []


func _reset(game: Node) -> void:
	game.wave_manager.stop()
	game.wave_manager.phase = WaveManager.Phase.FIGHTING
	game.wave_manager.wave_number = 1
	game.wave_manager.suspend_completion(true)
	game.get_tree().paused = false
	game.state = game.State.RUNNING
	game.tower.initialize(100)


func _spawn(game: Node, kind: String, tier: int = 5, offset: float = 50.0) -> ApproachingEnemy:
	var enemy: ApproachingEnemy = game.spawn_subject(kind,tier,offset)
	enemy.set_physics_process(false)
	enemy.abilities.set_physics_process(false)
	return enemy


func _corpses(game: Node, caster: ApproachingEnemy, count: int) -> void:
	for i: int in count:
		var dead: ApproachingEnemy = _spawn(game,"skeleton",1,caster._distance+10*i)
		dead.take_damage(100000)


func run(game: Node) -> Dictionary:
	_reset(game)
	var values: Dictionary = {"skeleton":[36,172.8,12,3],"zombie":[90,108,24,5],"ghoul":[24,216,18,4],"necromancer":[72,108,12,8],"flesh_golem":[288,84,36,8],"lich":[420,84,60,30]}
	var appearances: int = 0
	for kind: String in values:
		for tier: int in ([4,5] if kind == "flesh_golem" else [1,2,3,4,5]):
			var enemy: ApproachingEnemy = _spawn(game,kind,tier)
			var power: int = (2 if tier == 5 else 1) if kind == "flesh_golem" else 1<<(tier-1)
			assert(enemy.max_health == int(values[kind][0])*power)
			assert(enemy.tower_damage == int(values[kind][2]))
			assert(enemy.stats.kill_mana_for(enemy.max_health,enemy.difficulty_tier) == int(values[kind][3])*power)
			assert(is_equal_approx(enemy.move_speed,100.8 if kind == "flesh_golem" and tier == 5 else float(values[kind][1])))
			assert(enemy.undead_visual.get("level") == tier)
			assert(enemy.health_bar.z_index == 10 and not enemy.health_bar.z_as_relative)
			game.wave_manager._active.erase(enemy)
			enemy.stop()
			enemy.queue_free()
			appearances += 1
	groups.append("27 tier stats, visual levels and rewards")
	var zombie: ApproachingEnemy = _spawn(game,"zombie")
	zombie.take_damage(936)
	assert(zombie.current_health == 504)
	zombie.abilities._physics_process(2.0)
	assert(zombie.current_health == 792)
	zombie.take_damage(288)
	zombie.abilities._physics_process(2.0)
	assert(zombie.current_health == 504)
	groups.append("zombie regeneration once, exact 20 percent")
	_reset(game)
	var ghoul: ApproachingEnemy = _spawn(game,"ghoul")
	assert(is_equal_approx(ghoul.abilities.advance(5.0),5.0))
	assert(is_zero_approx(ghoul.abilities.advance(0.3)))
	ghoul.apply_haste(0.3,5.0)
	assert(is_equal_approx(ghoul.abilities.advance(0.8),1.28))
	assert(is_equal_approx(ghoul.current_move_speed(),280.8))
	groups.append("ghoul windup, dash integration and strongest haste")
	_reset(game)
	var necro: ApproachingEnemy = _spawn(game,"necromancer",3)
	var ally: ApproachingEnemy = _spawn(game,"skeleton",3,70)
	ally.take_damage(72)
	assert(game.wave_manager.graveyard_army.heal_target(necro) == ally)
	game.wave_manager.graveyard_army.heal(necro,ally)
	assert(ally.current_health == 79)
	game.wave_manager.graveyard_army.summon_skeletons(necro,false)
	game.wave_manager.graveyard_army.summon_skeletons(necro,false)
	game.wave_manager.graveyard_army.summon_skeletons(necro,false)
	assert(game.wave_manager.graveyard_army.summon_capacity(necro,&"skeleton") == 0)
	var summons: Array[ApproachingEnemy] = []
	for enemy: ApproachingEnemy in game.wave_manager._active:
		if enemy.get_meta("summoned",false):
			assert(enemy.max_health == 36)
			summons.append(enemy)
	assert(summons.size() == 4)
	summons[0].take_damage(100000)
	assert(game.wave_manager.graveyard_army._corpses.is_empty())
	necro.take_damage(100000)
	assert(summons[1].is_targetable())
	groups.append("nearest healing, skeleton cap, no summoned corpses, owner death")
	_reset(game)
	var first: ApproachingEnemy = _spawn(game,"necromancer",4)
	var second: ApproachingEnemy = _spawn(game,"necromancer",4,60)
	_corpses(game,first,1)
	assert(not game.wave_manager.graveyard_army.reserve_remains(first))
	_corpses(game,first,1)
	assert(game.wave_manager.graveyard_army.reserve_remains(first))
	assert(not game.wave_manager.graveyard_army.reserve_remains(second))
	first.take_damage(100000)
	assert(game.wave_manager.graveyard_army.reserve_remains(second))
	game.wave_manager.graveyard_army.assemble_flesh(second)
	assert(game.wave_manager.graveyard_army._corpses.size() == 1) # corpse of the dead caster remains
	var flesh: ApproachingEnemy
	for enemy: ApproachingEnemy in game.wave_manager._active:
		if enemy.stats.enemy_type == &"flesh_golem":
			flesh = enemy
	assert(flesh != null and flesh.max_health == 288 and flesh.move_speed == 84)
	_corpses(game,second,2)
	assert(not game.wave_manager.graveyard_army.reserve_remains(second))
	groups.append("one/two corpses, exclusive reservation, cancellation and flesh cap")
	_reset(game)
	necro = _spawn(game,"necromancer",5)
	_corpses(game,necro,2)
	assert(game.wave_manager.graveyard_army.reserve_remains(necro))
	game.wave_manager.graveyard_army.assemble_flesh(necro)
	for enemy: ApproachingEnemy in game.wave_manager._active:
		if enemy.stats.enemy_type == &"flesh_golem":
			assert(enemy.max_health == 576 and is_equal_approx(enemy.move_speed,100.8) and enemy.undead_visual.get("level") == 5)
	_corpses(game,necro,2)
	game.wave_manager.graveyard_army._physics_process(12.1)
	assert(game.wave_manager.graveyard_army._corpses.is_empty())
	groups.append("upgraded flesh and corpse expiry")
	_reset(game)
	var fallen: ApproachingEnemy = _spawn(game,"skeleton",1,100)
	fallen.take_damage(100000)
	var army: GraveyardArmy = game.wave_manager.graveyard_army
	var expiry: float = army._corpses[0].expires
	game.wave_manager.suspend_completion(false)
	assert(game.wave_manager.phase == WaveManager.Phase.INTERMISSION)
	assert(army._corpses.size() == 1)
	game.wave_manager.intermission_timer.stop()
	game.wave_manager._on_intermission_timeout()
	assert(game.wave_manager.wave_number == 2 and army._corpses.size() == 1)
	assert(army._corpses[0].expires == expiry)
	var next_caster: ApproachingEnemy = _spawn(game,"necromancer",4,100)
	_corpses(game,next_caster,1)
	assert(army.reserve_remains(next_caster))
	army.assemble_flesh(next_caster)
	assert(army._corpses.is_empty())
	groups.append("remains cross waves without lifetime reset and feed next-wave golem")
	for tier: int in range(1,6):
		_reset(game)
		var lich: ApproachingEnemy = _spawn(game,"lich",tier)
		var follower: ApproachingEnemy = _spawn(game,"skeleton",1,75)
		lich.take_damage(lich.max_health*0.8)
		lich.abilities._physics_process(0.3)
		lich.abilities._physics_process(0.3)
		var count: int = 0
		for enemy: ApproachingEnemy in game.wave_manager._active:
			if enemy.get_meta("summoned",false):
				count += 1
				assert(enemy.difficulty_tier == tier-1)
		assert(count == (3 if tier >= 3 else 0))
		assert(is_equal_approx(lich.abilities.shield_health,lich.max_health*0.2 if tier >= 4 else 0.0))
		assert(is_equal_approx(follower.abilities.haste_bonus,0.3 if tier == 5 else 0.0))
		assert(lich.abilities.haste_bonus == 0.0)
	groups.append("lich level gates, retinue tiers, shield and bell")
	_reset(game)
	necro = _spawn(game,"necromancer",3)
	ally = _spawn(game,"skeleton",1,70)
	ally.take_damage(10)
	necro.abilities.set("_heal_clock",0.0)
	necro.abilities._physics_process(0.01)
	ally.take_damage(100000)
	necro.abilities._physics_process(0.3)
	groups.append("healing target can die during cast")
	var forest: WaveConfig = load("res://resources/balance/wave_config.tres")
	var graveyard: WaveConfig = load("res://resources/balance/graveyard_waves.tres")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 91
	var old: Dictionary = WavePowerPlanner.new(forest).make_plan(1,0.0,rng)
	assert(old.sequence.size() == 5 and old.healths[0] == 30 and old.summary.counts.get("goblin_lv1") == 5)
	for wave: int in range(1,26):
		var plan: Dictionary = WavePowerPlanner.new(graveyard).make_plan(wave,80.0,rng)
		assert(plan.sequence.size() <= 81)
		if wave%5 == 0:
			assert(plan.sequence[0] == graveyard.boss_scene and plan.healths[0] == 420*(1<<(wave/5-1)))
		if wave == 1:
			assert(plan.sequence.size() == 5 and plan.healths[0] == 36)
	assert(WavePowerPlanner.new(graveyard)._candidates(4).size() == 8)
	assert(is_equal_approx(graveyard.power_balance.wave_budget_multiplier,1.0/3.0))
	groups.append("all 25 wave plans, four archetypes, unchanged forest and budget")
	_reset(game)
	var caster: ApproachingEnemy = _spawn(game,"necromancer",3)
	game.wave_manager.graveyard_army.summon_skeletons(caster,false)
	caster.take_damage(100000)
	game.wave_manager._completion_suspended = false
	game.wave_manager.wave_number = 25
	game.wave_manager._try_finish_wave()
	assert(game.wave_manager.phase == WaveManager.Phase.FIGHTING)
	for enemy: ApproachingEnemy in game.wave_manager._active.duplicate():
		enemy.take_damage(100000)
	assert(game.state == game.State.GAME_OVER and game.run_statistics.victory)
	assert(game.wave_manager.graveyard_army._corpses.is_empty())
	game.get_tree().paused = false
	groups.append("final victory waits for living summons and clears corpses")
	return {"passed":true,"appearances":appearances,"groups":groups}
