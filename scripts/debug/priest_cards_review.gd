extends "res://scripts/game/game_manager.gd"

const CARD_KINDS: Array[RunUpgrade.Kind] = [
	RunUpgrade.Kind.PRIEST_SUMMON, RunUpgrade.Kind.LIGHT_POWER,
	RunUpgrade.Kind.LONG_PRAYER, RunUpgrade.Kind.SACRED_RADIANCE
]
var review_tier: int = 2
var _web_callback: JavaScriptObject


func _ready() -> void:
	SessionProgress.use_test_save()
	SessionProgress.unlocked_biomes.assign(["forest", "graveyard"])
	SessionProgress.selected_biome_id = &"graveyard"
	AudioService.settings_store = AudioSettingsStore.new("")
	var run_mode: bool = false
	if OS.has_feature("web"):
		if str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('biome') || ''")) == "forest":
			SessionProgress.selected_biome_id = &"forest"
		run_mode = str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('mode') || ''")) == "run"
	super._ready()
	if OS.has_feature("web"):
		_web_callback = JavaScriptBridge.create_callback(_web_command)
		JavaScriptBridge.get_interface("window").priestCards = _web_callback
	if not run_mode:
		show_cards(review_tier)


func show_cards(tier: int) -> void:
	if state not in [State.RUNNING, State.UPGRADE_CHOICE]:
		return
	review_tier = clampi(tier, 1, 5)
	wave_manager.stop()
	wave_manager.wave_number = 5
	wave_manager.phase = WaveManager.Phase.UPGRADE_CHOICE
	_upgrade_wave = 5
	_rewarded_reroll_used_wave = -1
	state = State.UPGRADE_CHOICE
	drag_controller.cancel_drag()
	summon_manager.set_interaction_enabled(false)
	hud.set_settings_available(false)
	_offered_upgrades.clear()
	for kind: RunUpgrade.Kind in CARD_KINDS:
		_offered_upgrades.append(run_bonuses.pool.get_upgrade(kind).variant_for(review_tier))
	for index: int in 5:
		get_node("CardReview/Tier%d" % (index + 1)).set_pressed_no_signal(index + 1 == review_tier)
	get_tree().paused = true
	_show_upgrade_choices()


func snapshot() -> Dictionary:
	var offers: Array[Dictionary] = []
	for index: int in _offered_upgrades.size():
		var upgrade: RunUpgrade = _offered_upgrades[index]
		var button: Button = upgrade_choice.cards[index]
		var point: Vector2 = button.get_global_rect().get_center()
		offers.append({"kind":upgrade.kind, "tier":upgrade.tier, "title":tr(upgrade.title), "description":upgrade.description_text(), "x":point.x, "y":point.y})
	var units: Array[Dictionary] = []
	for slot: SummonSlot in summon_manager._slots:
		if not slot.is_empty():
			units.append({"type":str(slot.unit.stats.unit_type), "level":slot.unit.stats.level, "paid":slot.unit.paid_mana})
	var stats: UnitStats = load("res://resources/balance/priest_lv5.tres") as UnitStats
	var effective: UnitStats = run_bonuses.combat_stats_for(stats)
	return {"offers":offers, "tier":review_tier, "state":state, "wave":wave_manager.wave_number,
		"map_changes":map_changes, "units":units, "mana":summon_manager.mana,
		"pool_count":run_bonuses.pool.upgrades.size(), "weights":run_bonuses.pool.tier_weights,
		"biome":str(biome.biome_id), "test_save":SessionProgress._test_session,
		"priest_damage":run_bonuses.damage_amount_for(stats), "mark_duration":effective.light_mark_duration,
		"consecration_damage":run_bonuses.damage_amount_for(stats)*effective.ability_damage_ratio}


func _web_command(args: Array) -> void:
	var action: String = str(args[0]) if not args.is_empty() else "snapshot"
	var value: int = int(args[1]) if args.size() > 1 else 0
	match action:
		"tier": show_cards(value)
		"choose": _on_upgrade_chosen(value)
		"language":
			TranslationServer.set_locale("ru" if value == 0 else "en")
			if state == State.UPGRADE_CHOICE:
				_show_upgrade_choices()
		"roll":
			_offered_upgrades = run_bonuses.roll_choices(tower.current_health,tower.max_health)
			if state == State.UPGRADE_CHOICE:
				_show_upgrade_choices()
	JavaScriptBridge.get_interface("window").priestCardsJSON = JSON.stringify(snapshot())


func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").priestCards = null
	super._exit_tree()
