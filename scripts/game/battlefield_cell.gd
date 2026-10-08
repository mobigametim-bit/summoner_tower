class_name BattlefieldCell
extends Node2D

@export var environment_texture: Texture2D

@onready var fill: Sprite2D = $Fill


func configure(_kind: int, center: Vector2, size: float, _alternate: bool) -> void:
	position = center
	fill.texture = environment_texture
	fill.scale = Vector2.ONE * size / 128.0
	fill.modulate = Color.WHITE
