extends Node

var _pending_resize: bool = false

# Меняем только виртуальный экран; Web-шаблон по-прежнему ограничивает render buffer.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size_changed.connect(_request_resize)
	_resize()


func _request_resize() -> void:
	if _pending_resize:
		return
	_pending_resize = true
	_resize.call_deferred()


func _resize() -> void:
	# size_changed испускается внутри обновления Window. Повторный вход ломает stretch rect.
	_pending_resize = false
	var window: Window = get_window()
	var physical: Vector2i = window.size
	if physical.x <= 0 or physical.y <= 0:
		return
	var logical: Vector2i = Vector2i(720, 1280)
	if physical.x > physical.y:
		logical = Vector2i(roundi(720.0 * physical.x / physical.y), 720)
	if window.content_scale_size != logical:
		window.content_scale_size = logical


func landscape() -> bool:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return size.x > size.y


func battle_regions() -> Dictionary:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if landscape() and size.x / size.y >= 1.6:
		return {"field":Rect2(0,0,size.x-200,size.y), "hud":Rect2(size.x-200,0,200,size.y), "side":true}
	if landscape():
		var height: float = maxf(80.0, size.y - size.x * 2.0 / 3.0)
		return {"field":Rect2(0,height,size.x,size.y-height), "hud":Rect2(0,0,size.x,height), "side":false}
	return {"field":Rect2(0,0,size.x,1080), "hud":Rect2(0,1080,size.x,size.y-1080), "side":false}
