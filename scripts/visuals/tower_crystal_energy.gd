class_name TowerCrystalEnergy
extends Node2D

const BURST: GFFParticles = preload("res://resources/vfx/tower_energy/tap_burst.tres")

@onready var halo: Sprite2D = $Halo
@onready var idle_particles: CPUParticles2D = $IdleParticles
@onready var player: GFFPlayer = $GFFPlayer

var idle_enabled: bool = true
var _time: float = 0.0
var _tap_glow: float = 0.0
var _glow_tween: Tween


func _process(delta: float) -> void:
	_time += delta
	halo.modulate.a = (0.7 + 0.12 * sin(_time * 2.0) if idle_enabled else 0.0) + _tap_glow
	halo.scale = Vector2.ONE * 2.0 * (1.0 + 0.35 * _tap_glow)


func play_tap() -> void:
	if not is_visible_in_tree():
		return
	player.play(BURST.duplicate(true))
	if _glow_tween != null:
		_glow_tween.kill()
	_tap_glow = 0.8
	_glow_tween = create_tween()
	_glow_tween.tween_property(self, "_tap_glow", 0.0, 0.35)


func set_idle_enabled(enabled: bool) -> void:
	idle_enabled = enabled
	idle_particles.emitting = enabled
	idle_particles.visible = enabled
	if enabled:
		idle_particles.restart()
	else:
		stop_burst()


func stop_burst() -> void:
	player.stop()
	if _glow_tween != null:
		_glow_tween.kill()
	_tap_glow = 0.0


func _exit_tree() -> void:
	if is_instance_valid(player):
		stop_burst()
