class_name SummonManager
extends Node

signal state_changed(mana: int, cost: int, occupied: int, capacity: int, available: bool)
signal unit_refunded(amount: int)
signal unit_summoned(unit: CombatUnit, gift: bool)
signal transfer_completed(unit: CombatUnit, destination: SummonSlot, merged: bool, swapped: bool)
signal unit_merged

@export var config: SummonConfig
@export var pool: SummonPool

var mana: int = 0
var successful_summons: int = 0
var tutorial_archers_remaining: int = 0

var _slots: Array[SummonSlot] = []
var _enemies: Node2D
var _projectiles: Node2D
var _running: bool = false
var _busy: bool = false
var _interaction_enabled: bool = true
var _run_bonuses: RunBonuses
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func configure(slots: Node2D, enemies: Node2D, projectiles: Node2D, bonuses: RunBonuses = null) -> void:
	_enemies = enemies
	_projectiles = projectiles
	_run_bonuses = bonuses
	for child: Node in slots.get_children():
		_slots.append(child as SummonSlot)
	mana = _run_bonuses.starting_mana_for(config.starting_mana) if _run_bonuses != null else config.starting_mana
	successful_summons = 0
	_running = true
	_interaction_enabled = true
	_rng.randomize()
	_emit_state()


func set_random_seed(value: int) -> void:
	_rng.seed = value


func current_cost() -> int:
	var base_cost: int = config.cost_after(successful_summons)
	return _run_bonuses.summon_cost_for(base_cost) if _run_bonuses != null else base_cost


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	_emit_state()


func occupied_count() -> int:
	var occupied: int = 0
	for slot: SummonSlot in _slots:
		if not slot.is_empty():
			occupied += 1
	return occupied


func can_summon() -> bool:
	return _running and _interaction_enabled and not _busy and pool != null and pool.is_valid() and mana >= current_cost() and occupied_count() < _slots.size()


func try_summon() -> bool:
	if not can_summon():
		return false

	var destination: SummonSlot
	for slot: SummonSlot in _slots:
		if slot.is_empty():
			destination = slot
			break
	if destination == null:
		return false

	# Добавление узла вызывает сигналы дерева: исключаем повторный призыв до завершения операции.
	_busy = true
	var previous_random_state: int = _rng.state
	var packed: PackedScene = preload("res://scenes/archer.tscn") if tutorial_archers_remaining > 0 else pool.roll(_rng)
	var instance: Node = packed.instantiate()
	var unit: CombatUnit = instance as CombatUnit
	if unit == null or unit.stats == null or unit.stats.level != 1 or not destination.place_unit(unit):
		instance.free()
		_rng.state = previous_random_state
		_busy = false
		return false

	# Сигнал добавления узла может завершить забег: откатываем незавершённый призыв.
	if not _running or not _interaction_enabled:
		destination.assign_unit(null)
		unit.stop()
		destination.unit_host.remove_child(unit)
		unit.free()
		_rng.state = previous_random_state
		_busy = false
		return false

	unit.configure(_enemies, _projectiles, _run_bonuses)
	unit.paid_mana = current_cost()
	mana -= unit.paid_mana
	successful_summons += 1
	tutorial_archers_remaining = maxi(tutorial_archers_remaining - 1, 0)
	destination.play_summon_effect()
	AudioService.play_sfx(&"summon")
	_busy = false
	_emit_state()
	unit_summoned.emit(unit, false)
	return true


func add_mana(amount: int) -> void:
	if not _running or amount <= 0:
		return
	mana += amount
	_emit_state()


func stop() -> void:
	_running = false
	for slot: SummonSlot in _slots:
		if not slot.is_empty():
			slot.unit.stop()
	_emit_state()


func can_rearrange() -> bool:
	return _running and _interaction_enabled and not _busy


func try_transfer(source: SummonSlot, destination: SummonSlot, expected_unit: CombatUnit) -> bool:
	if not can_rearrange() or not is_instance_valid(expected_unit) or expected_unit.is_queued_for_deletion():
		return false
	if not _slots.has(source) or not _slots.has(destination) or source == destination:
		return false
	if source.unit != expected_unit or expected_unit.get_parent() != source.unit_host:
		return false
	var other: CombatUnit = destination.unit if not destination.is_empty() else null
	if other != null and (other.get_parent() != destination.unit_host or other.is_queued_for_deletion()):
		return false

	_busy = true
	if other != null and expected_unit.can_merge_with(other):
		# Ссылки и уровень фиксируются до сигналов удаления исходного узла.
		source.assign_unit(null)
		other.paid_mana += expected_unit.paid_mana
		expected_unit.paid_mana = 0
		other.promote()
		destination.play_merge_effect()
		AudioService.play_sfx(&"merge")
		expected_unit.retire_into(other)
		expected_unit.queue_free()
		unit_merged.emit()
		source.unit_host.remove_child(expected_unit)
		_busy = false
		_emit_state()
		transfer_completed.emit(expected_unit, destination, true, false)
		return true

	# Фиксируем обе ссылки до reparent: сигналы дерева видят согласованную операцию.
	source.assign_unit(other)
	destination.assign_unit(expected_unit)
	expected_unit.reparent(destination.unit_host, false)
	if other != null:
		other.reparent(source.unit_host, false)
	source.align_unit()
	destination.align_unit()
	expected_unit.refresh_target()
	if other != null:
		other.refresh_target()
	_busy = false
	_emit_state()
	transfer_completed.emit(expected_unit, destination, false, other != null)
	return true


func refund_amount(unit: CombatUnit, map_change: bool = false, boss_number: int = 1) -> int:
	if not is_instance_valid(unit):
		return 0
	if map_change or _run_bonuses == null:
		return config.refund_for(unit.paid_mana, map_change, boss_number)
	return floori(maxi(unit.paid_mana, 0) * _run_bonuses.manual_refund_percent(config.refund_percent) / 100.0 + RunBonuses.ROUNDING_EPSILON)


func grant_unit(scene: PackedScene, stats: UnitStats) -> bool:
	# Награда после генерации карты, без расхода маны и роста цены призыва.
	if not _running or _busy or scene == null or stats == null:
		return false
	var destination: SummonSlot
	for slot: SummonSlot in _slots:
		if slot.is_empty():
			destination = slot
			break
	if destination == null:
		return false
	_busy = true
	var unit: CombatUnit = scene.instantiate() as CombatUnit
	unit.stats = stats
	unit.paid_mana = 0
	if not destination.place_unit(unit):
		unit.free()
		_busy = false
		return false
	unit.configure(_enemies, _projectiles, _run_bonuses)
	destination.play_summon_effect()
	AudioService.play_sfx(&"summon")
	_busy = false
	_emit_state()
	unit_summoned.emit(unit, true)
	return true


func try_refund(source: SummonSlot, expected_unit: CombatUnit) -> bool:
	if not can_rearrange() or not is_instance_valid(expected_unit) or expected_unit.is_queued_for_deletion():
		return false
	if not _slots.has(source) or source.unit != expected_unit or expected_unit.get_parent() != source.unit_host:
		return false
	if expected_unit.paid_mana < 0:
		return false

	_busy = true
	var amount: int = refund_amount(expected_unit)
	# Фиксируем возврат до callbacks удаления: повторный запрос не найдёт бойца в слоте.
	source.assign_unit(null)
	expected_unit.paid_mana = 0
	expected_unit.stop()
	mana += amount
	for child: Node in _projectiles.get_children():
		var projectile: CombatProjectile = child as CombatProjectile
		if projectile != null:
			projectile.cancel_from(expected_unit)
	expected_unit.queue_free()
	source.unit_host.remove_child(expected_unit)
	_busy = false
	unit_refunded.emit(amount)
	AudioService.play_sfx(&"sell")
	_emit_state()
	return true


func _emit_state() -> void:
	state_changed.emit(mana, current_cost(), occupied_count(), _slots.size(), can_summon())


func sell_army_for_map_change(boss_number: int = 1) -> int:
	if not _running or _busy:
		return 0
	_busy = true
	var sold: Array[CombatUnit] = []
	var amount: int = 0
	for slot: SummonSlot in _slots:
		if not slot.is_empty():
			var unit: CombatUnit = slot.unit
			amount += refund_amount(unit, true, boss_number)
			unit.paid_mana = 0
			unit.stop()
			sold.append(unit)
			slot.assign_unit(null)
	# Все слоты очищены до callbacks удаления; повторный вызов не вернёт ману повторно.
	# На новой карте бюджет состоит только из возврата; накопленный остаток сгорает.
	mana = amount
	for unit: CombatUnit in sold:
		for child: Node in _projectiles.get_children():
			var projectile: CombatProjectile = child as CombatProjectile
			if projectile != null:
				projectile.cancel_from(unit)
		unit.queue_free()
		unit.get_parent().remove_child(unit)
	_busy = false
	if not sold.is_empty():
		unit_refunded.emit(amount)
		AudioService.play_sfx(&"sell")
	_emit_state()
	return amount


func rebind_slots(slots: Node2D, reset_price: bool) -> void:
	assert(occupied_count() == 0)
	_slots.clear()
	for child: Node in slots.get_children():
		_slots.append(child as SummonSlot)
	if reset_price:
		successful_summons = 0
	_emit_state()
