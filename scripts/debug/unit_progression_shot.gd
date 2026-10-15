extends Node2D

signal landed(target: int, special: bool)

@onready var sprite: Sprite2D = $Sprite
@onready var trail: CPUParticles2D = $Trail

var _flight: Tween


func launch(texture: Texture2D, start: Vector2, finish: Vector2, target: int, special: bool = false, meteor: bool = false, trace: bool = false) -> void:
	position = start
	sprite.texture = texture
	rotation = (finish - start).angle()
	if meteor:
		sprite.scale = Vector2(1.8, 1.8)
		trail.show()
		trail.emitting = true
	elif trace:
		trail.texture = preload("res://assets/vfx/energy_spark.svg")
		trail.color = Color("ffdb84")
		trail.amount = 8
		trail.lifetime = 0.16
		trail.scale_amount_min = 0.1
		trail.scale_amount_max = 0.16
		trail.show()
		trail.emitting = true
	_flight = create_tween()
	_flight.tween_property(self, "position", finish, 0.45 if meteor else 0.22)
	_flight.tween_callback(func() -> void:
		landed.emit(target, special)
		queue_free())


func _exit_tree() -> void:
	if _flight != null:
		_flight.kill()
