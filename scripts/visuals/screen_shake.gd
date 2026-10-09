class_name ScreenShake
extends Camera2D

@export var wave_config: WaveConfig
@export var tower_hit_effect: GFFCameraShake
@export var boss_intro_effect: GFFCameraShake
@export var strong_hit_minimum_damage: int = 20

@onready var player: GFFPlayer = $GFFPlayer

var _last_health: int = -1
var _last_boss_wave: int = 0
var _fighting: bool = false


func _on_wave_state_changed(wave: int, phase: WaveManager.Phase, _seconds: int, _alive: int, _pending: int) -> void:
	_fighting = phase == WaveManager.Phase.FIGHTING
	if not _fighting:
		stop_shake()
	elif wave_config != null and wave_config.is_boss_wave(wave) and wave != _last_boss_wave:
		_last_boss_wave = wave
		_play_shake(boss_intro_effect)


func _on_tower_health_changed(current: int, _maximum: int) -> void:
	var damage: int = _last_health - current
	_last_health = current
	if _fighting and damage >= strong_hit_minimum_damage:
		_play_shake(tower_hit_effect)


func _play_shake(effect: GFFCameraShake) -> void:
	if effect == null or get_tree().paused:
		return
	# Один эффект на камеру: исходный offset следующего импульса всегда нулевой.
	stop_shake()
	player.play(effect.duplicate(true))
	force_update_scroll()


func stop_shake() -> void:
	if is_instance_valid(player):
		player.stop()
	offset = Vector2.ZERO
	if is_inside_tree():
		force_update_scroll()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		stop_shake()


func _exit_tree() -> void:
	stop_shake()
