class_name SummonSlot
extends Node2D

@export_range(1, 15, 1) var slot_index: int = 1
@export var faces_left: bool = false
@export var hit_rect: Rect2 = Rect2(-70.0, -70.0, 140.0, 140.0)

@onready var unit_host: Node2D = $UnitHost
@onready var highlight: Sprite2D = $Highlight
@onready var summon_rays: CPUParticles2D = $SummonRays

var unit: CombatUnit


func fit_to_cell(size: float) -> void:
	clear_summon_effect()
	hit_rect = Rect2(-Vector2.ONE * size * 0.5, Vector2.ONE * size)
	$Visual.scale = Vector2.ONE * size / 140.0
	highlight.scale = $Visual.scale
	unit_host.scale = Vector2.ONE * minf((size - 12.0) / 100.0, 1.0)
	# Ступни стоят на верхней плоскости постамента; зона переноса остаётся всей клеткой.
	unit_host.position.y = 26.0 * size / 140.0 - 42.0 * unit_host.scale.y
	summon_rays.scale = unit_host.scale
	summon_rays.position = unit_host.position + Vector2(0.0, 44.0) * unit_host.scale


func is_empty() -> bool:
	return not is_instance_valid(unit)


func place_unit(creature: CombatUnit) -> bool:
	if not is_empty() or not is_instance_valid(creature):
		return false

	assign_unit(creature)
	unit_host.add_child(unit)
	align_unit()
	return true


func assign_unit(creature: CombatUnit) -> void:
	clear_summon_effect()
	unit = creature


func play_summon_effect() -> void:
	if is_empty():
		return
	summon_rays.visible = true
	summon_rays.restart()
	unit.modulate.a = 0.0
	# Tween принадлежит бойцу и прекращается при продаже или удалении карты.
	var reveal: Tween = unit.create_tween()
	reveal.tween_interval(0.1)
	reveal.tween_property(unit, "modulate:a", 1.0, 0.3)


func clear_summon_effect() -> void:
	summon_rays.emitting = false
	summon_rays.visible = false


func align_unit() -> void:
	if not is_empty():
		unit.position = Vector2.ZERO
		unit.set_facing_left(faces_left)


func contains_point(world_position: Vector2) -> bool:
	return hit_rect.has_point(to_local(world_position))


func set_drop_highlight(enabled: bool, merging: bool = false) -> void:
	highlight.visible = enabled
	highlight.modulate = Color("ffc45c") if merging else Color("82e9ed")
