class_name PriestVisual
extends Node2D

signal release
signal visual_animation_finished(animation_name: StringName)

const CAST_RELEASE_TIME: float = 0.18
const CAST_LENGTH: float = 0.5
const DRAG_TEXTURE: Texture2D = preload("res://art/source/priest/master.svg")
@export var level: int = 1
@export var part_variants: Dictionary[StringName, Array] = {}
@export var part_paths: Dictionary[StringName, NodePath] = {}
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var spawn_player: AnimationPlayer = $SpawnPlayer
@onready var rig_root: Bone2D = $Skeleton2D/Root
@onready var release_point: Marker2D = $Skeleton2D/Root/Body/FrontArm/Staff/ReleasePoint
@onready var staff_particles: CPUParticles2D = $Skeleton2D/Root/Body/FrontArm/Staff/ReleasePoint/StaffParticles
var cloth_material: ShaderMaterial
var _active_animation: StringName = &"idle_loop"
var _released: bool = false
var _gameplay_mode: bool = false
var _preparing: bool = false


func _ready() -> void:
	set_level(level)
	play_animation(&"idle_loop")


func set_level(value: int) -> void:
	level = clampi(value,1,5)
	if not is_inside_tree():
		return
	for part: StringName in part_paths:
		var sprite: Sprite2D = get_node(part_paths[part]) as Sprite2D
		sprite.texture = part_variants[part][level-1] as Texture2D
		sprite.visible = sprite.texture != null


func play_animation(clip: StringName) -> void:
	if clip == &"RESET" or not animation_player.has_animation(clip):
		return
	var saved_transform: Transform2D = rig_root.transform
	var saved_color: Color = rig_root.modulate
	animation_player.stop()
	animation_player.play(&"RESET")
	animation_player.advance(0.0)
	_active_animation = clip
	_released = false
	animation_player.play(clip)
	animation_player.advance(0.0)
	if _gameplay_mode:
		rig_root.transform = saved_transform
		rig_root.modulate = saved_color


func _emit_release() -> void:
	if _active_animation != &"cast" or _released:
		return
	_released = true
	release.emit()


func _on_animation_finished(clip: StringName) -> void:
	if clip == &"RESET":
		return
	visual_animation_finished.emit(clip)
	if _active_animation == clip:
		play_animation(&"idle_loop")


func enable_gameplay(play_spawn: bool = false) -> void:
	_gameplay_mode = true
	_preparing = false
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	play_animation(&"idle_loop")
	spawn_player.stop()
	rig_root.transform = rig_root.rest
	rig_root.modulate = Color.WHITE
	if play_spawn:
		spawn_player.play(&"spawn")
		spawn_player.advance(0.0)
	staff_particles.emitting = true


func advance_gameplay(delta: float, cooldown: float, interval: float, has_target: bool) -> void:
	var speed: float = maxf(1.0,CAST_LENGTH/interval)
	animation_player.speed_scale = speed if _active_animation == &"cast" else 1.0
	var anticipation: float = CAST_RELEASE_TIME-cooldown*speed
	if has_target and cooldown > 0.0 and anticipation >= 0.0:
		if not _preparing:
			play_animation(&"cast")
			_preparing = true
		animation_player.seek(minf(anticipation,CAST_RELEASE_TIME-0.0001),true,true)
	elif _preparing and has_target and cooldown <= 0.0:
		return
	elif _preparing:
		cancel_preparation()
	else:
		animation_player.advance(delta)


func release_now() -> void:
	if not _preparing:
		play_animation(&"cast")
	_preparing = false
	animation_player.seek(CAST_RELEASE_TIME,true,true)
	_emit_release()


func cancel_preparation() -> void:
	if _preparing:
		_preparing = false
		play_animation(&"idle_loop")


func stop_gameplay() -> void:
	_preparing = false
	_released = true
	animation_player.pause()
	spawn_player.pause()
	staff_particles.emitting = false
	release_point.get_node("Energy").modulate.a = 0.0
