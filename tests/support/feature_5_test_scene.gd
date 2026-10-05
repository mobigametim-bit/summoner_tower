extends Node

var _tier_preview: bool = false
var _web_sample_remaining: float = 0.0


func _ready() -> void:
	# Только отдельная браузерная тестовая сборка; tests/* исключены из обычного Web export.
	if OS.has_feature("web"):
		var manager: SummonManager = $Game/SummonManager
		manager.mana = 1000
		manager._emit_state()
		if bool(JavaScriptBridge.eval("location.search.includes('mcp_levels=1')")):
			prepare_level_preview(3)


func prepare_level_preview(level: int) -> void:
	_tier_preview = true
	var game: Node2D = $Game
	game.wave_manager.stop()
	for enemy: Node in game.enemies.get_children():
		enemy.free()
	var slots: Array[Node] = game.get_node("World/Slots").get_children()
	for slot: SummonSlot in slots:
		if not slot.is_empty():
			var old: CombatUnit = slot.unit
			slot.assign_unit(null)
			old.free()
	var types: Array[String] = ["archer", "mage", "frost_mage"]
	var checks: RefCounted = load("res://tests/support/feature_5_checks.gd").new()
	for index: int in slots.size():
		var packed: PackedScene = load("res://scenes/%s.tscn" % types[floori(index / 2.0)])
		checks._place_level(packed, slots[index], level, game.enemies, game.projectiles, 40)
	for tier: int in 5:
		var enemy: ApproachingEnemy = load("res://scenes/enemy.tscn").instantiate()
		game.enemies.add_child(enemy)
		enemy.configure(Vector2(360, 220 + tier * 135), 1100.0, 30 * int(pow(2, tier)))
		enemy.set_physics_process(false)
	game.summon_manager.mana = 1000
	game.summon_manager._emit_state()


func _process(delta: float) -> void:
	if not OS.has_feature("web") or not _tier_preview:
		return
	_web_sample_remaining -= delta
	if _web_sample_remaining > 0.0:
		return
	_web_sample_remaining = 0.1
	var requested: int = int(JavaScriptBridge.eval("Number(window.mcpTierLevel || 0)"))
	if requested >= 3 and requested <= 5:
		JavaScriptBridge.eval("window.mcpTierLevel = 0")
		prepare_level_preview(requested)
	var units: Array[Dictionary] = []
	for slot: SummonSlot in $Game/World/Slots.get_children():
		units.append({} if slot.is_empty() else {"id": slot.unit.get_instance_id(), "level": slot.unit.stats.level, "damage": slot.unit.stats.damage, "paid": slot.unit.paid_mana, "texture": slot.unit.stats.visual_texture.resource_path})
	var enemies: Array[Dictionary] = []
	for enemy: ApproachingEnemy in $Game.enemies.get_children():
		enemies.append({"hp": enemy.max_health, "tier": enemy.difficulty_tier, "color": enemy.visual.modulate.to_html(false)})
	var snapshot: Dictionary = {"units": units, "enemies": enemies, "mana": $Game.summon_manager.mana, "cost": $Game.summon_manager.current_cost()}
	JavaScriptBridge.eval("window.mcpTierState = %s" % JSON.stringify(snapshot))


func run_checks() -> void:
	set_meta("feature5_checks", load("res://tests/support/feature_5_checks.gd").new().run($Game))
