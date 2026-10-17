extends RefCounted

var checks: int = 0
var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func enemy(game: Node) -> ApproachingEnemy:
	var result: ApproachingEnemy = game.spawn_subject("zombie",1,200.0)
	result.max_health = 10000
	result.current_health = 10000
	result.move_speed = 0.0
	result.set_physics_process(false)
	result.abilities.set_physics_process(false)
	return result


func run(game: Node) -> Dictionary:
	game.select_priest_level(5)
	for slot: SummonSlot in game.summon_manager._slots:
		if not slot.is_empty():
			slot.unit.attack_enabled = false
	var balance: PowerBalanceConfig = load("res://resources/balance/power_balance.tres")
	var expected: Array[float] = [0.746666667,2.156,7.2128,20.50048,83.16]
	for tier: int in range(1,6):
		var stats: UnitStats = load("res://resources/balance/priest_lv%d.tres"%tier)
		check(is_equal_approx(stats.attack_range,140.0*(1.0+0.2*(tier-1))),"Lv%d range"%tier)
		check(absf(balance.unit_power(stats,stats.damage,stats.attack_interval)-expected[tier-1]) < 0.0001,"Lv%d power"%tier)
		check((stats.next_level != null and stats.next_level.level == tier+1) if tier < 5 else stats.next_level == null,"Lv%d chain"%tier)
	var base: SummonPool = load("res://resources/balance/summon_pool.tres")
	var catalog: BiomeCatalog = game.get_node("/root/SessionProgress").biome_catalog
	var locked: SummonPool = catalog.summon_pool_for(base,["forest"])
	var opened: SummonPool = catalog.summon_pool_for(base,["forest","graveyard"])
	check(locked.scenes.size() == 3 and locked.weights == [40,35,25],"locked pool unchanged")
	check(opened.scenes.size() == 4 and opened.weights == [40,35,25,25],"unlocked 32/28/20/20 pool")
	check(base.scenes.size() == 3,"source pool not mutated")
	var store: SaveManager = SaveManager.new("user://priest_unlock_checks.json")
	var zero_levels: Array[int] = []
	zero_levels.resize(MetaUpgradeConfig.Kind.COUNT)
	zero_levels.fill(0)
	check(store.save_progress(0,zero_levels,["forest","graveyard"],"forest") == OK,"test unlock saved")
	var restored: Dictionary = store.load_progress()
	var restored_biomes: Array[String] = []
	restored_biomes.assign(restored.unlocked_biomes)
	check(restored.selected_biome == "forest" and catalog.summon_pool_for(base,restored_biomes).scenes.size() == 4,"unlock restored in forest")
	DirAccess.remove_absolute(store.path)
	var e: ApproachingEnemy = enemy(game)
	CombatHit.apply(e,80,0,0,0,0,0,0.15,3)
	check(e.current_health == 9920,"first hit not amplified")
	e.take_damage(100)
	check(e.current_health == 9805,"next incoming damage amplified")
	e.light_mark_remaining = 1.0
	var visual: Node2D = e._light_mark_visual
	e.apply_light_mark(0.1,5)
	check(is_equal_approx(e.light_mark_ratio,0.15) and is_equal_approx(e.light_mark_remaining,1),"weaker ignored without extending")
	e.apply_light_mark(0.15,3)
	check(e._light_mark_visual == visual and is_equal_approx(e.light_mark_remaining,3),"equal refreshes one visual")
	var player: AnimationPlayer = visual.get_node("AnimationPlayer") as AnimationPlayer
	player.seek(2.8,true)
	e.apply_light_mark(0.15,3)
	check(is_zero_approx(player.current_animation_position),"refresh resets visual lifetime too")
	e.apply_light_mark(0.25,3)
	check(e._light_mark_visual == visual and is_equal_approx(e.light_mark_ratio,0.25),"stronger replaces without stacking")
	e.abilities.shield_health = 100
	var health: int = e.current_health
	e.take_damage(100)
	check(e.current_health == health-25 and is_zero_approx(e.abilities.shield_health),"amplify before shield, once")
	e._damage_remainder = 0
	e.apply_light_mark(0.25,0.5)
	e.apply_burn(100,1)
	health = e.current_health
	e._physics_process(1.0)
	check(e.current_health == health-112 and is_equal_approx(e._damage_remainder,0.5),"DOT partial lifetime: 112.5, no double bonus")
	check(is_zero_approx(e.light_mark_ratio) and is_zero_approx(e.light_mark_remaining),"mark expires independently")
	e.apply_light_mark(0.25,3)
	e.apply_freeze(5)
	e._physics_process(3)
	check(is_zero_approx(e.light_mark_remaining) and e._freeze_remaining > 0,"freeze does not prolong mark")
	e.apply_light_mark(0.25,3)
	e.stop()
	check(is_zero_approx(e.light_mark_ratio) and e._light_mark_visual == null,"stop clears mark")
	game.select_priest_level(5)
	var priest: CombatUnit = game.summon_manager._slots[0].unit
	priest.attack_enabled = false
	var target: ApproachingEnemy = game.wave_manager._active[0]
	var neighbor: ApproachingEnemy = game.wave_manager._active[1]
	var outside: ApproachingEnemy = game.wave_manager._active[2]
	target.global_position = Vector2(300,400)
	neighbor.global_position = Vector2(384,400)
	outside.global_position = Vector2(386,400)
	priest._spawn_projectile(target,priest.stats,300,false,true)
	var bolt: CombatProjectile = game.projectiles.get_child(game.projectiles.get_child_count()-1) as CombatProjectile
	check(bolt.global_position.is_equal_approx(priest.priest_visual.release_point.global_position),"shot starts at animated staff")
	bolt.global_position = target.global_position
	bolt._hit_target()
	check(target.current_health == 11700 and neighbor.current_health == 11700 and outside.current_health == 12000,"Consecration 300 damage, radius85")
	check(is_equal_approx(target.light_mark_ratio,0.25) and is_equal_approx(neighbor.light_mark_ratio,0.25) and is_zero_approx(outside.light_mark_ratio),"Consecration marks only survivors in area")
	bolt._hit_target()
	check(target.current_health == 11700,"projectile impact once")
	var normal: ApproachingEnemy = enemy(game)
	var level3: UnitStats = load("res://resources/balance/priest_lv3.tres")
	priest._spawn_projectile(normal,level3,80)
	bolt = game.projectiles.get_child(game.projectiles.get_child_count()-1) as CombatProjectile
	bolt.global_position = normal.global_position
	bolt._hit_target()
	check(normal.current_health == 9920 and is_equal_approx(normal.light_mark_ratio,0.15),"ordinary projectile first damage then mark")
	priest._spawn_projectile(normal,level3,80)
	bolt = game.projectiles.get_child(game.projectiles.get_child_count()-1) as CombatProjectile
	normal.stop()
	bolt._physics_process(0.1)
	check(bolt.is_queued_for_deletion() and normal.current_health == 9920,"disappeared target cancels projectile")
	var bonuses: RunBonuses = game.run_bonuses
	bonuses._multipliers[RunUpgrade.Kind.ARCHER_TRAINING] = 2.0
	check(is_equal_approx(bonuses.damage_amount_for(priest.stats),400),"archer card does not strengthen priest")
	bonuses._multipliers[RunUpgrade.Kind.POWER] = 1.5
	check(is_equal_approx(bonuses.damage_amount_for(priest.stats),600),"generic card strengthens priest once")
	bonuses.reset()
	game.select_priest_level(2)
	var manager: SummonManager = game.summon_manager
	var a: SummonSlot = manager._slots[0]
	check(manager.grant_unit(load("res://scenes/priest.tscn"),load("res://resources/balance/priest_lv2.tres")),"grant second priest")
	var b: SummonSlot = manager._slots[1]
	a.unit.paid_mana = 20
	b.unit.paid_mana = 30
	check(manager.try_transfer(a,b,a.unit),"merge accepted")
	check(a.is_empty() and b.unit.stats.level == 3 and b.unit.paid_mana == 50,"merge level and paid mana")
	check(b.unit.drag_texture() == b.unit.stats.visual_texture,"drag uses current level art")
	var before: int = manager.mana
	var survivor: ApproachingEnemy = game.wave_manager._active[0]
	survivor.apply_light_mark(0.15,3)
	check(manager.try_refund(b,b.unit) and manager.mana == before+25,"manual sale gives half paid mana")
	check(is_equal_approx(survivor.light_mark_ratio,0.15),"mark survives sale of priest")
	game.select_priest_level(5)
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures}
