extends Node

var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.15 or not OS.has_feature("web"):
		return
	_elapsed = 0.0
	var current: Node = get_tree().current_scene
	if current == null:
		return
	var state: Dictionary = {"scene":current.name,"crystals":SessionProgress.crystals,
		"levels":SessionProgress.upgrade_levels,"buttons":{}}
	for path: String in ["Center/VBox/Actions/PlayButton", "Center/VBox/Actions/UpgradesButton",
		"Center/Stack/Header/BackButton", "Center/Stack/Cards/TowerHealth",
		"Center/Stack/Cards/UnitDamage", "Center/Stack/Cards/ManaIncome", "Center/Stack/Cards/StartingMana"]:
		var button: Button = current.get_node_or_null(path) as Button
		if button != null:
			var center: Vector2 = button.get_global_rect().get_center()
			state.buttons[String(button.name)] = {"x":center.x,"y":center.y,"disabled":button.disabled}
	var game_root: Node = current.get_node_or_null("Game")
	if current.has_node("RunBonuses"):
		game_root = current
	if game_root != null:
		state.game_state = game_root.state
		state.health = game_root.tower.current_health
		state.mana = game_root.summon_manager.mana
		state.cost = game_root.summon_manager.current_cost()
		state.reward = game_root.run_statistics.earned_crystals
		state.damage = game_root.run_bonuses.damage_amount_for(load("res://resources/balance/archer_lv1.tres"))
		state.units = game_root.summon_manager.occupied_count()
		state.merges = game_root.run_statistics.merges
		for button: Button in [game_root.hud.restart_button,game_root.hud.menu_button]:
			var center: Vector2 = button.get_global_rect().get_center()
			state.buttons[String(button.name)] = {"x":center.x,"y":center.y,"disabled":button.disabled}
	# Мост только читает состояние отдельной тестовой сборки, не принимает команды.
	JavaScriptBridge.eval("window.feature11State=" + JSON.stringify(state))
