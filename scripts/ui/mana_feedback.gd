class_name ManaFeedback
extends Control

const GAIN_SCALE: GFFTween = preload("res://resources/ui/feedback/mana_scale.tres")
const GAIN_GLOW: GFFTween = preload("res://resources/ui/feedback/mana_glow.tres")

@onready var visual: TextureRect = $Visual
@onready var player: GFFPlayer = $Visual/GFFPlayer


func _ready() -> void:
	visual.resized.connect(_update_pivot)
	_update_pivot()


func play_gain() -> void:
	# Ignore repeated awards until this short pulse ends; counters still update immediately.
	if player.is_playing() or not is_visible_in_tree():
		return
	player.play(GAIN_SCALE.duplicate(true))
	player.play(GAIN_GLOW.duplicate(true))


func stop_feedback() -> void:
	player.stop()
	visual.scale = Vector2.ONE
	visual.self_modulate = Color.WHITE


func _update_pivot() -> void:
	visual.pivot_offset = visual.size * 0.5


func _exit_tree() -> void:
	if is_instance_valid(player):
		stop_feedback()
