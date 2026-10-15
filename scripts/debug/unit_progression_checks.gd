extends RefCounted

var failures: Array[String] = []
var cases: int = 0
var root: Node2D
var enemies: Node2D
var projectiles: Node2D


func check(condition: bool, label: String) -> void:
	cases += 1
	if not condition:
		failures.append(label)


func enemy(kind: String = "enemy", pos: Vector2 = Vector2(120.0, 120.0)) -> ApproachingEnemy:
	var instance: ApproachingEnemy = load("res://scenes/%s.tscn" % kind).instantiate()
	enemies.add_child(instance)
	instance.configure(pos, 10000.0, 10000)
	instance.move_speed = 0.0
	instance.set_physics_process(false)
	return instance


func unit(kind: String, level: int) -> CombatUnit:
	var instance: CombatUnit = load("res://scenes/%s.tscn" % kind).instantiate()
	instance.stats = load("res://resources/balance/%s_lv%d.tres" % [kind, level])
	root.add_child(instance)
	instance.position = Vector2(60.0, 120.0)
	instance.configure(enemies, projectiles)
	instance.set_physics_process(false)
	return instance


func run(host: Node) -> Dictionary:
	root = Node2D.new()
	host.add_child(root)
	enemies = Node2D.new()
	projectiles = Node2D.new()
	root.add_child(enemies)
	root.add_child(projectiles)
	var balance: PowerBalanceConfig = load("res://resources/balance/power_balance.tres")
	var expected: Array = [[1.0,2.904,8.4,22.88,74.25], [1.04,3.399066667,12.133333333,34.32,122.148], [0.483,1.44144,5.5125,15.6156,60.361875]]
	for type_index: int in 3:
		for index: int in 5:
			var stats: UnitStats = load("res://resources/balance/%s_lv%d.tres" % [["archer","mage","frost_mage"][type_index],index+1])
			check(absf(balance.unit_power(stats, stats.damage, stats.attack_interval) - expected[type_index][index]) < 0.00001, "Approved power %d/%d" % [type_index,index+1])
	check(is_equal_approx(balance.player_power(20.464583333, 150), 30.696875), "Maximum HP scales player power")
	var target: ApproachingEnemy = enemy()
	target.take_damage(0.5)
	target.take_damage(0.5)
	check(target.current_health == 9999, "Fractional damage preserved")
	target.apply_burn(150.0, 1.5)
	target._physics_process(0.5)
	check(target.current_health == 9949, "DOT proportional to elapsed time")
	var remaining: float = target._burn_remaining
	target.apply_burn(15.0, 1.5)
	check(is_equal_approx(target._burn_remaining, remaining) and is_equal_approx(target._burn_dps, 100.0), "Weaker burn cannot replace or refresh stronger burn")
	target.apply_burn(150.0, 1.5)
	check(is_equal_approx(target._burn_remaining,1.5), "Same burn refreshes without stacking")
	check(target._status_visual.get_node("BurnBack").amount == 6 and target._status_visual.get_node("BurnFront").amount == 4, "Burn count 6+4")
	check(is_equal_approx(target._status_visual.get_node("BurnFront").modulate.a,0.4), "Burn opacity 40 percent")
	target._physics_process(1.5)
	check(target._status_visual == null, "Burn expiration frees status visual")
	var frozen: ApproachingEnemy = enemy("enemy", Vector2(0.0,0.0))
	frozen.move_speed = 100.0
	frozen.apply_slow(0.5,1.5)
	frozen.apply_freeze(0.65)
	check(is_equal_approx(frozen._status_visual.get_node("Ice").modulate.a,0.5), "Ice opacity 50 percent")
	frozen._physics_process(1.0)
	check(is_equal_approx(frozen.position.y,17.5), "Freeze and slow integrate partial frame correctly")
	var boss: ApproachingEnemy = enemy("boss",Vector2(120.0,140.0))
	boss.apply_freeze(0.65)
	boss.apply_slow(0.7,1.5)
	check(boss._freeze_remaining == 0.0 and is_equal_approx(boss.current_move_speed(),boss.move_speed*0.3), "Boss immune to full freeze, accepts slow")
	# Сосед в области и дальняя цель проверяют границу и отсутствие второго прямого попадания.
	var neighbor: ApproachingEnemy = enemy("enemy", Vector2(145.0,120.0))
	var far: ApproachingEnemy = enemy("enemy", Vector2(220.0,120.0))
	var mage: CombatUnit = unit("mage",3)
	var bolt: CombatProjectile = mage.projectile_scene.instantiate()
	projectiles.add_child(bolt)
	bolt.launch(target.global_position,target,mage.stats,mage,null,120.0)
	bolt.configure_attack(enemies)
	var before: int = target.current_health
	bolt._hit_target()
	check(target.current_health == before-120 and neighbor.current_health == 9940 and far.current_health == 10000, "Primary damage once, neighbor 50 percent, outside unaffected")
	check(is_equal_approx(target._burn_dps,16.0) and is_equal_approx(neighbor._burn_dps,8.0), "Splash burn based on actual hit damage")
	var archer: CombatUnit = unit("archer",3)
	archer._target = target
	archer._fire()
	var shots: int = projectiles.get_children().filter(func(n: Node) -> bool: return n is CombatProjectile and not n.is_queued_for_deletion()).size()
	archer._advance_shots(0.099)
	check(archer._shots.size() == 1, "Second arrow not released early")
	archer._advance_shots(0.001)
	check(archer._shots.is_empty() and projectiles.get_children().filter(func(n: Node) -> bool: return n is CombatProjectile and not n.is_queued_for_deletion()).size() == shots+1, "Second arrow after 0.1 seconds")
	var normal_arrows: Array[Node] = projectiles.get_children().filter(func(n: Node) -> bool: return n is CombatProjectile and n._attacker == archer)
	check(normal_arrows.size() == 2 and normal_arrows[0]._damage == 25.0 and normal_arrows[1]._damage == 25.0, "Series damage split 25+25")
	archer._fire()
	archer.promote()
	check(archer._shots.is_empty() and normal_arrows[0]._stats.level == 3 and normal_arrows[0]._damage == 25.0, "Merge cancels pending shot and preserves airborne snapshot")
	archer._fire()
	archer.stop()
	check(archer._shots.is_empty(), "Stop/sale cancels pending shots")
	var frost: CombatUnit = unit("frost_mage",5)
	frost._target = target
	frost._fire_skill()
	check(target._freeze_remaining > 0.0 and neighbor._freeze_remaining > 0.0 and boss._freeze_remaining == 0.0, "Ice wave freezes group and leaves boss mobile")
	# Метеор должен долететь до земли, даже если исходная цель погибла раньше.
	var doomed: ApproachingEnemy = enemy("enemy",Vector2(500.0,500.0))
	var survivor: ApproachingEnemy = enemy("enemy",Vector2(525.0,500.0))
	var meteor: CombatProjectile = mage.projectile_scene.instantiate()
	projectiles.add_child(meteor)
	meteor.launch(Vector2(500.0,290.0),doomed,load("res://resources/balance/mage_lv5.tres"),mage,null,600.0)
	meteor.configure_attack(enemies,true)
	mage._target = doomed
	mage._search_remaining = 1.0
	doomed.queue_free()
	await host.get_tree().process_frame
	mage._physics_process(0.0)
	check(not is_instance_valid(mage._target), "Deleted target safely ignored before target search")
	meteor._physics_process(0.5)
	check(survivor.current_health == 9400 and survivor._burn_remaining == 0.0, "Meteor lands after original target deletion and damages area once")
	# Ни один навык не запускается до трёх секунд или дважды на одном release.
	for kind: String in ["archer","mage","frost_mage"]:
		var fighter: CombatUnit = unit(kind,5)
		fighter._target = target
		fighter._cooldown = 10.0
		fighter._physics_process(2.99)
		check(fighter._skill_cooldown > 0.0, "Ability waits three seconds: "+kind)
		fighter._physics_process(0.01)
		check(is_equal_approx(fighter._skill_cooldown,3.0) and is_equal_approx(fighter._cooldown,7.0), "Automatic ability keeps normal attack timer: "+kind)
		fighter._physics_process(0.0)
		check(is_equal_approx(fighter._skill_cooldown,3.0), "No duplicate ability: "+kind)
		fighter.stop()
	root.queue_free()
	await host.get_tree().process_frame
	return {"ok":failures.is_empty(),"cases":cases,"failures":failures}
