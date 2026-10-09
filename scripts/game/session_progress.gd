extends Node

signal crystals_changed(total: int)
signal upgrades_changed
signal save_failed(error: int)

const UPGRADE_CONFIG: MetaUpgradeConfig = preload("res://resources/balance/meta_upgrade_config.tres")

var crystals: int = 0
var upgrade_levels: Array[int] = [0, 0, 0, 0]
var save_manager: SaveManager = SaveManager.new(SaveManager.SAVE_PATH, UPGRADE_CONFIG.maximum_level)
var _buying: bool = false
var _test_session: bool = false


func _ready() -> void:
	var review_launch: bool = _is_review_path(str(ProjectSettings.get_setting("application/run/main_scene", "")))
	for argument: String in OS.get_cmdline_args():
		review_launch = review_launch or _is_review_path(argument)
	if review_launch:
		use_test_save()
	else:
		_restore_progress()
	# Срабатывает до _ready дочерних Game/RunBonuses: тесты не читают бонусы игрока.
	get_tree().root.child_entered_tree.connect(_on_root_child_entered)


func use_test_save(path: String = "") -> void:
	# Изоляция нужна и для release-сборок тестовых сцен, не только debug templates.
	_test_session = true
	save_manager = SaveManager.new(path, UPGRADE_CONFIG.maximum_level)
	_restore_progress()


func _on_root_child_entered(node: Node) -> void:
	var script: Script = node.get_script() as Script
	if not _test_session and (_is_review_path(node.scene_file_path) or (script != null and _is_review_path(script.resource_path))):
		use_test_save()


func _is_review_path(path: String) -> bool:
	return path.begins_with("res://tests/") or path.begins_with("res://scenes/debug/") or path.begins_with("res://scripts/debug/")


func _restore_progress() -> void:
	var data: Dictionary = save_manager.load_progress()
	crystals = data.crystals
	upgrade_levels.assign(data.upgrade_levels)
	if save_manager.load_status in ["invalid", "unreadable", "future_version"]:
		push_warning("Прогресс не загружен (%s); использованы начальные значения." % save_manager.load_status)


func _save_progress() -> bool:
	var error: Error = save_manager.save_progress(crystals, upgrade_levels)
	if error != OK:
		push_warning("Не удалось сохранить прогресс: %s" % error_string(error))
	return error == OK


func add_crystals(amount: int) -> void:
	if amount <= 0:
		return
	crystals += mini(amount, SaveManager.MAX_CRYSTALS - crystals)
	if not _save_progress():
		save_failed.emit(save_manager.last_error)
	crystals_changed.emit(crystals)


func try_add_reward(amount: int) -> bool:
	if amount <= 0 or not save_manager.writable:
		return false
	var previous: int = crystals
	crystals += mini(amount, SaveManager.MAX_CRYSTALS - crystals)
	if not _save_progress():
		crystals = previous
		save_failed.emit(save_manager.last_error)
		return false
	crystals_changed.emit(crystals)
	return true


func upgrade_level(kind: int) -> int:
	return upgrade_levels[kind] if UPGRADE_CONFIG.is_valid_kind(kind) else 0


func can_buy(kind: int) -> bool:
	if not save_manager.writable or not UPGRADE_CONFIG.is_valid_kind(kind):
		return false
	var price: int = UPGRADE_CONFIG.price_for(upgrade_level(kind))
	return price > 0 and crystals >= price


func try_buy(kind: int) -> bool:
	if _buying or not can_buy(kind):
		return false
	_buying = true
	var previous_crystals: int = crystals
	# Оба значения фиксируются до сигналов; callback не может повторить покупку.
	crystals -= UPGRADE_CONFIG.price_for(upgrade_level(kind))
	upgrade_levels[kind] += 1
	if not _save_progress():
		# Не подтверждаем покупку, которую не смогли сохранить.
		crystals = previous_crystals
		upgrade_levels[kind] -= 1
		save_failed.emit(save_manager.last_error)
		_buying = false
		return false
	crystals_changed.emit(crystals)
	upgrades_changed.emit()
	_buying = false
	return true
