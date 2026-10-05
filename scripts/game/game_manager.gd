extends Node2D

enum State { RUNNING, GAME_OVER, LEAVING }

@export var config: EncounterConfig
@export var enemy_scene: PackedScene
@export_file("*.tscn") var menu_scene_path: String = "res://scenes/main_menu.tscn"

@onready var tower: TowerHealth = $World/Tower
@onready var contact_point: Marker2D = $World/Tower/ContactPoint
@onready var spawn_point: Marker2D = $World/SpawnPoint
@onready var enemies: Node2D = $World/Enemies
@onready var projectiles: Node2D = $World/Projectiles
@onready var archer: Archer = $World/Archer
@onready var spawn_timer: Timer = $SpawnTimer
@onready var hud: GameHud = $Interface/Hud

var state: State = State.RUNNING
var _active_enemy: ApproachingEnemy


func _ready() -> void:
	archer.configure(enemies, projectiles)
	tower.initialize(config.tower_max_health)
	_spawn_enemy()


func _spawn_enemy() -> void:
	if state != State.RUNNING or is_instance_valid(_active_enemy):
		return

	_active_enemy = enemy_scene.instantiate() as ApproachingEnemy
	enemies.add_child(_active_enemy)
	_active_enemy.resolved.connect(_on_enemy_resolved)
	_active_enemy.configure(config, spawn_point.global_position, contact_point.global_position.y)


func _on_enemy_resolved(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void:
	if state != State.RUNNING or enemy != _active_enemy:
		return

	# Сначала учитываем врага, поскольку сигнал урона может завершить забег.
	_active_enemy = null
	if outcome == ApproachingEnemy.Outcome.REACHED_TOWER:
		tower.take_damage(enemy.tower_damage)
	if state == State.RUNNING:
		spawn_timer.start(config.next_enemy_delay)


func _on_tower_health_changed(current: int, maximum: int) -> void:
	hud.update_health(current, maximum)


func _on_tower_destroyed() -> void:
	if state != State.RUNNING:
		return

	state = State.GAME_OVER
	_stop_encounter()
	hud.show_game_over()


func _stop_encounter() -> void:
	spawn_timer.stop()
	archer.stop()
	for projectile: Node in projectiles.get_children():
		projectile.queue_free()
	for child: Node in enemies.get_children():
		var enemy: ApproachingEnemy = child as ApproachingEnemy
		enemy.stop()
		enemy.queue_free()
	_active_enemy = null


func _on_restart_requested() -> void:
	if state != State.GAME_OVER:
		return

	state = State.LEAVING
	hud.set_actions_enabled(false)
	_stop_encounter()
	var error: Error = get_tree().reload_current_scene()
	_handle_scene_change_error(error)


func _on_menu_requested() -> void:
	if state != State.GAME_OVER:
		return

	state = State.LEAVING
	hud.set_actions_enabled(false)
	_stop_encounter()
	var error: Error = get_tree().change_scene_to_file(menu_scene_path)
	_handle_scene_change_error(error)


func _handle_scene_change_error(error: Error) -> void:
	if error == OK:
		return

	state = State.GAME_OVER
	hud.set_actions_enabled(true)
	push_error("Cannot change scene (error %s)" % error)
