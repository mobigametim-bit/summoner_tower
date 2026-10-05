class_name SummonManager
extends Node

signal state_changed(mana: int, cost: int, occupied: int, capacity: int, available: bool)
signal unit_refunded(amount: int)

@export var config: SummonConfig
@export var pool: SummonPool

var mana: int = 0
var successful_summons: int = 0

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
	mana = config.starting_mana
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
	var instance: Node = pool.roll(_rng).instantiate()
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
	_busy = false
	_emit_state()
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
		expected_unit.retire_into(other)
		expected_unit.queue_free()
		source.unit_host.remove_child(expected_unit)
		_busy = false
		_emit_state()
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
	return true


func refund_amount(unit: CombatUnit) -> int:
	return config.refund_for(unit.paid_mana) if is_instance_valid(unit) else 0


func try_refund(source: SummonSlot, expected_unit: CombatUnit) -> bool:
	if not can_rearrange() or not is_instance_valid(expected_unit) or expected_unit.is_queued_for_deletion():
		return false
	if not _slots.has(source) or source.unit != expected_unit or expected_unit.get_parent() != source.unit_host:
		return false
	if expected_unit.paid_mana <= 0:
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
	_emit_state()
	return true


func _emit_state() -> void:
	state_changed.emit(mana, current_cost(), occupied_count(), _slots.size(), can_summon())
