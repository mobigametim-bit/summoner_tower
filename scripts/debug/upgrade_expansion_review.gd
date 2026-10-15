extends "res://scripts/game/game_manager.gd"

var _snapshot_callback: JavaScriptObject
var _pulse_review: bool = false


func _ready() -> void:
	SessionProgress.use_test_save("user://upgrade_expansion_review.json")
	if SessionProgress.save_manager.load_status == "missing":
		SessionProgress.add_crystals(5000)
	var requested: int = 6
	var requested_tier: int = 2
	if OS.has_feature("web"):
		requested = clampi(int(JavaScriptBridge.eval("Number(new URL(location.href).searchParams.get('card') ?? 6)", true)), 0, 19)
		requested_tier = clampi(int(JavaScriptBridge.eval("Number(new URL(location.href).searchParams.get('tier')) || 2", true)), 1, 5)
		_pulse_review = bool(JavaScriptBridge.eval("new URL(location.href).searchParams.get('mode') === 'pulse'", true))
		if bool(JavaScriptBridge.eval("new URL(location.href).searchParams.get('mode') === 'meta'", true)):
			get_tree().change_scene_to_file.call_deferred("res://scenes/debug/MetaUpgradesReview.tscn")
			return
	super._ready()
	wave_manager.stop()
	if _pulse_review:
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getUpgradeExpansionReview = _snapshot_callback
		return
	wave_manager.wave_number = 5
	wave_manager.phase = WaveManager.Phase.UPGRADE_CHOICE
	tower.take_damage(50)
	run_bonuses._meta_levels[MetaUpgradeConfig.Kind.EXPANDED_CHOICE] = 1
	run_bonuses.rerolls_remaining = 1
	_on_wave_upgrade_requested(5)
	var chosen: RunUpgrade = run_bonuses.pool.get_upgrade(requested as RunUpgrade.Kind)
	if chosen != null:
		for index: int in range(_offered_upgrades.size() - 1, -1, -1):
			if _offered_upgrades[index].kind == chosen.kind:
				_offered_upgrades.remove_at(index)
		_offered_upgrades.push_front(chosen.variant_for(requested_tier))
		_offered_upgrades.resize(4)
		upgrade_choice.show_choices(_offered_upgrades, run_bonuses, run_bonuses.rerolls_remaining)
	if OS.has_feature("web"):
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getUpgradeExpansionReview = _snapshot_callback


func _publish_snapshot(_arguments: Array) -> void:
	var cards: Array = []
	for index: int in _offered_upgrades.size():
		var button: Button = upgrade_choice.cards[index]
		var card_point: Vector2 = button.get_global_rect().get_center()
		var upgrade: RunUpgrade = _offered_upgrades[index]
		var frame: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
		cards.append({"kind":upgrade.kind,"tier":upgrade.tier,"strength":upgrade.strength,"color":frame.border_color.to_html(false),"description":button.get_node("Margin/Row/Content/Description").text,"position":[card_point.x,card_point.y],"height":button.size.y,"needed_height":button.get_node("Margin").get_combined_minimum_size().y})
	var units: Array = []
	for slot: SummonSlot in summon_manager._slots:
		if not slot.is_empty():
			units.append({"type": String(slot.unit.stats.unit_type), "level":slot.unit.stats.level,"paid":slot.unit.paid_mana})
	var point: Vector2 = upgrade_choice.reroll_button.get_global_rect().get_center()
	var rewarded_point: Vector2 = upgrade_choice.rewarded_reroll_button.get_global_rect().get_center()
	var cancel_point: Vector2 = hud.ad_overlay.get_node("Center/Panel/Stack/Cancel").get_global_rect().get_center()
	var snapshot: Dictionary = {"cards":cards,"state":state,"health":tower.current_health,"maximum":tower.max_health,"mana":summon_manager.mana,"maps":map_changes,"units":units,"rerolls":run_bonuses.rerolls_remaining,"reroll_position":[point.x,point.y]}
	snapshot["rewarded_position"] = [rewarded_point.x,rewarded_point.y]
	snapshot["cancel_position"] = [cancel_point.x,cancel_point.y]
	snapshot["rewarded_disabled"] = upgrade_choice.rewarded_reroll_button.disabled
	snapshot["watching"] = ad_service.busy
	snapshot["paused"] = get_tree().paused
	snapshot["cards_disabled"] = upgrade_choice.cards[0].disabled
	snapshot["rewarded_tooltip"] = tr(upgrade_choice.rewarded_reroll_button.tooltip_text)
	snapshot["tower_scale"] = tower.summon_pulse.scale.x
	snapshot["tower_position"] = [tower.global_position.x, tower.global_position.y]
	snapshot["cost_position"] = [tower.cost_label.global_position.x, tower.cost_label.global_position.y]
	snapshot["summon_available"] = summon_manager.can_summon()
	JavaScriptBridge.get_interface("window").upgradeExpansionSnapshotJSON = JSON.stringify(snapshot)


func _exit_tree() -> void:
	if _snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getUpgradeExpansionReview = null
	super._exit_tree()
