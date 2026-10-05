extends Node

signal crystals_changed(total: int)
signal upgrades_changed

const UPGRADE_CONFIG: MetaUpgradeConfig = preload("res://resources/balance/meta_upgrade_config.tres")

# Баланс между сценами в текущей сессии; запись в user:// относится к фиче 12.
var crystals: int = 0
var upgrade_levels: Array[int] = [0, 0, 0, 0]
var _buying: bool = false


func add_crystals(amount: int) -> void:
	if amount <= 0:
		return
	crystals += amount
	crystals_changed.emit(crystals)


func upgrade_level(kind: int) -> int:
	return upgrade_levels[kind] if UPGRADE_CONFIG.is_valid_kind(kind) else 0


func can_buy(kind: int) -> bool:
	if not UPGRADE_CONFIG.is_valid_kind(kind):
		return false
	var price: int = UPGRADE_CONFIG.price_for(upgrade_level(kind))
	return price > 0 and crystals >= price


func try_buy(kind: int) -> bool:
	if _buying or not can_buy(kind):
		return false
	_buying = true
	# Оба значения фиксируются до сигналов; callback не может повторить покупку.
	crystals -= UPGRADE_CONFIG.price_for(upgrade_level(kind))
	upgrade_levels[kind] += 1
	crystals_changed.emit(crystals)
	upgrades_changed.emit()
	_buying = false
	return true
