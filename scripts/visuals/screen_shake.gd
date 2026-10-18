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
var _field_rect: Rect2
var _hud: GameHud


func configure_field(rect: Rect2, hud: GameHud) -> void:
	_field_rect = rect
	_hud = hud
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	if not get_viewport().size_changed.is_connected(_request_layout):
		get_viewport().size_changed.connect(_request_layout)
	_layout_field()


func _request_layout() -> void:
	_layout_field.call_deferred()


func _layout_field() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	var game: Node = get_parent()
	if game.get("drag_controller") != null:
		game.drag_controller.cancel_drag()
	stop_shake()
	var regions: Dictionary = ScreenLayout.battle_regions()
	var area: Rect2 = regions.field
	var factor: float = minf(area.size.x/_field_rect.size.x, area.size.y/_field_rect.size.y)
	zoom = Vector2.ONE*factor
	position = _field_rect.get_center()-(area.get_center()-get_viewport_rect().size*0.5)/factor
	force_update_scroll()
	var displayed: Rect2 = Rect2(area.get_center()-_field_rect.size*factor*0.5, _field_rect.size*factor)
	_hud.configure_layout(displayed, regions.hud, regions.side)


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
