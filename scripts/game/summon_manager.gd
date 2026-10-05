class_name SummonManager
extends Node

signal state_changed(mana: int, cost: int, occupied: int, capacity: int, available: bool)

@export var config: SummonConfig
@export var unit_scene: PackedScene

var mana: int = 0
var successful_summons: int = 0

var _slots: Array[SummonSlot] = []
var _enemies: Node2D
var _projectiles: Node2D
var _running: bool = false
var _busy: bool = false


func configure(slots: Node2D, enemies: Node2D, projectiles: Node2D) -> void:
	_enemies = enemies
	_projectiles = projectiles
	for child: Node in slots.get_children():
		_slots.append(child as SummonSlot)
	mana = config.starting_mana
	successful_summons = 0
	_running = true
	_emit_state()


func current_cost() -> int:
	return config.cost_after(successful_summons)


func occupied_count() -> int:
	var occupied: int = 0
	for slot: SummonSlot in _slots:
		if not slot.is_empty():
			occupied += 1
	return occupied


func can_summon() -> bool:
	return _running and not _busy and mana >= current_cost() and occupied_count() < _slots.size()


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
	var instance: Node = unit_scene.instantiate()
	var archer: Archer = instance as Archer
	if archer == null or not destination.place_unit(archer):
		instance.free()
		_busy = false
		return false

	archer.configure(_enemies, _projectiles)
	mana -= current_cost()
	successful_summons += 1
	_busy = false
	_emit_state()
	return true


func stop() -> void:
	_running = false
	for slot: SummonSlot in _slots:
		if not slot.is_empty():
			slot.unit.stop()
	_emit_state()


func can_rearrange() -> bool:
	return _running and not _busy


func try_transfer(source: SummonSlot, destination: SummonSlot, expected_unit: Archer) -> bool:
	if not can_rearrange() or not is_instance_valid(expected_unit):
		return false
	if not _slots.has(source) or not _slots.has(destination) or source == destination:
		return false
	if source.unit != expected_unit or expected_unit.get_parent() != source.unit_host:
		return false
	var other: Archer = destination.unit if not destination.is_empty() else null
	if other != null and other.get_parent() != destination.unit_host:
		return false

	_busy = true
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


func _emit_state() -> void:
	state_changed.emit(mana, current_cost(), occupied_count(), _slots.size(), can_summon())
