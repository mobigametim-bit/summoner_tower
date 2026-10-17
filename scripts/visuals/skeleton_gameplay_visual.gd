extends "res://scripts/visuals/undead_enemy_visual.gd"
## Adapts the accepted cutout rig to ApproachingEnemy; never applies damage.

const IMPACT_TIME: float = 0.28
const CANVAS_SIZE: float = 104.0

@export var shield_scene: PackedScene
@export var shield_config: SkeletonShieldConfig
var _gameplay: bool = false
var _preparing: bool = false
var _tail: bool = false
var _impact_emitted: bool = false
var _shield: Node2D


func enable_gameplay() -> void:
	_gameplay = true
	_tail = false
	_preparing = false
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	set_playback_speed(1.0)
	play_animation(&"spawn_or_intro")


func set_difficulty(tier: int, _equipment_color: Color) -> void:
	set_level(tier)
	var fallback: Sprite2D = get_parent().get_node_or_null("Visual") as Sprite2D
	if fallback != null:
		fallback.texture = load("res://art/source/skeleton/master_lv%d.svg"%level)
		fallback.modulate = Color.WHITE


func advance_gameplay(delta: float, time_to_contact: float, direction: Vector2) -> void:
	if absf(direction.x) > 0.001:
		scale = Vector2(-1.0 if direction.x < 0 else 1.0,1.0)*(CANVAS_SIZE/256.0)
	if time_to_contact <= IMPACT_TIME:
		if not _preparing:
			play_animation(&"attack")
			_impact_emitted = false
			_preparing = true
		animation_player.seek(clampf(IMPACT_TIME-time_to_contact,0.0,IMPACT_TIME-0.0001),true,true)
	elif _preparing:
		_preparing = false
		play_animation(&"walk_loop")
	else:
		animation_player.advance(delta)


func impact_now() -> void:
	if not _preparing:
		play_animation(&"attack")
		_impact_emitted = false
	_preparing = false
	animation_player.seek(IMPACT_TIME,true,true)
	_emit_effect(&"impact")


func _emit_effect(effect_name: StringName) -> void:
	if _gameplay and effect_name == &"impact":
		if _impact_emitted:
			return
		_impact_emitted = true
	super._emit_effect(effect_name)


func show_hit() -> void:
	if not _preparing and _active_animation != &"hit":
		play_animation(&"hit")


func play_ability(_ability: StringName) -> void:
	# Passive shield has its own lifetime and must not interrupt walk or attack.
	pass


func set_shield_active(active: bool) -> void:
	if is_instance_valid(_shield):
		_shield.queue_free()
	_shield = null
	if not active or not visible:
		return
	_shield = shield_scene.instantiate() as Node2D
	add_child(_shield)
	_shield.z_index = 30
	var duration: float = (_shield.get_node("AnimationPlayer") as AnimationPlayer).get_animation(&"effect").length
	_shield.call("start",duration/shield_config.duration)


func finish_as_tail(killed: bool) -> void:
	_tail = true
	_preparing = false
	set_shield_active(false)
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	set_playback_speed(1.0)
	if killed:
		play_animation(&"death")
	else:
		animation_player.play()


func stop_gameplay() -> void:
	_preparing = false
	animation_player.stop()
	effects.call("stop_effects")
	set_shield_active(false)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"RESET":
		return
	super._on_animation_finished(animation_name)
	if _tail:
		queue_free()
	elif _gameplay and animation_name != &"death":
		play_animation(&"walk_loop")
