extends Control

const VISUAL_PULSE: GFFTween = preload("res://resources/debug/game_feel_flow/visual_pulse.tres")
const BUTTON_PULSE: GFFTween = preload("res://resources/debug/game_feel_flow/button_pulse.tres")
const PARTICLE_BURST: GFFParticles = preload("res://resources/debug/game_feel_flow/particle_burst.tres")

@onready var stage: Control = $Margin/Content/Stage
@onready var effect_root: Node2D = $Margin/Content/Stage/Anchor/EffectRoot
@onready var goblin: GoblinVisual = $Margin/Content/Stage/Anchor/EffectRoot/GoblinVisual
@onready var visual_player: GFFPlayer = $Margin/Content/Stage/Anchor/EffectRoot/GFFPlayer
@onready var particle_host: Node2D = $Margin/Content/Stage/Anchor/Particles
@onready var particle_player: GFFPlayer = $Margin/Content/Stage/Anchor/Particles/GFFPlayer
@onready var pulse_button: Button = $Margin/Content/Actions/Pulse
@onready var button_visual: Control = $Margin/Content/Actions/Pulse/Face
@onready var button_player: GFFPlayer = $Margin/Content/Actions/Pulse/Face/GFFPlayer
@onready var pause_button: Button = $Margin/Content/Playback/Pause
@onready var scale_picker: OptionButton = $Margin/Content/Options/Size
@onready var tier_picker: OptionButton = $Margin/Content/Options/Tier
@onready var status_label: Label = $Margin/Content/Status
@onready var burst_timer: Timer = $BurstTimer

var _tier: int = 3
var _large: bool = true
var _burst_remaining: int = 0
var _pulse_requests: int = 0
var _particle_requests: int = 0
var _materials: Array[int] = []
var _web_snapshot_callback: JavaScriptObject
var _web_command_callback: JavaScriptObject


func _ready() -> void:
	stage.resized.connect(_layout_preview)
	button_visual.resized.connect(_layout_button)
	pulse_button.pressed.connect(pulse)
	$Margin/Content/Actions/Particles.pressed.connect(particles)
	$Margin/Content/Actions/Burst.pressed.connect(burst)
	$Margin/Content/Playback/Stop.pressed.connect(stop_effects)
	pause_button.pressed.connect(toggle_pause)
	$Margin/Content/Playback/Reset.pressed.connect(reset_preview)
	$Margin/Content/Playback/Menu.pressed.connect(open_menu)
	tier_picker.item_selected.connect(select_tier)
	scale_picker.item_selected.connect(select_size)
	burst_timer.timeout.connect(_burst_tick)
	tier_picker.select(_tier - 1)
	goblin.set_difficulty(_tier, EnemyStats.TIER_COLORS[_tier - 1])
	_materials = _material_ids()
	_layout_preview()
	_layout_button()
	if OS.has_feature("web"):
		_web_snapshot_callback = JavaScriptBridge.create_callback(_web_snapshot)
		_web_command_callback = JavaScriptBridge.create_callback(_web_command)
		var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
		window.getGffPilotSnapshot = _web_snapshot_callback
		window.gffPilotCommand = _web_command_callback
	_update_status()


func pulse() -> void:
	if get_tree().paused:
		return
	_pulse_requests += 1
	# Single effects use GFFPlayer's overlap stack; rapid repeats are ignored while active.
	visual_player.play(VISUAL_PULSE.duplicate(true))
	button_player.play(BUTTON_PULSE.duplicate(true))
	_update_status()


func particles() -> void:
	if get_tree().paused:
		return
	_particle_requests += 1
	particle_player.play(PARTICLE_BURST.duplicate(true))
	_update_status()


func burst() -> void:
	if get_tree().paused:
		return
	_burst_remaining = 10
	_burst_tick()
	burst_timer.start()


func _burst_tick() -> void:
	if _burst_remaining <= 0:
		burst_timer.stop()
		return
	_burst_remaining -= 1
	pulse()
	particles()


func stop_effects() -> void:
	burst_timer.stop()
	_burst_remaining = 0
	visual_player.stop()
	button_player.stop()
	particle_player.stop()
	# GFFTween.stop kills its tween but doesn't restore the property itself.
	effect_root.scale = Vector2.ONE
	button_visual.scale = Vector2.ONE
	_update_status()


func toggle_pause() -> void:
	# Cancel transient feedback before pause: GFFParticles uses a real-time cleanup timer.
	if not get_tree().paused:
		stop_effects()
	get_tree().paused = not get_tree().paused
	pause_button.text = "Продолжить" if get_tree().paused else "Пауза"
	_update_status()


func reset_preview() -> void:
	get_tree().paused = false
	stop_effects()
	get_tree().reload_current_scene()


func open_menu() -> void:
	get_tree().paused = false
	stop_effects()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func select_tier(index: int) -> void:
	stop_effects()
	_tier = clampi(index + 1, 1, 5)
	goblin.set_difficulty(_tier, EnemyStats.TIER_COLORS[_tier - 1])
	_materials = _material_ids()
	_update_status()


func select_size(index: int) -> void:
	stop_effects()
	_large = index == 0
	_layout_preview()


func _layout_preview() -> void:
	var anchor: Node2D = stage.get_node("Anchor")
	anchor.position = stage.size * Vector2(0.5, 0.55)
	goblin.scale = Vector2.ONE * (1.05 if _large else GoblinVisual.GAMEPLAY_CANVAS_SIZE / 256.0)
	particle_host.scale = Vector2.ONE * goblin.scale.x


func _layout_button() -> void:
	button_visual.pivot_offset = button_visual.size * 0.5


func _material_ids() -> Array[int]:
	var result: Array[int] = []
	for sprite: Node in goblin.find_children("*", "Sprite2D", true, false):
		var material: Material = (sprite as Sprite2D).material
		result.append(material.get_instance_id() if material != null else 0)
	return result


func snapshot() -> Dictionary:
	return {
		"tier": _tier, "large": _large, "paused": get_tree().paused,
		"effect_scale": [effect_root.scale.x, effect_root.scale.y],
		"button_scale": [button_visual.scale.x, button_visual.scale.y],
		"visual_scale": goblin.scale.x,
		"materials_preserved": _materials == _material_ids(),
		"equipment_color": goblin.equipment_material.get_shader_parameter("equipment_color").to_html(),
		"particles": particle_host.get_child_count() - 1,
		"active": visual_player.is_playing() or button_player.is_playing() or particle_player.is_playing(),
		"pulse_requests": _pulse_requests, "particle_requests": _particle_requests,
		"node_count": get_tree().get_node_count(), "fps": Engine.get_frames_per_second(),
		"time_scale": Engine.time_scale,
		"animation_position": goblin.animation_player.current_animation_position,
	}


func _update_status() -> void:
	status_label.text = "Lv%d · %d импульсов · %d запросов частиц\n%s" % [
		_tier, _pulse_requests, _particle_requests,
		"Пауза · эффекты остановлены" if get_tree().paused else "Game Feel Flow Free · без остановки времени",
	]


func _web_snapshot(_arguments: Array) -> void:
	JavaScriptBridge.get_interface("window").gffPilotSnapshotJSON = JSON.stringify(snapshot())


func _web_command(arguments: Array) -> void:
	if arguments.is_empty():
		return
	match str(arguments[0]):
		"pulse": pulse()
		"particles": particles()
		"burst": burst()
		"stop": stop_effects()
		"pause": toggle_pause()
		"reset": reset_preview()
		"tier":
			if arguments.size() > 1:
				select_tier(int(arguments[1]) - 1)
				tier_picker.select(_tier - 1)
		"size":
			if arguments.size() > 1:
				select_size(int(arguments[1]))
				scale_picker.select(int(arguments[1]))


func _exit_tree() -> void:
	if is_instance_valid(visual_player):
		stop_effects()
	if OS.has_feature("web"):
		var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
		window.getGffPilotSnapshot = null
		window.gffPilotCommand = null
	get_tree().paused = false
