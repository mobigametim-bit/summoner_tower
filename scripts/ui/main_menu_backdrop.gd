extends Node2D

const DESIGN_WIDTH: float = 720.0

@onready var tower: Node2D = $Tower
@onready var landscape_layout: Node2D = $LandscapeLayout

@export var portrait_only_paths: Array[NodePath] = []

var _portrait_poses: Dictionary[Node2D,Transform2D] = {}
var _portrait_visibility: Dictionary[CanvasItem,bool] = {}
var _landscape_bounds: Rect2


func _ready() -> void:
	var outline: PackedVector2Array = $LandscapeLayout/Ground.polygon
	_landscape_bounds = Rect2(outline[0],Vector2.ZERO)
	for point: Vector2 in outline:
		_landscape_bounds = _landscape_bounds.expand(point)
	# Две расстановки используют те же живые visual/VFX, а не копии персонажей.
	for pose: Marker2D in $LandscapeLayout/Poses.get_children():
		var node: Node2D = get_node(pose.get_meta("target")) as Node2D
		_portrait_poses[node] = node.transform
	for path: NodePath in portrait_only_paths:
		var node: CanvasItem = get_node(path) as CanvasItem
		_portrait_visibility[node] = node.visible
	var menu: Control = get_parent() as Control
	if menu != null:
		menu.resized.connect(_center_in_menu)
		_center_in_menu()


func _center_in_menu() -> void:
	var menu: Control = get_parent() as Control
	var horizontal: bool = ScreenLayout.landscape()
	landscape_layout.visible = horizontal
	for node: CanvasItem in _portrait_visibility:
		node.visible = not horizontal and _portrait_visibility[node]
	if horizontal:
		var factor: float = minf(DESIGN_WIDTH,menu.size.x-380.0)/DESIGN_WIDTH
		scale = Vector2.ONE*factor
		var center_x: float = (menu.size.x-142.0)*0.5
		position = Vector2(center_x-_landscape_bounds.get_center().x*factor,(menu.size.y-720.0*factor)*0.5)
		for pose: Marker2D in $LandscapeLayout/Poses.get_children():
			var node: Node2D = get_node(pose.get_meta("target")) as Node2D
			node.transform = pose.transform
	else:
		scale = Vector2.ONE
		position = Vector2((menu.size.x-DESIGN_WIDTH)*0.5,0)
		for node: Node2D in _portrait_poses:
			node.transform = _portrait_poses[node]


func landscape_rect() -> Rect2:
	return get_global_transform()*_landscape_bounds


func _on_energy_pulse() -> void:
	tower.call("show_tap")
