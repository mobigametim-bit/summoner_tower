extends "res://tests/support/feature_7_test_scene.gd"


func _enter_tree() -> void:
	if OS.has_feature("web"):
		$Game.battlefield_slot_count = int(JavaScriptBridge.eval("Number(new URLSearchParams(location.search).get('slots') || 0)"))
		$Game.battlefield_columns = int(JavaScriptBridge.eval("Number(new URLSearchParams(location.search).get('columns') || 0)"))
		$Game.battlefield_seed = int(JavaScriptBridge.eval("Number(new URLSearchParams(location.search).get('seed') || -1)"))
		Engine.time_scale = clampf(float(JavaScriptBridge.eval("Number(new URLSearchParams(location.search).get('speed') || 1)")), 1.0, 3.0)


func _ready() -> void:
	super._ready()
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('input')")):
		game.summon_manager.pool = load("res://tests/resources/archer_only_pool.tres")
		game.wave_manager.spawn_timer.stop()
		for enemy: ApproachingEnemy in game.enemies.get_children():
			enemy.set_physics_process(false)
			enemy.current_health = 10000
			enemy.max_health = 10000
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('autoplay')")):
		start_autoplay()


func _advance_army() -> void:
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


func run_battlefield_checks() -> void:
	set_meta("battlefield_checks", load("res://tests/support/feature_11_1_checks.gd").new().run(self))


func snapshot() -> Dictionary:
	var result: Dictionary = super.snapshot()
	if game.battlefield.layout == null:
		return result
	result.layout_seed = game.battlefield.layout.seed_value
	result.grid_columns = game.battlefield.layout.grid_size.x
	result.grid_rows = game.battlefield.layout.grid_size.y
	result.cell_size = game.battlefield.layout.cell_size
	result.cell_types = Array(game.battlefield.layout.cells)
	result.road_cells = []
	for cell: Vector2i in game.battlefield.layout.road_cells:
		result.road_cells.append([cell.x, cell.y])
	result.turn_probability = game.battlefield.layout.turn_probability
	result.tower_position = [game.tower.global_position.x, game.tower.global_position.y]
	result.preview_scale = game.drag_controller.preview.scale.x
	result.route_length = game.battlefield.layout.curve.get_baked_length()
	result.path_points = []
	for point: Vector2 in game.battlefield.layout.curve.get_baked_points():
		result.path_points.append([point.x, point.y])
	result.slot_positions = []
	for slot: SummonSlot in slots:
		result.slot_positions.append([slot.global_position.x, slot.global_position.y])
	result.decorations = game.battlefield.layout.decorations.size()
	result.unit_ids = []
	result.paid_mana = []
	for slot: SummonSlot in slots:
		result.unit_ids.append(0 if slot.is_empty() else slot.unit.get_instance_id())
		result.paid_mana.append(0 if slot.is_empty() else slot.unit.paid_mana)
	result.enemy_positions = []
	for enemy: ApproachingEnemy in game.enemies.get_children():
		if enemy.is_targetable():
			result.enemy_positions.append([enemy.global_position.x, enemy.global_position.y, enemy._distance])
	result.buttons = {}
	for button_name: String in ["RestartButton", "MenuButton"]:
		var button: Button = game.hud.get_node("GameOverOverlay/Center/Panel/Stack/Actions/" + button_name)
		var center: Vector2 = button.get_global_rect().get_center()
		result.buttons[button_name] = [center.x, center.y]
	result.upgrade_visible = game.upgrade_choice.visible
	return result
