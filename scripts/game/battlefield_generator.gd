class_name BattlefieldGenerator
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]
# Собственные резервные деревья для трёх текущих сеток. Выбирается подмножество
# маршрутов и зеркальность; общий хвост сохраняется, случайных пересечений нет.
const SAFE_WAYPOINTS: Dictionary = {
	6: [
		[[3, 0], [1, 0], [1, 2], [3, 2], [3, 5], [5, 5], [5, 7], [1, 7], [1, 8]],
		[[0, 4], [3, 4], [3, 5], [5, 5], [5, 7], [1, 7], [1, 8]],
		[[5, 2], [3, 2], [3, 5], [5, 5], [5, 7], [1, 7], [1, 8]]],
	7: [
		[[3, 0], [0, 0], [0, 3], [3, 3], [3, 6], [6, 6], [6, 8], [4, 8], [4, 10]],
		[[0, 5], [3, 5], [3, 6], [6, 6], [6, 8], [4, 8], [4, 10]],
		[[6, 4], [3, 4], [3, 6], [6, 6], [6, 8], [4, 8], [4, 10]]],
	8: [
		[[6, 0], [2, 0], [2, 2], [5, 2], [5, 5], [3, 5], [3, 8], [5, 8], [5, 9], [7, 9], [7, 12]],
		[[0, 4], [2, 4], [2, 2], [5, 2], [5, 5], [3, 5], [3, 8], [5, 8], [5, 9], [7, 9], [7, 12]],
		[[7, 6], [5, 6], [5, 5], [3, 5], [3, 8], [5, 8], [5, 9], [7, 9], [7, 12]]]
}

var config: BattlefieldConfig


func _init(settings: BattlefieldConfig) -> void:
	config = settings


func generate(seed_value: int, columns: int, slot_override: int = 0, portal_override: int = 0) -> BattlefieldLayout:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	if columns == 0:
		columns = rng.randi_range(config.column_range.x, config.column_range.y)
	var layout: BattlefieldLayout = BattlefieldLayout.new()
	layout.seed_value = seed_value
	layout.grid_size = config.grid_size(columns)
	layout.cell_size = config.cell_size(columns)
	layout.origin = config.playable_rect.position
	layout.cells.resize(layout.grid_size.x * layout.grid_size.y)
	layout.cells.fill(BattlefieldLayout.Cell.ENVIRONMENT)
	layout.turn_probability = rng.randf_range(config.turn_probability_range.x, config.turn_probability_range.y)
	var count: int = rng.randi_range(config.slot_count_range.x, config.slot_count_range.y) if slot_override == 0 else clampi(slot_override, config.slot_count_range.x, config.slot_count_range.y)
	var portal_count: int = config.roll_portal_count(rng) if portal_override == 0 else clampi(portal_override, config.portal_count_range.x, config.portal_count_range.y)
	var sides: Array[int] = [BattlefieldLayout.PortalSide.TOP, BattlefieldLayout.PortalSide.LEFT, BattlefieldLayout.PortalSide.RIGHT]
	_shuffle(sides, rng)
	sides.resize(portal_count)
	# Верхняя ветвь остаётся основной, если эта сторона была выбрана.
	if sides.has(BattlefieldLayout.PortalSide.TOP):
		sides.erase(BattlefieldLayout.PortalSide.TOP)
		sides.push_front(BattlefieldLayout.PortalSide.TOP)
	layout.portal_sides = sides
	for attempt: int in config.generation_attempts:
		if _try_network(layout, count, rng):
			break
	if layout.paths.size() != portal_count or layout.slot_cells.size() != count:
		layout.used_fallback = true
		_fallback_network(layout, count, rng)
	_finalize(layout)
	_add_decorations(layout)
	return layout


func _try_network(layout: BattlefieldLayout, count: int, rng: RandomNumberGenerator) -> bool:
	layout.paths.clear()
	layout.slot_cells.clear()
	var starts: Array[Vector2i] = _entries(layout.portal_sides[0], layout)
	var start: Vector2i = starts[rng.randi_range(0, starts.size() - 1)]
	var finish: Vector2i = Vector2i(rng.randi_range(0, layout.grid_size.x - 1), layout.grid_size.y - 1)
	var min_steps: int = ceili(config.route_length_range.x / layout.cell_size)
	var max_steps: int = floori(config.route_length_range.y / layout.cell_size)
	var allowed_steps: Array[int] = []
	for steps: int in range(min_steps, max_steps + 1):
		if (steps - _manhattan(start, finish)) % 2 == 0:
			allowed_steps.append(steps)
	var target: int = allowed_steps[rng.randi_range(0, allowed_steps.size() - 1)]
	layout.target_length = target * layout.cell_size
	var budget: Array[int] = [0]
	var path: Array[Vector2i] = [start]
	var occupied: Dictionary = {start: true}
	var found: bool = _walk(path, occupied, finish, layout, rng, target, target, budget)
	if found:
		layout.paths.append(path)
		_set_network(layout)
		for index: int in range(1, layout.portal_sides.size()):
			if not _add_branch(layout, layout.portal_sides[index], rng, budget):
				found = false
				break
	layout.search_steps += budget[0]
	return found and _choose_slots(layout, layout.network_cells, count, rng)


func _entries(side: int, layout: BattlefieldLayout) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if side == BattlefieldLayout.PortalSide.TOP:
		for x: int in layout.grid_size.x:
			result.append(Vector2i(x, 0))
	else:
		var maximum: int = mini(floori((config.portal_max_y - layout.origin.y) / layout.cell_size - 0.5), layout.grid_size.y - 2)
		for y: int in range(1, maximum + 1):
			result.append(Vector2i(0 if side == BattlefieldLayout.PortalSide.LEFT else layout.grid_size.x - 1, y))
	return result


func _add_branch(layout: BattlefieldLayout, side: int, rng: RandomNumberGenerator, budget: Array[int]) -> bool:
	var network: Dictionary = {}
	for cell: Vector2i in layout.network_cells:
		network[cell] = true
	var starts: Array[Vector2i] = _entries(side, layout)
	_shuffle(starts, rng)
	var suffixes: Array[Array] = []
	var seen: Dictionary = {}
	for route: Array in layout.paths:
		for index: int in range(1, route.size() - 1):
			var join: Vector2i = route[index]
			var neighbors: int = 0
			for direction: Vector2i in DIRECTIONS:
				neighbors += int(network.has(join + direction))
			if neighbors == 2 and not seen.has(join):
				suffixes.append(route.slice(index))
				seen[join] = true
	_shuffle(suffixes, rng)
	for start: Vector2i in starts:
		var clear: bool = not network.has(start)
		for direction: Vector2i in DIRECTIONS:
			clear = clear and not network.has(start + direction)
		if not clear:
			continue
		for suffix: Array in suffixes:
			var min_steps: int = maxi(1, ceili(config.route_length_range.x / layout.cell_size) - suffix.size() + 1)
			var max_steps: int = floori(config.route_length_range.y / layout.cell_size) - suffix.size() + 1
			if _manhattan(start, suffix[0]) > max_steps:
				continue
			var path: Array[Vector2i] = [start]
			var occupied: Dictionary = {start: true}
			if _walk(path, occupied, suffix[0], layout, rng, min_steps, max_steps, budget, Vector2i.ZERO, 0, network, suffix):
				path.append_array(suffix.slice(1))
				layout.paths.append(path)
				_set_network(layout)
				return true
			if budget[0] >= config.search_steps_per_attempt:
				return false
	return false


func _set_network(layout: BattlefieldLayout) -> void:
	layout.network_cells.clear()
	layout.branch_cells.clear()
	var seen: Dictionary = {}
	for path: Array in layout.paths:
		var branch: Array[Vector2i] = []
		for cell: Vector2i in path:
			branch.append(cell)
			if seen.has(cell):
				break
			seen[cell] = true
			layout.network_cells.append(cell)
		layout.branch_cells.append(branch)


func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var temporary: Variant = values[index]
		values[index] = values[other]
		values[other] = temporary


func _walk(path: Array[Vector2i], occupied: Dictionary, finish: Vector2i, layout: BattlefieldLayout, rng: RandomNumberGenerator, min_steps: int, max_steps: int, budget: Array[int], previous_direction: Vector2i = Vector2i.ZERO, run_length: int = 0, network: Dictionary = {}, suffix: Array = []) -> bool:
	budget[0] += 1
	if budget[0] > config.search_steps_per_attempt:
		return false
	var current: Vector2i = path[-1]
	var steps: int = path.size() - 1
	if current == finish:
		var full_path: Array[Vector2i] = path.duplicate()
		full_path.append_array(suffix.slice(1))
		return steps >= min_steps and _runs_are_valid(full_path)
	if steps + _manhattan(current, finish) > max_steps or steps >= max_steps:
		return false
	var options: Array[Vector2i] = []
	for direction: Vector2i in DIRECTIONS:
		if not _allows_direction(previous_direction, run_length, direction):
			continue
		var next: Vector2i = current + direction
		if not _inside(next, layout.grid_size) or occupied.has(next):
			continue
		if next != finish and network.has(next):
			continue
		if not network.is_empty() and _manhattan(current, finish) == 1 and next != finish:
			continue
		if (next.y == 0 and current.y != 0) or (next.y == layout.grid_size.y - 1 and next != finish):
			continue
		var neighbors: int = 0
		var touches_network: bool = false
		for adjacent: Vector2i in DIRECTIONS:
			neighbors += int(occupied.has(next + adjacent))
			touches_network = touches_network or (next != finish and next + adjacent != finish and network.has(next + adjacent))
		if neighbors == 1 and not touches_network:
			options.append(next)
	var straight: Vector2i = current + (current - path[-2] if path.size() > 1 else Vector2i.DOWN)
	var ordered: Array[Vector2i] = []
	if options.has(straight) and rng.randf() >= layout.turn_probability:
		ordered.append(straight)
		options.erase(straight)
	elif options.has(straight) and options.size() > 1:
		options.erase(straight)
		while not options.is_empty():
			var index: int = rng.randi_range(0, options.size() - 1)
			ordered.append(options[index])
			options.remove_at(index)
		options.append(straight)
	while not options.is_empty():
		var index: int = rng.randi_range(0, options.size() - 1)
		ordered.append(options[index])
		options.remove_at(index)
	for next: Vector2i in ordered:
		var direction: Vector2i = next - current
		var next_run_length: int = run_length + 1 if direction == previous_direction else 1
		path.append(next)
		occupied[next] = true
		if _walk(path, occupied, finish, layout, rng, min_steps, max_steps, budget, direction, next_run_length, network, suffix):
			return true
		occupied.erase(next)
		path.pop_back()
		if budget[0] >= config.search_steps_per_attempt:
			break
	return false


func _fallback_network(layout: BattlefieldLayout, count: int, rng: RandomNumberGenerator) -> void:
	layout.paths.clear()
	var mirror: bool = rng.randi_range(0, 1) == 1
	for side: int in layout.portal_sides:
		var source_side: int = 3 - side if mirror and side != BattlefieldLayout.PortalSide.TOP else side
		var points: Array = SAFE_WAYPOINTS[layout.grid_size.x][source_side]
		var path: Array[Vector2i] = []
		for point: Array in points:
			var cell: Vector2i = Vector2i(layout.grid_size.x - 1 - int(point[0]) if mirror else int(point[0]), int(point[1]))
			if path.is_empty():
				path.append(cell)
			else:
				while path[-1] != cell:
					path.append(path[-1] + Vector2i(signi(cell.x - path[-1].x), signi(cell.y - path[-1].y)))
		layout.paths.append(path)
	_set_network(layout)
	layout.target_length = (layout.paths[0].size() - 1) * layout.cell_size
	if not _choose_slots(layout, layout.network_cells, count, rng):
		push_error("Battlefield settings do not allow enough safe summon slots")


func _allows_direction(previous: Vector2i, length: int, direction: Vector2i) -> bool:
	if previous == Vector2i.ZERO:
		return direction.y == 0
	var bounds: Vector2i = config.horizontal_run_range if previous.x != 0 else config.vertical_run_range
	if direction == previous:
		return length < bounds.y
	return length >= bounds.x


func _run_length_is_valid(direction: Vector2i, length: int) -> bool:
	var bounds: Vector2i = config.horizontal_run_range if direction.x != 0 else config.vertical_run_range
	return length >= bounds.x and length <= bounds.y


func _runs_are_valid(path: Array[Vector2i]) -> bool:
	var previous: Vector2i = path[1] - path[0]
	var length: int = 0
	for index: int in range(1, path.size()):
		var direction: Vector2i = path[index] - path[index - 1]
		if direction != previous:
			if not _run_length_is_valid(previous, length):
				return false
			previous = direction
			length = 0
		length += 1
	return _run_length_is_valid(previous, length)


func _choose_slots(layout: BattlefieldLayout, path: Array[Vector2i], count: int, rng: RandomNumberGenerator) -> bool:
	var bands: Array[Array] = [[], [], []]
	var candidates: Dictionary = {}
	var curves: Array[Curve2D] = []
	for route: Array in layout.paths:
		curves.append(_route_curve(layout, route))
	for index: int in path.size():
		for direction: Vector2i in DIRECTIONS:
			var cell: Vector2i = path[index] + direction
			if _inside(cell, layout.grid_size) and not path.has(cell) and not candidates.has(cell):
				if _coverage(curves, layout.cell_center(cell)) < config.minimum_coverage_length:
					continue
				candidates[cell] = true
				bands[mini(floori(index * 3.0 / path.size()), 2)].append(cell)
	if candidates.size() < count:
		return false
	layout.slot_cells.clear()
	var band: int = 0
	while layout.slot_cells.size() < count:
		var options: Array = bands[band % 3]
		if not options.is_empty():
			var index: int = rng.randi_range(0, options.size() - 1)
			layout.slot_cells.append(options[index])
			options.remove_at(index)
		band += 1
	return true


func _route_curve(layout: BattlefieldLayout, path: Array) -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	curve.bake_interval = 4.0
	for cell: Vector2i in path:
		curve.add_point(layout.cell_center(cell))
	return curve


func _finalize(layout: BattlefieldLayout) -> void:
	layout.road_cells.assign(layout.paths[0])
	layout.curves.clear()
	layout.portal_cells.clear()
	for path: Array in layout.paths:
		layout.curves.append(_route_curve(layout, path))
		layout.portal_cells.append(path[0])
	layout.curve = layout.curves[0]
	for cell: Vector2i in layout.network_cells:
		layout.cells[cell.y * layout.grid_size.x + cell.x] = BattlefieldLayout.Cell.ROAD
	var finish: Vector2i = layout.road_cells[-1]
	for start: Vector2i in layout.portal_cells:
		layout.cells[start.y * layout.grid_size.x + start.x] = BattlefieldLayout.Cell.SPAWN
	layout.cells[finish.y * layout.grid_size.x + finish.x] = BattlefieldLayout.Cell.TOWER
	for cell: Vector2i in layout.slot_cells:
		layout.cells[cell.y * layout.grid_size.x + cell.x] = BattlefieldLayout.Cell.SUMMON
		layout.slots.append(layout.cell_center(cell))


func is_valid(layout: BattlefieldLayout) -> bool:
	if layout.paths.size() < config.portal_count_range.x or layout.paths.size() > config.portal_count_range.y or layout.paths.size() != layout.portal_sides.size():
		return false
	if layout.slots.size() < config.slot_count_range.x or layout.slots.size() > config.slot_count_range.y:
		return false
	if layout.road_cells != layout.paths[0] or layout.curves.size() != layout.paths.size():
		return false
	var tower: Vector2i = layout.road_cells[-1]
	if tower.y != layout.grid_size.y - 1:
		return false
	var sides: Dictionary = {}
	var vertices: Dictionary = {}
	var edges: Dictionary = {}
	for route_index: int in layout.paths.size():
		var path: Array = layout.paths[route_index]
		var side: int = layout.portal_sides[route_index]
		if path.size() < 2 or sides.has(side) or path[-1] != tower or not _entries(side, layout).has(path[0]):
			return false
		if path[0].y != path[1].y or not _runs_are_valid(path):
			return false
		var length: float = layout.curves[route_index].get_baked_length()
		if length < config.route_length_range.x - 0.01 or length > config.route_length_range.y + 0.01:
			return false
		sides[side] = true
		var visited: Dictionary = {}
		for index: int in path.size():
			var cell: Vector2i = path[index]
			if not _inside(cell, layout.grid_size) or visited.has(cell):
				return false
			if index > 0:
				if _manhattan(cell, path[index - 1]) != 1:
					return false
				edges[_edge_key(cell, path[index - 1], layout.grid_size.x)] = true
			visited[cell] = true
			vertices[cell] = true
	# Все маршруты заканчиваются в одной башне. V-1 рёбер исключает циклы.
	if edges.size() != vertices.size() - 1 or vertices.size() != layout.network_cells.size():
		return false
	for cell: Vector2i in vertices:
		var degree: int = 0
		for direction: Vector2i in DIRECTIONS:
			if vertices.has(cell + direction):
				if not edges.has(_edge_key(cell, cell + direction, layout.grid_size.x)):
					return false
				degree += 1
		if degree > 3:
			return false
	var occupied_slots: Dictionary = {}
	for cell: Vector2i in layout.slot_cells:
		if not _inside(cell, layout.grid_size) or vertices.has(cell) or occupied_slots.has(cell):
			return false
		var adjacent: bool = false
		for direction: Vector2i in DIRECTIONS:
			adjacent = adjacent or vertices.has(cell + direction)
		if not adjacent or _coverage(layout.curves, layout.cell_center(cell)) < config.minimum_coverage_length:
			return false
		occupied_slots[cell] = true
	return true


func _edge_key(first: Vector2i, second: Vector2i, width: int) -> Vector2i:
	var a: int = first.y * width + first.x
	var b: int = second.y * width + second.x
	return Vector2i(mini(a, b), maxi(a, b))


func _coverage(curves: Array[Curve2D], position: Vector2) -> float:
	var covered: float = 0.0
	for curve: Curve2D in curves:
		covered = maxf(covered, coverage_length(curve, position))
	return covered


func coverage_length(curve: Curve2D, position: Vector2) -> float:
	var points: PackedVector2Array = curve.get_baked_points()
	var covered: float = 0.0
	for index: int in range(1, points.size()):
		if position.distance_to(points[index - 1].lerp(points[index], 0.5)) <= config.minimum_attack_range:
			covered += points[index].distance_to(points[index - 1])
	return covered


func _add_decorations(layout: BattlefieldLayout) -> void:
	if config.decoration_textures.is_empty():
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = layout.seed_value ^ 0x5A17C3
	for y: int in layout.grid_size.y:
		for x: int in layout.grid_size.x:
			var cell: Vector2i = Vector2i(x, y)
			if layout.cell_type(cell) != BattlefieldLayout.Cell.ENVIRONMENT or rng.randf() > config.decoration_probability:
				continue
			layout.decorations.append({"position": layout.cell_center(cell), "texture": rng.randi_range(0, config.decoration_textures.size() - 1), "scale": rng.randf_range(0.9, 1.5), "rotation": rng.randf_range(-0.2, 0.2)})


func _inside(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func _manhattan(first: Vector2i, second: Vector2i) -> int:
	return absi(first.x - second.x) + absi(first.y - second.y)
