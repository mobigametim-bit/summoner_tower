class_name UnitDragController
extends Node2D

enum Pointer { NONE, MOUSE, TOUCH }

@export_range(1.0, 64.0, 1.0) var drag_threshold: float = 12.0

@onready var preview: Node2D = $Preview
@onready var preview_visual: Sprite2D = $Preview/Visual

var _manager: SummonManager
var _return_zone: UnitReturnZone
var _slots: Array[SummonSlot] = []
var _enabled: bool = false
var _pointer: Pointer = Pointer.NONE
var _touch_index: int = -1
var _source: SummonSlot
var _unit: CombatUnit
var _press_position: Vector2
var _grab_offset: Vector2
var _original_modulate: Color
var _dragging: bool = false
var _web_canvas: JavaScriptObject
var _web_touch_cancel: JavaScriptObject


func _ready() -> void:
	if OS.has_feature("web"):
		_web_canvas = JavaScriptBridge.get_interface("document").getElementById("canvas")
		_web_touch_cancel = JavaScriptBridge.create_callback(_on_web_touch_cancel)
		# Web-шаблон 4.7.2 превращает touchcancel в release: отменяем жест до обработчика движка.
		_web_canvas.addEventListener("touchcancel", _web_touch_cancel, true)


func _exit_tree() -> void:
	if _web_canvas != null:
		_web_canvas.removeEventListener("touchcancel", _web_touch_cancel, true)


func _on_web_touch_cancel(arguments: Array) -> void:
	if _pointer != Pointer.TOUCH:
		return
	var touches: JavaScriptObject = arguments[0].changedTouches
	for index: int in int(touches.length):
		if int(touches.item(index).identifier) == _touch_index:
			cancel_drag()
			return


func configure(manager: SummonManager, slots: Node2D, return_zone: UnitReturnZone) -> void:
	_manager = manager
	_return_zone = return_zone
	for child: Node in slots.get_children():
		_slots.append(child as SummonSlot)
	_enabled = true


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled or _pointer != Pointer.NONE or not _manager.can_rearrange():
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			_begin(event.position, Pointer.TOUCH, event.index)
	elif event is InputEventMouseButton:
		if event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin(event.position, Pointer.MOUSE)


func _input(event: InputEvent) -> void:
	if _pointer == Pointer.NONE:
		return
	if not is_instance_valid(_unit) or _source.unit != _unit:
		cancel_drag()
		return
	if event.is_action_pressed("cancel_drag"):
		cancel_drag()
		get_viewport().set_input_as_handled()
		return

	# Захват продолжается над UI и вне слотов; второй указатель не вызывает действий.
	if event is InputEventScreenTouch:
		if _pointer == Pointer.TOUCH and event.index == _touch_index:
			if event.canceled:
				cancel_drag()
			elif not event.pressed:
				_finish(event.position)
	elif event is InputEventScreenDrag:
		if _pointer == Pointer.TOUCH and event.index == _touch_index:
			_update_drag(event.position)
	elif event is InputEventMouseMotion:
		if _pointer == Pointer.MOUSE and event.device != InputEvent.DEVICE_ID_EMULATION:
			_update_drag(event.position)
	elif event is InputEventMouseButton:
		if _pointer == Pointer.MOUSE and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish(event.position)
	else:
		return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_WM_SIZE_CHANGED:
		cancel_drag()
	elif what == NOTIFICATION_WM_MOUSE_EXIT and _pointer == Pointer.MOUSE:
		cancel_drag()


func _begin(viewport_position: Vector2, pointer: Pointer, touch_index: int = -1) -> void:
	var world_position: Vector2 = _world_position(viewport_position)
	var slot: SummonSlot = _slot_at(world_position)
	if slot == null or slot.is_empty():
		return
	_source = slot
	_unit = slot.unit
	_pointer = pointer
	_touch_index = touch_index
	_press_position = world_position
	_grab_offset = slot.global_position - world_position
	_original_modulate = _unit.modulate
	preview_visual.texture = _unit.get_node("Visual").texture
	preview_visual.flip_h = slot.faces_left
	get_viewport().set_input_as_handled()


func _update_drag(viewport_position: Vector2) -> void:
	var world_position: Vector2 = _world_position(viewport_position)
	if not _dragging and world_position.distance_squared_to(_press_position) < drag_threshold ** 2:
		return
	_dragging = true
	preview.show()
	preview.global_position = world_position + _grab_offset
	_unit.modulate = Color(_original_modulate, 0.45)
	var destination: SummonSlot = _slot_at(world_position)
	if destination != null:
		preview_visual.flip_h = destination.faces_left
	for slot: SummonSlot in _slots:
		var merging: bool = slot != _source and not slot.is_empty() and _unit.can_merge_with(slot.unit)
		slot.set_drop_highlight(slot == destination and slot != _source, merging)
	_return_zone.set_preview(true, _return_zone.contains_point(world_position), _manager.refund_amount(_unit))


func _finish(viewport_position: Vector2) -> void:
	_update_drag(viewport_position)
	var source: SummonSlot = _source
	var unit: CombatUnit = _unit
	var world_position: Vector2 = _world_position(viewport_position)
	var returning: bool = _dragging and _return_zone.contains_point(world_position)
	var destination: SummonSlot = _slot_at(world_position) if _dragging else null
	cancel_drag()
	if returning:
		_manager.try_refund(source, unit)
	elif destination != null:
		_manager.try_transfer(source, destination, unit)


func cancel_drag() -> void:
	if is_instance_valid(_unit):
		_unit.modulate = _original_modulate
	if is_instance_valid(preview):
		preview.hide()
	for slot: SummonSlot in _slots:
		slot.set_drop_highlight(false)
	if is_instance_valid(_return_zone):
		_return_zone.set_preview(false)
	_pointer = Pointer.NONE
	_touch_index = -1
	_source = null
	_unit = null
	_dragging = false


func stop() -> void:
	_enabled = false
	cancel_drag()


func _slot_at(world_position: Vector2) -> SummonSlot:
	for slot: SummonSlot in _slots:
		if slot.contains_point(world_position):
			return slot
	return null


func _world_position(viewport_position: Vector2) -> Vector2:
	return to_global(get_global_transform_with_canvas().affine_inverse() * viewport_position)
