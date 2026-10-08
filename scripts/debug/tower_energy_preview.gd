extends Control

@onready var large_stage: Control = $Margin/Content/LargeStage
@onready var small_stage: Control = $Margin/Content/SmallStage
@onready var large: Node2D = $Margin/Content/LargeStage/Avatar
@onready var small: Node2D = $Margin/Content/SmallStage/Avatar
@onready var idle_button: Button = $Margin/Content/Actions/Idle

var _idle_enabled: bool = true
var _snapshot_callback: JavaScriptObject


func _ready() -> void:
	large_stage.resized.connect(_layout)
	small_stage.resized.connect(_layout)
	_layout()
	if OS.has_feature("web"):
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getTowerEnergyPreview = _snapshot_callback


func _layout() -> void:
	large.position = large_stage.size * Vector2(0.5, 0.57)
	small.position = small_stage.size * Vector2(0.5, 0.58)


func _on_tap() -> void:
	large.play_tap()
	small.play_tap()


func _on_idle_toggled() -> void:
	_idle_enabled = not _idle_enabled
	large.set_idle_enabled(_idle_enabled)
	small.set_idle_enabled(_idle_enabled)
	idle_button.text = "Свечение: вкл." if _idle_enabled else "Свечение: выкл."


func _publish_snapshot(_arguments: Array) -> void:
	var bounds: Rect2 = large_stage.get_global_rect()
	var state: Dictionary = {"idle": _idle_enabled, "tap_requests": large.tap_requests,
		"large_bursts": large.energy.get_child_count() - 3, "small_bursts": small.energy.get_child_count() - 3,
		"idle_particles": large.idle_particles.amount, "gameplay_canvas": small.scale.x * 256.0,
		"tap_point": [bounds.get_center().x, bounds.get_center().y],
		"node_count": get_tree().get_node_count(), "fps": Engine.get_frames_per_second()}
	JavaScriptBridge.eval("window.towerEnergyPreview = %s;" % JSON.stringify(state), true)


func _exit_tree() -> void:
	if _snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getTowerEnergyPreview = null
		JavaScriptBridge.get_interface("window").towerEnergyPreview = null
