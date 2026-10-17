class_name EnemyPortal
extends Sprite2D

@export var energy_color: Color = Color("c091ff")
@export var smoke_gradient: Gradient = preload("res://resources/vfx/summon_portal/smoke_fade.tres")

@onready var swirl: CPUParticles2D = $Swirl
@onready var smoke: CPUParticles2D = $Smoke


func _ready() -> void:
	_apply_colors()


func configure_appearance(portal_texture: Texture2D, color: Color, gradient: Gradient) -> void:
	texture = portal_texture
	energy_color = color
	smoke_gradient = gradient
	_apply_colors()


func _apply_colors() -> void:
	swirl.color = energy_color
	smoke.color_ramp = smoke_gradient


func play_exit() -> void:
	# Один emitter на портал ограничивает дым при частом выходе пачек врагов.
	smoke.visible = true
	smoke.restart()


func reset_effects() -> void:
	# Первый портал переиспользуется при смене карты: старый дым не переносится.
	smoke.restart()
	smoke.emitting = false
	smoke.visible = false
