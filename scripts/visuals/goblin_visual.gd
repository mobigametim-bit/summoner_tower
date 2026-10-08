class_name GoblinVisual
extends Node2D

signal attack_impact
signal visual_animation_finished(animation_name: StringName)

const ATTACK_IMPACT_TIME: float = 0.16
const GAMEPLAY_CANVAS_SIZE: float = 86.4

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var equipment_material: ShaderMaterial = $Skeleton2D/Root/Body/Sprite.material
@onready var _equipment_sprites: Array[Node] = find_children("*", "Sprite2D", true, false)

var _active_animation: StringName = &"walk_loop"
var _impact_emitted: bool = false
var _finished: bool = false
var _preparing: bool = false
var _tail: bool = false


func _ready() -> void:
	set_difficulty(1, EnemyStats.TIER_COLORS[0])
	play_animation(&"walk_loop")


func play_animation(animation_name: StringName) -> void:
	if not animation_player.has_animation(animation_name) or animation_name == &"RESET":
		return
	animation_player.stop()
	animation_player.play(&"RESET")
	animation_player.advance(0.0)
	_active_animation = animation_name
	_impact_emitted = false
	_finished = false
	animation_player.play(animation_name)
	animation_player.advance(0.0)


func set_playback_speed(multiplier: float) -> void:
	animation_player.speed_scale = multiplier


func set_animation_paused(paused: bool) -> void:
	if paused:
		animation_player.pause()
	elif not _finished:
		animation_player.play()


func enable_gameplay() -> void:
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_player.speed_scale = 1.0
	_preparing = false
	_tail = false
	play_animation(&"walk_loop")


func set_difficulty(tier: int, equipment_color: Color) -> void:
	equipment_material.set_shader_parameter("recolor_enabled", tier >= 1)
	equipment_material.set_shader_parameter("equipment_color", equipment_color)
	for sprite: Node in _equipment_sprites:
		if sprite is EnemyEquipmentPart:
			(sprite as EnemyEquipmentPart).apply_tier(tier, equipment_color)


func advance_gameplay(delta: float, time_to_contact: float, direction: Vector2) -> void:
	if absf(direction.x) > 0.001:
		scale = Vector2(-1.0 if direction.x < 0.0 else 1.0, 1.0) * (GAMEPLAY_CANVAS_SIZE / 256.0)
	if time_to_contact <= ATTACK_IMPACT_TIME:
		if not _preparing:
			play_animation(&"attack")
			_preparing = true
		# Seek only changes the pose. Gameplay decides the exact contact frame.
		animation_player.seek(clampf(ATTACK_IMPACT_TIME - time_to_contact, 0.0, ATTACK_IMPACT_TIME - 0.0001), true, true)
	elif _preparing:
		_preparing = false
		play_animation(&"walk_loop")
	else:
		animation_player.advance(delta)


func impact_now() -> void:
	if not _preparing:
		play_animation(&"attack")
	_preparing = false
	animation_player.seek(ATTACK_IMPACT_TIME, true, true)
	_emit_attack_impact()


func show_hit() -> void:
	# Contact windup takes priority; repeated hits cannot postpone tower damage.
	if _preparing or _active_animation == &"hit":
		return
	play_animation(&"hit")


func finish_as_tail(killed: bool) -> void:
	_tail = true
	_preparing = false
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	animation_player.speed_scale = 1.0
	if killed:
		play_animation(&"death")
	else:
		animation_player.play()


func stop_gameplay() -> void:
	_preparing = false
	animation_player.stop()


func _emit_attack_impact() -> void:
	if _active_animation != &"attack" or _impact_emitted:
		return
	_impact_emitted = true
	attack_impact.emit()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"RESET":
		return
	_finished = true
	visual_animation_finished.emit(animation_name)
	if _tail:
		queue_free()
		return
	# Standalone review holds death's final pose until Replay.
	if _active_animation == animation_name and animation_name != &"death":
		play_animation(&"walk_loop")
