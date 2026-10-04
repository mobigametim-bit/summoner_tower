@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Physics: bodies with collision shapes in one call, auto-fitting shapes to sprites/meshes,
## named collision layers, joints, editor-world raycasts and project physics settings.

const BODY_TYPES := {
	"static_2d": "StaticBody2D", "character_2d": "CharacterBody2D", "rigid_2d": "RigidBody2D",
	"area_2d": "Area2D", "animatable_2d": "AnimatableBody2D",
	"static_3d": "StaticBody3D", "character_3d": "CharacterBody3D", "rigid_3d": "RigidBody3D",
	"area_3d": "Area3D", "animatable_3d": "AnimatableBody3D", "vehicle_3d": "VehicleBody3D",
	"kinematic_2d": "CharacterBody2D", "kinematic_3d": "CharacterBody3D",
}
const JOINT_TYPES := {
	"pin_2d": "PinJoint2D", "groove_2d": "GrooveJoint2D", "damped_spring_2d": "DampedSpringJoint2D", "spring_2d": "DampedSpringJoint2D",
	"pin_3d": "PinJoint3D", "hinge_3d": "HingeJoint3D", "slider_3d": "SliderJoint3D", "cone_3d": "ConeTwistJoint3D",
	"cone_twist_3d": "ConeTwistJoint3D", "generic_6dof_3d": "Generic6DOFJoint3D", "6dof_3d": "Generic6DOFJoint3D",
}
const SHAPES_2D := ["rect", "circle", "capsule", "segment", "world_boundary", "separation_ray", "convex", "concave", "polygon"]
const SHAPES_3D := ["box", "sphere", "capsule", "cylinder", "world_boundary", "separation_ray", "convex", "concave", "polygon"]
const ALIAS_2D := {"rectangle": "rect", "box": "rect", "square": "rect", "sphere": "circle", "ball": "circle", "line": "segment", "floor": "world_boundary", "plane": "world_boundary", "ray": "separation_ray"}
const ALIAS_3D := {"rect": "box", "cube": "box", "rectangle": "box", "circle": "sphere", "ball": "sphere", "floor": "world_boundary", "plane": "world_boundary", "ray": "separation_ray", "trimesh": "concave", "mesh": "concave"}

## Project settings exposed by physics.settings: friendly key -> setting.
const SETTINGS := {
	"gravity": "physics/3d/default_gravity",
	"gravity_direction": "physics/3d/default_gravity_vector",
	"linear_damp": "physics/3d/default_linear_damp",
	"angular_damp": "physics/3d/default_angular_damp",
	"engine_3d": "physics/3d/physics_engine",
	"gravity_2d": "physics/2d/default_gravity",
	"gravity_direction_2d": "physics/2d/default_gravity_vector",
	"linear_damp_2d": "physics/2d/default_linear_damp",
	"angular_damp_2d": "physics/2d/default_angular_damp",
	"engine_2d": "physics/2d/physics_engine",
	"ticks_per_second": "physics/common/physics_ticks_per_second",
	"max_steps_per_frame": "physics/common/max_physics_steps_per_frame",
	"jitter_fix": "physics/common/physics_jitter_fix",
	"interpolation": "physics/common/physics_interpolation",
}


# ---------------------------------------------------------------------------
# Layers
# ---------------------------------------------------------------------------

## Layer names/numbers -> bitmask using layer_names/<kind>/layer_N. Numbers are layer numbers (1..32).
## Public: also used by the tiles handler.
func layer_bits(v, kind: String = "2d_physics"):
	if v == null:
		return 0
	var items: Array = v if v is Array else [v]
	var bits := 0
	for item in items:
		if item is float or item is int or (item is String and item.is_valid_int()):
			var n := int(item)
			if n < 1 or n > 32:
				return U.err("Layer numbers must be 1..32, got %d." % n, "Numbers are layer numbers, not bitmasks: layer 3 = bit value 4. Or use layer names.")
			bits |= 1 << (n - 1)
			continue
		var name := str(item)
		var found := -1
		var names := []
		for i in range(1, 33):
			var ln := str(ProjectSettings.get_setting("layer_names/%s/layer_%d" % [kind, i], ""))
			if ln != "":
				names.append(ln)
				if ln.to_lower() == name.to_lower():
					found = i
		if found < 0:
			var s := U.suggest(name, names)
			return U.err("No %s layer named '%s'." % [kind, name], ("Did you mean '%s'? " % s if s != "" else "") + ("Named layers: %s. " % ", ".join(names) if not names.is_empty() else "No layers are named yet. ") + "Name one with project.set_layer_name {kind: '%s', layer: N, name: '%s'} or pass layer numbers." % [kind, name])
		bits |= 1 << (found - 1)
	return bits


func _layer_names(bits: int, kind: String) -> Array:
	var out := []
	for i in range(1, 33):
		if bits & (1 << (i - 1)):
			var ln := str(ProjectSettings.get_setting("layer_names/%s/layer_%d" % [kind, i], ""))
			out.append(ln if ln != "" else i)
	return out


func _kind(n: Node) -> String:
	return "3d_physics" if n is Node3D else "2d_physics"


func a_layers(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var paths: Array = U.p_arr(p, "paths") if p.has("paths") else [U.p_str(p, "path", "")]
	if paths.size() == 1 and str(paths[0]) == "":
		return U.err("Missing 'path' (or 'paths'): the physics body/area/raycast to configure.")
	var mode := U.p_str(p, "mode", "set")
	if not mode in ["set", "add", "remove"]:
		return U.err("mode must be set, add or remove.")
	var nodes := []
	for path in paths:
		var n: Node = ctx.find_node(str(path))
		if n == null:
			return ctx.node_not_found(str(path))
		if not ("collision_mask" in n):
			return U.err("%s ('%s') has no collision layers." % [n.get_class(), path], "Use a PhysicsBody, Area, RayCast or ShapeCast node. TileMapLayer collision layers live in its TileSet (tiles.create_tileset physics_layers).")
		nodes.append(n)
	var plan := []
	for n in nodes:
		var kind := _kind(n)
		var entry := {"node": n}
		for key in ["layer", "mask"]:
			if not p.has(key):
				continue
			var prop: String = "collision_" + str(key)
			if not (prop in n):
				return U.err("%s has no %s." % [n.get_class(), prop], "RayCast/ShapeCast only have a mask.")
			var b = layer_bits(p[key], kind)
			if U.is_err(b): return b
			var cur: int = n.get(prop)
			var nv: int = b if mode == "set" else (cur | b if mode == "add" else cur & ~b)
			entry[prop] = [cur, nv]
		plan.append(entry)
	var changed := false
	for entry in plan:
		if entry.size() > 1:
			changed = true
	if changed:
		var u = ctx.begin("Set collision layers")
		for entry in plan:
			for prop in ["collision_layer", "collision_mask"]:
				if entry.has(prop):
					u.add_do_property(entry.node, prop, entry[prop][1])
					u.add_undo_property(entry.node, prop, entry[prop][0])
		ctx.commit()
	var out := {}
	for n in nodes:
		var kind := _kind(n)
		var d := {}
		if "collision_layer" in n:
			d["layer"] = _layer_names(n.collision_layer, kind)
			d["collision_layer"] = n.collision_layer
		d["mask"] = _layer_names(n.collision_mask, kind)
		d["collision_mask"] = n.collision_mask
		out[ctx.node_path_str(n)] = d
	return {"nodes": out, "note": "layer = what the object is; mask = what it detects/collides with."}


# ---------------------------------------------------------------------------
# Shapes
# ---------------------------------------------------------------------------

func _shape_kind(t: String, is3d: bool) -> String:
	t = t.to_lower().replace("-", "_").replace(" ", "_")
	var aliases: Dictionary = ALIAS_3D if is3d else ALIAS_2D
	if aliases.has(t):
		t = aliases[t]
	return t


## Builds a CollisionShape2D/3D (or CollisionPolygon2D/3D) from a shape spec. Returns Node or error.
func build_shape_node(spec, is3d: bool, name: String = ""):
	if spec is String:
		spec = {"type": spec}
	if not (spec is Dictionary):
		return U.err("shape must be an object like {\"type\": \"rect\", \"size\": [32, 32]}.")
	var t := U.p_str(spec, "type", "box" if is3d else "rect")
	var n: Node
	var shape: Resource = null
	if t.begins_with("res://") or (ClassDB.class_exists(t) and ClassDB.is_parent_class(t, "Shape3D" if is3d else "Shape2D")):
		var obj = U.to_object(spec if not t.begins_with("res://") else t, "Shape3D" if is3d else "Shape2D")
		if U.is_err(obj): return obj
		if not obj.is_class("Shape3D" if is3d else "Shape2D"):
			return U.err("'%s' is a %s, expected a %s." % [t, obj.get_class(), "Shape3D" if is3d else "Shape2D"])
		shape = obj
	else:
		var k := _shape_kind(t, is3d)
		var valid: Array = SHAPES_3D if is3d else SHAPES_2D
		if not k in valid:
			var s := U.suggest(k, valid)
			return U.err("Unknown %s shape '%s'." % ["3D" if is3d else "2D", t], ("Did you mean '%s'? " % s if s != "" else "") + "Shapes: " + ", ".join(valid) + ". Or a Shape class name / res:// path.")
		if k == "polygon":
			if not spec.has("points"):
				return U.err("polygon shape needs 'points': [[x, y], ...].")
			if is3d:
				var cp3 := CollisionPolygon3D.new()
				cp3.polygon = U.coerce(spec.points, TYPE_PACKED_VECTOR2_ARRAY)
				cp3.depth = U.p_float(spec, "depth", 1.0)
				n = cp3
			else:
				var cp := CollisionPolygon2D.new()
				cp.polygon = U.coerce(spec.points, TYPE_PACKED_VECTOR2_ARRAY)
				if U.p_bool(spec, "one_way", false):
					cp.one_way_collision = true
				n = cp
		else:
			shape = _make_shape(k, spec, is3d)
			if U.is_err(shape): return shape
	if n == null:
		if is3d:
			var cs3 := CollisionShape3D.new()
			cs3.shape = shape
			n = cs3
		else:
			var cs := CollisionShape2D.new()
			cs.shape = shape
			if U.p_bool(spec, "one_way", false):
				cs.one_way_collision = true
			n = cs
	n.name = name if name != "" else U.p_str(spec, "name", n.get_class())
	if spec.has("position") or spec.has("offset"):
		n.set("position", U.to_vector(spec.get("position", spec.get("offset")), TYPE_VECTOR3 if is3d else TYPE_VECTOR2))
	if spec.has("rotation"):
		if is3d:
			var r: Vector3 = U.to_vector(spec.rotation, TYPE_VECTOR3)
			n.set("rotation_degrees", r)
		else:
			n.set("rotation_degrees", float(spec.rotation))
	if U.p_bool(spec, "disabled", false):
		n.set("disabled", true)
	if spec.has("props"):
		var pr = U.apply_props(n, U.p_dict(spec, "props"))
		if U.is_err(pr):
			n.free()
			return pr
	return n


func _make_shape(k: String, spec: Dictionary, is3d: bool):
	var pts = spec.get("points", null)
	if is3d:
		match k:
			"box":
				var b := BoxShape3D.new()
				b.size = U.to_vector(spec.get("size", [1, 1, 1]), TYPE_VECTOR3) if not (spec.get("size") is float or spec.get("size") is int) else Vector3.ONE * float(spec.size)
				return b
			"sphere":
				var s := SphereShape3D.new()
				s.radius = U.p_float(spec, "radius", 0.5)
				return s
			"capsule":
				var c := CapsuleShape3D.new()
				c.radius = U.p_float(spec, "radius", 0.5)
				c.height = maxf(U.p_float(spec, "height", 2.0), c.radius * 2.0)
				return c
			"cylinder":
				var cy := CylinderShape3D.new()
				cy.radius = U.p_float(spec, "radius", 0.5)
				cy.height = U.p_float(spec, "height", 2.0)
				return cy
			"world_boundary":
				var w := WorldBoundaryShape3D.new()
				w.plane = Plane(U.to_vector(spec.get("normal", [0, 1, 0]), TYPE_VECTOR3), U.p_float(spec, "distance", 0.0))
				return w
			"separation_ray":
				var r := SeparationRayShape3D.new()
				r.length = U.p_float(spec, "length", 1.0)
				return r
			"convex":
				if pts == null:
					return U.err("convex shape needs 'points': [[x, y, z], ...].", "To wrap a mesh, use physics.fit_shape {kind: 'convex'}.")
				var cv := ConvexPolygonShape3D.new()
				cv.points = U.coerce(pts, TYPE_PACKED_VECTOR3_ARRAY)
				return cv
			"concave":
				if pts == null:
					return U.err("concave shape needs 'points': triangle vertices [[x, y, z], ...] (multiple of 3).", "To use a mesh's triangles, use physics.fit_shape {kind: 'trimesh'}.")
				var cc := ConcavePolygonShape3D.new()
				cc.set_faces(U.coerce(pts, TYPE_PACKED_VECTOR3_ARRAY))
				return cc
	else:
		match k:
			"rect":
				var r2 := RectangleShape2D.new()
				r2.size = U.to_vector(spec.get("size", [32, 32]), TYPE_VECTOR2) if not (spec.get("size") is float or spec.get("size") is int) else Vector2.ONE * float(spec.size)
				return r2
			"circle":
				var c2 := CircleShape2D.new()
				c2.radius = U.p_float(spec, "radius", 16.0)
				return c2
			"capsule":
				var cp := CapsuleShape2D.new()
				cp.radius = U.p_float(spec, "radius", 10.0)
				cp.height = maxf(U.p_float(spec, "height", 40.0), cp.radius * 2.0)
				return cp
			"segment":
				var sg := SegmentShape2D.new()
				if pts is Array and pts.size() >= 2:
					sg.a = U.to_vector(pts[0], TYPE_VECTOR2)
					sg.b = U.to_vector(pts[1], TYPE_VECTOR2)
				else:
					sg.a = U.to_vector(spec.get("a", [0, 0]), TYPE_VECTOR2)
					sg.b = U.to_vector(spec.get("b", [32, 0]), TYPE_VECTOR2)
				return sg
			"world_boundary":
				var wb := WorldBoundaryShape2D.new()
				wb.normal = U.to_vector(spec.get("normal", [0, -1]), TYPE_VECTOR2).normalized()
				wb.distance = U.p_float(spec, "distance", 0.0)
				return wb
			"separation_ray":
				var sr := SeparationRayShape2D.new()
				sr.length = U.p_float(spec, "length", 20.0)
				return sr
			"convex":
				if pts == null:
					return U.err("convex shape needs 'points': [[x, y], ...].", "To wrap a sprite, use physics.fit_shape {kind: 'convex'}.")
				var cv2 := ConvexPolygonShape2D.new()
				cv2.points = U.coerce(pts, TYPE_PACKED_VECTOR2_ARRAY)
				return cv2
			"concave":
				if pts == null:
					return U.err("concave shape needs 'points': segment endpoints [[x, y], ...] (pairs).")
				var cc2 := ConcavePolygonShape2D.new()
				cc2.segments = U.coerce(pts, TYPE_PACKED_VECTOR2_ARRAY)
				return cc2
	return U.err("Unsupported shape '%s'." % k)


func _has_size(spec) -> bool:
	if not (spec is Dictionary):
		return false
	for k in ["size", "radius", "height", "points", "a", "b", "normal", "length"]:
		if spec.has(k):
			return true
	var t := U.p_str(spec, "type", "")
	return t.begins_with("res://") or ClassDB.class_exists(t)


# ---------------------------------------------------------------------------
# body
# ---------------------------------------------------------------------------

## Creates a physics body/area with collision shape(s), optional visual (sprite/mesh) and script.
func a_body(p: Dictionary):
	var e = U.require(p, ["type"])
	if e: return e
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var parent: Node = ctx.find_node(U.p_str(p, "parent", "."))
	if parent == null:
		return ctx.node_not_found(U.p_str(p, "parent"))
	var tname := U.p_str(p, "type")
	var cls: String = BODY_TYPES.get(tname.to_lower(), tname)
	if not ClassDB.class_exists(cls) or not (ClassDB.is_parent_class(cls, "CollisionObject2D") or ClassDB.is_parent_class(cls, "CollisionObject3D")) or not ClassDB.can_instantiate(cls):
		var s := U.suggest(tname, BODY_TYPES.keys())
		return U.err("Unknown body type '%s'." % tname, ("Did you mean '%s'? " % s if s != "" else "") + "Types: " + ", ".join(BODY_TYPES.keys()) + " (or a class name like CharacterBody2D).")
	var is3d := ClassDB.is_parent_class(cls, "CollisionObject3D")
	var body: Node = ClassDB.instantiate(cls)
	body.name = U.p_str(p, "name", cls)
	var kind := "3d_physics" if is3d else "2d_physics"
	var fail = func(err_dict):
		body.free()
		return err_dict
	if p.has("position"):
		body.set("position", U.to_vector(p.position, TYPE_VECTOR3 if is3d else TYPE_VECTOR2))
	if p.has("rotation"):
		if is3d:
			body.set("rotation_degrees", U.to_vector(p.rotation, TYPE_VECTOR3))
		else:
			body.set("rotation_degrees", float(p.rotation))
	if p.has("layer"):
		var lb = layer_bits(p.layer, kind)
		if U.is_err(lb): return fail.call(lb)
		body.set("collision_layer", lb)
	if p.has("mask"):
		var mb = layer_bits(p.mask, kind)
		if U.is_err(mb): return fail.call(mb)
		body.set("collision_mask", mb)
	if p.has("props"):
		var pr = U.apply_props(body, U.p_dict(p, "props"))
		if U.is_err(pr): return fail.call(pr)
	if p.has("script"):
		var sp := U.res_path(U.p_str(p, "script"))
		if not ResourceLoader.exists(sp):
			return fail.call(U.err("Script '%s' does not exist." % sp, "Create it first with script.create."))
		body.set_script(load(sp))
	for g in U.p_arr(p, "groups"):
		body.add_to_group(str(g), true)
	# Visual.
	var visual: Node = null
	if p.has("sprite"):
		if is3d:
			var s3 := Sprite3D.new()
			s3.name = "Sprite3D"
			var tex3 = U.to_object(p.sprite, "Texture2D")
			if U.is_err(tex3): return fail.call(tex3)
			s3.texture = tex3
			visual = s3
		else:
			var spr := Sprite2D.new()
			spr.name = "Sprite2D"
			var tex = U.to_object(p.sprite, "Texture2D")
			if U.is_err(tex): return fail.call(tex)
			if not (tex is Texture2D): return fail.call(U.err("sprite must be a texture, got %s." % tex.get_class()))
			spr.texture = tex
			visual = spr
	elif p.has("mesh"):
		if not is3d:
			return fail.call(U.err("mesh is for 3D bodies.", "For 2D pass sprite: 'res://image.png'."))
		var mi := MeshInstance3D.new()
		mi.name = "MeshInstance3D"
		var mesh = U.to_object(p.mesh, "Mesh")
		if U.is_err(mesh): return fail.call(mesh)
		if not (mesh is Mesh): return fail.call(U.err("mesh must be a Mesh, e.g. {\"type\": \"BoxMesh\", \"size\": [1, 1, 1]}."))
		mi.mesh = mesh
		visual = mi
	if visual:
		if p.has("visual_props"):
			var vr = U.apply_props(visual, U.p_dict(p, "visual_props"))
			if U.is_err(vr):
				visual.free()
				return fail.call(vr)
		body.add_child(visual, true)
	# Shapes.
	var specs: Array = U.p_arr(p, "shapes") if p.has("shapes") else [p.get("shape", {"type": "box" if is3d else "rect"})]
	var fitted := []
	for i in specs.size():
		var spec = specs[i]
		if spec is String:
			spec = {"type": spec}
		if not (spec is Dictionary):
			return fail.call(U.err("shape must be an object like {\"type\": \"rect\", \"size\": [32, 32]} or a shape name, got %s." % JSON.stringify(spec)))
		if visual and i == 0 and not _has_size(spec):
			# Size the first shape to the visual.
			var k := _shape_kind(U.p_str(spec, "type", "box" if is3d else "rect"), is3d)
			var fit = _fit_from_visual(visual, body, k, U.p_float(spec, "grow", 0.0), U.p_bool(spec, "trim", true))
			if U.is_err(fit): return fail.call(fit)
			var sn = _shape_node_from_fit(fit, is3d, "CollisionShape3D" if is3d else "CollisionShape2D")
			if spec is Dictionary and U.p_bool(spec, "one_way", false) and sn is CollisionShape2D:
				sn.one_way_collision = true
			body.add_child(sn, true)
			fitted.append(sn.name)
			continue
		var n = build_shape_node(spec, is3d, "" if specs.size() == 1 else "")
		if U.is_err(n): return fail.call(n)
		body.add_child(n, true)
	if p.has("children"):
		for cs in U.p_arr(p, "children"):
			if not (cs is Dictionary): continue
			var c = ctx.router.handlers["node"].build(cs)
			if U.is_err(c): return fail.call(c)
			body.add_child(c, true)
	var u = ctx.begin("Add %s" % cls)
	u.add_do_method(parent, "add_child", body, true)
	u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", body, root)
	u.add_do_reference(body)
	u.add_undo_method(parent, "remove_child", body)
	ctx.commit()
	var out := {"path": ctx.node_path_str(body), "type": cls, "children": body.get_children().map(func(c): return "%s (%s)" % [c.name, c.get_class()])}
	var first_shape = _first_shape_node(body)
	if first_shape and "shape" in first_shape and first_shape.shape:
		out["shape"] = _shape_summary(first_shape.shape)
	if not fitted.is_empty():
		out["fitted_to_visual"] = true
	out["collision_layer"] = _layer_names(body.get("collision_layer"), kind)
	out["collision_mask"] = _layer_names(body.get("collision_mask"), kind)
	var warnings: Array = ctx.router.handlers["node"].configuration_warnings(body)
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


func _first_shape_node(body: Node) -> Node:
	for c in body.get_children():
		if c is CollisionShape2D or c is CollisionShape3D or c is CollisionPolygon2D or c is CollisionPolygon3D:
			return c
	return null


# ---------------------------------------------------------------------------
# fit_shape
# ---------------------------------------------------------------------------

## Sizes a collision shape to a sibling/child visual (Sprite2D, AnimatedSprite2D, Sprite3D, MeshInstance3D...).
func a_fit_shape(p: Dictionary):
	var n = await node_arg(p)
	if U.is_err(n): return n
	var root: Node = ctx.edited_root()
	var body: Node
	var shape_node: Node = null
	if n is CollisionShape2D or n is CollisionShape3D:
		shape_node = n
		body = n.get_parent()
	elif n is CollisionObject2D or n is CollisionObject3D:
		body = n
		for c in n.get_children():
			if c is CollisionShape2D or c is CollisionShape3D:
				shape_node = c
				break
	elif (n is Node2D or n is Node3D) and (n.get_parent() is CollisionObject2D or n.get_parent() is CollisionObject3D) and not p.has("from"):
		# A visual (sprite/mesh) was passed: fit its body's shape to it.
		body = n.get_parent()
		p = p.duplicate()
		p["from"] = ctx.node_path_str(n)
		for c in body.get_children():
			if c is CollisionShape2D or c is CollisionShape3D:
				shape_node = c
				break
	else:
		return U.err("'%s' is a %s; pass a physics body/area or its CollisionShape." % [ctx.node_path_str(n), n.get_class()], "Create one with physics.body.")
	var is3d := body is Node3D
	var visual: Node = null
	if p.has("from"):
		visual = ctx.find_node(U.p_str(p, "from"))
		if visual == null:
			# Allow paths relative to the body.
			visual = body.get_node_or_null(U.p_str(p, "from"))
		if visual == null:
			return ctx.node_not_found(U.p_str(p, "from"))
	else:
		visual = _find_visual(body, is3d)
		if visual == null:
			return U.err("No visual found under '%s' to fit to." % ctx.node_path_str(body), "Add a Sprite2D/AnimatedSprite2D/MeshInstance3D child, or pass from: 'path/to/visual'.")
	var kind := _shape_kind(U.p_str(p, "kind", "box" if is3d else "rect"), is3d)
	if kind == "polygon":
		kind = "convex"
	var fit = _fit_from_visual(visual, body, kind, U.p_float(p, "grow", 0.0), U.p_bool(p, "trim", true))
	if U.is_err(fit): return fit
	var u = ctx.begin("Fit collision shape")
	if shape_node == null:
		shape_node = _shape_node_from_fit(fit, is3d, "CollisionShape3D" if is3d else "CollisionShape2D")
		u.add_do_method(body, "add_child", shape_node, true)
		u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", shape_node, root)
		u.add_do_reference(shape_node)
		u.add_undo_method(body, "remove_child", shape_node)
	else:
		u.add_do_property(shape_node, "shape", fit.shape)
		u.add_undo_property(shape_node, "shape", shape_node.shape)
		u.add_do_property(shape_node, "transform", fit.xform)
		u.add_undo_property(shape_node, "transform", shape_node.transform)
	ctx.commit()
	return {"path": ctx.node_path_str(shape_node), "visual": ctx.node_path_str(visual), "kind": kind, "shape": _shape_summary(shape_node.shape), "position": U.encode(shape_node.position)}


func _find_visual(body: Node, is3d: bool) -> Node:
	var types: Array = ["MeshInstance3D", "Sprite3D", "AnimatedSprite3D", "CSGShape3D", "GeometryInstance3D"] if is3d else ["Sprite2D", "AnimatedSprite2D", "Polygon2D", "TextureRect"]
	for t in types:
		var found := body.find_children("*", t, true, false)
		if not found.is_empty():
			return found[0]
	return null


func _shape_node_from_fit(fit: Dictionary, is3d: bool, name: String) -> Node:
	var sn: Node = CollisionShape3D.new() if is3d else CollisionShape2D.new()
	sn.name = name
	sn.set("shape", fit.shape)
	sn.set("transform", fit.xform)
	return sn


## Transform of `n` relative to `ancestor` (works for detached subtrees).
func _rel_xform(n: Node, ancestor: Node):
	var is3d := n is Node3D
	var xf = Transform3D.IDENTITY if is3d else Transform2D.IDENTITY
	var cur := n
	while cur != null and cur != ancestor:
		if is3d and cur is Node3D:
			xf = (cur as Node3D).transform * xf
		elif not is3d and cur is Node2D:
			xf = (cur as Node2D).transform * xf
		elif not is3d and cur is Control:
			xf = Transform2D(0, (cur as Control).position) * xf
		cur = cur.get_parent()
	return xf


## Computes {shape, xform} (shape-node transform relative to body) for a visual.
func _fit_from_visual(visual: Node, body: Node, kind: String, grow: float, trim: bool = true):
	if body is Node3D:
		return _fit_3d(visual, body, kind, grow)
	var rect = _visual_rect_2d(visual)
	if U.is_err(rect): return rect
	if trim and (visual is Sprite2D or visual is AnimatedSprite2D):
		# Fit the opaque pixels, not the whole (often padded) frame.
		var opaque = _opaque_rect(visual)
		if opaque != null:
			rect = opaque
	var rel: Transform2D = _rel_xform(visual, body)
	if kind == "convex" or kind == "concave":
		var pts = _alpha_hull(visual)
		if U.is_err(pts): return pts
		var world_pts := PackedVector2Array()
		for pt in pts:
			world_pts.append(rel * pt)
		if grow != 0.0:
			var grown := Geometry2D.offset_polygon(world_pts, grow)
			if not grown.is_empty():
				world_pts = grown[0]
		var cv := ConvexPolygonShape2D.new()
		cv.points = world_pts
		return {"shape": cv, "xform": Transform2D.IDENTITY}
	# Bounding box of the transformed rect.
	var r: Rect2 = rect
	var corners := [rel * r.position, rel * Vector2(r.end.x, r.position.y), rel * r.end, rel * Vector2(r.position.x, r.end.y)]
	var bb := Rect2(corners[0], Vector2.ZERO)
	for c in corners:
		bb = bb.expand(c)
	bb = bb.grow(grow)
	var center := bb.get_center()
	var sz := bb.size
	match kind:
		"rect":
			var rs := RectangleShape2D.new()
			rs.size = sz
			return {"shape": rs, "xform": Transform2D(0, center)}
		"circle":
			var cs := CircleShape2D.new()
			cs.radius = minf(sz.x, sz.y) / 2.0
			return {"shape": cs, "xform": Transform2D(0, center)}
		"capsule":
			var cp := CapsuleShape2D.new()
			if sz.y >= sz.x:
				cp.radius = sz.x / 2.0
				cp.height = sz.y
				return {"shape": cp, "xform": Transform2D(0, center)}
			cp.radius = sz.y / 2.0
			cp.height = sz.x
			return {"shape": cp, "xform": Transform2D(PI / 2.0, center)}
	return U.err("fit_shape kind '%s' is not supported in 2D." % kind, "Use rect, circle, capsule or convex.")


func _visual_rect_2d(v: Node):
	if v is Sprite2D:
		if v.texture == null:
			return U.err("Sprite2D '%s' has no texture." % v.name)
		return v.get_rect()
	if v is AnimatedSprite2D:
		var sf: SpriteFrames = v.sprite_frames
		if sf == null or not sf.has_animation(v.animation) or sf.get_frame_count(v.animation) == 0:
			return U.err("AnimatedSprite2D '%s' has no frames." % v.name, "Build its SpriteFrames first.")
		var tex := sf.get_frame_texture(v.animation, clampi(v.frame, 0, sf.get_frame_count(v.animation) - 1))
		var size := Vector2(tex.get_size()) if tex else Vector2.ZERO
		var pos: Vector2 = v.offset - (size / 2.0 if v.centered else Vector2.ZERO)
		return Rect2(pos, size)
	if v is Polygon2D:
		var poly: PackedVector2Array = v.polygon
		if poly.is_empty():
			return U.err("Polygon2D has no points.")
		var r := Rect2(poly[0] + v.offset, Vector2.ZERO)
		for pt in poly:
			r = r.expand(pt + v.offset)
		return r
	if v is Control:
		return Rect2(Vector2.ZERO, v.size)
	return U.err("Can't fit to a %s." % v.get_class(), "Supported: Sprite2D, AnimatedSprite2D, Polygon2D.")


## Image of a texture; reads the source file directly when possible (works headless).
func _tex_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img: Image = null
	var tp := tex.resource_path
	if tp.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "bmp", "tga"] and FileAccess.file_exists(tp):
		img = Image.load_from_file(ProjectSettings.globalize_path(tp))
	if img == null or img.is_empty():
		img = tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	return img


## Current frame of a Sprite2D / AnimatedSprite2D: {img: frame Image, rect: local Rect2, flip_h, flip_v}, or null
## when the pixels can't be read.
func _frame_pixels(v: Node):
	if v is Sprite2D:
		var spr: Sprite2D = v
		var img := _tex_image(spr.texture)
		if img == null:
			return null
		var region := Rect2i(Vector2i.ZERO, img.get_size())
		if spr.region_enabled:
			region = Rect2i(spr.region_rect).intersection(region)
		var fsize := Vector2i(region.size.x / spr.hframes, region.size.y / spr.vframes)
		var fc := Vector2i(spr.frame % spr.hframes, spr.frame / spr.hframes)
		region = Rect2i(region.position + fc * fsize, fsize)
		if region.size.x <= 0 or region.size.y <= 0:
			return null
		return {"img": img.get_region(region), "rect": spr.get_rect(), "flip_h": spr.flip_h, "flip_v": spr.flip_v}
	if v is AnimatedSprite2D:
		var sf: SpriteFrames = v.sprite_frames
		if sf == null or not sf.has_animation(v.animation) or sf.get_frame_count(v.animation) == 0:
			return null
		var tex := sf.get_frame_texture(v.animation, clampi(v.frame, 0, sf.get_frame_count(v.animation) - 1))
		var img2: Image = null
		if tex is AtlasTexture and tex.atlas:
			var full := _tex_image(tex.atlas)
			if full:
				var reg := Rect2i(tex.region).intersection(Rect2i(Vector2i.ZERO, full.get_size()))
				if reg.size.x > 0 and reg.size.y > 0:
					img2 = full.get_region(reg)
		elif tex:
			img2 = _tex_image(tex)
		if img2 == null:
			return null
		var rect = _visual_rect_2d(v)
		if U.is_err(rect):
			return null
		return {"img": img2, "rect": rect, "flip_h": v.flip_h, "flip_v": v.flip_v}
	return null


## Maps a pixel of the frame image to the visual's local coordinates (flips mirror inside the rect).
func _px_to_local(fp: Dictionary, pt: Vector2) -> Vector2:
	var r: Rect2 = fp.rect
	var local: Vector2 = r.position + pt * (r.size / Vector2(fp.img.get_size()))
	if fp.flip_h:
		local.x = r.position.x + r.end.x - local.x
	if fp.flip_v:
		local.y = r.position.y + r.end.y - local.y
	return local


## Bounding rect of the opaque pixels of the current frame (local coords), or null.
func _opaque_rect(v: Node):
	var fp = _frame_pixels(v)
	if fp == null:
		return null
	var used: Rect2i = fp.img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	var a := _px_to_local(fp, Vector2(used.position))
	var b := _px_to_local(fp, Vector2(used.end))
	return Rect2(a, Vector2.ZERO).expand(b)


## Convex hull of opaque pixels of a sprite's current frame, in sprite-local coordinates.
func _alpha_hull(v: Node):
	if not (v is Sprite2D or v is AnimatedSprite2D):
		return U.err("convex fitting needs a Sprite2D or AnimatedSprite2D (got %s)." % v.get_class(), "Use kind 'rect', 'circle' or 'capsule'.")
	var fp = _frame_pixels(v)
	if fp == null:
		return U.err("Could not read the sprite's image data.", "Use kind 'rect' or 'capsule' instead.")
	var sub: Image = fp.img
	var bm := BitMap.new()
	bm.create_from_image_alpha(sub, 0.1)
	var polys := bm.opaque_to_polygons(Rect2i(Vector2i.ZERO, sub.get_size()), 1.0)
	var all_pts := PackedVector2Array()
	for poly in polys:
		all_pts.append_array(poly)
	if all_pts.size() < 3:
		return U.err("The sprite frame is fully transparent.")
	var hull := Geometry2D.convex_hull(all_pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	var out := PackedVector2Array()
	for pt in hull:
		out.append(_px_to_local(fp, pt))
	if fp.flip_h != fp.flip_v:
		out.reverse()  # a single mirror flips the winding; keep the hull's original orientation
	return out


func _fit_3d(visual: Node, body: Node, kind: String, grow: float):
	if not (visual is VisualInstance3D):
		return U.err("Can't fit to a %s." % visual.get_class(), "Supported: MeshInstance3D, Sprite3D, CSG shapes, other GeometryInstance3D.")
	var rel: Transform3D = _rel_xform(visual, body)
	if kind == "convex" or kind == "concave":
		if not (visual is MeshInstance3D) or visual.mesh == null:
			return U.err("%s fitting needs a MeshInstance3D with a mesh." % kind, "Use kind 'box', 'sphere', 'capsule' or 'cylinder'.")
		var mesh: Mesh = visual.mesh
		var shp: Shape3D = mesh.create_convex_shape(true, false) if kind == "convex" else mesh.create_trimesh_shape()
		if shp == null:
			return U.err("Could not build a %s shape from the mesh." % kind)
		return {"shape": shp, "xform": rel}
	var aabb: AABB = (visual as VisualInstance3D).get_aabb()
	if aabb.size == Vector3.ZERO:
		return U.err("'%s' has an empty bounding box (no mesh/texture?)." % visual.name)
	# AABB in body space (axis aligned), grown.
	aabb = rel * aabb
	aabb = aabb.grow(grow)
	var center := aabb.get_center()
	var sz := aabb.size
	var xf := Transform3D(Basis.IDENTITY, center)
	match kind:
		"box":
			var b := BoxShape3D.new()
			b.size = sz
			return {"shape": b, "xform": xf}
		"sphere":
			var s := SphereShape3D.new()
			s.radius = maxf(sz.x, maxf(sz.y, sz.z)) / 2.0
			return {"shape": s, "xform": xf}
		"capsule":
			var c := CapsuleShape3D.new()
			c.radius = maxf(sz.x, sz.z) / 2.0
			c.height = maxf(sz.y, c.radius * 2.0)
			return {"shape": c, "xform": xf}
		"cylinder":
			var cy := CylinderShape3D.new()
			cy.radius = maxf(sz.x, sz.z) / 2.0
			cy.height = sz.y
			return {"shape": cy, "xform": xf}
	return U.err("fit_shape kind '%s' is not supported in 3D." % kind, "Use box, sphere, capsule, cylinder, convex or trimesh.")


# ---------------------------------------------------------------------------
# joint
# ---------------------------------------------------------------------------

func a_joint(p: Dictionary):
	var e = U.require(p, ["type", "node_a", "node_b"])
	if e: return e
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var tname := U.p_str(p, "type")
	var cls: String = JOINT_TYPES.get(tname.to_lower(), tname)
	if not ClassDB.class_exists(cls) or not (ClassDB.is_parent_class(cls, "Joint2D") or ClassDB.is_parent_class(cls, "Joint3D")) or not ClassDB.can_instantiate(cls):
		var s := U.suggest(tname, JOINT_TYPES.keys())
		return U.err("Unknown joint type '%s'." % tname, ("Did you mean '%s'? " % s if s != "" else "") + "Types: " + ", ".join(JOINT_TYPES.keys()) + ". A rope/chain = several small rigid bodies linked by pin joints.")
	var is3d := ClassDB.is_parent_class(cls, "Joint3D")
	var a: Node = ctx.find_node(U.p_str(p, "node_a"))
	if a == null: return ctx.node_not_found(U.p_str(p, "node_a"))
	var b: Node = ctx.find_node(U.p_str(p, "node_b"))
	if b == null: return ctx.node_not_found(U.p_str(p, "node_b"))
	for pair in [["node_a", a], ["node_b", b]]:
		var nd: Node = pair[1]
		var ok := (nd is PhysicsBody3D) if is3d else (nd is PhysicsBody2D)
		if not ok:
			var jhint := "Create bodies with physics.body (rigid/static/animatable)."
			if (nd is PhysicsBody2D) if is3d else (nd is PhysicsBody3D):
				jhint = "These are %s bodies: use a %s joint type (%s)." % ["2D" if is3d else "3D", "2D" if is3d else "3D", "pin_2d, groove_2d, damped_spring_2d" if is3d else "pin_3d, hinge_3d, slider_3d, cone_3d, generic_6dof_3d"]
			return U.err("%s '%s' is a %s; %s joints connect %s physics bodies." % [pair[0], ctx.node_path_str(nd), nd.get_class(), cls, "3D" if is3d else "2D"], jhint)
	if a == b:
		return U.err("node_a and node_b must be different bodies.")
	var parent: Node = ctx.find_node(U.p_str(p, "parent")) if p.has("parent") else a.get_parent()
	if parent == null:
		return ctx.node_not_found(U.p_str(p, "parent"))
	var j: Node = ClassDB.instantiate(cls)
	j.name = U.p_str(p, "name", cls)
	# Anchor: explicit position (parent space), or at: a | b | mid (default mid).
	var at := U.p_str(p, "at", "mid")
	if p.has("position"):
		j.set("position", U.to_vector(p.position, TYPE_VECTOR3 if is3d else TYPE_VECTOR2))
	else:
		var ga = a.global_position
		var gb = b.global_position
		var g = ga if at == "a" else (gb if at == "b" else (ga + gb) / 2.0)
		var inv = (parent.global_transform as Variant).affine_inverse() if (parent is Node2D or parent is Node3D) else null
		j.set("position", inv * g if inv != null else g)
	j.set("node_a", NodePath(_rel_path(parent, a)))
	j.set("node_b", NodePath(_rel_path(parent, b)))
	if cls == "GrooveJoint2D" and not (p.get("props", {}) as Dictionary).has("length"):
		j.set("length", maxf(10.0, (b.global_position - a.global_position).length()))
	if cls == "DampedSpringJoint2D" and not (p.get("props", {}) as Dictionary).has("length"):
		var d: float = (b.global_position - a.global_position).length()
		if d > 1.0:
			j.set("length", d)
			j.set("rest_length", d)
	if p.has("props"):
		var pr = U.apply_props(j, U.p_dict(p, "props"))
		if U.is_err(pr):
			j.free()
			return pr
	var u = ctx.begin("Add %s" % cls)
	u.add_do_method(parent, "add_child", j, true)
	u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", j, root)
	u.add_do_reference(j)
	u.add_undo_method(parent, "remove_child", j)
	ctx.commit()
	return {"path": ctx.node_path_str(j), "type": cls, "node_a": str(j.get("node_a")), "node_b": str(j.get("node_b")), "position": U.encode(j.get("position"))}


func _rel_path(from_parent: Node, to: Node) -> String:
	var rel := str(from_parent.get_path_to(to))
	return ".." if rel == "." else "../" + rel


# ---------------------------------------------------------------------------
# raycast (editor world)
# ---------------------------------------------------------------------------

func a_raycast(p: Dictionary):
	var e = U.require(p, ["from", "to"])
	if e: return e
	var root = root_or_err()
	if U.is_err(root): return root
	var from_v = p.from
	var is3d: bool = (from_v is Array and from_v.size() == 3) or (from_v is String and from_v.begins_with("Vector3")) or (from_v is Dictionary and from_v.has("z")) or U.p_str(p, "type").to_lower() == "3d"
	var mask := 0xFFFFFFFF
	if p.has("mask"):
		var mb = layer_bits(p.mask, "3d_physics" if is3d else "2d_physics")
		if U.is_err(mb): return mb
		mask = mb
	var areas := U.p_bool(p, "areas", false)
	# The edited scene lives in the editor's own world; its physics space is flushed by the
	# engine each frame, so direct queries work for bodies already in the tree.
	await ctx.frame()
	await ctx.plugin.get_tree().physics_frame
	var hit := {}
	if is3d:
		var w3: World3D = (root as Node).get_viewport().find_world_3d() if root.get_viewport() else null
		if w3 == null:
			return U.err("No 3D world for the edited scene.")
		var q := PhysicsRayQueryParameters3D.create(U.to_vector(p.from, TYPE_VECTOR3), U.to_vector(p.to, TYPE_VECTOR3), mask)
		q.collide_with_areas = areas
		hit = w3.direct_space_state.intersect_ray(q)
	else:
		var w2: World2D = (root as Node).get_viewport().find_world_2d() if root.get_viewport() else null
		if w2 == null:
			return U.err("No 2D world for the edited scene.")
		var q2 := PhysicsRayQueryParameters2D.create(U.to_vector(p.from, TYPE_VECTOR2), U.to_vector(p.to, TYPE_VECTOR2), mask)
		q2.collide_with_areas = areas
		hit = w2.direct_space_state.intersect_ray(q2)
	if hit.is_empty():
		return {"hit": false, "note": "Queries the edited scene in the editor (global coordinates). For the running game use game.raycast."}
	var col = hit.get("collider")
	var out := {"hit": true, "position": U.encode(hit.position), "normal": U.encode(hit.normal)}
	if col is Node:
		out["collider"] = ctx.node_path_str(col)
		out["collider_type"] = col.get_class()
	if hit.has("shape"):
		out["shape_index"] = hit.shape
	out["distance"] = (hit.position - U.to_vector(p.from, TYPE_VECTOR3 if is3d else TYPE_VECTOR2)).length()
	return out


# ---------------------------------------------------------------------------
# settings
# ---------------------------------------------------------------------------

func a_settings(p: Dictionary):
	var changes := {}
	for key in p:
		if key in ["scene"]:
			continue
		if key == "settings" and p[key] is Dictionary:
			for k2 in p[key]:
				var full := str(k2) if str(k2).begins_with("physics/") else ""
				if full == "" or not ProjectSettings.has_setting(full):
					return U.err("Unknown physics setting '%s'." % k2, "Use a full name under physics/, e.g. 'physics/2d/default_gravity', or a friendly key: " + ", ".join(SETTINGS.keys()))
				changes[full] = p[key][k2]
			continue
		if not SETTINGS.has(key):
			var s := U.suggest(str(key), SETTINGS.keys())
			return U.err("Unknown physics setting '%s'." % key, ("Did you mean '%s'? " % s if s != "" else "") + "Keys: " + ", ".join(SETTINGS.keys()) + ", or settings: {'physics/...': value}.")
		changes[SETTINGS[key]] = p[key]
	var applied := {}
	if not changes.is_empty():
		var coerced := {}
		for full in changes:
			var cur = ProjectSettings.get_setting(full)
			var v = changes[full]
			if full.ends_with("physics_engine"):
				v = _engine_name(str(v), full.contains("/2d/"))
				if U.is_err(v): return v
			elif cur != null:
				v = U.coerce(v, typeof(cur))
				if U.is_err(v):
					v["message"] = "%s: %s" % [full, v.message]
					return v
			coerced[full] = v
		ctx.before_write(["res://project.godot"])
		for full in coerced:
			ProjectSettings.set_setting(full, coerced[full])
			applied[full] = U.encode(coerced[full])
		ProjectSettings.save()
	var current := {}
	for key in SETTINGS:
		current[key] = U.encode(ProjectSettings.get_setting(SETTINGS[key]))
	var out := {"current": current}
	if not applied.is_empty():
		out["changed"] = applied
		if applied.keys().any(func(k): return str(k).ends_with("physics_engine")):
			out["note"] = "Physics engine changes take effect after restarting the editor/game."
	return out


func _engine_name(v: String, is2d: bool):
	var options := ["DEFAULT", "GodotPhysics2D", "Dummy"] if is2d else ["DEFAULT", "GodotPhysics3D", "Jolt Physics", "Dummy"]
	for o in options:
		if o.to_lower() == v.to_lower() or o.to_lower().replace(" ", "_") == v.to_lower() or (v.to_lower() == "jolt" and o.begins_with("Jolt")) or (v.to_lower() == "godot" and o.begins_with("GodotPhysics")):
			return o
	return U.err("Unknown physics engine '%s'." % v, "Options: " + ", ".join(options))


## Compact description of a shape (hulls/trimeshes report point counts instead of every vertex).
func _shape_summary(shape: Resource) -> Variant:
	if shape is ConvexPolygonShape2D or shape is ConvexPolygonShape3D:
		var pts = shape.points
		if pts.size() > 12:
			return {"type": shape.get_class(), "points": pts.size()}
	elif shape is ConcavePolygonShape3D:
		return {"type": shape.get_class(), "triangles": shape.get_faces().size() / 3}
	elif shape is ConcavePolygonShape2D:
		return {"type": shape.get_class(), "segments": shape.segments.size() / 2}
	return U.encode_object(shape)
