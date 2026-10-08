class_name MageVisual
extends Node2D

signal release
signal visual_animation_finished(animation_name: StringName)

const CAST_RELEASE_TIME: float = 0.18
const CAST_LENGTH: float = 0.42
const DRAG_TEXTURE: Texture2D = preload("res://art/source/mage/master.svg")
const CLOTH_COLORS: Array[Color] = [
	Color("71913e"), Color("ef9639"), Color("de595b"), Color("529be5"), Color("a46be0")
]

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var spawn_player: AnimationPlayer = $SpawnPlayer
@onready var release_point: Marker2D = $Skeleton2D/Root/Body/FrontArm/Staff/ReleasePoint
@onready var staff_particles: CPUParticles2D = $Skeleton2D/Root/Body/FrontArm/Staff/ReleasePoint/StaffParticles
@onready var rig_root: Bone2D = $Skeleton2D/Root
@onready var cloth_material: ShaderMaterial = $Skeleton2D/Root/Body/Sprite.material

var _active_animation: StringName = &"idle_loop"
var _released: bool = false
var _gameplay_mode: bool = false
var _preparing: bool = false


func _ready() -> void:
	play_animation(&"idle_loop")


func play_animation(animation_name: StringName) -> void:
	if not animation_player.has_animation(animation_name) or animation_name == &"RESET":
		return
	var root_transform: Transform2D = rig_root.transform
	var root_color: Color = rig_root.modulate
	if not _gameplay_mode:
		spawn_player.stop()
	animation_player.stop()
	animation_player.play(&"RESET")
	animation_player.advance(0.0)
	if _gameplay_mode:
		rig_root.transform = root_transform
		rig_root.modulate = root_color
	_active_animation = animation_name
	_released = false
	animation_player.play(animation_name)
	animation_player.advance(0.0)
	if _gameplay_mode:
		rig_root.transform = root_transform
		rig_root.modulate = root_color


func enable_gameplay(play_spawn: bool = false) -> void:
	staff_particles.visible = true
	staff_particles.emitting = true
	_gameplay_mode = true
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_preparing = false
	play_animation(&"idle_loop")
	if play_spawn:
		spawn_player.play(&"spawn")
		spawn_player.advance(0.0)
	else:
		spawn_player.stop()
		rig_root.position = Vector2(-128.0, -128.0)
		rig_root.scale = Vector2.ONE
		rig_root.modulate = Color.WHITE


func set_level(level: int) -> void:
	cloth_material.set_shader_parameter("cloth_color", CLOTH_COLORS[clampi(level - 1, 0, 4)])


func advance_gameplay(delta: float, cooldown: float, interval: float, has_target: bool) -> void:
	var cast_speed: float = maxf(1.0, CAST_LENGTH / interval)
	animation_player.speed_scale = cast_speed if _active_animation == &"cast" else 1.0
	var anticipation: float = CAST_RELEASE_TIME - cooldown * cast_speed
	if has_target and cooldown > 0.0 and anticipation >= 0.0:
		if not _preparing:
			play_animation(&"cast")
			_preparing = true
		# Подготовка следует cooldown: seek не выполняет release раньше готовности.
		animation_player.seek(minf(anticipation, CAST_RELEASE_TIME - 0.0001), true, true)
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
	animation_player.seek(CAST_RELEASE_TIME, true, true)
	_emit_release()


func cancel_preparation() -> void:
	if not _preparing:
		return
	_preparing = false
	play_animation(&"idle_loop")


func stop_gameplay() -> void:
	staff_particles.visible = false
	staff_particles.emitting = false
	_preparing = false
	_released = true
	animation_player.pause()
	spawn_player.pause()
	$Skeleton2D/Root/Body/FrontArm/Staff/ReleasePoint/Energy.modulate.a = 0.0


func set_playback_speed(multiplier: float) -> void:
	animation_player.speed_scale = multiplier


func set_animation_paused(paused: bool) -> void:
	if paused:
		animation_player.pause()
	else:
		animation_player.play()


func _emit_release() -> void:
	# Только визуальное событие. Существующий fireball создаст gameplay entity.
	if _active_animation != &"cast" or _released:
		return
	_released = true
	release.emit()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"RESET":
		return
	visual_animation_finished.emit(animation_name)
	if _active_animation == animation_name:
		play_animation(&"idle_loop")
