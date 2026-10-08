extends Control

@onready var fire_stage: Control = $Margin/Content/FireStage
@onready var frost_stage: Control = $Margin/Content/FrostStage
@onready var fire_large: Node2D = $Margin/Content/FireStage/Large
@onready var fire_small: Node2D = $Margin/Content/FireStage/Small
@onready var frost_large: Node2D = $Margin/Content/FrostStage/Large
@onready var frost_small: Node2D = $Margin/Content/FrostStage/Small
@onready var idle_button: Button = $Margin/Content/Actions/Idle

var _idle: bool = true
var _snapshot_callback: JavaScriptObject


func _ready() -> void:
	fire_stage.resized.connect(_layout)
	frost_stage.resized.connect(_layout)
	_layout()
	if OS.has_feature("web"):
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getMagicParticlePreview = _snapshot_callback


func _layout() -> void:
	for stage: Control in [fire_stage, frost_stage]:
		stage.get_node("Large").position = Vector2(stage.size.x * 0.5, stage.size.y * 0.4)
		stage.get_node("Small").position = Vector2(stage.size.x * 0.5, stage.size.y * 0.83)


func _on_fire() -> void:
	fire_large.cast()
	fire_small.cast()


func _on_frost() -> void:
	frost_large.cast()
	frost_small.cast()


func _on_both() -> void:
	_on_fire()
	_on_frost()


func _on_idle() -> void:
	_idle = not _idle
	for pair: Node2D in [fire_large, fire_small, frost_large, frost_small]:
		pair.set_idle_enabled(_idle)
	idle_button.text = "Аура: вкл." if _idle else "Аура: выкл."


func _publish_snapshot(_arguments: Array) -> void:
	var state: Dictionary = {"idle": _idle, "fire_hits": fire_large.hits, "frost_hits": frost_large.hits,
		"fire_bursts": fire_large.impact_host.get_child_count() - 1,
		"frost_bursts": frost_large.impact_host.get_child_count() - 1,
		"fire_tap": _center(fire_stage), "frost_tap": _center(frost_stage),
		"nodes": get_tree().get_node_count(), "fps": Engine.get_frames_per_second()}
	JavaScriptBridge.eval("window.magicParticlePreview = %s;" % JSON.stringify(state), true)


func _center(control: Control) -> Array[float]:
	var point: Vector2 = control.get_global_rect().get_center()
	return [point.x, point.y]


func _exit_tree() -> void:
	if _snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getMagicParticlePreview = null
		JavaScriptBridge.get_interface("window").magicParticlePreview = null
