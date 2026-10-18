extends RefCounted


static func run(tree: SceneTree) -> Dictionary:
	var service: Node = tree.root.get_node("ShopService")
	var progress: Node = tree.root.get_node("SessionProgress")
	if not progress._test_session or not progress.save_manager.path.is_empty():
		return {"ok":false,"reason":"Only an isolated in-memory review is allowed"}
	var initial: int = progress.crystals
	var checks: Dictionary = {}
	for product: ShopProduct in service.CATALOG.products:
		if product.kind == ShopProduct.Kind.NO_ADS:
			continue
		var before: int = progress.crystals
		var request: int = service.begin_purchase(product.product_id)
		var busy_rejected: bool = service.begin_purchase(product.product_id) == 0
		var completed: bool = service.finish_purchase(request, service.Outcome.SUCCESS)
		var once: bool = not service.finish_purchase(request, service.Outcome.SUCCESS)
		checks[String(product.product_id)] = request > 0 and busy_rejected and completed and once and progress.crystals == before + product.crystals
	for outcome: int in [service.Outcome.CANCELED, service.Outcome.FAILED]:
		var before: int = progress.crystals
		var request: int = service.begin_purchase(&"souls_300")
		service.finish_purchase(request, outcome)
		checks["no_grant_%d" % outcome] = progress.crystals == before
	var before_failure: int = progress.crystals
	progress.save_manager.writable = false
	var failed: int = service.begin_purchase(&"souls_300")
	service.finish_purchase(failed, service.Outcome.SUCCESS)
	checks["save_failure_no_grant"] = progress.crystals == before_failure
	progress.save_manager.writable = true
	var entitlement: int = service.begin_purchase(&"no_ads")
	service.finish_purchase(entitlement, service.Outcome.SUCCESS)
	checks["permanent_once"] = service.has_no_ads() and service.begin_purchase(&"no_ads") == 0 and progress.crystals == before_failure
	service.test_mode = false
	checks["ordinary_mode_unavailable"] = not service.has_no_ads() and service.begin_purchase(&"souls_300") == 0
	service.test_mode = true
	progress.crystals = initial
	progress.crystals_changed.emit(initial)
	var ok: bool = true
	for passed: bool in checks.values():
		ok = ok and passed
	return {"ok":ok,"checks":checks,"balance_restored":progress.crystals,"save_path":progress.save_manager.path}
