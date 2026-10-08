extends Node2D

enum State { RUNNING, GAME_OVER, LEAVING, UPGRADE_CHOICE, SETTINGS }

@export var config: EncounterConfig
@export var procedural_battlefield_enabled: bool = true
@export var battlefield_seed: int = -1
@export_range(0, 15, 1) var battlefield_slot_count: int = 0
@export_range(0, 8, 1) var battlefield_columns: int = 0
@export_range(0, 3, 1) var battlefield_portal_count: int = 0
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
@onready var battlefield: Battlefield = $World/Battlefield

var state: State = State.RUNNING
var map_changes: int = 0
var _offered_upgrades: Array[RunUpgrade] = []


func _ready() -> void:
	run_statistics.reset()
	run_bonuses.reset()
	if procedural_battlefield_enabled:
		_build_battlefield()
	else:
		battlefield.hide()
	summon_manager.configure($World/Slots, enemies, projectiles, run_bonuses)
	drag_controller.configure(summon_manager, $World/Slots, $World/Tower/ReturnZone)
	tower.initialize(run_bonuses.tower_health_for(config.tower_max_health))
	wave_manager.configure(enemies, spawn_point, contact_point, battlefield.route if procedural_battlefield_enabled else null, battlefield.routes, _player_power)
	wave_manager.start()


func _build_battlefield() -> void:
	var seed_value: int = battlefield_seed + 1000 * map_changes if battlefield_seed >= 0 else -1
	battlefield.build($World/Slots, spawn_point, tower, battlefield_columns, seed_value, battlefield_slot_count, battlefield_portal_count)
	hud.set_field_bottom(battlefield.layout.origin.y + battlefield.layout.grid_size.y * battlefield.layout.cell_size)


func _renew_battlefield() -> void:
	drag_controller.cancel_drag()
	summon_manager.sell_army_for_map_change()
	for projectile: Node in projectiles.get_children():
		projectile.set_physics_process(false)
		projectile.queue_free()
	get_tree().call_group(&"enemy_visual_tails", &"queue_free")
	if procedural_battlefield_enabled:
		map_changes += 1
		_build_battlefield()
	summon_manager.rebind_slots($World/Slots, true)
	drag_controller.configure(summon_manager, $World/Slots, $World/Tower/ReturnZone)
	wave_manager.configure(enemies, spawn_point, contact_point, battlefield.route if procedural_battlefield_enabled else null, battlefield.routes, _player_power)


func _player_power() -> float:
	var balance: PowerBalanceConfig = wave_manager.config.power_balance
	if balance == null:
		return 0.0
	var total: float = 0.0
	for slot: SummonSlot in summon_manager._slots:
		if not slot.is_empty():
			var unit: CombatUnit = slot.unit
			total += balance.unit_power(unit.stats, run_bonuses.damage_amount_for(unit.stats), unit.effective_attack_interval())
	return balance.player_power(total, tower.max_health)


func _on_enemy_spawned(portal_index: int) -> void:
	if procedural_battlefield_enabled:
		battlefield.play_portal_exit(portal_index)


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
	hud.set_settings_available(false)
	upgrade_choice.show_choices(_offered_upgrades, run_bonuses)


func _on_upgrade_chosen(index: int) -> void:
	if state != State.UPGRADE_CHOICE or index < 0 or index >= _offered_upgrades.size():
		return
	var upgrade: RunUpgrade = _offered_upgrades[index]
	# Закрываем выбор до сигналов лечения и изменения цены: повторный клик не выдаст бонус.
	_offered_upgrades.clear()
	upgrade_choice.close_choice()
	run_bonuses.apply(upgrade)
	tower.increase_max_health(run_bonuses.tower_health_for(config.tower_max_health))
	# Бой остаётся на паузе до очистки армии и перепривязки новой карты.
	_renew_battlefield()
	state = State.RUNNING
	wave_manager.finish_upgrade_choice()
	summon_manager.set_interaction_enabled(true)
	get_tree().paused = false
	hud.set_settings_available(true)


func _on_settings_requested() -> void:
	if state != State.RUNNING:
		return
	state = State.SETTINGS
	drag_controller.cancel_drag()
	summon_manager.set_interaction_enabled(false)
	hud.show_settings()
	get_tree().paused = true


func _on_resume_requested() -> void:
	if state != State.SETTINGS:
		return
	state = State.RUNNING
	hud.close_settings()
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
	hud.close_settings()
	hud.set_settings_available(false)
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
	if state != State.GAME_OVER and state != State.SETTINGS:
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
