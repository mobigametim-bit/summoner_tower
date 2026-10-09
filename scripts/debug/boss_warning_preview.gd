extends "res://scripts/debug/tower_gameplay_review.gd"

@onready var warning: BossWarning = $Interface/Hud/BossWarning
var _warning_snapshot_callback: JavaScriptObject


func _ready() -> void:
	super._ready()
	wave_manager.stop()
	for enemy: Node in enemies.get_children():
		enemy.queue_free()
	var unit_paths: Array[String] = ["res://scenes/archer.tscn", "res://scenes/mage.tscn", "res://scenes/frost_mage.tscn"]
	for index: int in unit_paths.size():
		var unit: CombatUnit = (load(unit_paths[index]) as PackedScene).instantiate() as CombatUnit
		unit.attack_enabled = false
		summon_manager._slots[index].place_unit(unit)
		unit.configure(enemies, projectiles, run_bonuses)
	var boss: ApproachingEnemy = (load("res://scenes/boss.tscn") as PackedScene).instantiate() as ApproachingEnemy
	enemies.add_child(boss)
	boss.configure(spawn_point.global_position, contact_point.global_position.y)
	boss.follow_route(battlefield.route.curve, battlefield.route.global_transform, battlefield.layout.cell_size)
	boss._distance = 120.0
	boss.global_position = battlefield.route.global_transform * battlefield.route.curve.sample_baked(120.0)
	boss.move_speed = 0.0
	hud.update_wave(5, WaveManager.Phase.FIGHTING, 0, 1, 0)
	if OS.has_feature("web"):
		_warning_snapshot_callback = JavaScriptBridge.create_callback(_publish_warning_snapshot)
		JavaScriptBridge.get_interface("window").getBossWarningPreview = _warning_snapshot_callback
	warning.call_deferred(&"play_warning")


func _on_preview_repeat() -> void:
	warning.play_warning()


func _publish_warning_snapshot(_arguments: Array) -> void:
	var text: Label = warning.get_node("Text") as Label
	var bounds: Rect2 = text.get_global_rect()
	var snapshot: Dictionary = {"visible":warning.visible, "color":[text.self_modulate.r,text.self_modulate.g,text.self_modulate.b],
		"alpha":warning.modulate.a,"frame":warning.animation_player.current_animation_position if warning.animation_player.is_playing() else 0.0,
		"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]}
	JavaScriptBridge.eval("window.bossWarningPreview = %s;" % JSON.stringify(snapshot), true)


func _exit_tree() -> void:
	if _warning_snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getBossWarningPreview = null
		JavaScriptBridge.get_interface("window").bossWarningPreview = null
	super._exit_tree()
