class_name UndeadEnemyVisual
extends Node2D

signal attack_impact
signal effect_requested(effect_name: StringName)
signal visual_animation_finished(animation_name: StringName)

@export var entity_key: StringName
@export var level_ids: PackedInt32Array = PackedInt32Array([1, 2, 3, 4, 5])
@export var level: int = 1
@export var part_variants: Dictionary[StringName, Array] = {}
@export var part_paths: Dictionary[StringName, NodePath] = {}
@export var ability_levels: Dictionary[StringName, int] = {}

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var effects: Node2D = $AbilityEffects

var _parts: Dictionary[StringName, Sprite2D] = {}
var _active_animation: StringName = &"walk_loop"
var _finished: bool = false


func _ready() -> void:
	for part: StringName in part_paths:
		_parts[part] = get_node(part_paths[part]) as Sprite2D
	set_level(level)
	play_animation(&"walk_loop")
	animation_player.animation_finished.connect(_on_animation_finished)


func set_level(value: int) -> void:
	var index: int = level_ids.find(value)
	if index < 0:
		index = 0
	level = level_ids[index]
	for part: StringName in _parts:
		var variants: Array = part_variants[part]
		var texture: Texture2D = variants[index] as Texture2D
		_parts[part].texture = texture
		_parts[part].visible = texture != null


func available_animations() -> Array[StringName]:
	var result: Array[StringName] = [&"walk_loop", &"attack", &"hit", &"death", &"spawn_or_intro"]
	for clip: StringName in ability_levels:
		if level >= ability_levels[clip]:
			result.append(clip)
	return result


func play_animation(animation_name: StringName) -> void:
	if not animation_player.has_animation(animation_name) or animation_name == &"RESET":
		return
	effects.call("stop_effects")
	animation_player.stop()
	animation_player.play(&"RESET")
	animation_player.advance(0.0)
	_active_animation = animation_name
	_finished = false
	animation_player.play(animation_name)
	animation_player.advance(0.0)


func set_playback_speed(multiplier: float) -> void:
	animation_player.speed_scale = multiplier
	effects.call("set_speed", multiplier)


func set_animation_paused(paused: bool) -> void:
	if paused:
		animation_player.pause()
	elif not _finished:
		animation_player.play()
	effects.call("set_paused", paused)


func _emit_effect(effect_name: StringName) -> void:
	# Visual-only event. No healing, summons, movement or damage is applied here.
	if effect_name == &"impact":
		attack_impact.emit()
	effect_requested.emit(effect_name)
	effects.call("play_effect", effect_name)


func _on_animation_finished(animation_name: StringName) -> void:
	_finished = true
	visual_animation_finished.emit(animation_name)


func _exit_tree() -> void:
	if is_instance_valid(effects):
		effects.call("stop_effects")
