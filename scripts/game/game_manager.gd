extends Node2D

enum State { RUNNING, GAME_OVER, LEAVING, UPGRADE_CHOICE }

@export var config: EncounterConfig
@export_file("*.tscn") var menu_scene_path: String = "res://scenes/main_menu.tscn"

@onready var tower: TowerHealth = $World/Tower
@onready var contact_point: Marker2D = $World/Tower/ContactPoint
@onready var spawn_point: Marker2D = $World/SpawnPoint
@onready var enemies: Node2D = $World/Enemies
@onready var projectiles: Node2D = $World/Projectiles
@onready var summon_manager: SummonManager = $SummonManager
@onready var drag_controller: UnitDragController = $World/DragController
@onready var wave_manager: WaveManager = $WaveManager
@onready var hud: GameHud = $Interface/Hud
@onready var run_bonuses: RunBonuses = $RunBonuses
@onready var upgrade_choice: UpgradeChoice = $Interface/Hud/UpgradeChoice
@onready var run_statistics: RunStatistics = $RunStatistics

var state: State = State.RUNNING
var _offered_upgrades: Array[RunUpgrade] = []


func _ready() -> void:
	run_statistics.reset()
	run_bonuses.reset()
	summon_manager.configure($World/Slots, enemies, projectiles, run_bonuses)
	drag_controller.configure(summon_manager, $World/Slots, $World/Tower/ReturnZone)
	tower.initialize(run_bonuses.tower_health_for(config.tower_max_health))
	wave_manager.configure(enemies, spawn_point, contact_point)
	wave_manager.start()


func _on_enemy_resolved(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome, mana: int) -> void:
	if state != State.RUNNING:
		return
	run_statistics.record_enemy(enemy, outcome)

	if outcome == ApproachingEnemy.Outcome.REACHED_TOWER:
		tower.take_damage(enemy.tower_damage)
	else:
		summon_manager.add_mana(run_bonuses.kill_mana_for(mana))


func _on_tower_health_changed(current: int, maximum: int) -> void:
	hud.update_health(current, maximum)


func _on_summon_requested() -> void:
	if state == State.RUNNING:
		summon_manager.try_summon()


func _on_wave_upgrade_requested(_wave: int) -> void:
	if state != State.RUNNING:
		return
	state = State.UPGRADE_CHOICE
	drag_controller.cancel_drag()
	summon_manager.set_interaction_enabled(false)
	_offered_upgrades = run_bonuses.roll_choices()
	get_tree().paused = true
	upgrade_choice.show_choices(_offered_upgrades, run_bonuses)


func _on_upgrade_chosen(index: int) -> void:
	if state != State.UPGRADE_CHOICE or index < 0 or index >= _offered_upgrades.size():
		return
	var upgrade: RunUpgrade = _offered_upgrades[index]
	# Закрываем выбор до сигналов лечения и изменения цены: повторный клик не выдаст бонус.
	_offered_upgrades.clear()
	state = State.RUNNING
	upgrade_choice.close_choice()
	run_bonuses.apply(upgrade)
	tower.increase_max_health(run_bonuses.tower_health_for(config.tower_max_health))
	wave_manager.finish_upgrade_choice()
	summon_manager.set_interaction_enabled(true)
	get_tree().paused = false


func _on_tower_destroyed() -> void:
	if state != State.RUNNING and state != State.UPGRADE_CHOICE:
		return

	state = State.GAME_OVER
	run_statistics.finish()
	_stop_encounter()
	hud.show_game_over(run_statistics)


func _stop_encounter() -> void:
	get_tree().paused = false
	_offered_upgrades.clear()
	upgrade_choice.close_choice()
	wave_manager.stop()
	get_tree().call_group(&"enemy_visual_tails", &"queue_free")
	drag_controller.stop()
	summon_manager.stop()
	for projectile: Node in projectiles.get_children():
		projectile.queue_free()


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


func _exit_tree() -> void:
	get_tree().paused = false
