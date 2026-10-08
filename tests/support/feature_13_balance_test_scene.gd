extends Node

@onready var game: Node2D = $Game
var seed_value: int = 1301
var speed: float = 3.0
var strategy: String = "merge"
var elapsed: float = 0.0
var decisions_elapsed: float = 0.0
var publish_elapsed: float = 0.0
var spent: int = 0
var earned: int = 0
var refunded: int = 0
var kills: int = 0
var escapes: int = 0
var completed: Array[Dictionary] = []
var plans: Array[Dictionary] = []
var spawns: Array[Dictionary] = []
var checks: Dictionary = {}
var done: bool = false
var transitions: Array[Dictionary] = []
var _previous_mana: int = 100


func _enter_tree() -> void:
	if OS.has_feature("web"):
		seed_value = int(JavaScriptBridge.eval("Number(new URLSearchParams(location.search).get('seed') || 1301)"))
		speed = clampf(float(JavaScriptBridge.eval("Number(new URLSearchParams(location.search).get('speed') || 3)")), 1.0, 3.0)
		strategy = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('strategy') || 'merge'"))
	get_node("/root/SessionProgress").use_test_save()
	$Game.battlefield_seed = seed_value
	Engine.time_scale = speed


func _ready() -> void:
	checks = load("res://tests/support/feature_13_balance_checks.gd").new().run()
	game.summon_manager.set_random_seed(seed_value)
	game.wave_manager.set_random_seed(seed_value + 1000)
	game.run_bonuses.set_random_seed(seed_value + 2000)
	game.wave_manager.wave_completed.connect(_on_wave_completed)
	game.wave_manager.enemy_resolved.connect(_on_enemy_resolved)
	game.enemies.child_entered_tree.connect(_on_enemy_entered)
	for enemy: Node in game.enemies.get_children():
		_on_enemy_entered(enemy)
	game.summon_manager.unit_refunded.connect(func(amount: int) -> void: refunded += amount)
	_previous_mana = game.summon_manager.mana
	game.summon_manager.state_changed.connect(_on_summon_changed)


func _process(delta: float) -> void:
	if OS.has_feature("web"):
		var command: String = str(JavaScriptBridge.eval("window.feature13Command || ''"))
		if command == "hold":
			strategy = "manual"
			Engine.time_scale = 1.0
		elif command == "defeat" and game.state == 0:
			game.tower.take_damage(game.tower.max_health)
		if not command.is_empty():
			JavaScriptBridge.eval("window.feature13Command = null")
	if not done:
		elapsed += delta
		if game.state == 0:
			decisions_elapsed += delta
			if decisions_elapsed >= 0.15:
				decisions_elapsed = 0.0
				_advance_army()
			if plans.is_empty() or plans.back().wave != game.wave_manager.wave_number:
				plans.append(game.wave_manager.power_summary.duplicate(true))
		elif game.state == 3 and strategy not in ["manual", "review"]:
			# Deterministic choice; the real game still presents three cards to the player.
			var choice: int = 0
			for index: int in game._offered_upgrades.size():
				if game._offered_upgrades[index].kind == RunUpgrade.Kind.POWER:
					choice = index
			_choose_upgrade(choice)
		elif game.state == 1:
			done = true
	publish_elapsed += delta
	if publish_elapsed >= 0.25 and OS.has_feature("web"):
		publish_elapsed = 0.0
		JavaScriptBridge.eval("window.feature13State=" + JSON.stringify(snapshot()))


func _advance_army() -> void:
	if strategy == "none" or strategy == "manual":
		return
	var slots: Array[SummonSlot] = game.summon_manager._slots
	if strategy in ["merge", "review"]:
		for destination: SummonSlot in slots:
			if destination.is_empty():
				continue
			for index: int in range(slots.size() - 1, -1, -1):
				var source: SummonSlot = slots[index]
				if not source.is_empty() and source.unit.can_merge_with(destination.unit):
					game.summon_manager.try_transfer(source, destination, source.unit)
					return
	if game.summon_manager.can_summon():
		game.summon_manager.try_summon()


func _on_summon_changed(mana: int, _cost: int, _occupied: int, _capacity: int, _available: bool) -> void:
	spent += maxi(_previous_mana - mana, 0)
	_previous_mana = mana


func _choose_upgrade(choice: int) -> void:
	var expected: int = 0
	for slot: SummonSlot in game.summon_manager._slots:
		if not slot.is_empty():
			expected += game.summon_manager.refund_amount(slot.unit)
	var mana_before: int = game.summon_manager.mana
	var previous_map: int = game.map_changes
	var previous_wave: int = game.wave_manager.wave_number
	var previous_hp: int = game.tower.current_health
	var previous_max: int = game.tower.max_health
	game._on_upgrade_chosen(choice)
	var mana_after: int = game.summon_manager.mana
	var correct: bool = game.map_changes == previous_map + 1 and game.summon_manager.occupied_count() == 0 and mana_after == mana_before + expected
	correct = correct and game.wave_manager.wave_number == previous_wave and game.wave_manager.phase == WaveManager.Phase.INTERMISSION
	correct = correct and game.summon_manager.current_cost() == game.run_bonuses.summon_cost_for(game.summon_manager.config.initial_cost)
	correct = correct and game.tower.current_health == previous_hp + game.tower.max_health - previous_max
	correct = correct and game.drag_controller._slots == game.summon_manager._slots
	# A second press must not sell, regenerate or award the same upgrade again.
	game._on_upgrade_chosen(choice)
	correct = correct and game.map_changes == previous_map + 1 and game.summon_manager.mana == mana_after
	transitions.append({"wave": previous_wave, "refund": expected, "ok": correct,
		"seed": game.battlefield.layout.seed_value, "slots": game.summon_manager._slots.size(), "portals": game.battlefield.routes.size(), "hp": game.tower.current_health})


func _on_enemy_entered(enemy: Node) -> void:
	var creep: ApproachingEnemy = enemy as ApproachingEnemy
	if creep != null:
		spawns.append({"wave": game.wave_manager.wave_number, "seconds": elapsed,
			"boss": creep.stats.is_boss, "type": creep.stats.enemy_type, "speed": creep.stats.move_speed})


func _on_wave_completed(wave: int) -> void:
	completed.append({"wave": wave, "seconds": elapsed, "hp": game.tower.current_health,
		"mana": game.summon_manager.mana, "power": game._player_power(),
		"cost": game.summon_manager.current_cost(), "occupied": game.summon_manager.occupied_count()})


func _on_enemy_resolved(_enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome, mana: int) -> void:
	if outcome == ApproachingEnemy.Outcome.KILLED:
		kills += 1
		earned += game.run_bonuses.kill_mana_for(mana)
	else:
		escapes += 1


func snapshot() -> Dictionary:
	return {"seed": seed_value, "strategy": strategy, "done": done, "map_changes": game.map_changes, "transitions": transitions,
		"wave": game.wave_manager.wave_number, "phase": game.wave_manager.phase, "state": game.state,
		"seconds": elapsed, "hp": game.tower.current_health, "mana": game.summon_manager.mana,
		"power": game._player_power(), "cost": game.summon_manager.current_cost(),
		"portals": game.battlefield.routes.size(), "slots": game.summon_manager._slots.size(),
		"bosses": game.run_statistics.killed_bosses,
		"kills": kills, "escapes": escapes, "spent": spent, "earned": earned, "refunded": refunded,
		"economy_ok": game.summon_manager.mana == 100 + earned + refunded - spent,
		"completed": completed, "plans": plans, "checks": checks, "spawns": spawns,
		"buttons": _button_bounds(),
		"army": _army_snapshot(),
		"fps": Engine.get_frames_per_second(), "nodes": get_tree().get_node_count()}


func _button_bounds() -> Dictionary:
	var result: Dictionary = {}
	for button: Button in game.find_children("*", "Button", true, false):
		var rect: Rect2 = button.get_global_rect()
		result[button.name] = {"x": rect.get_center().x, "y": rect.get_center().y, "visible": button.is_visible_in_tree()}
	return result


func _army_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: SummonSlot in game.summon_manager._slots:
		result.append({"index": slot.slot_index, "occupied": not slot.is_empty(),
			"x": slot.global_position.x, "y": slot.global_position.y,
			"level": 0 if slot.is_empty() else slot.unit.stats.level})
	return result


func _exit_tree() -> void:
	Engine.time_scale = 1.0
