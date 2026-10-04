@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Navigation: NavigationRegion2D/3D (outlines + baking), agents with sane defaults, links,
## and an overview of the navigation setup of the edited scene.


## Navigation maps changed by this handler: map RID -> iteration id at the time of the change.
## navigation.path waits until the map has synchronised past it (maps update a few frames later).
var _pending_sync := {}

const PARSED_TYPES := {"meshes": 0, "mesh": 0, "mesh_instances": 0, "static_colliders": 1, "colliders": 1, "static": 1, "both": 2, "meshes_and_static_colliders": 2}
const SOURCE_MODES := {"root_node_children": 0, "children": 0, "root": 0, "groups_with_children": 1, "group_with_children": 1, "group": 1, "groups_explicit": 2, "group_explicit": 2, "explicit": 2}
## 2D name -> 3D name of the equivalent NavigationPolygon / NavigationMesh property.
const NAV_KEYS_3D := {"parsed_geometry_type": "geometry_parsed_geometry_type", "source_geometry_mode": "geometry_source_geometry_mode", "source_geometry_group_name": "geometry_source_group_name", "parsed_collision_mask": "geometry_collision_mask", "collision_mask": "geometry_collision_mask"}


func _map_of(n: Node) -> RID:
	if n.has_method("get_navigation_map"):
		var m: RID = n.get_navigation_map()
		if m.is_valid():
			return m
	if n is Node3D:
		return n.get_world_3d().navigation_map
	return n.get_world_2d().navigation_map


func _mark_changed(n: Node) -> void:
	var m := _map_of(n)
	var is3d := n is Node3D
	_pending_sync[m] = NavigationServer3D.map_get_iteration_id(m) if is3d else NavigationServer2D.map_get_iteration_id(m)


## Applies NavigationPolygon / NavigationMesh props with friendly names: 2D and 3D property names
## are interchangeable, enums accept 'both' / 'static_colliders' / 'groups_with_children', masks accept layer names.
func _nav_props(res: Resource, props: Dictionary, is3d: bool):
	var fixed := {}
	for key in props:
		var k := str(key)
		var v = props[key]
		if is3d and NAV_KEYS_3D.has(k):
			k = NAV_KEYS_3D[k]
		elif not is3d:
			for k2 in NAV_KEYS_3D:
				if NAV_KEYS_3D[k2] == k:
					k = "parsed_collision_mask" if k2 == "collision_mask" else k2
					break
			if k == "collision_mask":
				k = "parsed_collision_mask"
		if k.ends_with("parsed_geometry_type") and v is String and PARSED_TYPES.has(v.to_lower()):
			v = PARSED_TYPES[v.to_lower()]
		elif k.ends_with("source_geometry_mode") and v is String and SOURCE_MODES.has(v.to_lower()):
			v = SOURCE_MODES[v.to_lower()]
		elif k.ends_with("collision_mask") and (v is Array or (v is String and not v.is_valid_int())):
			var bits = ctx.router.handlers["physics"].layer_bits(v, "3d_physics" if is3d else "2d_physics") if ctx.router.handlers.has("physics") else U.err("Use a bitmask number for %s." % k)
			if U.is_err(bits): return bits
			v = bits
		fixed[k] = v
	return U.apply_props(res, fixed)


func _dim_of(p: Dictionary, parent: Node) -> String:
	var t := U.p_str(p, "type", "").to_lower()
	if t in ["2d", "3d"]:
		return t
	return "3d" if parent is Node3D else "2d"


func _add_node(parent: Node, n: Node, action: String) -> void:
	var root: Node = ctx.edited_root()
	var u = ctx.begin(action)
	u.add_do_method(parent, "add_child", n, true)
	u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", n, root)
	u.add_do_reference(n)
	u.add_undo_method(parent, "remove_child", n)
	ctx.commit()


func _parent(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var parent: Node = ctx.find_node(U.p_str(p, "parent", "."))
	if parent == null:
		return ctx.node_not_found(U.p_str(p, "parent"))
	return parent


# ---------------------------------------------------------------------------
# region
# ---------------------------------------------------------------------------

## Creates a NavigationRegion2D/3D. 2D: outline(s)/rect define the walkable area; obstacles
## (child collision shapes / meshes) are carved out when baking.
func a_region(p: Dictionary):
	var parent = await _parent(p)
	if U.is_err(parent): return parent
	var dim := _dim_of(p, parent)
	var region: Node
	if dim == "2d":
		var r2 := NavigationRegion2D.new()
		var np := NavigationPolygon.new()
		var outlines := []
		if p.has("outline"):
			outlines.append(p.outline)
		for o in U.p_arr(p, "outlines"):
			outlines.append(o)
		if p.has("rect"):
			var rc = p.rect
			if not (rc is Array and rc.size() == 4):
				return U.err("rect must be [x, y, width, height] in pixels.")
			var x := float(rc[0]); var y := float(rc[1]); var w := float(rc[2]); var h := float(rc[3])
			outlines.append([[x, y], [x + w, y], [x + w, y + h], [x, y + h]])
		for o in outlines:
			var pts: PackedVector2Array = U.coerce(o, TYPE_PACKED_VECTOR2_ARRAY)
			if pts.size() < 3:
				r2.free()
				return U.err("An outline needs at least 3 points: [[x, y], ...].")
			np.add_outline(pts)
		if p.has("nav"):
			var pr = _nav_props(np, U.p_dict(p, "nav"), false)
			if U.is_err(pr):
				r2.free()
				return pr
		r2.navigation_polygon = np
		# Holes: NavigationObstacle2D children that remove their area from the bake (kept for re-bakes).
		var hi := 0
		for h in U.p_arr(p, "holes"):
			var hpts: PackedVector2Array = U.coerce(h, TYPE_PACKED_VECTOR2_ARRAY)
			if hpts.size() < 3:
				r2.free()
				return U.err("A hole needs at least 3 points: [[x, y], ...].")
			var ob := NavigationObstacle2D.new()
			hi += 1
			ob.name = "Hole%d" % hi
			ob.vertices = hpts
			ob.affect_navigation_mesh = true
			r2.add_child(ob, true)
		region = r2
	else:
		var r3 := NavigationRegion3D.new()
		var nm := NavigationMesh.new()
		if p.has("nav"):
			var pr3 = _nav_props(nm, U.p_dict(p, "nav"), true)
			if U.is_err(pr3):
				r3.free()
				return pr3
		r3.navigation_mesh = nm
		region = r3
	region.name = U.p_str(p, "name", region.get_class())
	if p.has("position"):
		region.set("position", U.to_vector(p.position, TYPE_VECTOR3 if dim == "3d" else TYPE_VECTOR2))
	if p.has("props"):
		var rp = U.apply_props(region, U.p_dict(p, "props"))
		if U.is_err(rp):
			region.free()
			return rp
	var has_outline: bool = dim == "2d" and region.navigation_polygon.get_outline_count() > 0
	# Resolve source nodes before adding anything, so a bad path leaves the scene untouched.
	var srcs = _source_nodes(p)
	if U.is_err(srcs):
		region.free()
		return srcs
	_add_node(parent, region, "Add %s" % region.get_class())
	_mark_changed(region)
	var out := {"path": ctx.node_path_str(region), "type": region.get_class()}
	if not srcs.is_empty():
		out["sources"] = _set_sources(region, srcs)
	var bake := U.p_bool(p, "bake", has_outline or dim == "3d")
	if bake:
		var br = await _bake(region)
		out.merge(br)
	elif dim == "2d" and not has_outline:
		out["next"] = "Give it a walkable outline (outline/rect) and bake with navigation.bake."
	return out


# ---------------------------------------------------------------------------
# bake
# ---------------------------------------------------------------------------

func a_bake(p: Dictionary):
	var n = await node_arg(p)
	if U.is_err(n): return n
	if not (n is NavigationRegion2D or n is NavigationRegion3D):
		var found := []
		for c in n.find_children("*", "NavigationRegion2D", true, false) + n.find_children("*", "NavigationRegion3D", true, false):
			found.append(ctx.node_path_str(c))
		return U.err("'%s' is a %s, not a NavigationRegion2D/3D." % [ctx.node_path_str(n), n.get_class()], ("Regions under it: " + ", ".join(found)) if not found.is_empty() else "Create one with navigation.region.")
	var srcs = _source_nodes(p)
	if U.is_err(srcs): return srcs
	var src_info = null
	if not srcs.is_empty():
		src_info = _set_sources(n, srcs)
	if p.has("nav"):
		var res: Resource = n.get("navigation_polygon" if n is NavigationRegion2D else "navigation_mesh")
		if res:
			var before_nav: Resource = res.duplicate()
			var pr = _nav_props(res, U.p_dict(p, "nav"), n is NavigationRegion3D)
			if U.is_err(pr):
				return pr
			var u = ctx.begin("Set navigation bake settings")
			var prop := "navigation_polygon" if n is NavigationRegion2D else "navigation_mesh"
			u.add_do_property(n, prop, res)
			u.add_undo_property(n, prop, before_nav)
			ctx.commit()
	var out: Dictionary = await _bake(n)
	if src_info != null:
		out["sources"] = src_info
	return out


## `sources: [node paths]`: extra nodes whose geometry/colliders the bake uses (e.g. a TileMapLayer
## with wall collision, or level geometry that isn't a child of the region). Returns Array[Node] or error.
func _source_nodes(p: Dictionary):
	var out := []
	for sp in U.p_arr(p, "sources"):
		var sn: Node = ctx.find_node(str(sp))
		if sn == null:
			return ctx.node_not_found(str(sp))
		out.append(sn)
	return out


## Puts the region and the source nodes in the bake group and switches the region to group mode (undoable).
func _set_sources(region: Node, nodes: Array) -> Dictionary:
	var is2d := region is NavigationRegion2D
	var res: Resource = region.get("navigation_polygon" if is2d else "navigation_mesh")
	var group := str(res.get("source_geometry_group_name" if is2d else "geometry_source_group_name"))
	var mode_prop := "source_geometry_mode" if is2d else "geometry_source_geometry_mode"
	var u = ctx.begin("Set navigation sources")
	u.add_do_property(res, mode_prop, 1)
	u.add_undo_property(res, mode_prop, res.get(mode_prop))
	var all: Array = [region] + nodes
	for n in all:
		if not n.is_in_group(group):
			u.add_do_method(n, "add_to_group", group, true)
			u.add_undo_method(n, "remove_from_group", group)
	ctx.commit()
	return {"group": group, "mode": "groups_with_children", "nodes": all.map(func(n): return ctx.node_path_str(n))}


## Bakes synchronously on the main thread and records an undoable resource swap.
func _bake(region: Node) -> Dictionary:
	var is2d := region is NavigationRegion2D
	var prop := "navigation_polygon" if is2d else "navigation_mesh"
	var res: Resource = region.get(prop)
	if res == null:
		res = NavigationPolygon.new() if is2d else NavigationMesh.new()
		region.set(prop, res)
	if is2d and (res as NavigationPolygon).get_outline_count() == 0:
		return {"baked": false, "warning": "No outline: a 2D navigation polygon bakes inside its outlines. Pass outline/rect to navigation.region, or edit the polygon in the editor."}
	var before: Resource = res.duplicate()
	# Let pending transform changes (nodes moved/added this request) reach the servers first.
	await ctx.frame()
	var t0 := Time.get_ticks_msec()
	if is2d:
		(region as NavigationRegion2D).bake_navigation_polygon(false)
	else:
		(region as NavigationRegion3D).bake_navigation_mesh(false)
	# Synchronous bakes finish before returning; wait a frame in case the server defers.
	var waited := 0
	while region.is_baking() and waited < 600:
		await ctx.frame()
		waited += 1
	var after: Resource = region.get(prop)
	var u = ctx.begin("Bake navigation")
	u.add_do_property(region, prop, after)
	u.add_undo_property(region, prop, before)
	ctx.commit()
	# The server sometimes misses a navmesh that changed while its async region update was still
	# running (seen with bakes that end up empty), leaving path queries on the old mesh: re-push it.
	await ctx.plugin.get_tree().physics_frame
	await ctx.plugin.get_tree().physics_frame
	if region.get(prop) == after:
		if is2d:
			NavigationServer2D.region_set_navigation_polygon(region.get_rid(), after)
		else:
			NavigationServer3D.region_set_navigation_mesh(region.get_rid(), after)
	_mark_changed(region)
	var out := {"baked": true, "path": ctx.node_path_str(region), "ms": Time.get_ticks_msec() - t0}
	out.merge(_region_stats(region))
	if out.get("polygons", 0) == 0:
		if is2d:
			out["warning"] = "Bake produced no polygons. The outline may be smaller than agent_radius*2 (nav.agent_radius, default 10px), or obstacles cover it."
		else:
			out["warning"] = "Bake produced no polygons. NavigationMesh parses child geometry: add a floor (MeshInstance3D or StaticBody3D with CollisionShape3D) under the region, check nav.geometry_parsed_geometry_type and agent_radius/height."
	return out


func _region_stats(region: Node) -> Dictionary:
	var out := {}
	if region is NavigationRegion2D:
		var np: NavigationPolygon = region.navigation_polygon
		if np:
			out["polygons"] = np.get_polygon_count()
			out["vertices"] = np.get_vertices().size()
			out["outlines"] = np.get_outline_count()
			out["agent_radius"] = np.agent_radius
			var verts := np.get_vertices()
			if verts.size() > 0:
				var bb := Rect2(verts[0], Vector2.ZERO)
				for v in verts:
					bb = bb.expand(v)
				out["bounds"] = [bb.position.x, bb.position.y, bb.size.x, bb.size.y]
	elif region is NavigationRegion3D:
		var nm: NavigationMesh = region.navigation_mesh
		if nm:
			out["polygons"] = nm.get_polygon_count()
			out["vertices"] = nm.get_vertices().size()
			out["agent_radius"] = nm.agent_radius
			out["agent_height"] = nm.agent_height
			var verts3 := nm.get_vertices()
			if verts3.size() > 0:
				var bb3 := AABB(verts3[0], Vector3.ZERO)
				for v3 in verts3:
					bb3 = bb3.expand(v3)
				out["bounds"] = U.encode(bb3)
	out["enabled"] = region.enabled
	out["navigation_layers"] = region.navigation_layers
	return out


# ---------------------------------------------------------------------------
# agent
# ---------------------------------------------------------------------------

const AGENT_SHORTHANDS := ["radius", "max_speed", "path_desired_distance", "target_desired_distance", "height", "avoidance_enabled"]


func a_agent(p: Dictionary):
	var e = U.require(p, ["parent"])
	if e: return e
	var parent = await _parent(p)
	if U.is_err(parent): return parent
	var dim := _dim_of(p, parent)
	var agent: Node
	if dim == "2d":
		var a2 := NavigationAgent2D.new()
		a2.path_desired_distance = 4.0
		a2.target_desired_distance = 4.0
		a2.path_max_distance = 64.0
		agent = a2
	else:
		var a3 := NavigationAgent3D.new()
		a3.path_desired_distance = 0.5
		a3.target_desired_distance = 0.5
		a3.path_max_distance = 3.0
		agent = a3
	agent.name = U.p_str(p, "name", agent.get_class())
	var props := U.p_dict(p, "props").duplicate()
	for k in AGENT_SHORTHANDS:
		if p.has(k) and not props.has(k):
			props[k] = p[k]
	if p.has("avoidance") and not props.has("avoidance_enabled"):
		props["avoidance_enabled"] = U.p_bool(p, "avoidance")
	var pr = U.apply_props(agent, props)
	if U.is_err(pr):
		agent.free()
		return pr
	_add_node(parent, agent, "Add %s" % agent.get_class())
	var out := {"path": ctx.node_path_str(agent), "type": agent.get_class(), "props": U.changed_props(agent)}
	var body_ok: bool = parent is CharacterBody2D or parent is CharacterBody3D or parent is RigidBody2D or parent is RigidBody3D
	var v := "Vector2" if dim == "2d" else "Vector3"
	out["usage"] = "In the parent's script: @onready var agent: %s = $%s ... in _physics_process: agent.target_position = target.global_position; if agent.is_navigation_finished(): return; var next := agent.get_next_path_position(); velocity = global_position.direction_to(next) * speed; move_and_slide()." % [agent.get_class(), agent.name]
	if agent.get("avoidance_enabled"):
		out["usage"] += " With avoidance: agent.velocity = desired (%s) and move in the velocity_computed(safe_velocity) signal." % v
	if not body_ok:
		out["note"] = "The agent is usually a child of a CharacterBody (it only computes paths; the body moves)."
	var regions := _find_all(ctx.edited_root(), "NavigationRegion2D" if dim == "2d" else "NavigationRegion3D")
	if regions.is_empty():
		out["warning"] = "No %s NavigationRegion in this scene yet; create one with navigation.region." % dim.to_upper()
	return out


# ---------------------------------------------------------------------------
# link
# ---------------------------------------------------------------------------

func a_link(p: Dictionary):
	var e = U.require(p, ["from", "to"])
	if e: return e
	var parent = await _parent(p)
	if U.is_err(parent): return parent
	var from_v = p.from
	var dim := U.p_str(p, "type", "").to_lower()
	if dim == "":
		dim = "3d" if (from_v is Array and from_v.size() == 3) else ("3d" if parent is Node3D else "2d")
	var link: Node
	if dim == "3d":
		var l3 := NavigationLink3D.new()
		l3.start_position = U.to_vector(p.from, TYPE_VECTOR3)
		l3.end_position = U.to_vector(p.to, TYPE_VECTOR3)
		link = l3
	else:
		var l2 := NavigationLink2D.new()
		l2.start_position = U.to_vector(p.from, TYPE_VECTOR2)
		l2.end_position = U.to_vector(p.to, TYPE_VECTOR2)
		link = l2
	link.name = U.p_str(p, "name", link.get_class())
	if p.has("bidirectional"):
		link.set("bidirectional", U.p_bool(p, "bidirectional"))
	if p.has("props"):
		var pr = U.apply_props(link, U.p_dict(p, "props"))
		if U.is_err(pr):
			link.free()
			return pr
	_add_node(parent, link, "Add %s" % link.get_class())
	_mark_changed(link)
	return {"path": ctx.node_path_str(link), "type": link.get_class(), "start": U.encode(link.get("start_position")), "end": U.encode(link.get("end_position")), "bidirectional": link.get("bidirectional"), "note": "from/to are local to the link (placed at the parent's origin). Both ends must lie on (or near, within the map's link connection radius) a navigation region."}


# ---------------------------------------------------------------------------
# path (editor-side query)
# ---------------------------------------------------------------------------

## Queries a path on the edited scene's navigation map (verifies a level is connected).
func a_path(p: Dictionary):
	var e = U.require(p, ["from", "to"])
	if e: return e
	var root = root_or_err()
	if U.is_err(root): return root
	var from_v = p.from
	var is3d: bool = (from_v is Array and from_v.size() == 3) or (from_v is Dictionary and from_v.has("z")) or U.p_str(p, "type").to_lower() == "3d"
	var vp: Viewport = (root as Node).get_viewport()
	var map: RID = vp.find_world_3d().navigation_map if is3d else vp.find_world_2d().navigation_map
	var layers := U.p_int(p, "navigation_layers", 1)
	var from_p = U.to_vector(p.from, TYPE_VECTOR3 if is3d else TYPE_VECTOR2)
	var to_p = U.to_vector(p.to, TYPE_VECTOR3 if is3d else TYPE_VECTOR2)
	var path: PackedVector2Array
	var path3: PackedVector3Array
	var start_point = from_p
	# Maps synchronise a few physics frames after regions change (asynchronously), so a query
	# right after a bake would see the old navmesh. Wait until the map has iterated past our last
	# change (tracked), or briefly for any other pending change (e.g. an undo or a moved region).
	# Region updates are asynchronous and can land in several map iterations, so also wait until
	# the iteration id has been stable for a few frames.
	var target: int = _pending_sync.get(map, -1)
	var max_frames := 240
	var last_iter := -1
	var stable := 0
	for attempt in max_frames:
		await ctx.plugin.get_tree().physics_frame
		var iter: int = NavigationServer3D.map_get_iteration_id(map) if is3d else NavigationServer2D.map_get_iteration_id(map)
		if iter == 0:
			continue  # not synchronised yet; querying now logs an engine error
		if iter != last_iter:
			last_iter = iter
			stable = 0
		else:
			stable += 1
		var last_chance := attempt >= max_frames - 1
		if target >= 0 and iter <= target and not last_chance:
			continue
		if stable < 8 and not last_chance:
			continue
		_pending_sync.erase(map)
		if is3d:
			path3 = NavigationServer3D.map_get_path(map, from_p, to_p, true, layers)
			start_point = NavigationServer3D.map_get_closest_point(map, from_p)
			if path3.size() > 0:
				break
		else:
			path = NavigationServer2D.map_get_path(map, from_p, to_p, true, layers)
			start_point = NavigationServer2D.map_get_closest_point(map, from_p)
			if path.size() > 0:
				break
		if stable >= 30:
			break  # synced and stable for half a second: the map really has no route data
	var regions: Array = NavigationServer3D.map_get_regions(map) if is3d else NavigationServer2D.map_get_regions(map)
	if regions.is_empty():
		return U.err("No navigation regions are active in this scene's %s map." % ("3D" if is3d else "2D"), "Create and bake one with navigation.region.")
	var length := 0.0
	var end_point = null
	if is3d:
		for i in range(1, path3.size()):
			length += path3[i - 1].distance_to(path3[i])
		if path3.size() > 0:
			end_point = path3[path3.size() - 1]
	else:
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		if path.size() > 0:
			end_point = path[path.size() - 1]
	var pts: Array = Array(path3) if is3d else Array(path)
	var out := {"points": pts.map(func(v): return U.encode(v)), "point_count": pts.size(), "length": length}
	var tol := U.p_float(p, "tolerance", 0.5 if is3d else 8.0)
	out["reachable"] = end_point != null and end_point.distance_to(to_p) <= tol
	if end_point != null:
		out["end"] = U.encode(end_point)
	if start_point.distance_to(from_p) > tol:
		out["warning"] = "'from' is %.1f away from the navigation mesh; the path starts at the closest point %s." % [start_point.distance_to(from_p), start_point]
	if not out.reachable:
		out["hint"] = "The target isn't reachable (path ends at the closest point). Check that regions touch/overlap or add a navigation.link, and that obstacles don't block the route."
	return out


# ---------------------------------------------------------------------------
# info
# ---------------------------------------------------------------------------

func a_info(p: Dictionary):
	if p.has("path") and U.p_str(p, "path") != "":
		var n = await node_arg(p)
		if U.is_err(n): return n
		return _node_info(n)
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var out := {}
	for kind in [["regions", ["NavigationRegion2D", "NavigationRegion3D"]], ["agents", ["NavigationAgent2D", "NavigationAgent3D"]], ["links", ["NavigationLink2D", "NavigationLink3D"]], ["obstacles", ["NavigationObstacle2D", "NavigationObstacle3D"]]]:
		var arr := []
		for cls in kind[1]:
			for n in _find_all(root, cls):
				arr.append(_node_info(n))
		out[kind[0]] = arr
	var tile_nav := []
	for layer in _find_all(root, "TileMapLayer"):
		if layer.tile_set and layer.tile_set.get_navigation_layers_count() > 0:
			tile_nav.append(ctx.node_path_str(layer))
	if not tile_nav.is_empty():
		out["tilemap_layers_with_navigation"] = tile_nav
	out["map_settings"] = {"2d_cell_size": ProjectSettings.get_setting("navigation/2d/default_cell_size", 1.0), "3d_cell_size": ProjectSettings.get_setting("navigation/3d/default_cell_size", 0.25), "3d_cell_height": ProjectSettings.get_setting("navigation/3d/default_cell_height", 0.25)}
	if out.regions.is_empty():
		out["hint"] = "No navigation regions. Create one with navigation.region {type: '2d', rect: [x, y, w, h]}."
	return out


func _node_info(n: Node) -> Dictionary:
	var d := {"path": ctx.node_path_str(n), "type": n.get_class()}
	if n is NavigationRegion2D or n is NavigationRegion3D:
		d.merge(_region_stats(n))
		var obstacles := 0
		for cls in ["CollisionShape2D", "CollisionPolygon2D", "MeshInstance3D", "CollisionShape3D", "NavigationObstacle2D", "NavigationObstacle3D", "TileMapLayer", "CSGShape3D"]:
			obstacles += n.find_children("*", cls, true, false).size()
		d["source_geometry_nodes"] = obstacles
		var res: Resource = n.get("navigation_polygon" if n is NavigationRegion2D else "navigation_mesh")
		if res:
			var mode: int = res.get("source_geometry_mode" if n is NavigationRegion2D else "geometry_source_geometry_mode")
			if mode != 0:
				var group := str(res.get("source_geometry_group_name" if n is NavigationRegion2D else "geometry_source_group_name"))
				d["source_mode"] = "groups_with_children" if mode == 1 else "groups_explicit"
				d["source_group_nodes"] = n.get_tree().get_nodes_in_group(group).filter(func(x): return ctx.edited_root() == x or ctx.edited_root().is_ancestor_of(x)).map(func(x): return ctx.node_path_str(x))
	elif n is NavigationAgent2D or n is NavigationAgent3D:
		for k in ["radius", "max_speed", "path_desired_distance", "target_desired_distance", "avoidance_enabled", "navigation_layers"]:
			d[k] = U.encode(n.get(k))
		d["parent"] = ctx.node_path_str(n.get_parent())
	elif n is NavigationLink2D or n is NavigationLink3D:
		d["start"] = U.encode(n.get("start_position"))
		d["end"] = U.encode(n.get("end_position"))
		d["bidirectional"] = n.get("bidirectional")
	elif n is NavigationObstacle2D or n is NavigationObstacle3D:
		d["radius"] = n.get("radius")
		d["avoidance_enabled"] = n.get("avoidance_enabled")
	else:
		d["props"] = U.changed_props(n)
		d["hint"] = "Not a navigation node; call navigation.info without path for a scene overview."
	return d


func _find_all(root: Node, cls: String) -> Array:
	if root == null:
		return []
	var out := []
	if root.is_class(cls):
		out.append(root)
	out.append_array(root.find_children("*", cls, true, false))
	return out
