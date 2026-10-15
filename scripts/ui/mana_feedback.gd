class_name ManaFeedback
extends Control

const GAIN_SCALE: GFFTween = preload("res://resources/ui/feedback/mana_scale.tres")
const GAIN_GLOW: GFFTween = preload("res://resources/ui/feedback/mana_glow.tres")

@export var counter_label: Label
@export_range(0.0, 15.0) var shake_angle_degrees: float = 7.0
@export_range(0.1, 0.6) var shake_duration: float = 0.24

@onready var visual: TextureRect = $Visual
@onready var player: GFFPlayer = $Visual/GFFPlayer

var _shake_tween: Tween


func _ready() -> void:
	visual.resized.connect(_update_pivot)
	if counter_label != null:
		counter_label.resized.connect(_update_pivot)
	_update_pivot()


func play_change(gained: bool) -> void:
	# Новый приход/расход перезапускает короткий импульс без накопления поворота.
	stop_feedback()
	if not is_visible_in_tree():
		return
	if gained:
		play_gain()
	_shake_tween = create_tween()
	for strength: float in [1.0, -0.85, 0.6, -0.35, 0.0]:
		var angle: float = deg_to_rad(shake_angle_degrees) * strength
		_shake_tween.tween_property(visual, "rotation", angle, shake_duration / 5.0)
		if counter_label != null:
			_shake_tween.parallel().tween_property(counter_label, "rotation", angle, shake_duration / 5.0)


func play_gain() -> void:
	# Ignore repeated awards until this short pulse ends; counters still update immediately.
	if player.is_playing() or not is_visible_in_tree():
		return
	player.play(GAIN_SCALE.duplicate(true))
	player.play(GAIN_GLOW.duplicate(true))


func stop_feedback() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	player.stop()
	visual.scale = Vector2.ONE
	visual.self_modulate = Color.WHITE
	visual.rotation = 0.0
	if is_instance_valid(counter_label):
		counter_label.rotation = 0.0


func _update_pivot() -> void:
	visual.pivot_offset = visual.size * 0.5
	if counter_label != null:
		counter_label.pivot_offset = counter_label.size * 0.5


func _exit_tree() -> void:
	if is_instance_valid(player):
		stop_feedback()
