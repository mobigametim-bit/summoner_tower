extends Node

enum Outcome { SUCCESS, CANCELED, FAILED }

signal completed(product_id: StringName, outcome: Outcome)
signal ownership_changed

const CATALOG: ShopCatalog = preload("res://resources/balance/shop_catalog.tres")

var test_mode: bool = false
var _no_ads: bool = false
var _pending: StringName = &""
var _request_id: int = 0


func enable_test_mode() -> bool:
	if not SessionProgress._test_session:
		return false
	test_mode = true
	_no_ads = false
	_pending = &""
	return true


func has_no_ads() -> bool:
	# Тестовое право не может примениться к настоящему прогрессу игрока.
	return test_mode and SessionProgress._test_session and _no_ads


func is_available() -> bool:
	return test_mode and SessionProgress._test_session


func begin_purchase(product_id: StringName) -> int:
	var product: ShopProduct = CATALOG.find(product_id)
	if not is_available() or not _pending.is_empty() or product == null:
		return 0
	if product.kind == ShopProduct.Kind.NO_ADS and has_no_ads():
		return 0
	_request_id += 1
	_pending = product_id
	return _request_id


func finish_purchase(request_id: int, outcome: Outcome) -> bool:
	if not is_available() or _pending.is_empty() or request_id != _request_id:
		return false
	var product: ShopProduct = CATALOG.find(_pending)
	# Закрываем запрос до сохранения и сигналов: повторное уведомление ничего не выдаёт.
	_pending = &""
	if outcome == Outcome.SUCCESS:
		if product.kind == ShopProduct.Kind.NO_ADS:
			_no_ads = true
			ownership_changed.emit()
		elif not SessionProgress.try_add_reward(product.crystals):
			outcome = Outcome.FAILED
	completed.emit(product.product_id, outcome)
	return true
