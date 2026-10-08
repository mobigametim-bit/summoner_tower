class_name WaveManager
extends Node

enum Phase { STOPPED, FIGHTING, INTERMISSION, UPGRADE_CHOICE }

signal state_changed(wave: int, phase: Phase, seconds: int, alive: int, pending: int)
signal enemy_resolved(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome, mana: int)
signal wave_completed(wave: int)
signal upgrade_requested(wave: int)

@export var config: WaveConfig

@onready var spawn_timer: Timer = $SpawnTimer
@onready var intermission_timer: Timer = $IntermissionTimer

var wave_number: int = 0
var phase: Phase = Phase.STOPPED

var _enemies: Node2D
var _spawn_point: Marker2D
var _contact_point: Marker2D
var _route: Path2D
var _routes: Array[Path2D] = []
var _active: Array[ApproachingEnemy] = []
var _spawn_remaining: int = 0
var _countdown_seconds: int = -1
var _sequence: Array[PackedScene] = []
var _boss_killed: bool = false
var _health_sequence: Array[int] = []
var _power_source: Callable
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var power_summary: Dictionary = {}
var _batch_remaining: int = 0
var _batch_spawned: int = 0


func _ready() -> void:
	_rng.randomize()


func set_random_seed(value: int) -> void:
	_rng.seed = value


func configure(enemies: Node2D, spawn_point: Marker2D, contact_point: Marker2D, route: Path2D = null, routes: Array[Path2D] = [], power_source: Callable = Callable()) -> void:
	_enemies = enemies
	_spawn_point = spawn_point
	_contact_point = contact_point
	_power_source = power_source
	_route = route
	_routes.assign(routes)
	if _routes.is_empty() and route != null:
		_routes.append(route)


func start() -> bool:
	if phase != Phase.STOPPED or wave_number != 0:
		return false
	wave_number = 1
	phase = Phase.FIGHTING
	_begin_wave()
	return true


func active_count() -> int:
	return _active.size()


func _begin_wave() -> void:
	_boss_killed = false
	_batch_remaining = 0
	_batch_spawned = 0
	_health_sequence.clear()
	if config.power_balance != null:
		var power: float = float(_power_source.call()) if _power_source.is_valid() else 0.0
		var plan: Dictionary = WavePowerPlanner.new(config).make_plan(wave_number, power, _rng)
		_sequence.assign(plan.sequence)
		_health_sequence.assign(plan.healths)
		power_summary = plan.summary
	else:
		_sequence = config.sequence_for(wave_number)
		power_summary.clear()
	_spawn_remaining = _sequence.size()
	_emit_state()
	# Дополнительный босс не занимает место в первой пачке обычных врагов.
	if config.is_boss_wave(wave_number):
		_spawn_enemy()
	_start_spawn_batch()


func _start_spawn_batch() -> void:
	if phase != Phase.FIGHTING or _spawn_remaining <= 0:
		return
	_batch_remaining = mini(_rng.randi_range(config.spawn_batch_minimum, config.spawn_batch_maximum), _spawn_remaining)
	_batch_spawned = 0
	_spawn_next()


func _spawn_next() -> void:
	if phase != Phase.FIGHTING or _spawn_remaining <= 0 or _batch_remaining <= 0:
		return
	_batch_remaining -= 1
	_batch_spawned += 1
	_spawn_enemy()
	if phase != Phase.FIGHTING or _spawn_remaining <= 0:
		return
	var delay: float = config.spawn_stagger if _batch_remaining > 0 else config.spawn_batch_pause_after(_batch_spawned)
	spawn_timer.start(delay)


func _spawn_enemy() -> void:
	if phase != Phase.FIGHTING or _spawn_remaining <= 0:
		return
	# Учитываем экземпляр до add_child: callbacks дерева не могут создать лишний спавн.
	var next_scene: PackedScene = _sequence[_sequence.size() - _spawn_remaining]
	_spawn_remaining -= 1
	var enemy: ApproachingEnemy = next_scene.instantiate() as ApproachingEnemy
	_active.append(enemy)
	enemy.resolved.connect(_on_enemy_resolved)
	_enemies.add_child(enemy)
	if phase != Phase.FIGHTING:
		enemy.stop()
		enemy.queue_free()
		return
	var health: int = config.boss_health_for(wave_number, enemy.stats.base_health) if enemy.stats.is_boss else config.enemy_health_for(wave_number, enemy.stats.base_health)
	var sequence_index: int = _sequence.size() - _spawn_remaining - 1
	if not _health_sequence.is_empty():
		health = _health_sequence[sequence_index]
	var portal_index: int = (sequence_index + wave_number - 1) % _routes.size() if not _routes.is_empty() else 0
	var selected_route: Path2D = _routes[portal_index] if not _routes.is_empty() else null
	var position: Vector2 = _spawn_point.global_position
	if selected_route != null:
		position = selected_route.to_global(selected_route.curve.get_point_position(0))
	enemy.set_meta("portal_index", portal_index)
	enemy.set_meta("spawn_frame", Engine.get_process_frames())
	enemy.configure(position, _contact_point.global_position.y, health)
	if selected_route != null:
		enemy.follow_route(selected_route.curve, selected_route.global_transform, float(selected_route.get_meta("cell_size", 140.0)))
	if phase != Phase.FIGHTING:
		return
	_emit_state()
	_try_finish_wave()


func _on_spawn_timeout() -> void:
	# Повторный старый timeout не должен обходить уже начавшийся интервал.
	if spawn_timer.is_stopped():
		if _batch_remaining > 0:
			_spawn_next()
		else:
			_start_spawn_batch()


func _on_enemy_resolved(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void:
	if phase != Phase.FIGHTING or not _active.has(enemy):
		return
	_active.erase(enemy)
	if enemy.stats.is_boss and outcome == ApproachingEnemy.Outcome.KILLED:
		_boss_killed = true
	var mana: int = enemy.stats.kill_mana if outcome == ApproachingEnemy.Outcome.KILLED else 0
	# Сначала закрываем событие; урон башне может остановить WaveManager из сигнала.
	enemy_resolved.emit(enemy, outcome, mana)
	if phase == Phase.FIGHTING:
		_emit_state()
		_try_finish_wave()


func _try_finish_wave() -> void:
	if phase != Phase.FIGHTING or _spawn_remaining > 0 or not _active.is_empty():
		return
	spawn_timer.stop()
	if config.is_boss_wave(wave_number) and _boss_killed:
		phase = Phase.UPGRADE_CHOICE
		_emit_state()
		wave_completed.emit(wave_number)
		if phase == Phase.UPGRADE_CHOICE:
			upgrade_requested.emit(wave_number)
		return
	_begin_intermission()
	wave_completed.emit(wave_number)


func finish_upgrade_choice() -> bool:
	if phase != Phase.UPGRADE_CHOICE:
		return false
	_begin_intermission()
	return true


func _begin_intermission() -> void:
	phase = Phase.INTERMISSION
	intermission_timer.start(config.intermission_duration)
	_countdown_seconds = ceili(config.intermission_duration)
	_emit_state()


func _process(_delta: float) -> void:
	if phase != Phase.INTERMISSION:
		return
	var seconds: int = ceili(intermission_timer.time_left)
	if seconds != _countdown_seconds:
		_countdown_seconds = seconds
		_emit_state()


func _on_intermission_timeout() -> void:
	if phase != Phase.INTERMISSION or not intermission_timer.is_stopped():
		return
	wave_number += 1
	phase = Phase.FIGHTING
	_begin_wave()


func stop() -> void:
	if phase == Phase.STOPPED:
		return
	phase = Phase.STOPPED
	spawn_timer.stop()
	intermission_timer.stop()
	_spawn_remaining = 0
	_batch_remaining = 0
	_batch_spawned = 0
	_sequence.clear()
	_health_sequence.clear()
	var remaining: Array[ApproachingEnemy] = _active.duplicate()
	_active.clear()
	for enemy: ApproachingEnemy in remaining:
		if is_instance_valid(enemy):
			enemy.stop()
			enemy.queue_free()
	_emit_state()


func _emit_state() -> void:
	state_changed.emit(wave_number, phase, maxi(_countdown_seconds, 0), _active.size(), _spawn_remaining)
