extends RefCounted


func run(scene: Node) -> Dictionary:
	var manager: SummonManager = scene.get_node("SummonManager")
	var drag: UnitDragController = scene.get_node("World/DragController")
	var slots: Array[Node] = scene.get_node("World/Slots").get_children()
	var viewport: Viewport = scene.get_viewport()
	assert(manager.try_summon() and manager.try_summon())
	var first: Archer = slots[0].unit
	var second: Archer = slots[1].unit
	# Разные уровни сохраняют проверку swap после появления merge одинаковых юнитов.
	second.promote()
	first._cooldown = 0.42
	second._cooldown = 0.37

	var transfers: int = 0
	for source: SummonSlot in slots:
		var current: SummonSlot = _slot_for(slots, first)
		if current != source:
			assert(manager.try_transfer(current, source, first))
		for destination: SummonSlot in slots:
			if source == destination:
				continue
			assert(manager.try_transfer(source, destination, first))
			_assert_field(slots, first, second)
			assert(manager.try_transfer(destination, source, first))
			transfers += 1
	assert(transfers == 30)
	assert(is_equal_approx(first._cooldown, 0.42) and is_equal_approx(second._cooldown, 0.37))
	assert(manager.mana == 55 and manager.current_cost() == 30)
	var reset_slot: SummonSlot = _slot_for(slots, first)
	if reset_slot != slots[0]:
		assert(manager.try_transfer(reset_slot, slots[0], first))
	reset_slot = _slot_for(slots, second)
	if reset_slot != slots[1]:
		assert(manager.try_transfer(reset_slot, slots[1], second))

	var reentry: Array[bool] = []
	slots[2].unit_host.child_entered_tree.connect(func(_child: Node) -> void:
		reentry.append(manager.try_transfer(slots[2], slots[3], first))
		reentry.append(manager.try_summon()), CONNECT_ONE_SHOT)
	assert(manager.try_transfer(slots[0], slots[2], first))
	assert(reentry == [false, false])
	assert(manager.try_transfer(slots[2], slots[0], first))
	assert(not manager.try_transfer(slots[0], slots[0], first))
	assert(not manager.try_transfer(slots[0], null, first))
	assert(not manager.try_transfer(slots[0], slots[3], second))

	_touch(viewport, 7, Vector2(180, 360), true)
	_motion_touch(viewport, 7, Vector2(540, 600))
	assert(drag._touch_index == 7 and drag.preview.visible and slots[3].highlight.visible)
	assert(slots[0].unit == first and first.global_position == slots[0].global_position)
	_touch(viewport, 9, Vector2(360, 1220), true)
	_motion_touch(viewport, 9, Vector2(180, 840))
	_touch(viewport, 9, Vector2(360, 1220), false)
	_mouse(viewport, Vector2(360, 1220), true, InputEvent.DEVICE_ID_EMULATION)
	_mouse(viewport, Vector2(360, 1220), false, InputEvent.DEVICE_ID_EMULATION)
	assert(drag._touch_index == 7 and drag.preview.global_position == Vector2(540, 600))
	assert(manager.occupied_count() == 2 and manager.mana == 55)
	_touch(viewport, 7, Vector2(540, 600), false)
	assert(slots[3].unit == first and slots[0].is_empty())
	_assert_cancelled(drag, slots, first)

	_touch(viewport, 7, Vector2(540, 600), true)
	_motion_touch(viewport, 7, Vector2(180, 840))
	_touch(viewport, 7, Vector2(180, 840), false, true)
	assert(slots[3].unit == first and slots[4].is_empty())
	_assert_cancelled(drag, slots, first)
	_touch(viewport, 7, Vector2(540, 600), true)
	_motion_touch(viewport, 7, Vector2(360, 700))
	_touch(viewport, 7, Vector2(360, 700), false)
	assert(slots[3].unit == first)
	_assert_cancelled(drag, slots, first)

	for notice: int in [Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT, Node.NOTIFICATION_WM_SIZE_CHANGED, Node.NOTIFICATION_WM_MOUSE_EXIT]:
		_mouse(viewport, Vector2(540, 600), true)
		_motion_mouse(viewport, Vector2(180, 840))
		assert(drag.preview.visible)
		drag._notification(notice)
		_mouse(viewport, Vector2(180, 840), false)
		assert(slots[3].unit == first)
		_assert_cancelled(drag, slots, first)
	_mouse(viewport, Vector2(540, 600), true)
	_motion_mouse(viewport, Vector2(180, 840))
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	viewport.push_input(escape, true)
	escape.pressed = false
	viewport.push_input(escape, true)
	_mouse(viewport, Vector2(180, 840), false)
	assert(slots[3].unit == first)
	_assert_cancelled(drag, slots, first)

	_touch(viewport, 7, Vector2(540, 600), true)
	_motion_touch(viewport, 7, Vector2(180, 360))
	scene.get_node("World/Tower").take_damage(100)
	_assert_cancelled(drag, slots, first)
	_touch(viewport, 7, Vector2(180, 360), false)
	assert(slots[3].unit == first and not manager.try_transfer(slots[3], slots[0], first))
	assert(manager.mana == 55 and manager.current_cost() == 30 and manager.occupied_count() == 2)
	_assert_field(slots, first, second)
	return {"passed": true, "ordered_slot_pairs": transfers, "reentry": reentry, "touch": true, "cancellation": true}


func _slot_for(slots: Array[Node], unit: Archer) -> SummonSlot:
	for slot: SummonSlot in slots:
		if slot.unit == unit:
			return slot
	return null


func _assert_field(slots: Array[Node], first: Archer, second: Archer) -> void:
	var found: Array[Archer] = []
	for slot: SummonSlot in slots:
		assert(slot.unit_host.get_child_count() == (0 if slot.is_empty() else 1))
		if not slot.is_empty():
			assert(slot.unit.get_parent() == slot.unit_host and slot.unit.position == Vector2.ZERO)
			assert(slot.unit.get_node("Visual").flip_h == slot.faces_left)
			found.append(slot.unit)
	assert(found.size() == 2 and found.has(first) and found.has(second))


func _assert_cancelled(drag: UnitDragController, slots: Array[Node], unit: Archer) -> void:
	assert(drag._pointer == UnitDragController.Pointer.NONE and not drag.preview.visible)
	assert(unit.modulate == Color.WHITE)
	for slot: SummonSlot in slots:
		assert(not slot.highlight.visible)


func _touch(viewport: Viewport, index: int, position: Vector2, pressed: bool, cancelled: bool = false) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = cancelled
	viewport.push_input(event, true)


func _motion_touch(viewport: Viewport, index: int, position: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = position
	viewport.push_input(event, true)


func _mouse(viewport: Viewport, position: Vector2, pressed: bool, device: int = InputEvent.DEVICE_ID_MOUSE) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.device = device
	viewport.push_input(event, true)


func _motion_mouse(viewport: Viewport, position: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(event, true)
