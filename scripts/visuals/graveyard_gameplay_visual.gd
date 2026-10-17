extends "res://scripts/visuals/skeleton_gameplay_visual.gd"

@export var regeneration_scene: PackedScene
var _regeneration: Node2D


func _shield_lifetime() -> float:
	return (get_parent().get("abilities") as GraveyardAbilities).undead_config.shield_duration


func set_difficulty(tier: int, _equipment_color: Color) -> void:
	set_level(tier)
	var fallback: Sprite2D = get_parent().get_node_or_null("Visual") as Sprite2D
	if fallback != null:
		fallback.texture = load("res://art/source/%s/master_lv%d.svg"%[entity_key,level])
		fallback.modulate = Color.WHITE


func play_ability(ability: StringName) -> void:
	if not _preparing and not _tail and animation_player.has_animation(ability):
		play_animation(ability)


func show_hit() -> void:
	if _active_animation in ability_levels and not _finished:
		return
	super.show_hit()


func _emit_effect(effect_name: StringName) -> void:
	# Healing/summons use actual world targets. Preview offsets must never leak into battle.
	if _gameplay and effect_name in [&"heal",&"summon_skeletons",&"assemble_flesh",&"flesh_arrives",&"retinue",&"regenerate",&"bone_cover"]:
		effect_requested.emit(effect_name)
		return
	super._emit_effect(effect_name)


func show_regeneration(duration: float) -> void:
	if is_instance_valid(_regeneration):
		_regeneration.queue_free()
	_regeneration = regeneration_scene.instantiate() as Node2D
	add_child(_regeneration)
	_regeneration.z_index = 30
	var length: float = (_regeneration.get_node("AnimationPlayer") as AnimationPlayer).get_animation(&"effect").length
	_regeneration.call("start",length/duration)


func _clear_regeneration() -> void:
	if is_instance_valid(_regeneration):
		_regeneration.queue_free()
	_regeneration = null


func finish_as_tail(killed: bool) -> void:
	_clear_regeneration()
	super.finish_as_tail(killed)


func stop_gameplay() -> void:
	_clear_regeneration()
	super.stop_gameplay()
