extends Node

@onready var game: Node2D = $Game
@onready var slots: Array[Node] = $Game/World/Slots.get_children()

var completed: Array[int] = []
var kills: int = 0
var escapes: int = 0
var earned: int = 0
var refunded: int = 0
var _bot_enabled: bool = false
var _bot_elapsed: float = 0.0
var _web_elapsed: float = 0.0


func _ready() -> void:
	game.wave_manager.wave_completed.connect(_on_wave_completed)
	game.wave_manager.enemy_resolved.connect(_on_enemy_resolved)
	game.summon_manager.unit_refunded.connect(func(amount: int) -> void: refunded += amount)


func run_checks() -> void:
	set_meta("feature6_checks", load("res://tests/support/feature_6_checks.gd").new().run(game))


func start_autoplay() -> void:
	assert(game.summon_manager.mana == 100 and game.summon_manager.successful_summons == 0)
	_bot_enabled = true


func _on_wave_completed(wave: int) -> void:
	assert(not completed.has(wave))
	completed.append(wave)


func _on_enemy_resolved(_enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome, mana: int) -> void:
	if outcome == ApproachingEnemy.Outcome.KILLED:
		kills += 1
	else:
		escapes += 1
	earned += mana


func _process(delta: float) -> void:
	if _bot_enabled and game.state == 0:
		_bot_elapsed += delta
		if _bot_elapsed >= 0.1:
			_bot_elapsed = 0.0
			_advance_army()
	if OS.has_feature("web"):
		_web_elapsed += delta
		if _web_elapsed >= 0.25:
			_web_elapsed = 0.0
			# Данные только для отдельной тестовой Web-сцены; игровых действий мост не принимает.
			JavaScriptBridge.eval("window.feature6State=" + JSON.stringify(snapshot()))


func _advance_army() -> void:
	for destination: SummonSlot in slots:
		if destination.is_empty():
			continue
		for index: int in range(slots.size() - 1, -1, -1):
			var source: SummonSlot = slots[index]
			if not source.is_empty() and source.unit.can_merge_with(destination.unit):
				assert(game.summon_manager.try_transfer(source, destination, source.unit))
				return
	if game.summon_manager.can_summon():
		assert(game.summon_manager.try_summon())


func economy_valid() -> bool:
	var spent: int = 0
	for index: int in game.summon_manager.successful_summons:
		spent += game.summon_manager.config.cost_after(index)
	return game.summon_manager.mana == game.summon_manager.config.starting_mana + earned + refunded - spent


func snapshot() -> Dictionary:
	var levels: Array[int] = []
	for slot: SummonSlot in slots:
		levels.append(0 if slot.is_empty() else slot.unit.stats.level)
	return {"wave": game.wave_manager.wave_number, "phase": game.wave_manager.phase,
		"completed": completed, "kills": kills, "escapes": escapes, "earned": earned, "refunded": refunded,
		"mana": game.summon_manager.mana, "cost": game.summon_manager.current_cost(),
		"summons": game.summon_manager.successful_summons, "levels": levels,
		"health": game.tower.current_health, "active": game.wave_manager.active_count(),
		"pending": game.wave_manager._spawn_remaining, "arrows": game.projectiles.get_child_count(),
		"nodes": game.get_tree().get_node_count(), "fps": Engine.get_frames_per_second(),
		"state": game.state, "economy_valid": economy_valid(),
		"preview": game.drag_controller.preview.visible, "hud": game.hud.wave_label.text}


func _exit_tree() -> void:
	Engine.time_scale = 1.0
