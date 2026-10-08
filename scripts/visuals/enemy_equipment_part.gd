class_name EnemyEquipmentPart
extends Sprite2D

## Пять записей соответствуют Lv1–Lv5. null скрывает ещё не открывшуюся деталь.
@export var tier_textures: Array[Texture2D] = []


func apply_tier(tier: int, accent_color: Color) -> void:
	if tier_textures.is_empty():
		return
	var index: int = clampi(tier - 1, 0, tier_textures.size() - 1)
	var selected_texture: Texture2D = tier_textures[index]
	visible = selected_texture != null
	if selected_texture != null:
		texture = selected_texture
	# Материал local_to_scene общий для деталей одного врага, но не разных врагов.
	var accent_material: ShaderMaterial = material as ShaderMaterial
	if accent_material != null:
		accent_material.set_shader_parameter("accent_color", accent_color)
