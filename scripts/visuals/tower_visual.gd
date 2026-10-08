class_name TowerVisual
extends Node2D

signal visual_animation_finished(animation_name: StringName)

const CANVAS_SIZE: float = 256.0
const BASE_BOTTOM_Y: float = 254.0

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var crystal_energy: TowerCrystalEnergy = $CrystalPivot/CrystalEnergy

var _active_animation: StringName = &"crystal_pulse"
var _pending_reaction: StringName = &""
var _destroyed: bool = false
var _finished: bool = false


func _ready() -> void:
	play_animation(&"crystal_pulse")


func play_animation(animation_name: StringName) -> void:
	if not animation_player.has_animation(animation_name) or animation_name == &"RESET":
		return
	# Review / initialize полностью восстанавливают позу, включая destroyed.
	_pending_reaction = &""
	_destroyed = animation_name == &"destroyed"
	_play_clip(animation_name)


func _play_clip(animation_name: StringName) -> void:
	if crystal_energy.idle_enabled == _destroyed:
		crystal_energy.set_idle_enabled(not _destroyed)
	animation_player.stop()
	animation_player.play(&"RESET")
	animation_player.advance(0.0)
	_active_animation = animation_name
	_finished = false
	animation_player.play(animation_name)
	animation_player.advance(0.0)


func show_tap() -> void:
	if not _destroyed:
		crystal_energy.play_tap()
	_request_reaction(&"tap")


func show_refund() -> void:
	_request_reaction(&"refund")


func show_hit() -> void:
	_request_reaction(&"hit")


func show_destroyed() -> void:
	if _destroyed:
		return
	_destroyed = true
	_pending_reaction = &""
	_play_clip(&"destroyed")


func _request_reaction(animation_name: StringName) -> void:
	if _destroyed:
		return
	if animation_name == &"hit" and _active_animation == &"hit":
		return
	if _priority(animation_name) < _priority(_active_animation):
		# Один ожидающий отклик: частые действия не создают длинную очередь.
		if _priority(animation_name) >= _priority(_pending_reaction):
			_pending_reaction = animation_name
		return
	_play_clip(animation_name)


func _priority(animation_name: StringName) -> int:
	match animation_name:
		&"hit": return 3
		&"refund": return 2
		&"tap": return 1
	return 0


func set_playback_speed(multiplier: float) -> void:
	animation_player.speed_scale = multiplier


func set_animation_paused(paused: bool) -> void:
	if paused:
		animation_player.pause()
	elif not _finished:
		animation_player.play()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"RESET":
		return
	_finished = true
	visual_animation_finished.emit(animation_name)
	if _active_animation != animation_name or _destroyed:
		return
	var next_animation: StringName = _pending_reaction
	_pending_reaction = &""
	_play_clip(next_animation if next_animation != &"" else &"crystal_pulse")
