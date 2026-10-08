extends Node2D

@onready var enemy: GoblinVisual = $Enemy
@onready var smoke: CPUParticles2D = $Smoke
@onready var swirl: CPUParticles2D = $Swirl

var requests: int = 0
var _exit_tween: Tween


func _ready() -> void:
	# Демонстрация использует свои emitters, чтобы не удвоить внедрённый эффект.
	var portal_swirl: CPUParticles2D = $Portal/Swirl
	portal_swirl.emitting = false
	portal_swirl.visible = false


func exit_portal() -> void:
	requests += 1
	if _exit_tween != null:
		_exit_tween.kill()
	enemy.visible = true
	enemy.position = Vector2(0.0, 10.0)
	enemy.modulate.a = 0.0
	enemy.scale = Vector2.ONE * (GoblinVisual.GAMEPLAY_CANVAS_SIZE / 256.0)
	enemy.play_animation(&"walk_loop")
	smoke.restart()
	_exit_tween = create_tween().set_parallel(true)
	_exit_tween.tween_property(enemy, "modulate:a", 1.0, 0.25)
	_exit_tween.tween_property(enemy, "position", Vector2(80.0, 25.0), 1.1)


func _exit_tree() -> void:
	if _exit_tween != null:
		_exit_tween.kill()
