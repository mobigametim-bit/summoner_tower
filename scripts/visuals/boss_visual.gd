class_name BossVisual
extends CanvasGroup

signal attack_impact
signal visual_animation_finished(animation_name: StringName)

const ATTACK_IMPACT_TIME: float = 0.22
const GAMEPLAY_CANVAS_SIZE: float = 166.0

@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _active_animation: StringName = &"walk_loop"
var _impact_emitted: bool = false
var _finished: bool = false
var _gameplay_enabled: bool = false
var _intro_played: bool = false
var _preparing: bool = false
var _tail: bool = false


func _ready() -> void:
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


func _emit_attack_impact() -> void:
	if _active_animation != &"attack" or _impact_emitted:
		return
	_impact_emitted = true
	attack_impact.emit()


func enable_gameplay() -> void:
	# Ready и configure могут включить visual в одном кадре: intro запускается один раз.
	if _gameplay_enabled:
		return
	_gameplay_enabled = true
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_player.speed_scale = 1.0
	_preparing = false
	_tail = false
	if not _intro_played:
		_intro_played = true
		play_animation(&"spawn_or_intro")
	else:
		play_animation(&"walk_loop")


func set_difficulty(_tier: int, _color: Color) -> void:
	# Boss сохраняет принятую палитру при любом HP, общий enemy contract остаётся прежним.
	pass


func advance_gameplay(delta: float, time_to_contact: float, direction: Vector2) -> void:
	if absf(direction.x) > 0.001:
		var visual_scale: float = GAMEPLAY_CANVAS_SIZE / 256.0
		scale = Vector2(-visual_scale if direction.x < 0.0 else visual_scale, visual_scale)
	if time_to_contact <= ATTACK_IMPACT_TIME:
		if not _preparing:
			play_animation(&"attack")
			_preparing = true
		# Seek готовит позу без события; contact выбирает существующая gameplay logic.
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
	if _preparing or _active_animation == &"hit":
		return
	play_animation(&"hit")


func finish_as_tail(killed: bool) -> void:
	_tail = true
	_gameplay_enabled = false
	_preparing = false
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	animation_player.speed_scale = 1.0
	if killed:
		play_animation(&"death")
	else:
		animation_player.play()


func stop_gameplay() -> void:
	_gameplay_enabled = false
	_preparing = false
	animation_player.stop()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"RESET":
		return
	_finished = true
	visual_animation_finished.emit(animation_name)
	if _tail:
		queue_free()
		return
	# В review смерть удерживает финальную позу; Replay восстанавливает rig.
	if _active_animation == animation_name and animation_name != &"death":
		play_animation(&"walk_loop")
