extends Control

@onready var panel: Control = $Panel
var _pending: bool = false


func _ready() -> void:
	resized.connect(_request_fit)
	panel.minimum_size_changed.connect(_request_fit)
	get_parent().visibility_changed.connect(_request_fit)
	_request_fit()


func _request_fit() -> void:
	if _pending:
		return
	_pending = true
	_fit.call_deferred()


func _fit() -> void:
	_pending = false
	if not is_inside_tree():
		return
	panel.reset_size()
	var factor: float = minf(1.0, minf((size.x-40.0)/maxf(panel.size.x,1), (size.y-40.0)/maxf(panel.size.y,1)))
	panel.scale = Vector2.ONE * maxf(factor,0.1)
	panel.position = (size-panel.size*panel.scale)*0.5
