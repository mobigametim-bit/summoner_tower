class_name TowerHealth
extends Node2D

signal health_changed(current: int, maximum: int)
signal destroyed
signal summon_requested

@export var animated_visual_enabled: bool = true

@onready var summon_button: Button = $SummonButton
@onready var cost_label: Label = $CostLabel
@onready var static_visual: Sprite2D = $Visual
@onready var tower_visual: TowerVisual = $TowerVisual

var current_health: int = 0
var max_health: int = 0
var _is_destroyed: bool = false


func _ready() -> void:
	set_animated_visual(animated_visual_enabled)


func set_animated_visual(enabled: bool) -> void:
	animated_visual_enabled = enabled
	static_visual.visible = not enabled
	tower_visual.visible = enabled
	if enabled:
		# Tint относится только к SVG частям, а цена остаётся независимой.
		modulate = Color.WHITE
		tower_visual.set_playback_speed(1.0)
		tower_visual.play_animation(&"destroyed" if _is_destroyed else &"crystal_pulse")
		tower_visual.set_animation_paused(false)
	else:
		tower_visual.set_animation_paused(true)
		modulate = Color(0.45, 0.45, 0.45) if _is_destroyed else Color.WHITE
	_align_cost_label()


func _align_cost_label() -> void:
	var bottom: Vector2
	if animated_visual_enabled:
		bottom = to_local(tower_visual.to_global(Vector2(0.0, TowerVisual.BASE_BOTTOM_Y - TowerVisual.CANVAS_SIZE * 0.5)))
	else:
		bottom = to_local(static_visual.to_global(Vector2(0.0, static_visual.get_rect().end.y)))
	var font: Font = cost_label.get_theme_font("font")
	var font_size: int = cost_label.get_theme_font_size("font_size")
	var outline: int = cost_label.get_theme_constant("outline_size")
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# У цифр нет descenders: компенсируем запас шрифта и учитываем нижнюю обводку.
	cost_label.position.y = bottom.y - cost_label.size.y + font.get_descent(font_size) - float(outline)


func fit_to_cell(size: float, field_center_x: float) -> void:
	$Visual.scale = Vector2.ONE * size / 182.0
	$Visual.position = Vector2.ZERO
	tower_visual.scale = Vector2.ONE * size / TowerVisual.CANVAS_SIZE
	tower_visual.position = Vector2.ZERO
	$ContactPoint.position = Vector2.ZERO
	summon_button.position = -Vector2.ONE * size * 0.5
	summon_button.size = Vector2.ONE * size
	cost_label.position.x = -size * 0.5
	cost_label.size = Vector2(size, 34.0)
	cost_label.add_theme_font_size_override("font_size", 28)
	_align_cost_label()
	var zone: UnitReturnZone = $ReturnZone
	zone.hit_rect = Rect2(-Vector2.ONE * size * 0.5, Vector2.ONE * size)
	zone.highlight.scale = Vector2.ONE * size / 200.0
	zone.highlight.position = Vector2.ZERO
	zone.refund_label.position = Vector2(field_center_x - global_position.x - 180.0, -size * 0.5 - 40.0)


func initialize(health: int) -> void:
	max_health = maxi(health, 1)
	current_health = max_health
	_is_destroyed = false
	modulate = Color.WHITE
	set_animated_visual(animated_visual_enabled)
	health_changed.emit(current_health, max_health)


func take_damage(amount: int) -> void:
	if _is_destroyed or amount <= 0:
		return

	current_health = maxi(current_health - amount, 0)
	_is_destroyed = current_health == 0
	if animated_visual_enabled:
		if _is_destroyed:
			tower_visual.show_destroyed()
		else:
			tower_visual.show_hit()
	elif _is_destroyed:
		modulate = Color(0.45, 0.45, 0.45)
	health_changed.emit(current_health, max_health)
	if _is_destroyed:
		destroyed.emit()


func increase_max_health(health: int) -> void:
	if _is_destroyed or health <= max_health:
		return
	current_health += health - max_health
	max_health = health
	health_changed.emit(current_health, max_health)


func update_summon(_mana: int, cost: int, _occupied: int, _capacity: int, available: bool) -> void:
	cost_label.text = str(cost)
	summon_button.disabled = not available
	cost_label.modulate = Color.WHITE if available else Color("7c8999")


func _on_summon_button_pressed() -> void:
	if animated_visual_enabled and not _is_destroyed and not summon_button.disabled:
		tower_visual.show_tap()
	summon_requested.emit()


func _on_unit_refunded(_amount: int) -> void:
	if animated_visual_enabled and not _is_destroyed:
		tower_visual.show_refund()
