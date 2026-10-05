extends "res://tests/support/feature_10_test_scene.gd"

var _reward_elapsed: float = 0.0
var _reward_prepared: bool = false


func _ready() -> void:
	# Родительский Web preview не нужен: этот сценарий готовит свою награду.
	game.summon_manager.pool = load("res://tests/resources/archer_only_pool.tres")


func _process(delta: float) -> void:
	if OS.has_feature("web") and not _reward_prepared:
		_reward_elapsed += delta
		if _reward_elapsed >= 2.0:
			_reward_prepared = true
			prepare_result(8)


func run_meta_checks() -> void:
	var before_crystals: int = SessionProgress.crystals
	var before_levels: Array[int] = SessionProgress.upgrade_levels.duplicate()
	var config: MetaUpgradeConfig = SessionProgress.UPGRADE_CONFIG
	SessionProgress.upgrade_levels = [0, 0, 0, 0]
	SessionProgress.crystals = 24
	var failed: bool = SessionProgress.try_buy(0)
	assert(not failed and SessionProgress.crystals == 24 and SessionProgress.upgrade_level(0) == 0)
	assert(not SessionProgress.can_buy(-1) and not SessionProgress.can_buy(4))
	SessionProgress.crystals = 25
	SessionProgress.crystals_changed.connect(_attempt_reentrant_buy)
	var bought: bool = SessionProgress.try_buy(0)
	SessionProgress.crystals_changed.disconnect(_attempt_reentrant_buy)
	assert(bought and SessionProgress.crystals == 0 and SessionProgress.upgrade_level(0) == 1)
	assert(config.price_for(1) == 50 and config.price_for(9) == 250 and config.price_for(10) == 0)
	SessionProgress.upgrade_levels = [0, 0, 0, 0]
	SessionProgress.crystals = 5500
	for kind: int in 4:
		for level: int in 10:
			var price: int = config.price_for(level)
			var wallet: int = SessionProgress.crystals
			var success: bool = SessionProgress.try_buy(kind)
			assert(success and SessionProgress.crystals == wallet - price and SessionProgress.upgrade_level(kind) == level + 1)
		var extra: bool = SessionProgress.try_buy(kind)
		assert(not extra)
	assert(SessionProgress.crystals == 0)
	game.run_bonuses.reset()
	assert(game.run_bonuses.tower_health_for(100) == 200 and game.run_bonuses.starting_mana_for(100) == 200)
	var maximum_income: int = 0
	for index: int in 10:
		maximum_income += game.run_bonuses.kill_mana_for(3)
	assert(maximum_income == 45)
	SessionProgress.upgrade_levels = [1, 1, 1, 1]
	game.run_bonuses.reset()
	var income: int = 0
	for index: int in 20:
		income += game.run_bonuses.kill_mana_for(3)
	assert(income == 63)
	assert(game.run_bonuses.tower_health_for(100) == 110 and game.run_bonuses.starting_mana_for(100) == 110)
	var unit: CombatUnit = load("res://scenes/archer.tscn").instantiate()
	add_child(unit)
	unit.configure(game.enemies, game.projectiles, game.run_bonuses)
	unit.attack_enabled = false
	var damage: int = 0
	for index: int in 20:
		damage += unit._next_damage()
	assert(damage == 210)
	game.run_bonuses.apply(game.run_bonuses.pool.get_upgrade(RunUpgrade.Kind.POWER))
	game.run_bonuses.apply(game.run_bonuses.pool.get_upgrade(RunUpgrade.Kind.TOWER_ARMOR))
	game.run_bonuses.apply(game.run_bonuses.pool.get_upgrade(RunUpgrade.Kind.MANA_FLOW))
	assert(game.run_bonuses.tower_health_for(100) == 137)
	damage = 0
	for index: int in 10:
		damage += unit._next_damage()
	assert(damage == 126)
	income = 0
	for index: int in 10:
		income += game.run_bonuses.kill_mana_for(5)
	assert(income == 63)
	for type: String in ["archer", "mage", "frost_mage"]:
		for level: int in range(1, UnitStats.MAX_LEVEL + 1):
			var stats: UnitStats = load("res://resources/balance/%s_lv%d.tres" % [type, level])
			assert(is_equal_approx(game.run_bonuses.damage_amount_for(stats), stats.damage * 1.05 * 1.2))
	var target: ApproachingEnemy = load("res://scenes/enemy.tscn").instantiate()
	game.enemies.add_child(target)
	target.configure(Vector2.ZERO, 100000.0, 1000)
	target.set_physics_process(false)
	unit._target = target
	var health: int = target.current_health
	unit._fire()
	var projectile: CombatProjectile = game.projectiles.get_child(game.projectiles.get_child_count() - 1)
	var snapshot_damage: int = projectile._damage
	game.run_bonuses.apply(game.run_bonuses.pool.get_upgrade(RunUpgrade.Kind.POWER))
	projectile._hit_target()
	assert(target.current_health == health - snapshot_damage)
	target.queue_free()
	unit.queue_free()
	assert(load("res://resources/balance/archer_lv1.tres").damage == 10)
	SessionProgress.upgrade_levels = before_levels
	SessionProgress.crystals = before_crystals
	game.run_bonuses.reset()
	set_meta("meta_checks", {"passed":true, "maximum_cost_all_branches":5500, "damage_20_shots":210, "income_20_kills":63})


func _attempt_reentrant_buy(_total: int) -> void:
	var repeated: bool = SessionProgress.try_buy(1)
	assert(not repeated)
