class_name Battlefield
extends Node2D

@export var config: BattlefieldConfig
@export var slot_scene: PackedScene
@export var decoration_scene: PackedScene
@export var cell_scene: PackedScene
@export var portal_scene: PackedScene
@export var branch_scene: PackedScene

@onready var route: Path2D = $EnemyRoute
@onready var road_edge: Line2D = $RoadEdge
@onready var road_surface: Line2D = $RoadSurfaces/RoadSurface
@onready var road_surfaces: Node2D = $RoadSurfaces
@onready var decorations: Node2D = $Decorations
@onready var cells: Node2D = $Cells
@onready var portal: EnemyPortal = $Portal
@onready var branches: Node2D = $Branches
@onready var portals: Node2D = $Portals

var layout: BattlefieldLayout
var routes: Array[Path2D] = []


func build(slots: Node2D, spawn: Marker2D, tower: TowerHealth, columns: int, seed_value: int = -1, slot_override: int = 0, portal_override: int = 0) -> void:
	if seed_value < 0:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		seed_value = int(rng.randi())
	layout = BattlefieldGenerator.new(config).generate(seed_value, columns, slot_override, portal_override)
	route.curve = layout.curve
	route.set_meta("cell_size", layout.cell_size)
	spawn.global_position = to_global(layout.cell_center(layout.road_cells[0]))
	portal.position = layout.cell_center(layout.road_cells[0])
	portal.scale = Vector2.ONE * (layout.cell_size - config.cell_gap) / 128.0
	portal.reset_effects()
	tower.global_position = to_global(layout.cell_center(layout.road_cells[-1]))
	tower.fit_to_cell(layout.cell_size - config.cell_gap, config.playable_rect.get_center().x)
	for old: Node in cells.get_children():
		old.free()
	for y: int in layout.grid_size.y:
		for x: int in layout.grid_size.x:
			var cell: Vector2i = Vector2i(x, y)
			var instance: BattlefieldCell = cell_scene.instantiate() as BattlefieldCell
			cells.add_child(instance)
			instance.configure(layout.cell_type(cell), layout.cell_center(cell), layout.cell_size, (x + y) % 2 == 1)
	road_edge.width = layout.cell_size * 0.70
	road_surface.width = layout.cell_size * 0.62
	road_edge.points = layout.curve.get_baked_points()
	road_surface.points = road_edge.points
	_build_branches()
	_resize_slots(slots)
	for old: Node in decorations.get_children():
		old.free()
	for data: Dictionary in layout.decorations:
		var decoration: Sprite2D = decoration_scene.instantiate() as Sprite2D
		decoration.texture = config.decoration_textures[data.texture]
		decoration.position = data.position
		decoration.scale = Vector2.ONE * float(data.scale)
		decoration.rotation = data.rotation
		decorations.add_child(decoration)


func _build_branches() -> void:
	for old: Node in branches.get_children():
		old.free()
	for old: Node in portals.get_children():
		old.free()
	for old: Node in road_surfaces.get_children():
		if old != road_surface:
			old.free()
	routes.assign([route])
	for index: int in range(1, layout.paths.size()):
		var branch: Path2D = branch_scene.instantiate() as Path2D
		branch.name = "Branch%d" % (index + 1)
		branches.add_child(branch)
		branch.curve = layout.curves[index]
		branch.set_meta("cell_size", layout.cell_size)
		routes.append(branch)
		# Рисуем только новую ветвь: общий участок дороги уже нарисован.
		var points: PackedVector2Array = []
		for cell: Vector2i in layout.branch_cells[index]:
			points.append(layout.cell_center(cell))
		var edge: Line2D = branch.get_node("RoadEdge") as Line2D
		var surface: Line2D = branch.get_node("RoadSurface") as Line2D
		edge.width = road_edge.width
		surface.width = road_surface.width
		edge.points = points
		surface.points = points
		# Все обводки рисуются раньше мощения, чтобы на слиянии не возникала кромка.
		surface.reparent(road_surfaces)
		var entrance: EnemyPortal = portal_scene.instantiate() as EnemyPortal
		entrance.name = "Portal%d" % (index + 1)
		portals.add_child(entrance)
		entrance.position = layout.cell_center(layout.portal_cells[index])
		entrance.scale = portal.scale


func play_portal_exit(index: int) -> void:
	var entrance: EnemyPortal = portal if index == 0 else portals.get_child(index - 1) as EnemyPortal
	entrance.play_exit()


func _resize_slots(slots: Node2D) -> void:
	while slots.get_child_count() > layout.slots.size():
		var extra: Node = slots.get_child(slots.get_child_count() - 1)
		slots.remove_child(extra)
		extra.queue_free()
	while slots.get_child_count() < layout.slots.size():
		var slot: SummonSlot = slot_scene.instantiate() as SummonSlot
		slot.name = "Slot%d" % (slots.get_child_count() + 1)
		slots.add_child(slot)
	for index: int in layout.slots.size():
		var slot: SummonSlot = slots.get_child(index) as SummonSlot
		slot.slot_index = index + 1
		slot.global_position = to_global(layout.slots[index])
		var nearest: Vector2 = layout.curve.get_closest_point(layout.slots[index])
		for candidate: Curve2D in layout.curves:
			var point: Vector2 = candidate.get_closest_point(layout.slots[index])
			if point.distance_squared_to(layout.slots[index]) < nearest.distance_squared_to(layout.slots[index]):
				nearest = point
		slot.faces_left = nearest.x < layout.slots[index].x
		slot.fit_to_cell(layout.cell_size - config.cell_gap)
