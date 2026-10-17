extends RefCounted


# Вызывать только в изолированной review/test-сессии: проверяет реальные покупки.
static func run(progress: Node) -> Dictionary:
	assert(progress._test_session and progress.save_manager.path.is_empty())
	var config: MetaUpgradeConfig = progress.UPGRADE_CONFIG
	var before_levels: Array[int] = progress.upgrade_levels.duplicate()
	var before_crystals: int = progress.crystals
	var expected: Array[int] = [25, 50, 100, 200, 400, 800, 1600, 3200, 6400, 12800]
	var costs: Array[int] = []
	var purchases: int = 0
	for kind: int in MetaUpgradeConfig.Kind.COUNT:
		progress.upgrade_levels.fill(0)
		var branch_cost: int = 0
		for level: int in config.maximum_for(kind):
			var price: int = 250 if kind >= MetaUpgradeConfig.Kind.LUCKY_CHOICE else expected[level]
			assert(config.price_for(level, kind) == price)
			progress.crystals = price - 1
			assert(not progress.can_buy(kind) and not progress.try_buy(kind))
			assert(progress.crystals == price - 1 and progress.upgrade_level(kind) == level)
			progress.crystals = price
			assert(progress.can_buy(kind) and progress.try_buy(kind))
			assert(progress.crystals == 0 and progress.upgrade_level(kind) == level + 1)
			branch_cost += price
			purchases += 1
		progress.crystals = 1000000
		assert(config.price_for(config.maximum_for(kind), kind) == 0)
		assert(not progress.can_buy(kind) and not progress.try_buy(kind))
		assert(progress.crystals == 1000000)
		costs.append(branch_cost)
	assert(config.price_for(-1) == 0 and config.price_for(0, -1) == 0)
	assert(not progress.can_buy(-1) and not progress.can_buy(MetaUpgradeConfig.Kind.COUNT))
	var total: int = 0
	for cost: int in costs:
		total += cost
	assert(total == 156275 and purchases == 77)
	progress.upgrade_levels = before_levels
	progress.crystals = before_crystals
	progress.upgrades_changed.emit()
	progress.crystals_changed.emit(before_crystals)
	return {"purchases": purchases, "branch_costs": costs, "total": total}
