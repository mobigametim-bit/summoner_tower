extends Control

const ANIMATIONS: Array[StringName] = [&"idle_loop", &"attack", &"spawn"]
const PREVIEW_SCALES: Array[float] = [3.0, 0.96, 0.8, 0.68]
const PAUSE_ICON: Texture2D = preload("res://assets/debug/animation_controls/pause.svg")
const PLAY_ICON: Texture2D = preload("res://assets/debug/animation_controls/play.svg")

@onready var content: VBoxContainer = $Margin/Content
@onready var stage: Control = $Margin/Content/Stage
@onready var preview_host: Node2D = $Margin/Content/Stage/PreviewHost
@onready var preview_visual: Node2D = $Margin/Content/Stage/PreviewHost/ArcherVisual
@onready var animation_label: Label = $Margin/Content/AnimationRow/AnimationName
@onready var event_label: Label = $Margin/Content/Event
@onready var pause_button: Button = $Margin/Content/Playback/Pause
@onready var repeat_button: CheckButton = $Margin/Content/Options/Repeat
@onready var mirror_button: CheckButton = $Margin/Content/Options/Mirror
@onready var scale_picker: OptionButton = $Margin/Content/Options/Scale
@onready var repeat_timer: Timer = $RepeatTimer

var _visuals: Array[Node2D] = []
var _animation_index: int = 0
var _speed: float = 1.0
var _paused: bool = false
var _release_count: int = 0


func _ready() -> void:
	_visuals.append(preview_visual)
	for columns: int in [6, 7, 8]:
		var cell: Control = content.get_node("Samples/Columns%d/Cell" % columns)
		var anchor: Node2D = cell.get_node("Anchor")
		var host: Node2D = anchor.get_node("UnitHost")
		var cell_size: float = 672.0 / float(columns) - 4.0
		var unit_scale: float = minf((cell_size - 12.0) / 100.0, 1.0)
		var ground: Sprite2D = anchor.get_node("Ground")
		ground.scale = Vector2.ONE * (cell_size + 4.0) / float(ground.texture.get_width())
		var pedestal: Sprite2D = anchor.get_node("Pedestal")
		pedestal.scale = Vector2.ONE * cell_size / 140.0
		host.position.y = 26.0 * cell_size / 140.0 - 42.0 * unit_scale
		host.scale = Vector2.ONE * unit_scale
		_visuals.append(host.get_node("ArcherVisual") as Node2D)

	$Margin/Content/AssetRow/PreviousAsset.disabled = true
	$Margin/Content/AssetRow/NextAsset.disabled = true
	_layout_previews()
	_set_speed(1.0)
	replay()


func _layout_previews() -> void:
	if not is_node_ready():
		return
	preview_host.position = stage.size * 0.5 + Vector2(0.0, 8.0)
	var multiplier: float = PREVIEW_SCALES[scale_picker.selected]
	preview_host.scale = Vector2(-multiplier if mirror_button.button_pressed else multiplier, multiplier)
	for columns: int in [6, 7, 8]:
		var cell: Control = content.get_node("Samples/Columns%d/Cell" % columns)
		var anchor: Node2D = cell.get_node("Anchor")
		anchor.position = cell.size * 0.5
		var host: Node2D = anchor.get_node("UnitHost")
		host.scale.x = -absf(host.scale.x) if mirror_button.button_pressed else absf(host.scale.x)


func replay() -> void:
	repeat_timer.stop()
	_set_paused(false)
	_release_count = 0
	event_label.text = "Release: —"
	var animation_name: StringName = ANIMATIONS[_animation_index]
	animation_label.text = String(animation_name)
	for visual: Node2D in _visuals:
		visual.call(&"set_playback_speed", _speed)
		visual.call(&"play_animation", animation_name)


func _on_previous_animation() -> void:
	_animation_index = posmod(_animation_index - 1, ANIMATIONS.size())
	replay()


func _on_next_animation() -> void:
	_animation_index = posmod(_animation_index + 1, ANIMATIONS.size())
	replay()


func _on_pause() -> void:
	_set_paused(not _paused)


func _set_paused(paused: bool) -> void:
	_paused = paused
	pause_button.text = ""
	pause_button.tooltip_text = "Resume" if paused else "Pause"
	pause_button.icon = PLAY_ICON if paused else PAUSE_ICON
	repeat_timer.paused = paused
	for visual: Node2D in _visuals:
		visual.call(&"set_animation_paused", paused)


func _set_speed(multiplier: float) -> void:
	_speed = multiplier
	($Margin/Content/SpeedRow/Half as Button).set_pressed_no_signal(is_equal_approx(multiplier, 0.5))
	($Margin/Content/SpeedRow/Normal as Button).set_pressed_no_signal(is_equal_approx(multiplier, 1.0))
	($Margin/Content/SpeedRow/Double as Button).set_pressed_no_signal(is_equal_approx(multiplier, 2.0))
	for visual: Node2D in _visuals:
		visual.call(&"set_playback_speed", multiplier)


func _on_half_speed() -> void:
	_set_speed(0.5)


func _on_normal_speed() -> void:
	_set_speed(1.0)


func _on_double_speed() -> void:
	_set_speed(2.0)


func _on_scale_selected(_index: int) -> void:
	_layout_previews()


func _on_mirror_toggled(_enabled: bool) -> void:
	_layout_previews()


func _on_repeat_toggled(enabled: bool) -> void:
	if not enabled:
		repeat_timer.stop()


func _on_visual_release() -> void:
	_release_count += 1
	event_label.text = "Release: %.2f s · %d event" % [0.24, _release_count]


func _on_visual_animation_finished(_animation_name: StringName) -> void:
	if repeat_button.button_pressed:
		repeat_timer.start(0.6 / _speed)


func _on_repeat_timeout() -> void:
	replay()
