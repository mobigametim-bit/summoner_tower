@tool
class_name ButtonFeedback
extends Control

const PRESS: GFFTween = preload("res://resources/ui/feedback/button_press.tres")
const HOVER: GFFTween = preload("res://resources/ui/feedback/button_hover.tres")

@export var normal_style: StyleBox
@export var hover_style: StyleBox
@export var pressed_style: StyleBox
@export var disabled_style: StyleBox
@export var focus_style: StyleBox
@export var icon: Texture2D
@export var icon_width: float = 48.0

var hover_amount: float = 0.0:
	set(value):
		hover_amount = clampf(value, 0.0, 1.0)
		queue_redraw()

@onready var player: GFFPlayer = $GFFPlayer

var _button: Button
var _blended_style: StyleBoxFlat
var _touch_input: bool = false
var _hover_effect: GFFTween


func _ready() -> void:
	_button = get_parent() as Button
	resized.connect(_update_pivot)
	_update_pivot()
	if Engine.is_editor_hint() or _button == null:
		return
	_button.button_down.connect(_on_button_down)
	_button.button_up.connect(queue_redraw)
	_button.mouse_entered.connect(_on_mouse_entered)
	_button.mouse_exited.connect(_on_mouse_exited)
	_button.gui_input.connect(_on_gui_input)
	_button.draw.connect(queue_redraw)
	_button.visibility_changed.connect(_on_visibility_changed)


func _draw() -> void:
	var style: StyleBox = normal_style
	if _button != null and _button.disabled:
		style = disabled_style
	elif _button != null and _button.is_pressed():
		style = pressed_style
	elif normal_style is StyleBoxFlat and hover_style is StyleBoxFlat:
		if _blended_style == null:
			_blended_style = normal_style.duplicate() as StyleBoxFlat
		_blended_style.bg_color = (normal_style as StyleBoxFlat).bg_color.lerp((hover_style as StyleBoxFlat).bg_color, hover_amount)
		style = _blended_style
	elif hover_amount > 0.5:
		style = hover_style
	if style != null:
		draw_style_box(style, Rect2(Vector2.ZERO, size))
	if icon != null:
		var icon_size: Vector2 = icon.get_size() * icon_width / maxf(icon.get_width(), 1.0)
		var tint: Color = Color.WHITE
		if _button != null and _button.disabled:
			tint = _button.get_theme_color("icon_disabled_color")
		draw_texture_rect(icon, Rect2((size - icon_size) * 0.5, icon_size), false, tint)
	if _button != null and _button.has_focus() and focus_style != null:
		draw_style_box(focus_style, Rect2(Vector2.ZERO, size))


func _on_button_down() -> void:
	if _button.disabled:
		return
	player.play(PRESS.duplicate(true))
	queue_redraw()


func _on_mouse_entered() -> void:
	if not _touch_input:
		_set_hover(true)


func _on_mouse_exited() -> void:
	_set_hover(false)


func _set_hover(hovered: bool) -> void:
	if _button.disabled:
		hovered = false
	var value: float = 1.0 if hovered else 0.0
	# Keep the live tween so rapid enter/leave can cancel it without deferred stack callbacks.
	if _hover_effect != null:
		_hover_effect.stop()
	_hover_effect = HOVER.duplicate(true) as GFFTween
	_hover_effect.apply(self, GFFParams.from_dict({"value": value}))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION):
		_touch_input = true
		if _hover_effect != null:
			_hover_effect.stop()
		hover_amount = 0.0
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _touch_input:
			_touch_input = false
			_set_hover(true)


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _on_visibility_changed() -> void:
	if not _button.is_visible_in_tree():
		stop_feedback()


func stop_feedback() -> void:
	player.stop()
	if _hover_effect != null:
		_hover_effect.stop()
	scale = Vector2.ONE
	hover_amount = 0.0


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and is_instance_valid(player):
		stop_feedback()
