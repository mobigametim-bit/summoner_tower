class_name WaveManager
extends Node

enum Phase { STOPPED, FIGHTING, INTERMISSION }

signal state_changed(wave: int, phase: Phase, seconds: int, alive: int, pending: int)
signal enemy_resolved(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome, mana: int)
signal wave_completed(wave: int)

@export var config: WaveConfig
@export var enemy_config: EncounterConfig
@export var enemy_scene: PackedScene

@onready var spawn_timer: Timer = $SpawnTimer
@onready var intermission_timer: Timer = $IntermissionTimer

var wave_number: int = 0
var phase: Phase = Phase.STOPPED

var _enemies: Node2D
var _spawn_point: Marker2D
var _contact_point: Marker2D
var _active: Array[ApproachingEnemy] = []
var _spawn_remaining: int = 0
var _countdown_seconds: int = -1


func configure(enemies: Node2D, spawn_point: Marker2D, contact_point: Marker2D) -> void:
	_enemies = enemies
	_spawn_point = spawn_point
	_contact_point = contact_point


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
	_spawn_remaining = config.enemy_count_for(wave_number)
	_emit_state()
	_spawn_next()


func _spawn_next() -> void:
	if phase != Phase.FIGHTING or _spawn_remaining <= 0:
		return
	# Учитываем экземпляр до add_child: callbacks дерева не могут создать лишний спавн.
	_spawn_remaining -= 1
	var enemy: ApproachingEnemy = enemy_scene.instantiate() as ApproachingEnemy
	_active.append(enemy)
	enemy.resolved.connect(_on_enemy_resolved)
	_enemies.add_child(enemy)
	if phase != Phase.FIGHTING:
		enemy.stop()
		enemy.queue_free()
		return
	enemy.configure(enemy_config, _spawn_point.global_position, _contact_point.global_position.y,
		config.enemy_health_for(wave_number, enemy_config.enemy_max_health))
	if phase != Phase.FIGHTING:
		return
	if _spawn_remaining > 0:
		spawn_timer.start(config.spawn_interval)
	_emit_state()
	_try_finish_wave()


func _on_spawn_timeout() -> void:
	# Повторный старый timeout не должен обходить уже начавшийся интервал.
	if spawn_timer.is_stopped():
		_spawn_next()


func _on_enemy_resolved(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void:
	if phase != Phase.FIGHTING or not _active.has(enemy):
		return
	_active.erase(enemy)
	var mana: int = config.kill_mana if outcome == ApproachingEnemy.Outcome.KILLED else 0
	# Сначала закрываем событие; урон башне может остановить WaveManager из сигнала.
	enemy_resolved.emit(enemy, outcome, mana)
	if phase == Phase.FIGHTING:
		_emit_state()
		_try_finish_wave()


func _try_finish_wave() -> void:
	if phase != Phase.FIGHTING or _spawn_remaining > 0 or not _active.is_empty():
		return
	phase = Phase.INTERMISSION
	spawn_timer.stop()
	intermission_timer.start(config.intermission_duration)
	_countdown_seconds = ceili(config.intermission_duration)
	_emit_state()
	wave_completed.emit(wave_number)


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
	var remaining: Array[ApproachingEnemy] = _active.duplicate()
	_active.clear()
	for enemy: ApproachingEnemy in remaining:
		if is_instance_valid(enemy):
			enemy.stop()
			enemy.queue_free()
	_emit_state()


func _emit_state() -> void:
	state_changed.emit(wave_number, phase, maxi(_countdown_seconds, 0), _active.size(), _spawn_remaining)
