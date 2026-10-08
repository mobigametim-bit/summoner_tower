class_name EnemyPortal
extends Sprite2D

@onready var swirl: CPUParticles2D = $Swirl
@onready var smoke: CPUParticles2D = $Smoke


func play_exit() -> void:
	# Один emitter на портал ограничивает дым при частом выходе пачек врагов.
	smoke.visible = true
	smoke.restart()


func reset_effects() -> void:
	# Первый портал переиспользуется при смене карты: старый дым не переносится.
	smoke.restart()
	smoke.emitting = false
	smoke.visible = false
