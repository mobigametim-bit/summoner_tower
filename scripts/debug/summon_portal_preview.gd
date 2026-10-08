extends Control

@onready var summon_stage: Control = $Margin/Content/SummonStage
@onready var portal_stage: Control = $Margin/Content/PortalStage
@onready var summon_large: Node2D = $Margin/Content/SummonStage/Large
@onready var summon_small: Node2D = $Margin/Content/SummonStage/Small
@onready var portal_large: Node2D = $Margin/Content/PortalStage/Large
@onready var portal_small: Node2D = $Margin/Content/PortalStage/Small

var _snapshot_callback: JavaScriptObject


func _ready() -> void:
	summon_stage.resized.connect(_layout)
	portal_stage.resized.connect(_layout)
	_layout()
	if OS.has_feature("web"):
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getSummonPortalPreview = _snapshot_callback


func _layout() -> void:
	for stage: Control in [summon_stage, portal_stage]:
		stage.get_node("Large").position = stage.size * Vector2(0.32, 0.61)
		stage.get_node("Small").position = stage.size * Vector2(0.77, 0.64)


func _on_summon() -> void:
	summon_large.summon()
	summon_small.summon()


func _on_portal() -> void:
	portal_large.exit_portal()
	portal_small.exit_portal()


func _publish_snapshot(_arguments: Array) -> void:
	var state: Dictionary = {"summons": summon_large.requests, "exits": portal_large.requests,
		"unit_visible": summon_large.unit.visible, "unit_alpha": summon_large.unit.modulate.a,
		"swirl": portal_large.swirl.emitting, "rays": summon_large.rays.emitting,
		"smoke": portal_large.smoke.emitting, "enemy_visible": portal_large.enemy.visible,
		"nodes": get_tree().get_node_count(), "fps": Engine.get_frames_per_second(),
		"summon_tap": _center(summon_stage), "portal_tap": _center(portal_stage)}
	JavaScriptBridge.eval("window.summonPortalPreview = %s;" % JSON.stringify(state), true)


func _center(control: Control) -> Array[float]:
	var point: Vector2 = control.get_global_rect().get_center()
	return [point.x, point.y]


func _exit_tree() -> void:
	if _snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getSummonPortalPreview = null
		JavaScriptBridge.get_interface("window").summonPortalPreview = null
