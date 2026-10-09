extends "res://scripts/game/game_manager.gd"

var _snapshot_callback: JavaScriptObject
var _reload_only: bool = false


func _ready() -> void:
	if OS.has_feature("web"):
		_reload_only = bool(JavaScriptBridge.eval("new URL(location.href).searchParams.get('reload') === '1'", true))
		SessionProgress.use_test_save("user://rewarded_review.json")
		if not _reload_only and not get_tree().has_meta("rewarded_review_started"):
			get_tree().set_meta("rewarded_review_started", true)
			SessionProgress.crystals = 0
			SessionProgress.upgrade_levels.assign([0, 0, 0, 0])
			SessionProgress._save_progress()
	super._ready()
	if OS.has_feature("web"):
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getRewardedReview = _snapshot_callback
	if _reload_only:
		wave_manager.stop()
		return
	wave_manager.stop()
	wave_manager.wave_number = 4
	wave_manager.phase = WaveManager.Phase.FIGHTING
	wave_manager._begin_wave()
	run_statistics.completed_waves = 3
	var archer: PackedScene = load("res://scenes/archer.tscn")
	for index: int in 2:
		var unit: CombatUnit = archer.instantiate() as CombatUnit
		summon_manager._slots[index].place_unit(unit)
		unit.configure(enemies, projectiles, run_bonuses)
		unit.paid_mana = 20
	get_node("ReviewTimer").start(1.5)


func _on_review_timer_timeout() -> void:
	if state == State.RUNNING:
		tower.take_damage(tower.current_health)


func _on_ad_completed(placement: AdService.Placement, outcome: AdService.Outcome) -> void:
	super._on_ad_completed(placement, outcome)
	if state == State.RUNNING:
		get_node("ReviewTimer").start(8.0)


func _center(control: Control) -> Array:
	var center: Vector2 = control.get_global_rect().get_center()
	return [center.x, center.y]


func _bounds(control: Control) -> Array:
	var rect: Rect2 = control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _publish_snapshot(_arguments: Array) -> void:
	var controls: Dictionary = {
		"accept": _center(hud.revive_overlay.get_node("Center/Panel/Stack/Actions/Accept")),
		"decline": _center(hud.revive_overlay.get_node("Center/Panel/Stack/Actions/Decline")),
		"cancel": _center(hud.ad_overlay.get_node("Center/Panel/Stack/Cancel")),
		"double": _center(hud.double_reward_button),
		"restart": _center(hud.restart_button), "menu": _center(hud.menu_button),
		"settings": _center(hud.settings_button), "resume": _center(hud.resume_button)
	}
	var snapshot: Dictionary = {
		"state": state, "paused": get_tree().paused, "wave": wave_manager.wave_number,
		"phase": wave_manager.phase, "health": tower.current_health, "max_health": tower.max_health,
		"revive_used": revive_used, "finished": run_statistics.finished,
		"wallet": SessionProgress.crystals, "earned": run_statistics.earned_crystals,
		"doubled": run_statistics.reward_doubled, "double_disabled": hud.double_reward_button.disabled,
		"offer": hud.revive_overlay.visible, "ad": hud.ad_overlay.visible,
		"ad_busy": ad_service.busy, "timer": ad_service.watch_timer.time_left,
		"mana": summon_manager.mana, "cost": summon_manager.current_cost(),
		"army": summon_manager._slots.map(func(slot: SummonSlot) -> int: return 0 if slot.is_empty() else slot.unit.get_instance_id()),
		"enemy_positions": wave_manager._active.map(func(enemy: ApproachingEnemy) -> Array: return [enemy.global_position.x, enemy.global_position.y]),
		"pending": wave_manager._spawn_remaining, "spawn_time": wave_manager.spawn_timer.time_left,
		"map_changes": map_changes, "controls": controls,
		"bounds": {"offer": _bounds(hud.revive_overlay.get_node("Center/Panel")),
			"ad": _bounds(hud.ad_overlay.get_node("Center/Panel")),
			"result": _bounds(hud.game_over_overlay.get_node("Center/Panel"))},
		"reward_text": hud.game_over_overlay.get_node("Center/Panel/Stack/Reward/Amount").text,
		"tower": [tower.global_position.x, tower.global_position.y], "summons": summon_manager.successful_summons
	}
	JavaScriptBridge.eval("window.rewardedReview = %s;" % JSON.stringify(snapshot), true)


func _exit_tree() -> void:
	if _snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getRewardedReview = null
		JavaScriptBridge.get_interface("window").rewardedReview = null
	super._exit_tree()
