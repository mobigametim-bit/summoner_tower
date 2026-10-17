extends RefCounted

var checks: int = 0
var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func run(game: Node) -> Dictionary:
	game.wave_manager.stop()
	var bonuses: RunBonuses = game.run_bonuses
	var pool: RunUpgradePool = bonuses.pool
	var base: RunUpgradePool = load("res://resources/balance/run_upgrade_pool.tres")
	var catalog: BiomeCatalog = game.get_node("/root/SessionProgress").biome_catalog
	check(base.upgrades.size() == 20, "base pool remains20")
	check(catalog.upgrade_pool_for(base,["forest"]).upgrades.size() == 20, "locked forest has no Priest cards")
	check(catalog.upgrade_pool_for(base,["forest","graveyard"]).upgrades.size() == 24, "unlocked pool24")
	check(catalog.upgrade_pool_for(pool,["forest","graveyard"]).upgrades.size() == 24, "pool deduplicated")
	check(pool.tier_weights == [50,25,15,8,2], "rarity unchanged")
	var strengths: Array = [[0,0,0,0,0],[0.07,0.15,0.22,0.3,0.45],[0.25,0.5,0.75,1.0,1.5],[0.1,0.2,0.3,0.4,0.6]]
	var icons: Array[String] = []
	for index: int in 4:
		var source: RunUpgrade = pool.get_upgrade((20+index) as RunUpgrade.Kind)
		check(source.icon != null and not icons.has(source.icon.resource_path), "distinct icon%d"%index)
		icons.append(source.icon.resource_path)
		for tier: int in range(1,6):
			var card: RunUpgrade = source.variant_for(tier)
			check(is_equal_approx(card.strength,float(strengths[index][tier-1])), "card%d tier%d strength"%[index,tier])
			check(card.unit_stats.level == tier if index == 0 else card.unit_scene == null, "card%d tier%d reward"%[index,tier])
			check(not card.description_text().contains("{value}"), "formatted description")
		check(source.tier == 2, "source rarity not mutated")
	var priest: UnitStats = load("res://resources/balance/priest_lv5.tres")
	bonuses.reset()
	bonuses.apply(pool.get_upgrade(RunUpgrade.Kind.LIGHT_POWER).variant_for(1))
	bonuses.apply(pool.get_upgrade(RunUpgrade.Kind.LIGHT_POWER).variant_for(5))
	bonuses.apply(pool.get_upgrade(RunUpgrade.Kind.LONG_PRAYER).variant_for(1))
	bonuses.apply(pool.get_upgrade(RunUpgrade.Kind.LONG_PRAYER).variant_for(5))
	bonuses.apply(pool.get_upgrade(RunUpgrade.Kind.SACRED_RADIANCE).variant_for(1))
	bonuses.apply(pool.get_upgrade(RunUpgrade.Kind.SACRED_RADIANCE).variant_for(5))
	var effective: UnitStats = bonuses.combat_stats_for(priest)
	check(is_equal_approx(bonuses.damage_amount_for(priest),620.6), "multiplicative Priest damage")
	check(is_equal_approx(effective.light_mark_duration,4.75), "additive prayer duration")
	check(is_equal_approx(effective.ability_damage_ratio,1.32), "multiplicative Consecration ratio")
	check(priest.damage == 400 and priest.light_mark_duration == 3 and priest.ability_damage_ratio == 0.75, "source stats unchanged")
	for kind: String in ["archer","mage","frost_mage"]:
		var other: UnitStats = load("res://resources/balance/%s_lv5.tres"%kind)
		check(is_equal_approx(bonuses.damage_amount_for(other),other.damage), "no damage spill to %s"%kind)
		check(is_equal_approx(bonuses.combat_stats_for(other).ability_damage_ratio,other.ability_damage_ratio), "no ability spill to %s"%kind)
	for tier: int in [1,2]:
		var low: UnitStats = load("res://resources/balance/priest_lv%d.tres"%tier)
		check(is_zero_approx(bonuses.combat_stats_for(low).light_mark_duration), "no mark beforeLv3")
	var enemy: ApproachingEnemy = load("res://scenes/zombie.tscn").instantiate()
	game.enemies.add_child(enemy)
	enemy.configure(Vector2(300,400),100000,20000)
	enemy.set_physics_process(false)
	enemy.abilities.set_physics_process(false)
	game.summon_manager._running = true
	game.summon_manager.grant_unit(load("res://scenes/priest.tscn"),priest)
	var unit: CombatUnit = game.summon_manager._slots[0].unit
	unit.attack_enabled = false
	unit._target = enemy
	unit._fire_skill()
	var shot: CombatProjectile = game.projectiles.get_child(game.projectiles.get_child_count()-1) as CombatProjectile
	check(is_equal_approx(shot._damage,819.192), "actual skill uses both damage bonuses once")
	shot.global_position = enemy.global_position
	shot._hit_target()
	check(enemy.current_health == 19181 and is_equal_approx(enemy._damage_remainder,0.192), "actual AoE damage")
	check(is_equal_approx(enemy.light_mark_remaining,4.75), "actual extended mark")
	check(is_equal_approx(enemy._light_mark_visual.get_node("AnimationPlayer").speed_scale,3.0/4.75), "visual lifetime tracks extended mark")
	var balance: PowerBalanceConfig = game.wave_manager.config.power_balance
	check(balance.unit_power(effective,bonuses.damage_amount_for(priest),unit.effective_attack_interval()) > balance.unit_power(priest,priest.damage,priest.attack_interval), "power uses stronger ability")
	enemy.stop()
	enemy.queue_free()
	bonuses.reset()
	check(bonuses.damage_amount_for(priest) == 400 and bonuses.combat_stats_for(priest).light_mark_duration == 3, "new run resets bonuses")
	# Реальный обработчик выбора: старое войско продаётся до выдачи подаренного Жреца.
	for tier: int in range(1,6):
		game.show_cards(tier)
		game._on_upgrade_chosen(0)
		var granted: CombatUnit
		for slot: SummonSlot in game.summon_manager._slots:
			if not slot.is_empty():
				granted = slot.unit
		check(granted != null and granted.stats.unit_type == &"priest" and granted.stats.level == tier, "actual grant tier%d"%tier)
		check(granted.paid_mana == 0 and game.summon_manager.refund_amount(granted) == 0 and game.summon_manager.refund_amount(granted,true) == 0, "gift zero resale tier%d"%tier)
		var changes: int = game.map_changes
		game._on_upgrade_chosen(0)
		check(game.map_changes == changes and game.summon_manager.occupied_count() == 1, "choose once tier%d"%tier)
	game.show_cards(2)
	return {"passed":failures.is_empty(), "checks":checks, "failures":failures}
