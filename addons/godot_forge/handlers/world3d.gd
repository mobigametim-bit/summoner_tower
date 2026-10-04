@tool
extends "res://addons/godot_forge/handlers/base.gd"
## 3D world building: primitive meshes, CSG blockouts, materials, lights, environment/sky,
## cameras, model import options and instancing, GridMap/MeshLibrary, and scattering.

const MAT_TYPES := {"standard": "StandardMaterial3D", "orm": "ORMMaterial3D", "shader": "ShaderMaterial"}
const FRIENDLY_MAT_KEYS := ["albedo_color", "albedo_texture", "metallic", "roughness", "emission", "emission_energy", "emission_texture",
	"normal_texture", "normal_scale", "ao_texture", "height_texture", "unshaded", "transparent", "double_sided", "uv_scale", "triplanar",
	"billboard", "rim", "clearcoat", "filter"]
const SHAPES := ["box", "sphere", "capsule", "cylinder", "cone", "plane", "prism", "torus", "quad", "text"]
const CSG_TYPES := {
	"box": "CSGBox3D", "cube": "CSGBox3D", "sphere": "CSGSphere3D", "cylinder": "CSGCylinder3D", "cone": "CSGCylinder3D",
	"torus": "CSGTorus3D", "polygon": "CSGPolygon3D", "mesh": "CSGMesh3D", "combiner": "CSGCombiner3D",
}
const CSG_KEYS := ["size", "radius", "height", "inner_radius", "outer_radius", "sides", "ring_sides", "cone",
	"polygon", "depth", "mode", "spin_degrees", "spin_sides", "path_node", "smooth_faces", "flip_faces",
	"radial_segments", "rings", "mesh", "material", "operation", "use_collision", "collision_layer", "collision_mask"]
const LIGHT_TYPES := {"directional": "DirectionalLight3D", "omni": "OmniLight3D", "point": "OmniLight3D", "spot": "SpotLight3D"}
const PRESETS := ["default", "sunny", "night", "foggy", "studio", "space"]
const SCENE_IMPORT_ALIASES := {
	"root_type": "nodes/root_type", "root_name": "nodes/root_name", "root_scale": "nodes/root_scale",
	"scale": "nodes/root_scale", "apply_root_scale": "nodes/apply_root_scale", "root_script": "nodes/root_script",
	"import_animation": "animation/import", "animation": "animation/import", "fps": "animation/fps",
	"generate_lods": "meshes/generate_lods", "lods": "meshes/generate_lods", "light_baking": "meshes/light_baking",
	"lightmap_texel_size": "meshes/lightmap_texel_size", "ensure_tangents": "meshes/ensure_tangents",
	"shadow_meshes": "meshes/create_shadow_meshes", "create_shadow_meshes": "meshes/create_shadow_meshes",
	"use_name_suffixes": "nodes/use_name_suffixes", "extract_materials": "materials/extract",
}
const LIGHT_BAKING := {"disabled": 0, "static": 1, "static_lightmaps": 2, "dynamic": 3}
const SHAPE_TYPES := {"decompose_convex": 0, "convex": 1, "simple_convex": 1, "trimesh": 2, "concave": 2, "box": 3, "sphere": 4, "cylinder": 5, "capsule": 6, "auto": 7, "automatic": 7}
const BODY_TYPES := {"static": 0, "rigid": 1, "dynamic": 1, "area": 2}


# =============================================================================
# Shared helpers
# =============================================================================

## Opens p.scene if given and resolves p[key] (default ".") as the parent node.
func _parent_arg(p: Dictionary, key: String = "parent"):
	if p.has("scene") and U.p_str(p, "scene") != "":
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var pp := U.p_str(p, key, ".")
	var parent: Node = ctx.find_node(pp)
	if parent == null:
		return ctx.node_not_found(pp)
	return parent


## Adds detached nodes under parent as one undoable action.
func _add_nodes(parent: Node, nodes: Array, label: String) -> void:
	var root: Node = ctx.edited_root()
	var nh = ctx.router.handlers["node"]
	var u = ctx.begin(label)
	for n in nodes:
		u.add_do_method(parent, "add_child", n, true)
		u.add_do_method(nh, "set_owner_rec", n, root)
		u.add_do_reference(n)
		u.add_undo_method(parent, "remove_child", n)
	ctx.commit()


func _v3(v, def: Vector3 = Vector3.ZERO) -> Vector3:
	if v == null:
		return def
	if v is int or v is float:
		return Vector3(v, v, v)
	var r = U.to_vector(v, TYPE_VECTOR3)
	return r if r is Vector3 else def


func _v2(v, def: Vector2 = Vector2.ZERO) -> Vector2:
	if v == null:
		return def
	if v is int or v is float:
		return Vector2(v, v)
	var r = U.to_vector(v, TYPE_VECTOR2)
	return r if r is Vector2 else def


func _is_color_str(v) -> bool:
	if not (v is String) or str(v).begins_with("res://") or str(v).begins_with("uid://"):
		return false
	var s := str(v).strip_edges()
	if s.begins_with("#") or s.begins_with("Color(") or Color.html_is_valid(s):
		return true
	# Named colors ('red', 'dark_green') — never file-like strings.
	return not s.contains("/") and not s.contains(".") and _named_color(s) != null


const _SENTINEL := Color(0.1234, 0.4321, 0.9876, 0.5432)


func _named_color(s: String) -> Variant:
	var c := Color.from_string(s, _SENTINEL)
	return null if c == _SENTINEL else c


## Strict number from JSON (numeric strings accepted). Returns float or an error dict.
func _num(v, key: String, lo: float = -INF, hi: float = INF) -> Variant:
	var f := 0.0
	if v is int or v is float:
		f = float(v)
	elif v is String and (str(v).strip_edges().is_valid_float() or str(v).strip_edges().is_valid_int()):
		f = str(v).strip_edges().to_float()
	else:
		return U.err("'%s' must be a number (got %s)." % [key, JSON.stringify(v)], "e.g. %s: %s" % [key, str(maxf(lo, 1.0)) if lo > -INF else "1.5"])
	if is_nan(f) or is_inf(f):
		return U.err("'%s' must be a finite number." % key)
	if f < lo or f > hi:
		var rng := "at least %s" % lo
		if hi < INF:
			rng = "between %s and %s" % [lo, hi]
		elif lo > 0.0 and lo < 0.01:
			rng = "greater than 0"
		return U.err("'%s' must be %s (got %s)." % [key, rng, f])
	return f


## Strict Vector3 from JSON: [x,y,z], {x,y,z}, "Vector3(1, 2, 3)", "1,2,3" (or a number when
## allow_scalar). Returns Vector3 or an error dict.
func _vec3(v, key: String, allow_scalar: bool = false) -> Variant:
	if v is Vector3 or v is Vector3i:
		return Vector3(v)
	if allow_scalar and (v is int or v is float or (v is String and str(v).is_valid_float())):
		var f = _num(v, key)
		if U.is_err(f): return f
		return Vector3(f, f, f)
	var comps := []
	if v is Array:
		comps = v
	elif v is Dictionary and v.has("x") and v.has("y") and v.has("z"):
		comps = [v.x, v.y, v.z]
	elif v is String:
		var parsed = str_to_var(str(v)) if str(v).begins_with("Vector3") else null
		if parsed is Vector3 or parsed is Vector3i:
			return Vector3(parsed)
		comps = Array(str(v).replace("(", " ").replace(")", " ").replace(",", " ").split(" ", false))
	if comps.size() != 3:
		return U.err("'%s' must be [x, y, z] (got %s)." % [key, JSON.stringify(v)], "e.g. %s: %s%s" % [key, "[2, 1, 2]" if (key.contains("size") or key.contains("scale")) else "[0, 1.5, -2]", " or a single number" if allow_scalar else ""])
	var out := []
	for c in comps:
		var f2 = _num(c, key)
		if U.is_err(f2):
			return U.err("'%s' must be [x, y, z] numbers (got %s)." % [key, JSON.stringify(v)])
		out.append(f2)
	return Vector3(out[0], out[1], out[2])


## Strict color: '#hex', 'red', 'Color(...)', [r,g,b(,a)] (0-1 or 0-255), {r,g,b,a}. Color or error.
func _color(v, key: String) -> Variant:
	if v is Color:
		return v
	if v is String:
		var s := str(v).strip_edges()
		if s.begins_with("Color("):
			var c = str_to_var(s)
			if c is Color:
				return c
		if Color.html_is_valid(s):
			return Color.html(s)
		var named = _named_color(s)
		if named != null:
			return named
	elif v is Array and v.size() in [3, 4] and v.all(func(x): return x is int or x is float):
		return U.to_color(v)
	elif v is Dictionary and v.has("r") and v.has("g") and v.has("b"):
		return U.to_color(v)
	return U.err("'%s': %s is not a color." % [key, JSON.stringify(v)], "Use a hex color like '#ff8800', a name like 'orange', or [r, g, b] (0-1 or 0-255).")


## Applies position / rotation_degrees / scale from p to a detached or attached Node3D.
## Returns an error dict for malformed values, else null.
func _apply_xform(n: Node3D, p: Dictionary) -> Variant:
	if p.has("position") and p.position != null:
		var v = _vec3(p.position, "position")
		if U.is_err(v): return v
		n.position = v
	var rk := "rotation_degrees" if p.has("rotation_degrees") else ("rotation" if p.has("rotation") else "")
	if rk != "" and p[rk] != null:
		var r = _vec3(p[rk], rk)
		if U.is_err(r): return r
		n.rotation_degrees = r
	if p.has("scale") and p.scale != null:
		var s = _vec3(p.scale, "scale", true)
		if U.is_err(s): return s
		if s.x == 0 or s.y == 0 or s.z == 0:
			return U.err("'scale' components must not be 0 (got %s)." % JSON.stringify(p.scale))
		n.scale = s
	return null


## Resolves a look target: [x,y,z] (global point) or a node path (its global position).
func _target_point(t):
	if t is Array or t is Dictionary or (t is String and str(t).begins_with("Vector3")):
		return _vec3(t, "look_at target")
	if t is String:
		var tn: Node = ctx.find_node(str(t))
		if tn == null:
			return ctx.node_not_found(str(t))
		if not (tn is Node3D):
			return U.err("Target '%s' is a %s, not a Node3D." % [t, tn.get_class()], "Pass a Node3D path or a point [x, y, z].")
		return (tn as Node3D).global_position
	return U.err("Invalid look target %s." % JSON.stringify(t), "Pass a point [x, y, z] or a node path like 'Player'.")


## Global transform of a (possibly not yet added) child of parent.
func _parent_global(parent: Node) -> Transform3D:
	if parent is Node3D and parent.is_inside_tree():
		return (parent as Node3D).global_transform
	return Transform3D.IDENTITY


## Local transform for node n (child of parent) so that it faces a global point.
func _look_xform(n: Node3D, parent: Node, target: Vector3, model_front: bool = false):
	var pg := _parent_global(parent)
	var gpos: Vector3 = pg * n.position
	var dir := target - gpos
	if dir.length() < 0.0001:
		return U.err("The target is at the node's own position; can't look at it.", "Move the node or pick another target.")
	var up := Vector3.UP
	if absf(dir.normalized().dot(up)) > 0.999:
		up = Vector3.FORWARD
	var gbasis := Basis.looking_at(dir, up, model_front)
	var local_basis := (pg.basis.inverse() * gbasis).orthonormalized() * Basis.from_scale(n.scale)
	return Transform3D(local_basis, n.position)


# =============================================================================
# Materials
# =============================================================================

## Builds a Material from "res://m.tres" | "#hex" | "res://x.gdshader" | {type?, ...friendly props}.
func build_material(spec):
	if spec == null:
		return null
	if spec is Material:
		return spec
	if spec is String:
		var s: String = spec
		if _is_color_str(s):
			var m := StandardMaterial3D.new()
			apply_material_props(m, {"albedo_color": s})
			return m
		var rp := U.res_path(s)
		if rp.get_extension() == "gdshader":
			return make_material("shader", {"shader": rp})
		if not ResourceLoader.exists(rp):
			return U.err("Material '%s' does not exist." % rp, "Pass a res:// material (.tres), a hex color like '#aa8844', or {\"albedo_color\": \"#aa8844\", \"roughness\": 0.8} to create one inline.")
		var r = load(rp)
		if not (r is Material):
			return U.err("'%s' is a %s, not a Material." % [rp, r.get_class() if r else "null"])
		return r
	if spec is Dictionary:
		var d: Dictionary = spec
		if d.has("path") and d.size() == 1:
			return build_material(str(d.path))
		var t := str(d.get("type", "shader" if d.has("shader") else "standard"))
		return make_material(t, d)
	return U.err("Invalid material %s." % JSON.stringify(spec), "Pass a res:// path, a hex color or a dict of material props.")


func make_material(t: String, props: Dictionary):
	var cls: String = MAT_TYPES.get(t.to_lower(), t)
	if not ClassDB.class_exists(cls) or not ClassDB.is_parent_class(cls, "Material") or not ClassDB.can_instantiate(cls):
		return U.err("Unknown material type '%s'." % t, "Use 'standard', 'orm' or 'shader' (or a Material class such as CanvasItemMaterial).")
	var m: Material = ClassDB.instantiate(cls)
	var r = apply_material_props(m, props)
	if U.is_err(r): return r
	return m


## Friendly material properties. BaseMaterial3D: albedo_color/color, albedo_texture/texture,
## emission (color), emission_energy, normal_texture, unshaded, transparent, double_sided,
## uv_scale, triplanar, filter ('nearest'), ... Anything else is set as a raw property.
func apply_material_props(m: Material, props: Dictionary) -> Variant:
	if m is ShaderMaterial:
		var sh = ctx.router.handlers.get("shader")
		if sh == null:
			return U.err("The shader handler is not loaded.")
		return sh.configure_material(m, props)
	var skip := ["type", "path"]
	if not (m is BaseMaterial3D):
		return U.apply_props(m, props, skip)
	var bm: BaseMaterial3D = m
	for key in props:
		if key in skip:
			continue
		var v = props[key]
		var r = null
		var num = null  # validated number for the numeric friendly keys
		if str(key) in ["emission_energy", "emission_energy_multiplier", "normal_scale", "normal_strength", "rim", "clearcoat"]:
			num = _num(v, str(key))
			if U.is_err(num):
				num["message"] = "Material: " + str(num.message)
				return num
		match str(key):
			"color", "albedo", "albedo_color":
				var c = _color(v, str(key))
				if U.is_err(c):
					r = c
				else:
					bm.albedo_color = c
					if c.a < 0.999 and not props.has("transparency") and not props.has("transparent"):
						bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			"texture", "albedo_texture":
				r = U.set_prop(bm, "albedo_texture", v)
			"emission", "emission_color":
				if v is bool:
					bm.emission_enabled = v
				else:
					var ec = _color(v, str(key))
					if U.is_err(ec):
						r = ec
					else:
						bm.emission_enabled = true
						bm.emission = ec
			"emission_energy", "emission_energy_multiplier":
				bm.emission_enabled = true
				bm.emission_energy_multiplier = num
			"emission_texture":
				bm.emission_enabled = true
				r = U.set_prop(bm, "emission_texture", v)
			"normal_texture", "normal_map":
				bm.normal_enabled = true
				r = U.set_prop(bm, "normal_texture", v)
			"normal_scale", "normal_strength":
				bm.normal_enabled = true
				bm.normal_scale = num
			"ao_texture":
				bm.ao_enabled = true
				r = U.set_prop(bm, "ao_texture", v)
			"height_texture", "heightmap_texture":
				bm.heightmap_enabled = true
				r = U.set_prop(bm, "heightmap_texture", v)
			"unshaded":
				bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if U.coerce(v, TYPE_BOOL) else BaseMaterial3D.SHADING_MODE_PER_PIXEL
			"transparent":
				bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if U.coerce(v, TYPE_BOOL) else BaseMaterial3D.TRANSPARENCY_DISABLED
			"double_sided":
				bm.cull_mode = BaseMaterial3D.CULL_DISABLED if U.coerce(v, TYPE_BOOL) else BaseMaterial3D.CULL_BACK
			"uv_scale", "uv1_scale":
				var uv = _vec3(v + [1] if (v is Array and v.size() == 2) else v, str(key), true)
				if U.is_err(uv):
					r = uv
				else:
					bm.uv1_scale = uv
			"triplanar", "uv1_triplanar":
				bm.uv1_triplanar = U.coerce(v, TYPE_BOOL)
			"billboard":
				if v is bool:
					bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if v else BaseMaterial3D.BILLBOARD_DISABLED
				else:
					r = U.set_prop(bm, "billboard_mode", v)
			"rim":
				bm.rim_enabled = true
				bm.rim = num
			"clearcoat":
				bm.clearcoat_enabled = true
				bm.clearcoat = num
			"filter":
				r = U.set_prop(bm, "texture_filter", "nearest" if str(v) in ["nearest", "pixel"] else v)
			"metallic", "roughness", "metallic_texture", "roughness_texture":
				if bm is ORMMaterial3D:
					return U.err("ORMMaterial3D ignores '%s': metallic and roughness come from orm_texture (R=AO, G=roughness, B=metallic)." % key, "Pass orm_texture='res://x_orm.png', or use type='standard' for scalar metallic/roughness.")
				r = U.set_prop(bm, str(key), v)
			_:
				if not str(key) in bm:
					var cands := FRIENDLY_MAT_KEYS.duplicate()
					for pi in bm.get_property_list():
						if pi.usage & PROPERTY_USAGE_EDITOR and not (pi.usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SUBGROUP)):
							cands.append(pi.name)
					var sg := U.suggest(str(key), cands)
					return U.err("Material: unknown property '%s'." % key, ("Did you mean '%s'? " % sg if sg != "" else "") + "Friendly keys: " + ", ".join(FRIENDLY_MAT_KEYS) + "; or any StandardMaterial3D property.")
				r = U.set_prop(bm, str(key), v)
		if U.is_err(r):
			r["message"] = "Material: " + str(r.message)
			return r
	return null


## Where a material goes on a node: [object, property] or [object, "surface", index].
func _material_slot(n: Node, surface: int):
	if surface >= 0:
		if not (n is MeshInstance3D):
			return U.err("'surface' only applies to MeshInstance3D nodes (%s is a %s)." % [n.name, n.get_class()])
		var mi: MeshInstance3D = n
		var count := mi.get_surface_override_material_count()
		if surface >= count:
			return U.err("Surface %d does not exist; the mesh has %d surface(s)." % [surface, count], "Omit 'surface' to use material_override.")
		return [n, "surface", surface]
	if n.is_class("CSGPrimitive3D"):
		return [n, "material"]
	if n is GeometryInstance3D:
		return [n, "material_override"]
	if n is CanvasItem or n is FogVolume:
		return [n, "material"]
	return U.err("%s ('%s') can't hold a material." % [n.get_class(), n.name], "Target a MeshInstance3D, CSG shape, GPUParticles3D, Sprite3D, CanvasItem or FogVolume.")


func _slot_get(slot: Array):
	if slot.size() == 3:
		return (slot[0] as MeshInstance3D).get_surface_override_material(slot[2])
	return slot[0].get(slot[1])


func _slot_set_undoable(u, slot: Array, m) -> void:
	if slot.size() == 3:
		u.add_do_method(slot[0], "set_surface_override_material", slot[2], m)
		u.add_undo_method(slot[0], "set_surface_override_material", slot[2], _slot_get(slot))
	else:
		u.add_do_property(slot[0], slot[1], m)
		u.add_undo_property(slot[0], slot[1], _slot_get(slot))


func _save_res(res: Resource, path: String):
	ctx.before_write([path])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return U.err("Failed to save '%s' (error %d: %s)." % [path, err, error_string(err)])
	res.take_over_path(path)
	ctx.fs().update_file(path)
	return null


func _is_file_path(s: String) -> bool:
	return s.begins_with("res://") or s.get_extension() in ["tres", "res", "material"]


## Creates/edits a material file, or builds and assigns a material to a node.
func a_material(p: Dictionary):
	var target := U.p_str(p, "path", U.p_str(p, "node"))
	if target == "":
		return U.err("Missing required parameter 'path'.", "Pass a res://name.tres path to create a material file, or a node path to assign a material to that node.")
	var props := U.p_dict(p, "props").duplicate()
	for k in ["albedo_color", "color", "albedo_texture", "texture", "metallic", "roughness", "emission", "shader", "params"]:
		if p.has(k) and not props.has(k):
			props[k] = p[k]
	var type := U.p_str(p, "type", "")
	if _is_file_path(target) and not p.has("node"):
		var path := U.res_path(target)
		if path.get_extension() == "":
			path += ".tres"
		var m
		var existed := ResourceLoader.exists(path)
		if existed and not U.p_bool(p, "overwrite", false):
			var cur = load(path)
			if not (cur is Material):
				return U.err("'%s' exists and is a %s, not a Material." % [path, cur.get_class()], "Pick another path.")
			var want: String = MAT_TYPES.get(type.to_lower(), type)
			if type != "" and cur.get_class() != want:
				return U.err("'%s' is a %s, not %s." % [path, cur.get_class(), want], "Pass overwrite=true to replace it, or omit 'type' to edit it.")
			# Validate on a copy first: the loaded material is shared with every node using it,
			# so a bad key halfway through must not leave it half-edited in memory.
			var r = apply_material_props(cur.duplicate(), props)
			if U.is_err(r): return r
			m = cur
			apply_material_props(m, props)
		else:
			m = make_material(type if type != "" else ("shader" if props.has("shader") else "standard"), {})
			if U.is_err(m): return m
			var r2 = apply_material_props(m, props)
			if U.is_err(r2): return r2
		var sr = _save_res(m, path)
		if U.is_err(sr): return sr
		var changed := U.changed_props(m)
		changed.erase("resource_path")
		var out := {"path": path, "type": m.get_class(), "created": not existed, "props": changed}
		if p.has("assign_to"):
			var ar = await a_material({"path": U.p_str(p, "assign_to"), "node": U.p_str(p, "assign_to"), "material": path, "surface": p.get("surface", -1), "scene": p.get("scene", "")})
			if U.is_err(ar): return ar
			out["assigned_to"] = ar.path
		return out
	# --- node mode ---
	var n = await node_arg({"path": target, "scene": p.get("scene", "")})
	if U.is_err(n): return n
	var slot = _material_slot(n, U.p_int(p, "surface", -1))
	if U.is_err(slot): return slot
	var mat
	var note := ""
	if p.has("material"):
		mat = build_material(p.material)
		if U.is_err(mat): return mat
		if not props.is_empty():
			mat = mat.duplicate()
			var r3 = apply_material_props(mat, props)
			if U.is_err(r3): return r3
	else:
		var cur2 = _slot_get(slot)
		if type == "" and cur2 is Material:
			mat = cur2.duplicate()  # edit a copy so undo restores the original
			var cp: String = cur2.resource_path
			if cp.begins_with("res://") and not cp.contains("::") and not p.has("save_as"):
				note = "The node used the shared file %s; this node now has an edited embedded copy (the file and its other users are unchanged). To change the file itself, call world3d.material with path='%s'." % [cp, cp]
		else:
			if type == "":
				type = "shader" if (props.has("shader") or n is CanvasItem) else "standard"
			if n is CanvasItem and not (MAT_TYPES.get(type.to_lower(), type) in ["ShaderMaterial", "CanvasItemMaterial"]):
				return U.err("2D nodes need a 'shader' or 'CanvasItemMaterial' material, not '%s'." % type, "Pass type='shader' with shader='res://x.gdshader' (see shader.create).")
			mat = make_material(type, {})
			if U.is_err(mat): return mat
		var r4 = apply_material_props(mat, props)
		if U.is_err(r4): return r4
	if p.has("save_as"):
		var sp := U.res_path(U.p_str(p, "save_as"))
		if sp.get_extension() == "":
			sp += ".tres"
		p["save_as"] = sp
		var sr2 = _save_res(mat, sp)
		if U.is_err(sr2): return sr2
	var u = ctx.begin("Set material on " + str(n.name))
	_slot_set_undoable(u, slot, mat)
	ctx.commit()
	var res := {"path": ctx.node_path_str(n), "slot": "surface %d" % slot[2] if slot.size() == 3 else slot[1], "material": U.encode(mat)}
	if p.has("save_as"):
		res["saved"] = p.save_as
	if note != "":
		res["note"] = note
	return res


# =============================================================================
# Meshes
# =============================================================================

## Builds a PrimitiveMesh from a friendly shape spec.
func build_primitive(shape: String, p: Dictionary):
	shape = shape.to_lower()
	if shape == "cube":
		shape = "box"
	if not shape in SHAPES:
		var s2 := U.suggest(shape, SHAPES)
		return U.err("Unknown shape '%s'." % shape, ("Did you mean '%s'? " % s2 if s2 != "" else "") + "Shapes: " + ", ".join(SHAPES) + ". Or pass mesh='res://model.mesh'.")
	# Validate every numeric input up front (bad values would silently make NaN/zero-size meshes).
	var nv := {}
	for k in ["radius", "height", "top_radius", "bottom_radius", "inner_radius", "outer_radius", "depth", "pixel_size", "font_size"]:
		if p.has(k) and p[k] != null:
			var f = _num(p[k], k, 0.0 if k in ["top_radius", "bottom_radius", "depth"] else 0.0001)
			if U.is_err(f): return f
			nv[k] = f
	var size = null  # Vector3; 2-component sizes become [w, 0, d]/[w, h, 0] below
	if p.has("size") and p.size != null:
		var sv = p.size
		if sv is Array and sv.size() == 2:
			sv = [sv[0], 0, sv[1]] if shape == "plane" else [sv[0], sv[1], 0]
		size = _vec3(sv, "size", true)
		if U.is_err(size): return size
		var need := [0, 2] if shape == "plane" else ([0, 1] if shape == "quad" else [0, 1, 2])
		for i in need:
			if size[i] <= 0.0:
				return U.err("'size' must be positive (got %s)." % JSON.stringify(p.size), "e.g. size: [2, 1, 2] (meters)%s." % (" or [w, d] for a plane" if shape == "plane" else ""))
	var m: PrimitiveMesh
	match shape:
		"box":
			var bm := BoxMesh.new()
			bm.size = size if size != null else Vector3.ONE
			m = bm
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = nv.get("radius", size.x / 2.0 if size != null else 0.5)
			sm.height = nv.get("height", size.y if size != null else sm.radius * 2.0)
			m = sm
		"capsule":
			var cm := CapsuleMesh.new()
			cm.radius = nv.get("radius", 0.5)
			cm.height = maxf(nv.get("height", 2.0), cm.radius * 2.0)
			m = cm
		"cylinder", "cone":
			var cy := CylinderMesh.new()
			var r: float = nv.get("radius", size.x / 2.0 if size != null else 0.5)
			cy.top_radius = nv.get("top_radius", 0.0 if shape == "cone" or U.p_bool(p, "cone") else r)
			cy.bottom_radius = nv.get("bottom_radius", r)
			cy.height = nv.get("height", size.y if size != null else 1.0)
			m = cy
		"plane":
			var pm := PlaneMesh.new()
			pm.size = Vector2(size.x, size.z) if size != null else Vector2(2, 2)
			m = pm
		"prism":
			var pr := PrismMesh.new()
			pr.size = size if size != null else Vector3.ONE
			m = pr
		"torus":
			var tm := TorusMesh.new()
			tm.inner_radius = nv.get("inner_radius", 0.5)
			tm.outer_radius = nv.get("outer_radius", maxf(1.0, tm.inner_radius + 0.25))
			if tm.outer_radius <= tm.inner_radius:
				return U.err("Torus outer_radius (%s) must be larger than inner_radius (%s)." % [tm.outer_radius, tm.inner_radius])
			m = tm
		"quad":
			var qm := QuadMesh.new()
			qm.size = Vector2(size.x, size.y) if size != null else Vector2.ONE
			m = qm
		"text":
			var tx := TextMesh.new()
			tx.text = U.p_str(p, "text", "Text")
			tx.font_size = int(nv.get("font_size", 16))
			tx.depth = nv.get("depth", 0.05)
			if nv.has("pixel_size"):
				tx.pixel_size = nv.pixel_size
			if p.has("font"):
				var fr = U.set_prop(tx, "font", p.font)
				if U.is_err(fr): return fr
			m = tx
		_:
			var s2 := U.suggest(shape, SHAPES)
			return U.err("Unknown shape '%s'." % shape, ("Did you mean '%s'? " % s2 if s2 != "" else "") + "Shapes: " + ", ".join(SHAPES) + ". Or pass mesh='res://model.mesh'.")
	if p.has("mesh_props"):
		var mr = U.apply_props(m, U.p_dict(p, "mesh_props"))
		if U.is_err(mr): return mr
	return m


## Collision shape for a mesh: kind = static/auto (best primitive fit), trimesh, convex.
func shape_for_mesh(mesh: Mesh, kind: String) -> Shape3D:
	if kind == "trimesh" or kind == "concave":
		return mesh.create_trimesh_shape()
	if kind == "convex":
		return mesh.create_convex_shape()
	if mesh is BoxMesh:
		var b := BoxShape3D.new()
		b.size = (mesh as BoxMesh).size
		return b
	if mesh is SphereMesh and is_equal_approx((mesh as SphereMesh).height, (mesh as SphereMesh).radius * 2.0):
		var s := SphereShape3D.new()
		s.radius = (mesh as SphereMesh).radius
		return s
	if mesh is CapsuleMesh:
		var c := CapsuleShape3D.new()
		c.radius = (mesh as CapsuleMesh).radius
		c.height = (mesh as CapsuleMesh).height
		return c
	if mesh is CylinderMesh and is_equal_approx((mesh as CylinderMesh).top_radius, (mesh as CylinderMesh).bottom_radius):
		var cy := CylinderShape3D.new()
		cy.radius = (mesh as CylinderMesh).top_radius
		cy.height = (mesh as CylinderMesh).height
		return cy
	if mesh is PlaneMesh or mesh is QuadMesh or mesh is TorusMesh or mesh is TextMesh:
		return mesh.create_trimesh_shape()
	return mesh.create_convex_shape()


## Adds StaticBody3D > CollisionShape3D under a detached MeshInstance3D.
func _add_static_collision(mi: MeshInstance3D, kind: String):
	var shape := shape_for_mesh(mi.mesh, kind)
	if shape == null:
		return U.err("Could not build a collision shape from the mesh.", "Try collision='convex' or 'trimesh'.")
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)
	return shape


## MeshInstance3D with a primitive mesh (or a mesh file), material, transform and optional collision.
func a_mesh(p: Dictionary):
	var parent = await _parent_arg(p)
	if U.is_err(parent): return parent
	var mesh
	if p.has("mesh"):
		var mp := U.res_path(U.p_str(p, "mesh"))
		if not ResourceLoader.exists(mp):
			return U.err("Mesh '%s' does not exist." % mp, "Use shape='box'|'sphere'|... for a primitive, or world3d.instance for .glb/.tscn models.")
		mesh = load(mp)
		if not (mesh is Mesh):
			return U.err("'%s' is a %s, not a Mesh." % [mp, mesh.get_class()], "For models (.glb/.gltf/.tscn) use world3d.instance.")
	else:
		var shape := U.p_str(p, "shape", "box")
		mesh = build_primitive(shape, p)
		if U.is_err(mesh): return mesh
	var mi := MeshInstance3D.new()
	mi.name = U.p_str(p, "name", U.p_str(p, "shape", "Mesh").capitalize().replace(" ", ""))
	mi.mesh = mesh
	var xr = _apply_xform(mi, p)
	if U.is_err(xr):
		mi.free()
		return xr
	if p.has("material"):
		var mat = build_material(p.material)
		if U.is_err(mat):
			mi.free()
			return mat
		mi.material_override = mat
	if p.has("cast_shadow"):
		var cr = U.set_prop(mi, "cast_shadow", p.cast_shadow)
		if U.is_err(cr):
			mi.free()
			return cr
	if p.has("props"):
		var pr = U.apply_props(mi, U.p_dict(p, "props"))
		if U.is_err(pr):
			mi.free()
			return pr
	var coll := U.p_str(p, "collision", "none").to_lower()
	if coll in ["true", "static", "auto", "trimesh", "concave", "convex"]:
		var sh = _add_static_collision(mi, "auto" if coll in ["true", "static"] else coll)
		if U.is_err(sh):
			mi.free()
			return sh
	elif not coll in ["none", "false", ""]:
		mi.free()
		return U.err("Unknown collision '%s'." % coll, "Use 'static' (best-fit primitive shape), 'convex', 'trimesh' or 'none'.")
	if p.has("look_at"):
		var t = _target_point(p.look_at)
		if U.is_err(t):
			mi.free()
			return t
		var xf = _look_xform(mi, parent, t)
		if not U.is_err(xf):
			mi.transform = xf
	_add_nodes(parent, [mi], "Add mesh " + str(mi.name))
	var out := {"path": ctx.node_path_str(mi), "mesh": mesh.get_class(), "aabb": var_to_str(mesh.get_aabb())}
	if coll != "none" and coll != "false" and coll != "":
		out["collision"] = ctx.node_path_str(mi.get_child(0).get_child(0)) + " (%s)" % mi.get_child(0).get_child(0).shape.get_class()
	return out


# =============================================================================
# CSG
# =============================================================================

func _build_csg(spec: Dictionary, is_root: bool):
	var raw_type := U.p_str(spec, "type", "box")
	var type := raw_type.to_lower()
	var cls: String = CSG_TYPES.get(type, raw_type if raw_type.begins_with("CSG") else "")
	if cls == "" or not ClassDB.class_exists(cls):
		var s := U.suggest(type, CSG_TYPES.keys())
		return U.err("Unknown CSG type '%s'." % type, ("Did you mean '%s'? " % s if s != "" else "") + "Types: " + ", ".join(CSG_TYPES.keys()))
	var n: Node3D = ClassDB.instantiate(cls)
	n.name = U.p_str(spec, "name", cls.trim_prefix("CSG").trim_suffix("3D"))
	var props := U.p_dict(spec, "props").duplicate()
	for k in CSG_KEYS:
		if spec.has(k) and not props.has(k):
			props[k] = spec[k]
	if type == "cone" and not props.has("cone"):
		props["cone"] = true
	var err = null
	for k in props:
		var v = props[k]
		match str(k):
			"operation":
				var ops := {"union": 0, "intersection": 1, "intersect": 1, "subtraction": 2, "subtract": 2, "difference": 2}
				if not str(v).to_lower() in ops:
					err = U.err("Unknown CSG operation '%s'." % v, "Use union, intersection or subtraction.")
				else:
					n.set("operation", ops[str(v).to_lower()])
			"material":
				var m = build_material(v)
				if U.is_err(m):
					err = m
				elif "material" in n:
					n.set("material", m)
				else:
					n.set("material_override", m)  # combiner: overrides every child shape
			"mesh":
				var mm = build_primitive(str(v.get("shape", "box")), v) if v is Dictionary else U.to_object(v)
				if U.is_err(mm):
					err = mm
				elif not (mm is Mesh):
					err = U.err("'mesh' must be a Mesh (got %s)." % (mm.get_class() if mm is Object else JSON.stringify(v)), "Pass {shape: 'prism', size: [1, 1, 1]} or a res:// mesh resource.")
				else:
					n.set("mesh", mm)
			"size":
				var sz = _vec3(v, "size", true)
				if U.is_err(sz):
					err = sz
				elif sz.x <= 0 or sz.y <= 0 or sz.z <= 0:
					err = U.err("'size' must be positive (got %s)." % JSON.stringify(v))
				elif n is CSGBox3D:
					n.set("size", sz)
				elif n is CSGSphere3D:
					n.set("radius", sz.x / 2.0)  # size = diameter
				elif n is CSGCylinder3D:
					n.set("radius", sz.x / 2.0)
					n.set("height", sz.y)
				else:
					err = U.err("%s has no 'size'." % cls, "Use radius/height (sphere, cylinder), inner_radius/outer_radius (torus) or polygon+depth (polygon).")
			"use_collision", "collision_layer", "collision_mask":
				if is_root:
					err = U.set_prop(n, str(k), v)
			_:
				err = U.set_prop(n, str(k), v)
		if U.is_err(err):
			n.free()
			err["message"] = "CSG '%s': %s" % [spec.get("name", type), err.message]
			return err
	var xr = _apply_xform(n, spec)
	if U.is_err(xr):
		n.free()
		xr["message"] = "CSG '%s': %s" % [spec.get("name", type), xr.message]
		return xr
	for child_spec in U.p_arr(spec, "children"):
		if not (child_spec is Dictionary):
			n.free()
			return U.err("CSG '%s': each child must be a spec like {type: 'box', operation: 'subtraction', size: [1, 2, 1]} (got %s)." % [spec.get("name", type), JSON.stringify(child_spec)])
		var c = _build_csg(child_spec, false)
		if U.is_err(c):
			n.free()
			return c
		n.add_child(c, true)
	return n


## CSG blockout shape (or a whole nested tree via children) with operation/material/collision.
func a_csg(p: Dictionary):
	var parent = await _parent_arg(p)
	if U.is_err(parent): return parent
	var n = _build_csg(p, not parent.is_class("CSGShape3D"))
	if U.is_err(n): return n
	_add_nodes(parent, [n], "Add CSG " + str(n.name))
	var out := {"path": ctx.node_path_str(n), "type": n.get_class()}
	var kids := n.find_children("*", "CSGShape3D", true, false)
	if not kids.is_empty():
		out["children"] = kids.map(func(c): return "%s (%s)" % [ctx.node_path_str(c), c.get_class()])
	if parent.is_class("CSGShape3D"):
		out["note"] = "Added inside CSG '%s': its operation applies against the parent shape." % parent.name
	return out


# =============================================================================
# Lights, camera, look_at
# =============================================================================

func _configure_light(l: Light3D, p: Dictionary) -> Variant:
	var props := U.p_dict(p, "props").duplicate()
	for k in ["color", "energy", "range", "angle", "shadow", "shadows", "shadow_enabled", "indirect_energy", "attenuation", "specular", "bake_mode"]:
		if p.has(k) and not props.has(k):
			props[k] = p[k]
	for k in props:
		var v = props[k]
		var r = null
		var key := str(k)
		var num = null
		if key in ["energy", "light_energy", "indirect_energy", "specular", "range", "attenuation"] or (key == "angle" and l is SpotLight3D):
			num = _num(v, key, 0.0, 180.0 if key == "angle" else INF)
			if U.is_err(num):
				return num
		match key:
			"color", "light_color":
				var c = _color(v, key)
				if U.is_err(c):
					r = c
				else:
					l.light_color = c
			"energy", "light_energy":
				l.light_energy = num
			"indirect_energy":
				l.light_indirect_energy = num
			"specular":
				l.light_specular = num
			"shadow", "shadows", "shadow_enabled":
				l.shadow_enabled = U.coerce(v, TYPE_BOOL)
			"range":
				if l is OmniLight3D:
					l.omni_range = num
				elif l is SpotLight3D:
					l.spot_range = num
				else:
					r = U.err("Directional lights have no range.", "Remove 'range'; directional lights light the whole scene.")
			"angle":
				if l is SpotLight3D:
					l.spot_angle = num
				else:
					r = U.set_prop(l, "light_angular_distance", v)
			"attenuation":
				if l is OmniLight3D:
					l.omni_attenuation = num
				elif l is SpotLight3D:
					l.spot_attenuation = num
				else:
					r = U.err("Directional lights have no attenuation.")
			_:
				r = U.set_prop(l, key, v)
		if U.is_err(r):
			return r
	return null


## Adds a DirectionalLight3D / OmniLight3D / SpotLight3D with friendly props.
func a_light(p: Dictionary):
	var parent = await _parent_arg(p)
	if U.is_err(parent): return parent
	var type := U.p_str(p, "type", "omni").to_lower()
	if not LIGHT_TYPES.has(type):
		return U.err("Unknown light type '%s'." % type, "Use directional (sun), omni (point/lamp) or spot.")
	var l: Light3D = ClassDB.instantiate(LIGHT_TYPES[type])
	l.name = U.p_str(p, "name", {"directional": "Sun", "omni": "OmniLight3D", "point": "OmniLight3D", "spot": "SpotLight3D"}[type])
	if l is DirectionalLight3D:
		l.shadow_enabled = true
		l.rotation_degrees = Vector3(-50, -30, 0)
	var xr = _apply_xform(l, p)
	if U.is_err(xr):
		l.free()
		return xr
	var r = _configure_light(l, p)
	if U.is_err(r):
		l.free()
		return r
	if p.has("look_at"):
		var t = _target_point(p.look_at)
		if U.is_err(t):
			l.free()
			return t
		var xf = _look_xform(l, parent, t)
		if U.is_err(xf):
			l.free()
			return xf
		l.transform = xf
	_add_nodes(parent, [l], "Add light " + str(l.name))
	return {"path": ctx.node_path_str(l), "type": l.get_class(), "props": U.changed_props(l)}


func a_camera(p: Dictionary):
	var parent = await _parent_arg(p)
	if U.is_err(parent): return parent
	var cam := Camera3D.new()
	cam.name = U.p_str(p, "name", "Camera3D")
	if not p.has("position"):
		cam.position = Vector3(0, 2, 5)
	var xr = _apply_xform(cam, p)
	if U.is_err(xr):
		cam.free()
		return xr
	for k in ["fov", "size", "near", "far"]:
		if p.has(k) and p[k] != null:
			var f = _num(p[k], k, 1.0 if k == "fov" else 0.0001, 179.0 if k == "fov" else INF)
			if U.is_err(f):
				cam.free()
				return f
			cam.set(k, f)
	if p.has("projection"):
		var pv = p.projection
		if str(pv).to_lower() in ["orthographic", "ortho"]:
			pv = "orthogonal"
		var pr0 = U.set_prop(cam, "projection", pv)
		if U.is_err(pr0):
			cam.free()
			return pr0
	cam.current = U.p_bool(p, "current", true)
	if p.has("props"):
		var pr = U.apply_props(cam, U.p_dict(p, "props"))
		if U.is_err(pr):
			cam.free()
			return pr
	if p.has("look_at"):
		var t = _target_point(p.look_at)
		if U.is_err(t):
			cam.free()
			return t
		var xf = _look_xform(cam, parent, t)
		if U.is_err(xf):
			cam.free()
			return xf
		cam.transform = xf
	var others := []
	if cam.current:
		for c in ctx.edited_root().find_children("*", "Camera3D", true, false):
			if c.current:
				others.append(c)
	var root: Node = ctx.edited_root()
	var u = ctx.begin("Add camera " + str(cam.name))
	for c in others:
		u.add_do_property(c, "current", false)
		u.add_undo_property(c, "current", true)
	u.add_do_method(parent, "add_child", cam, true)
	u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", cam, root)
	u.add_do_reference(cam)
	u.add_undo_method(parent, "remove_child", cam)
	ctx.commit()
	var out := {"path": ctx.node_path_str(cam), "position": var_to_str(cam.position), "rotation_degrees": var_to_str(cam.rotation_degrees.snapped(Vector3.ONE * 0.01)), "current": cam.current}
	if not others.is_empty():
		out["note"] = "Made this the current camera (was: %s)." % ", ".join(others.map(func(c): return str(c.name)))
	return out


## Rotates a Node3D to face a point or another node (Node3D -Z faces the target).
func a_look_at(p: Dictionary):
	var e = U.require(p, ["path", "target"])
	if e: return e
	var n = await node_arg(p)
	if U.is_err(n): return n
	if not (n is Node3D):
		return U.err("'%s' is a %s, not a Node3D." % [p.path, n.get_class()], "look_at rotates 3D nodes (cameras, lights, meshes).")
	var t = _target_point(p.target)
	if U.is_err(t): return t
	var xf = _look_xform(n, n.get_parent(), t, U.p_bool(p, "model_front", false))
	if U.is_err(xf): return xf
	var u = ctx.begin("Look at")
	u.add_do_property(n, "transform", xf)
	u.add_undo_property(n, "transform", n.transform)
	ctx.commit()
	return {"path": ctx.node_path_str(n), "rotation_degrees": var_to_str(n.rotation_degrees.snapped(Vector3.ONE * 0.01)), "target": var_to_str(t)}


# =============================================================================
# Environment
# =============================================================================

func _preset(name: String) -> Dictionary:
	match name:
		"sunny":
			return {"sky": {"type": "procedural", "top_color": "#3d7bd9", "horizon_color": "#b8d0ec", "ground_color": "#3b3226", "ground_horizon_color": "#b8d0ec"},
				"env": {"tonemap_mode": "agx", "ssao_enabled": true, "glow_enabled": true, "glow_intensity": 0.3},
				"sun": {"rotation_degrees": [-55, 40, 0], "energy": 1.3, "color": "#fff3dc"}}
		"night":
			return {"sky": {"type": "procedural", "top_color": "#02040d", "horizon_color": "#0c1a33", "ground_color": "#010203", "ground_horizon_color": "#0c1a33", "energy": 0.4},
				"env": {"ambient_light_source": "color", "ambient_light_color": "#26345a", "ambient_light_energy": 0.5, "glow_enabled": true, "glow_intensity": 0.6, "tonemap_mode": "filmic"},
				"sun": {"name": "Moon", "rotation_degrees": [-35, -30, 0], "energy": 0.15, "color": "#a8bcff"}}
		"foggy":
			return {"sky": {"type": "procedural", "top_color": "#8f9aa3", "horizon_color": "#c5cacf", "ground_color": "#5b5f63", "ground_horizon_color": "#c5cacf"},
				"env": {"fog_enabled": true, "fog_density": 0.035, "fog_light_color": "#c4cad0", "fog_sky_affect": 0.7, "tonemap_mode": "filmic"},
				"sun": {"rotation_degrees": [-65, 20, 0], "energy": 0.5, "color": "#e1e6ea"}}
		"studio":
			return {"sky": null,
				"env": {"background_mode": "custom_color", "background_color": "#3a3d42", "ambient_light_source": "color", "ambient_light_color": "#a7adb6", "ambient_light_energy": 0.6, "ssao_enabled": true, "tonemap_mode": "filmic"},
				"sun": {"name": "KeyLight", "rotation_degrees": [-45, 35, 0], "energy": 1.0}}
		"space":
			return {"sky": null,
				"env": {"background_mode": "custom_color", "background_color": "#000005", "ambient_light_source": "color", "ambient_light_color": "#20263a", "ambient_light_energy": 0.3, "glow_enabled": true, "glow_intensity": 0.8, "glow_bloom": 0.1, "tonemap_mode": "aces"},
				"sun": {"name": "Star", "rotation_degrees": [-20, -60, 0], "energy": 2.0, "color": "#ffffff"}}
	return {"sky": {"type": "procedural"}, "env": {"tonemap_mode": "filmic"}, "sun": {"rotation_degrees": [-60, 150, 0], "energy": 1.0}}


func _build_sky(spec, existing: Sky):
	if spec is String:
		var rp := U.res_path(str(spec))
		if not ResourceLoader.exists(rp):
			return U.err("Sky resource '%s' does not exist." % rp, "Pass a panorama image (.hdr/.exr/.png), a .gdshader sky shader, a Sky/.tres material, or {type: 'procedural', top_color: ...}.")
		var r = load(rp)
		if r is Sky:
			return r
		if r is Texture2D:
			spec = {"type": "panorama", "panorama": rp}
		elif r is Material or r is Shader:
			var sky0 := Sky.new()
			sky0.sky_material = r if r is Material else build_material(rp)
			return sky0
		else:
			return U.err("'%s' (%s) can't be used as a sky." % [rp, r.get_class()])
	if not (spec is Dictionary):
		return U.err("Invalid sky %s." % JSON.stringify(spec))
	var d: Dictionary = spec
	var sky := Sky.new()
	var mat: Material = null
	var type := U.p_str(d, "type", "panorama" if d.has("panorama") else "")
	if type == "" and existing and existing.sky_material:
		mat = existing.sky_material.duplicate()
		sky.radiance_size = existing.radiance_size
		sky.process_mode = existing.process_mode
	else:
		var sky_type := type if type != "" else "procedural"
		match sky_type:
			"procedural": mat = ProceduralSkyMaterial.new()
			"panorama", "hdri": mat = PanoramaSkyMaterial.new()
			"physical": mat = PhysicalSkyMaterial.new()
			"shader":
				var sm = build_material({"type": "shader", "shader": d.get("shader", "")})
				if U.is_err(sm): return sm
				mat = sm
			_:
				return U.err("Unknown sky type '%s'." % type, "Use procedural, panorama (with panorama: 'res://sky.hdr'), physical or shader.")
	sky.sky_material = mat
	for k in d:
		if k in ["type", "shader"]:
			continue
		var v = d[k]
		var r2 = null
		var key := str(k)
		if key in ["radiance_size", "process_mode"]:
			r2 = U.set_prop(sky, key, v)
		elif mat is ProceduralSkyMaterial and key in ["top_color", "horizon_color", "ground_color", "ground_horizon_color", "energy", "sun_size", "cover"]:
			var val = _color(v, key) if key.ends_with("_color") else (_num(v, key, 0.0) if key != "cover" else null)
			if U.is_err(val):
				r2 = val
			else:
				match key:
					"top_color": mat.sky_top_color = val
					"horizon_color":
						mat.sky_horizon_color = val
						if not d.has("ground_horizon_color"):
							mat.ground_horizon_color = val
					"ground_color": mat.ground_bottom_color = val
					"ground_horizon_color": mat.ground_horizon_color = val
					"energy": mat.energy_multiplier = val
					"sun_size": mat.sun_angle_max = val
					"cover": r2 = U.set_prop(mat, "sky_cover", v)
		elif mat is PanoramaSkyMaterial and key in ["texture", "energy"]:
			r2 = U.set_prop(mat, "panorama" if key == "texture" else "energy_multiplier", v)
		elif mat is PhysicalSkyMaterial and key == "energy":
			var e2 = _num(v, key, 0.0)
			if U.is_err(e2):
				r2 = e2
			else:
				mat.energy_multiplier = e2
		elif mat is ShaderMaterial and key == "params":
			var sh = ctx.router.handlers.get("shader")
			r2 = sh.configure_material(mat, {"params": v})
		else:
			r2 = U.set_prop(mat, key, v)
		if U.is_err(r2):
			r2["message"] = "Sky: " + str(r2.message)
			return r2
	return sky


## Applies a feature group (fog, glow, ssao...) given as bool / number / dict.
func _env_group(env: Environment, prefix: String, v, num_key: String) -> Variant:
	if v is bool:
		env.set(prefix + "enabled", v)
		return null
	if v is int or v is float:
		env.set(prefix + "enabled", true)
		env.set(prefix + num_key, float(v))
		return null
	if not (v is Dictionary):
		return U.err("'%s' must be true/false, a number or a dict." % prefix.trim_suffix("_"), "e.g. %s: true, %s: 0.5, or %s: {\"enabled\": true, ...%s* properties without the prefix}." % [prefix.trim_suffix("_"), prefix.trim_suffix("_"), prefix.trim_suffix("_"), prefix])
	env.set(prefix + "enabled", U.p_bool(v, "enabled", true))
	var aliases := {"fog_color": "fog_light_color", "fog_energy": "fog_light_energy", "volumetric_fog_color": "volumetric_fog_albedo", "glow_threshold": "glow_hdr_threshold", "glow_scale": "glow_hdr_scale"}
	var infos := U.prop_infos(env)
	for k in v:
		if k == "enabled":
			continue
		var name: String = aliases.get(prefix + str(k), prefix + str(k))
		if not infos.has(name):
			name = str(k)
		var val = v[k]
		if infos.has(name) and infos[name].type == TYPE_COLOR:
			val = _color(val, str(k))
			if U.is_err(val):
				return val
		var r = U.set_prop(env, name, val, infos)
		if U.is_err(r):
			return r
	return null


func _configure_env(env: Environment, p: Dictionary) -> Variant:
	var r = null
	for key in ["background", "ambient", "fog", "volumetric_fog", "glow", "ssao", "ssil", "ssr", "sdfgi", "tonemap", "adjustment"]:
		if not p.has(key):
			continue
		var v = p[key]
		match key:
			"background":
				if _is_color_str(v) or v is Array:
					var bc = _color(v, "background")
					if U.is_err(bc):
						r = bc
					else:
						env.background_mode = Environment.BG_COLOR
						env.background_color = bc
				else:
					r = U.set_prop(env, "background_mode", {"color": "custom_color", "sky": "sky", "clear": "clear_color"}.get(str(v), v))
			"ambient":
				if v is Dictionary:
					for ak in v:
						if not str(ak) in ["color", "energy", "source", "sky_contribution"]:
							r = U.err("Unknown ambient key '%s'." % ak, "ambient: {color: '#hex', energy: 0.5, source: 'color'|'sky'|'background'|'disabled', sky_contribution: 0..1}")
							break
					var ac = _color(v.color, "ambient.color") if v.has("color") else null
					var ae = _num(v.energy, "ambient.energy", 0.0) if v.has("energy") else null
					var asc = _num(v.sky_contribution, "ambient.sky_contribution", 0.0, 1.0) if v.has("sky_contribution") else null
					for x in [ac, ae, asc]:
						if U.is_err(x):
							r = x
					if not U.is_err(r):
						if ac != null:
							env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
							env.ambient_light_color = ac
						if ae != null:
							env.ambient_light_energy = ae
						if asc != null:
							env.ambient_light_sky_contribution = asc
						if v.has("source"):
							r = U.set_prop(env, "ambient_light_source", v.source)
				elif v is int or v is float:
					env.ambient_light_energy = float(v)
				else:
					var ac2 = _color(v, "ambient")
					if U.is_err(ac2):
						r = ac2
					else:
						env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
						env.ambient_light_color = ac2
			"fog": r = _env_group(env, "fog_", v, "density")
			"volumetric_fog": r = _env_group(env, "volumetric_fog_", v, "density")
			"glow": r = _env_group(env, "glow_", v, "intensity")
			"ssao": r = _env_group(env, "ssao_", v, "intensity")
			"ssil": r = _env_group(env, "ssil_", v, "intensity")
			"ssr": r = _env_group(env, "ssr_", v, "max_steps")
			"sdfgi": r = _env_group(env, "sdfgi_", v, "energy")
			"adjustment": r = _env_group(env, "adjustment_", v, "brightness")
			"tonemap":
				if v is Dictionary:
					for k in v:
						r = U.set_prop(env, "tonemap_" + ("mode" if k == "mode" else str(k)), v[k])
						if U.is_err(r): break
				else:
					r = U.set_prop(env, "tonemap_mode", v)
		if U.is_err(r):
			r["message"] = "%s: %s" % [key, r.message]
			return r
	return null


## WorldEnvironment + Environment + Sky (+ a sun DirectionalLight3D) from a preset and overrides.
func a_environment(p: Dictionary):
	var parent = await _parent_arg(p)
	if U.is_err(parent): return parent
	var root: Node = ctx.edited_root()
	var preset_name := U.p_str(p, "preset", "")
	if preset_name != "" and not preset_name in PRESETS:
		var s := U.suggest(preset_name, PRESETS)
		return U.err("Unknown preset '%s'." % preset_name, ("Did you mean '%s'? " % s if s != "" else "") + "Presets: " + ", ".join(PRESETS))
	var existing: WorldEnvironment = null
	var found := root.find_children("*", "WorldEnvironment", true, false)
	if root is WorldEnvironment:
		existing = root
	elif not found.is_empty():
		existing = found[0]
	var creating := existing == null or U.p_bool(p, "reset", false)
	if preset_name == "" and creating:
		preset_name = "default"
	var env: Environment
	# A preset defines the whole look, so it starts from a fresh Environment (keep=true layers it on top).
	var fresh := U.p_bool(p, "reset", false) or (p.has("preset") and not U.p_bool(p, "keep", false))
	if existing and existing.environment and not fresh:
		env = existing.environment.duplicate(true)
	else:
		env = Environment.new()
	var preset := _preset(preset_name) if preset_name != "" else {}
	# Sky: preset first, then explicit sky spec.
	if preset.has("sky"):
		if preset.sky == null:
			env.sky = null
		else:
			var sk = _build_sky(preset.sky, null)
			if U.is_err(sk): return sk
			env.sky = sk
			env.background_mode = Environment.BG_SKY
	if p.has("sky"):
		if p.sky == null or (p.sky is bool and not p.sky):
			env.sky = null
			if env.background_mode == Environment.BG_SKY:
				env.background_mode = Environment.BG_CLEAR_COLOR
		else:
			var sk2 = _build_sky(p.sky if not (p.sky is bool) else {"type": "procedural"}, env.sky)
			if U.is_err(sk2): return sk2
			env.sky = sk2
			env.background_mode = Environment.BG_SKY
	if preset.has("env"):
		var pr = U.apply_props(env, preset.env)
		if U.is_err(pr): return pr
	var cr = _configure_env(env, p)
	if U.is_err(cr): return cr
	if p.has("props"):
		var pr2 = U.apply_props(env, U.p_dict(p, "props"))
		if U.is_err(pr2): return pr2
	var save_path := U.p_str(p, "save_path", "")
	if save_path == "" and existing and existing.environment and existing.environment.resource_path.begins_with("res://") and not existing.environment.resource_path.contains("::"):
		save_path = existing.environment.resource_path
	if save_path != "":
		save_path = U.res_path(save_path)
		if save_path.get_extension() == "":
			save_path += ".tres"
		var sr = _save_res(env, save_path)
		if U.is_err(sr): return sr
	# Sun
	var sun_spec = p.get("sun", null)
	var want_sun := false
	var sun_cfg: Dictionary = preset.get("sun", {}).duplicate() if preset.has("sun") else {}
	if sun_spec is Dictionary:
		want_sun = true
		sun_cfg.merge(sun_spec, true)
	elif sun_spec is bool:
		want_sun = sun_spec
	else:
		want_sun = preset.has("sun")
	var existing_sun: DirectionalLight3D = null
	var suns := root.find_children("*", "DirectionalLight3D", true, false)
	if not suns.is_empty():
		existing_sun = suns[0]
	var new_sun: DirectionalLight3D = null
	var sun_update := {}
	if want_sun:
		if sun_cfg.is_empty():
			sun_cfg = {"rotation_degrees": [-60, 150, 0]}
		if existing_sun == null:
			new_sun = DirectionalLight3D.new()
			new_sun.name = str(sun_cfg.get("name", "Sun"))
			new_sun.shadow_enabled = true
			var lc = _apply_xform(new_sun, sun_cfg)
			if not U.is_err(lc):
				lc = _configure_light(new_sun, _strip(sun_cfg, ["name", "rotation_degrees", "rotation", "position"]))
			if U.is_err(lc):
				new_sun.free()
				return lc
		elif sun_spec is Dictionary or (preset_name != "" and U.p_bool(p, "update_sun", true)):
			var tmp: DirectionalLight3D = existing_sun.duplicate(0)
			var lc2 = _apply_xform(tmp, sun_cfg)
			if not U.is_err(lc2):
				lc2 = _configure_light(tmp, _strip(sun_cfg, ["name", "rotation_degrees", "rotation", "position"]))
			if U.is_err(lc2):
				tmp.free()
				return lc2
			# Everything the preset/sun spec changed (color, energy, shadows, any raw light prop).
			for pi in tmp.get_property_list():
				if not (pi.usage & PROPERTY_USAGE_STORAGE) or pi.name in ["name", "owner", "script", "unique_name_in_owner"]:
					continue
				var nv = tmp.get(pi.name)
				var ov = existing_sun.get(pi.name)
				if typeof(nv) != typeof(ov) or nv != ov:
					sun_update[pi.name] = nv
			tmp.free()
	# Commit everything as one undo step.
	var we: WorldEnvironment = existing
	var nh = ctx.router.handlers["node"]
	var u = ctx.begin("Set up environment" + (" (%s)" % preset_name if preset_name != "" else ""))
	if we == null:
		we = WorldEnvironment.new()
		we.name = U.p_str(p, "name", "WorldEnvironment")
		we.environment = env
		u.add_do_method(parent, "add_child", we, true)
		u.add_do_method(nh, "set_owner_rec", we, root)
		u.add_do_reference(we)
		u.add_undo_method(parent, "remove_child", we)
	else:
		u.add_do_property(we, "environment", env)
		u.add_undo_property(we, "environment", we.environment)
	if new_sun:
		u.add_do_method(parent, "add_child", new_sun, true)
		u.add_do_method(nh, "set_owner_rec", new_sun, root)
		u.add_do_reference(new_sun)
		u.add_undo_method(parent, "remove_child", new_sun)
	for k in sun_update:
		u.add_do_property(existing_sun, k, sun_update[k])
		u.add_undo_property(existing_sun, k, existing_sun.get(k))
	ctx.commit()
	var out := {"path": ctx.node_path_str(we), "created": existing == null, "preset": preset_name, "environment": U.changed_props(env)}
	if env.sky:
		out["sky"] = {"material": env.sky.sky_material.get_class() if env.sky.sky_material else null, "props": U.changed_props(env.sky.sky_material) if env.sky.sky_material else {}}
	if save_path != "":
		out["saved"] = save_path
		out["note"] = "The Environment lives in %s (shared resource); it was saved there. Undo restores the node, not the file (use changes.* to revert files)." % save_path
	if new_sun:
		out["sun"] = ctx.node_path_str(new_sun) + " (added)"
	elif existing_sun:
		out["sun"] = ctx.node_path_str(existing_sun) + (" (updated)" if not sun_update.is_empty() else " (existing, unchanged)")
	return out


func _strip(d: Dictionary, keys: Array) -> Dictionary:
	var o := d.duplicate()
	for k in keys:
		o.erase(k)
	return o


# =============================================================================
# Import & instance models
# =============================================================================

## Reads/changes import options of an asset (.glb/.gltf/.fbx/.blend/.obj/.png/...) and reimports.
func a_import(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not FileAccess.file_exists(path):
		return U.err("File '%s' does not exist." % path, "Copy the model into the project first (e.g. assets.* or files.copy), then call this.")
	var ipath := path + ".import"
	if not FileAccess.file_exists(ipath):
		ctx.fs().scan()
		await ctx.wait_fs(60000)
		if not FileAccess.file_exists(ipath):
			return U.err("'%s' has not been imported (no .import file)." % path, "Is it a supported format? Try files.rescan, then retry.")
	var cfg := ConfigFile.new()
	if cfg.load(ipath) != OK:
		return U.err("Could not read '%s'." % ipath)
	var importer := str(cfg.get_value("remap", "importer", ""))
	var keys: PackedStringArray = cfg.get_section_keys("params") if cfg.has_section("params") else PackedStringArray()
	var props := U.p_dict(p, "props").duplicate()
	for k in ["root_type", "root_name", "root_scale", "scale", "generate_collisions", "collision_shape", "body_type", "fps", "import_animation", "generate_lods", "light_baking"]:
		if p.has(k) and not props.has(k):
			props[k] = p[k]
	if props.is_empty():
		var opts := {}
		for k in keys:
			opts[k] = U.encode(cfg.get_value("params", k))
		return {"path": path, "importer": importer, "options": opts, "hint": "Pass props: {option: value} to change options (friendly: root_type, root_scale, generate_collisions, collision_shape, fps, generate_lods, light_baking)."}
	var changed := {}
	var coll_request = null
	for k in props:
		var key := str(k)
		var v = props[k]
		if key in ["generate_collisions", "collisions", "collision"]:
			coll_request = v
			continue
		if key in ["collision_shape", "body_type"]:
			continue
		if importer == "scene" and SCENE_IMPORT_ALIASES.has(key):
			key = SCENE_IMPORT_ALIASES[key]
		if key == "nodes/root_type" and str(v) != "":
			var rt := str(v)
			if not (ClassDB.class_exists(rt) and ClassDB.is_parent_class(rt, "Node")):
				var common := ["Node3D", "StaticBody3D", "RigidBody3D", "CharacterBody3D", "AnimatableBody3D", "Area3D", "VehicleBody3D"]
				var sg := U.suggest(rt, common)
				return U.err("root_type '%s' is not a Node class." % rt, ("Did you mean '%s'? " % sg if sg != "" else "") + "e.g. " + ", ".join(common) + " ('' = Node3D).")
		if key == "meshes/light_baking" and v is String:
			if not LIGHT_BAKING.has(str(v)):
				return U.err("Unknown light_baking '%s'." % v, "Use: " + ", ".join(LIGHT_BAKING.keys()))
			v = LIGHT_BAKING[str(v)]
		if not key in keys and not (importer == "scene" and key == "nodes/root_script"):  # null values aren't listed by ConfigFile
			var s := U.suggest(key, Array(keys) + SCENE_IMPORT_ALIASES.keys())
			return U.err("Import option '%s' does not exist for importer '%s'." % [key, importer], ("Did you mean '%s'? " % s if s != "" else "") + "Call world3d.import with only {path} to list options.")
		var cur = cfg.get_value("params", key)
		var nv = v
		if key == "nodes/root_script":
			nv = null
			if v is String and str(v) != "":
				var scp := U.res_path(str(v))
				if not ResourceLoader.exists(scp):
					return U.err("Root script '%s' does not exist." % scp)
				nv = load(scp)
		elif cur != null:
			nv = U.coerce(v, typeof(cur))
			if U.is_err(nv):
				nv["message"] = "%s: %s" % [key, nv.message]
				return nv
		else:
			nv = U._auto(v)
		cfg.set_value("params", key, nv)
		changed[key] = U.encode(nv)
	var coll_nodes := []
	if coll_request != null:
		if importer != "scene":
			return U.err("generate_collisions only applies to 3D scenes (.glb/.gltf/.fbx/.blend/.obj), not importer '%s'." % importer)
		var enable: bool = not (coll_request is bool and not coll_request) and str(coll_request) != "none"
		var shape_name := U.p_str(props, "collision_shape", str(coll_request) if coll_request is String else "trimesh").to_lower()
		if enable and not SHAPE_TYPES.has(shape_name):
			return U.err("Unknown collision_shape '%s'." % shape_name, "Use: " + ", ".join(SHAPE_TYPES.keys()))
		var body_name := U.p_str(props, "body_type", "static").to_lower()
		if not BODY_TYPES.has(body_name):
			return U.err("Unknown body_type '%s'." % body_name, "Use static, rigid or area.")
		var packed = load(path)
		if not (packed is PackedScene):
			return U.err("'%s' did not import as a scene." % path)
		var inst: Node = packed.instantiate()
		var meshes := inst.find_children("*", "ImporterMeshInstance3D", true, false) + inst.find_children("*", "MeshInstance3D", true, false)
		var subres: Dictionary = cfg.get_value("params", "_subresources", {})
		if not subres.has("nodes"):
			subres["nodes"] = {}
		for mi in meshes:
			var np := "PATH:" + str(inst.get_path_to(mi))
			var nd: Dictionary = subres.nodes.get(np, {})
			nd["generate/physics"] = enable
			if enable:
				nd["physics/body_type"] = BODY_TYPES[body_name]
				nd["physics/shape_type"] = SHAPE_TYPES[shape_name]
			subres.nodes[np] = nd
			coll_nodes.append(str(inst.get_path_to(mi)))
		inst.free()
		if coll_nodes.is_empty():
			return U.err("No meshes found in '%s' to generate collisions for." % path)
		cfg.set_value("params", "_subresources", subres)
		changed["generate_collisions"] = {"enabled": enable, "shape": shape_name, "body": body_name, "meshes": coll_nodes} if enable else {"enabled": false, "meshes": coll_nodes}
	ctx.before_write([ipath])
	if cfg.save(ipath) != OK:
		return U.err("Could not write '%s'." % ipath)
	ctx.fs().reimport_files(PackedStringArray([path]))
	await ctx.wait_fs(120000)
	var out := {"path": path, "importer": importer, "changed": changed, "reimported": true}
	if importer == "scene":
		var packed2 = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if packed2 is PackedScene:
			var inst2: Node = packed2.instantiate()
			out["root"] = "%s (%s)" % [inst2.name, inst2.get_class()]
			out["bodies"] = inst2.find_children("*", "CollisionObject3D", true, false).size()
			out["meshes"] = inst2.find_children("*", "MeshInstance3D", true, false).size()
			inst2.free()
	return out


## Instances an imported model (.glb/.gltf/.fbx/.blend) or .tscn, once or at several positions.
func a_instance(p: Dictionary):
	var e = U.require(p, ["model"])
	if e: return e
	var parent = await _parent_arg(p)
	if U.is_err(parent): return parent
	var mp := U.res_path(U.p_str(p, "model"))
	if not ResourceLoader.exists(mp):
		if FileAccess.file_exists(mp):
			ctx.fs().scan()
			await ctx.wait_fs(60000)
		if not ResourceLoader.exists(mp):
			return U.err("Model '%s' does not exist or isn't imported." % mp, "Check the path with files.list pattern='*.glb'.")
	var packed = load(mp)
	if not (packed is PackedScene):
		if packed is Mesh:
			return U.err("'%s' is a Mesh, not a scene." % mp, "Use world3d.mesh with mesh='%s'." % mp)
		return U.err("'%s' is a %s, not a scene/model." % [mp, packed.get_class()])
	if mp == ctx.edited_root().scene_file_path:
		return U.err("Cannot instance a scene inside itself.")
	if p.has("positions") and not (p.positions is Array):
		return U.err("'positions' must be a list of [x, y, z] (got %s)." % JSON.stringify(p.positions), "e.g. positions: [[0, 0, 0], [4, 0, 0]]")
	var positions := U.p_arr(p, "positions")
	if positions.is_empty():
		positions = [p.get("position", [0, 0, 0])]
	if positions.size() > 500:
		return U.err("Too many positions (%d, max 500)." % positions.size(), "Use world3d.scatter for large counts.")
	var nodes := []
	var base_name := U.p_str(p, "name", "")
	for i in positions.size():
		var inst: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		if base_name != "":
			inst.name = base_name if positions.size() == 1 else "%s%d" % [base_name, i + 1]
		var pr = null
		if inst is Node3D:
			var q := p.duplicate()
			q["position"] = positions[i]
			pr = _apply_xform(inst, q)
		if not U.is_err(pr) and p.has("props"):
			pr = U.apply_props(inst, U.p_dict(p, "props"))
		if U.is_err(pr):
			inst.free()
			for x in nodes:
				x.free()
			if positions.size() > 1:
				pr["message"] = "positions[%d]: %s" % [i, pr.message]
			return pr
		nodes.append(inst)
	_add_nodes(parent, nodes, "Instance " + mp.get_file())
	var paths := nodes.map(func(x): return ctx.node_path_str(x))
	var out := {"instance_of": mp, "type": nodes[0].get_class()}
	if paths.size() == 1:
		out["path"] = paths[0]
	else:
		out["paths"] = paths
	return out


# =============================================================================
# GridMap / MeshLibrary
# =============================================================================

## GridMap orientation index from 0-23 (raw index), 90/180/270 (Y degrees), 'x90'/'z-90'/'y180',
## or [rx, ry, rz] degrees (multiples of 90). Returns int or an error dict.
func _orientation(gm: GridMap, v) -> Variant:
	if v == null:
		return 0
	var bad := U.err("Invalid orientation %s." % JSON.stringify(v), "Use 0/90/180/270 (degrees around Y), 'x90' / 'z-90' / 'y180', [rx, ry, rz] in multiples of 90, or a raw index 0-23.")
	if v is int or v is float:
		var f := float(v)
		if f in [90.0, 180.0, 270.0, -90.0, -180.0, -270.0]:
			return gm.get_orthogonal_index_from_basis(Basis.from_euler(Vector3(0, deg_to_rad(f), 0)))
		if f == floorf(f) and f >= 0 and f <= 23:
			return int(f)
		return bad
	if v is String:
		var s: String = str(v).to_lower().strip_edges().replace("deg", "")
		var axis := Vector3.UP
		if s.begins_with("x"): axis = Vector3.RIGHT
		elif s.begins_with("z"): axis = Vector3.BACK
		var num := s.trim_prefix("x").trim_prefix("y").trim_prefix("z")
		if not num.is_valid_float() or fmod(num.to_float(), 90.0) != 0.0:
			return bad
		if s == num:  # plain number string
			return _orientation(gm, num.to_float())
		return gm.get_orthogonal_index_from_basis(Basis(axis, deg_to_rad(num.to_float())))
	var r = _vec3(v, "orientation")
	if U.is_err(r) or fmod(r.x, 90.0) != 0.0 or fmod(r.y, 90.0) != 0.0 or fmod(r.z, 90.0) != 0.0:
		return bad
	return gm.get_orthogonal_index_from_basis(Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))))


## Integer grid cell from [x, y, z] / {x, y, z}. Returns Vector3i or an error dict.
func _cell(v, key: String) -> Variant:
	var r = _vec3(v, key)
	if U.is_err(r):
		return r
	if r.x != floorf(r.x) or r.y != floorf(r.y) or r.z != floorf(r.z):
		return U.err("'%s' must be whole cell coordinates (got %s)." % [key, JSON.stringify(v)], "GridMap cells are integers, e.g. [3, 0, -2] (cell index, not meters).")
	return Vector3i(r)


func _item_id(lib: MeshLibrary, item):
	if item == null:
		return U.err("Cell is missing 'item'.")
	if item is int or item is float:
		var id := int(item)
		if id >= 0 and not id in lib.get_item_list():
			return U.err("Item id %d is not in the MeshLibrary." % id, "Items: " + _lib_items_str(lib))
		return id
	var s := str(item)
	if s.is_valid_int():
		return _item_id(lib, s.to_int())
	var id2 := lib.find_item_by_name(s)
	if id2 < 0:
		var names := Array(lib.get_item_list()).map(func(i): return lib.get_item_name(i))
		var sg := U.suggest(s, names)
		return U.err("No item named '%s' in the MeshLibrary." % s, ("Did you mean '%s'? " % sg if sg != "" else "") + "Items: " + _lib_items_str(lib))
	return id2


func _lib_items_str(lib: MeshLibrary) -> String:
	var parts := []
	for i in lib.get_item_list():
		parts.append("%d=%s" % [i, lib.get_item_name(i)])
		if parts.size() >= 40:
			parts.append("...")
			break
	return ", ".join(parts)


## Creates or paints a GridMap: cells [{pos, item, orientation}], fill boxes, erase, clear.
func a_gridmap(p: Dictionary):
	var gm: GridMap = null
	var parent = null
	var existing := false
	if p.has("path"):
		var n = await node_arg(p)
		if U.is_err(n): return n
		if not (n is GridMap):
			return U.err("'%s' is a %s, not a GridMap." % [p.path, n.get_class()], "Omit 'path' to create a new GridMap (with parent/name).")
		gm = n
		existing = true
	else:
		parent = await _parent_arg(p)
		if U.is_err(parent): return parent
		gm = GridMap.new()
		gm.name = U.p_str(p, "name", "GridMap")
	var lib: MeshLibrary = gm.mesh_library
	if p.has("mesh_library"):
		var lp := U.res_path(U.p_str(p, "mesh_library"))
		var l = load(lp) if ResourceLoader.exists(lp) else null
		if not (l is MeshLibrary):
			if not existing: gm.free()
			return U.err("MeshLibrary '%s' not found." % lp if l == null else "'%s' is not a MeshLibrary." % lp, "Create one with world3d.mesh_library {path, from_scene} or {path, items}.")
		lib = l
	if lib == null:
		if not existing: gm.free()
		return U.err("The GridMap needs a mesh_library.", "Pass mesh_library='res://tiles.tres' (create it with world3d.mesh_library).")
	var new_props := {}
	if p.has("cell_size"):
		var cs = _vec3(p.cell_size, "cell_size", true)
		if not U.is_err(cs) and (cs.x <= 0 or cs.y <= 0 or cs.z <= 0):
			cs = U.err("'cell_size' must be positive (got %s)." % JSON.stringify(p.cell_size))
		if U.is_err(cs):
			if not existing: gm.free()
			return cs
		new_props["cell_size"] = cs
	if p.has("mesh_library"):
		new_props["mesh_library"] = lib
	for k in U.p_dict(p, "props"):
		new_props[k] = p.props[k]
	# Collect cell edits: [Vector3i, item, orientation]
	var edits := []
	for c in U.p_arr(p, "cells"):
		var pos
		var item
		var orient = null
		if c is Array and c.size() in [4, 5]:
			pos = _cell(c.slice(0, 3), "cell")
			item = c[3]
			orient = c[4] if c.size() > 4 else null
		elif c is Dictionary and (c.has("pos") or c.has("position")):
			pos = _cell(c.get("pos", c.get("position")), "pos")
			item = c.get("item", null)
			orient = c.get("orientation", c.get("rotation", null))
		else:
			pos = U.err("Invalid cell %s." % JSON.stringify(c), "Cells are {pos: [x,y,z], item: 'Floor' | 0, orientation?: 90} or [x, y, z, item, orientation?].")
		var id = pos if U.is_err(pos) else _item_id(lib, item)
		var ori = id if U.is_err(id) else _orientation(gm, orient)
		if U.is_err(ori):
			if not existing: gm.free()
			ori["message"] = "cells: " + str(ori.message)
			return ori
		edits.append([pos, id, ori])
	for f in U.p_arr(p, "fill"):
		if not (f is Dictionary) or not f.has("from") or not f.has("to"):
			if not existing: gm.free()
			return U.err("Invalid fill %s." % JSON.stringify(f), "fill: [{from: [x,y,z], to: [x,y,z], item: 'Floor', orientation?}] (inclusive box).")
		var a = _cell(f.from, "fill.from")
		var b = _cell(f.to, "fill.to")
		var id2 = a if U.is_err(a) else (b if U.is_err(b) else _item_id(lib, f.get("item")))
		var o = id2 if U.is_err(id2) else _orientation(gm, f.get("orientation", null))
		if U.is_err(o):
			if not existing: gm.free()
			return o
		var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
		var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
		var vol := (hi.x - lo.x + 1) * (hi.y - lo.y + 1) * (hi.z - lo.z + 1)
		if vol > 200000:
			if not existing: gm.free()
			return U.err("Fill box has %d cells (max 200000)." % vol)
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					edits.append([Vector3i(x, y, z), id2, o])
	var erase := U.p_arr(p, "erase")
	if erase.size() == 3 and erase.all(func(x): return x is int or x is float):
		erase = [erase]  # a single cell
	for c in erase:
		var ec = _cell(c, "erase")
		if U.is_err(ec):
			if not existing: gm.free()
			return ec
		edits.append([ec, -1, 0])
	var clear := U.p_bool(p, "clear", false)
	if not existing:
		var pr = U.apply_props(gm, new_props)
		if U.is_err(pr):
			gm.free()
			return pr
		var xr = _apply_xform(gm, p)
		if U.is_err(xr):
			gm.free()
			return xr
		for ed in edits:
			gm.set_cell_item(ed[0], ed[1], ed[2])
		_add_nodes(parent, [gm], "Add GridMap")
	else:
		var infos := U.prop_infos(gm)
		var coerced := {}
		for k in new_props:
			if not infos.has(k):
				var sg := U.suggest(str(k), infos.keys())
				return U.err("Property '%s' not found on GridMap." % k, "Did you mean '%s'?" % sg if sg != "" else "")
			var v = U.coerce(new_props[k], infos[k].type, infos[k].hint, infos[k].hint_string) if not (new_props[k] is Object) else new_props[k]
			if U.is_err(v): return v
			coerced[k] = v
		var u = ctx.begin("Paint GridMap %d cell(s)" % edits.size())
		for k in coerced:
			u.add_do_property(gm, k, coerced[k])
			u.add_undo_property(gm, k, gm.get(k))
		if clear:
			var old := []
			for c2 in gm.get_used_cells():
				old.append([c2, gm.get_cell_item(c2), gm.get_cell_item_orientation(c2)])
			u.add_do_method(gm, "clear")
			u.add_undo_method(gm, "clear")  # undo ops run in order: wipe, then restore the old cells
			for o2 in old:
				u.add_undo_method(gm, "set_cell_item", o2[0], o2[1], o2[2])
		var seen := {}
		for ed in edits:
			u.add_do_method(gm, "set_cell_item", ed[0], ed[1], ed[2])
			if not seen.has(ed[0]) and not clear:
				seen[ed[0]] = true
				u.add_undo_method(gm, "set_cell_item", ed[0], gm.get_cell_item(ed[0]), maxi(0, gm.get_cell_item_orientation(ed[0])))
		ctx.commit()
	return {"path": ctx.node_path_str(gm), "created": not existing, "cells_set": edits.size(), "used_cells": gm.get_used_cells().size(), "cell_size": var_to_str(gm.cell_size), "mesh_library": lib.resource_path, "items": _lib_items_str(lib)}


## Creates a MeshLibrary (.tres) from a scene of MeshInstance3D children (like Scene > Export As >
## MeshLibrary: meshes, StaticBody3D collision shapes, NavigationRegion3D navmeshes) or from items.
func a_mesh_library(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if path.get_extension() == "":
		path += ".tres"
	if not p.has("from_scene") and not p.has("items"):
		return U.err("Pass from_scene='res://tiles.tscn' or items=[{name, shape|mesh, material?, collision?}].")
	var lib: MeshLibrary
	var merged := false
	if ResourceLoader.exists(path) and not U.p_bool(p, "replace", false):
		var cur = load(path)
		if not (cur is MeshLibrary):
			return U.err("'%s' exists and is a %s." % [path, cur.get_class()], "Pick another path.")
		lib = cur
		merged = true
	else:
		lib = MeshLibrary.new()
	# Everything is built into a staging library first; the (possibly shared, already loaded)
	# target library is only touched once all items are valid.
	var staging := MeshLibrary.new()
	var added := []
	var ignored := []
	if p.has("from_scene"):
		var sp := U.res_path(U.p_str(p, "from_scene"))
		if not ResourceLoader.exists(sp):
			return U.err("Scene '%s' does not exist." % sp, "Build a scene with one MeshInstance3D child per tile (optionally with StaticBody3D/CollisionShape3D children), or pass items=[...].")
		var packed = load(sp)
		if not (packed is PackedScene):
			return U.err("'%s' is not a scene." % sp)
		var inst: Node = packed.instantiate()
		_lib_parse(staging, inst, inst, added, ignored)
		inst.free()
		if added.is_empty():
			return U.err("No MeshInstance3D nodes with meshes found in '%s'." % sp, "Each tile must be a MeshInstance3D (direct child of the root or nested).")
	var items := U.p_arr(p, "items")
	for i in items.size():
		var it = items[i]
		if not (it is Dictionary):
			return U.err("Invalid item %s." % JSON.stringify(it), "items: [{name: 'Floor', shape: 'box', size: [2, 0.2, 2], material: {albedo_color: '#777'}, collision: true}]")
		var nm := U.p_str(it, "name", "Item%d" % (lib.get_last_unused_item_id() + staging.get_item_list().size()))
		var mesh
		if it.has("mesh"):
			mesh = U.to_object(it.mesh)
			if U.is_err(mesh): return mesh
			if not (mesh is Mesh):
				return U.err("Item '%s': mesh must be a Mesh resource." % nm)
		else:
			mesh = build_primitive(U.p_str(it, "shape", "box"), it)
			if U.is_err(mesh):
				mesh["message"] = "Item '%s': %s" % [nm, mesh.message]
				return mesh
		if it.has("material"):
			var mat = build_material(it.material)
			if U.is_err(mat):
				mat["message"] = "Item '%s': %s" % [nm, mat.message]
				return mat
			mesh = mesh.duplicate()
			_set_mesh_material(mesh, -1, mat)
		var xf := Transform3D.IDENTITY
		if it.has("offset"):
			var off = _vec3(it.offset, "offset")
			if U.is_err(off): return off
			xf.origin = off
		var coll = it.get("collision", true)
		var shapes := []
		if not (coll is bool and not coll) and str(coll) != "none":
			var kind := "auto" if coll is bool or str(coll) in ["static", "true", "auto"] else str(coll)
			if not kind in ["auto", "convex", "trimesh", "concave"]:
				return U.err("Item '%s': unknown collision '%s'." % [nm, coll], "Use true (best-fit shape), 'convex', 'trimesh' or false.")
			var sh := shape_for_mesh(mesh, kind)
			if sh:
				shapes = [sh, xf]
		var id := staging.find_item_by_name(nm)
		if id < 0:
			id = staging.get_last_unused_item_id()
			staging.create_item(id)
		staging.set_item_name(id, nm)
		staging.set_item_mesh(id, mesh)
		staging.set_item_mesh_transform(id, xf)
		staging.set_item_shapes(id, shapes)
		added.append({"id": -1, "name": nm, "shapes": shapes.size() / 2})
	# Merge the staged items into the target library by name.
	var previews_for := []
	for sid in staging.get_item_list():
		var nm2 := staging.get_item_name(sid)
		var id2 := lib.find_item_by_name(nm2)
		if id2 < 0:
			id2 = lib.get_last_unused_item_id()
			lib.create_item(id2)
		lib.set_item_name(id2, nm2)
		lib.set_item_mesh(id2, staging.get_item_mesh(sid))
		lib.set_item_mesh_transform(id2, staging.get_item_mesh_transform(sid))
		lib.set_item_mesh_cast_shadow(id2, staging.get_item_mesh_cast_shadow(sid))
		lib.set_item_shapes(id2, staging.get_item_shapes(sid))
		lib.set_item_navigation_mesh(id2, staging.get_item_navigation_mesh(sid))
		lib.set_item_navigation_mesh_transform(id2, staging.get_item_navigation_mesh_transform(sid))
		lib.set_item_navigation_layers(id2, staging.get_item_navigation_layers(sid))
		for a in added:
			if a.name == nm2:
				a.id = id2
		previews_for.append([id2, staging.get_item_mesh(sid)])
	var previews := _make_previews(lib, previews_for)
	var sr = _save_res(lib, path)
	if U.is_err(sr): return sr
	var out := {"path": path, "merged_into_existing": merged, "items": added, "item_count": lib.get_item_list().size(), "previews": previews}
	if not ignored.is_empty():
		out["note"] = "Not included (not MeshInstance3D or no mesh): " + ", ".join(ignored.slice(0, 20))
	return out


func _lib_parse(lib: MeshLibrary, root: Node, n: Node, added: Array, ignored: Array) -> void:
	for c in n.get_children():
		if c is CSGShape3D and not (c.get_parent() is CSGShape3D):
			ignored.append("%s (CSG; tiles must be MeshInstance3D)" % c.name)
			continue
		if c is MeshInstance3D and c.mesh:
			var mi: MeshInstance3D = c
			var mesh: Mesh = mi.mesh
			# Bake surface override / material_override into a mesh copy (the library has no overrides).
			var has_override := mi.material_override != null
			for s in mi.get_surface_override_material_count():
				if mi.get_surface_override_material(s):
					has_override = true
			if has_override:
				mesh = mesh.duplicate()
				for s in mesh.get_surface_count():
					var m: Material = mi.material_override if mi.material_override else mi.get_surface_override_material(s)
					if m:
						_set_mesh_material(mesh, s, m)
			var nm := str(mi.name)
			var id := lib.find_item_by_name(nm)
			if id < 0:
				id = lib.get_last_unused_item_id()
				lib.create_item(id)
			lib.set_item_name(id, nm)
			lib.set_item_mesh(id, mesh)
			var mxf := Transform3D(mi.basis, Vector3.ZERO)  # tiles are laid out side by side; drop their offset
			lib.set_item_mesh_transform(id, mxf)
			var shapes := []
			for body in mi.get_children():
				if body is StaticBody3D:
					for cs in body.get_children():
						if cs is CollisionShape3D and cs.shape:
							shapes.append(cs.shape)
							shapes.append(mxf * (body as Node3D).transform * (cs as Node3D).transform)
				elif body is NavigationRegion3D and body.navigation_mesh:
					lib.set_item_navigation_mesh(id, body.navigation_mesh)
					lib.set_item_navigation_mesh_transform(id, mxf * (body as Node3D).transform)
			lib.set_item_shapes(id, shapes)
			added.append({"id": id, "name": nm, "shapes": shapes.size() / 2})
		_lib_parse(lib, root, c, added, ignored)


func _make_previews(lib: MeshLibrary, items: Array) -> String:
	if items.is_empty():
		return "none"
	if DisplayServer.get_name() == "headless":
		return "skipped (headless editor can't render previews)"
	var meshes := items.map(func(x): return x[1])
	var tex := EditorInterface.make_mesh_previews(meshes, 64)
	for i in mini(tex.size(), items.size()):
		if tex[i]:
			lib.set_item_preview(items[i][0], tex[i])
	return "generated"


# =============================================================================
# Scatter
# =============================================================================

## Scatters a mesh or scene over an area (MultiMeshInstance3D or real instances), optionally
## dropped onto the ground by raycasting (physics colliders first, then visible meshes).
func a_scatter(p: Dictionary):
	var e = U.require(p, ["source"])
	if e: return e
	var parent = await _parent_arg(p)
	if U.is_err(parent): return parent
	var src = p.source
	var mesh: Mesh = null
	var packed: PackedScene = null
	var mesh_xf := Transform3D.IDENTITY
	var src_material: Material = null
	if src is Dictionary:
		var bm = build_primitive(U.p_str(src, "shape", "box"), src)
		if U.is_err(bm): return bm
		mesh = bm
		if src.has("material"):
			var m0 = build_material(src.material)
			if U.is_err(m0): return m0
			src_material = m0
	else:
		var sp := U.res_path(str(src))
		if not ResourceLoader.exists(sp):
			return U.err("Source '%s' does not exist." % sp, "Pass a res:// scene/model (.tscn/.glb), a mesh (.tres/.mesh), or an inline {shape: 'sphere', radius: 0.3, material: '#3a5'}.")
		var r = load(sp)
		if r is Mesh:
			mesh = r
		elif r is PackedScene:
			packed = r
		else:
			return U.err("Source '%s' is a %s; expected a Mesh or a scene." % [sp, r.get_class()])
	if p.has("material"):
		var m1 = build_material(p.material)
		if U.is_err(m1): return m1
		src_material = m1
	var mode := U.p_str(p, "mode", "multimesh" if mesh else "instances").to_lower()
	if not mode in ["multimesh", "instances"]:
		return U.err("Unknown mode '%s'." % mode, "Use 'multimesh' (fast, visual only) or 'instances' (real nodes, keeps scripts/collision).")
	if mode == "multimesh" and packed:
		var inst0: Node = packed.instantiate()
		var mis := inst0.find_children("*", "MeshInstance3D", true, false)
		if inst0 is MeshInstance3D:
			mis.push_front(inst0)
		if mis.is_empty() or mis[0].mesh == null:
			inst0.free()
			return U.err("The scene has no MeshInstance3D to use for a MultiMesh.", "Use mode='instances' to place copies of the whole scene.")
		var mi0: MeshInstance3D = mis[0]
		mesh = mi0.mesh
		if src_material == null:
			src_material = mi0.material_override if mi0.material_override else (mi0.get_surface_override_material(0) if mi0.get_surface_override_material_count() > 0 else null)
		mesh_xf = _rel_xform(inst0, mi0)
		var note_multi := mis.size() > 1
		var first_name := str(mi0.name)
		var mesh_count := mis.size()
		inst0.free()
		if note_multi:
			p["_note"] = "The scene has %d meshes; MultiMesh uses only the first ('%s'). Use mode='instances' for the whole scene." % [mesh_count, first_name]
	if mode == "multimesh" and not _multimesh_persists():
		if mesh == null and packed == null:
			return U.err("No source mesh.")
		mode = "instances"
		p["_note"] = "This editor's renderer (headless/dummy) can't store MultiMesh data, so real nodes were placed instead. Run the normal editor to get a MultiMeshInstance3D."
		if packed and mesh != null and p.get("mode", "") == "multimesh":
			mesh = null  # place the whole scene
	var max_count := 100000 if mode == "multimesh" else 2000
	var count_f = _num(p.get("count", 50), "count", 1, max_count)
	if U.is_err(count_f):
		count_f["hint"] = "count is 1..%d for mode '%s'%s." % [max_count, mode, " (use mode='multimesh' for more)" if mode == "instances" else ""]
		return count_f
	var count := int(count_f)
	var area := U.p_dict(p, "area")
	if p.has("area") and not (p.area is Dictionary):
		return U.err("'area' must be {center: [x,y,z], size: [w,d]} or {center, radius}.")
	for ak in area:
		if not str(ak) in ["center", "size", "radius"]:
			return U.err("Unknown area key '%s'." % ak, "area: {center: [x,y,z], size: [w,d] | [w,h,d]} or {center, radius}.")
	var center = _vec3(area.get("center", p.get("center", [0, 0, 0])), "area.center")
	if U.is_err(center): return center
	var sz = area.get("size", p.get("size", [10, 10]))
	var size3 = null
	if sz is Array and sz.size() == 2:
		size3 = _vec3([sz[0], 0, sz[1]], "area.size")
	else:
		size3 = _vec3(sz, "area.size", true)
		if not U.is_err(size3) and (sz is int or sz is float or sz is String):
			size3.y = 0.0  # a single number is a square [w, w]
	if U.is_err(size3): return size3
	if size3.x < 0 or size3.y < 0 or size3.z < 0:
		return U.err("'area.size' must not be negative.")
	var radius = _num(area.get("radius", 0.0), "area.radius", 0.0)
	if U.is_err(radius): return radius
	var rng := RandomNumberGenerator.new()
	rng.seed = U.p_int(p, "seed", randi())
	var rot_y := U.p_bool(p, "random_rotation_y", true)
	var sr_arr = p.get("scale_range", [1, 1])
	if not (sr_arr is Array):
		sr_arr = [sr_arr, sr_arr]
	if sr_arr.size() != 2:
		return U.err("'scale_range' must be [min, max] (got %s)." % JSON.stringify(p.scale_range), "e.g. scale_range: [0.8, 1.3]")
	var smin = _num(sr_arr[0], "scale_range", 0.0001)
	var smax = _num(sr_arr[1], "scale_range", 0.0001)
	for x in [smin, smax]:
		if U.is_err(x): return x
	if smax < smin:
		var t0 = smin
		smin = smax
		smax = t0
	var min_dist = _num(p.get("min_distance", 0.0), "min_distance", 0.0)
	if U.is_err(min_dist): return min_dist
	var y_off = _num(p.get("y_offset", 0.0), "y_offset")
	if U.is_err(y_off): return y_off
	var align := U.p_bool(p, "align_to_ground", false) or p.has("ground")
	var align_normal := U.p_bool(p, "align_to_normal", false)
	# Ground: explicit node(s), else every collider/mesh (the LOWEST surface under each point wins,
	# so props land on the floor/terrain rather than on roofs, trees or earlier scattered props).
	var ground_nodes := []
	for gp0 in U.p_arr(p, "ground"):
		var gn: Node = ctx.find_node(str(gp0))
		if gn == null:
			return ctx.node_not_found(str(gp0))
		ground_nodes.append(gn)
	var ground_method := "none"
	var space: PhysicsDirectSpaceState3D = null
	var tri_meshes := []
	if align:
		var root3d: Node = ctx.edited_root()
		if root3d is Node3D or parent is Node3D:
			await ctx.plugin.get_tree().physics_frame
			var w: World3D = (parent as Node3D).get_world_3d() if parent is Node3D else (root3d as Node3D).get_world_3d()
			if w:
				space = w.direct_space_state
		var mesh_roots: Array = ground_nodes if not ground_nodes.is_empty() else [ctx.edited_root()]
		for mr in mesh_roots:
			var mis: Array = mr.find_children("*", "MeshInstance3D", true, false)
			if mr is MeshInstance3D:
				mis.append(mr)
			for mi in mis:
				if mi.mesh and mi.is_visible_in_tree():
					var tm: TriangleMesh = mi.mesh.generate_triangle_mesh()
					if tm:
						tri_meshes.append([mi.global_transform, tm])
	var pg := _parent_global(parent)
	var pg_inv := pg.affine_inverse()
	var xforms := []
	var misses := 0
	var attempts := 0
	var hits_physics := 0
	var hits_mesh := 0
	while xforms.size() < count and attempts < count * 30:
		attempts += 1
		var off: Vector3
		if radius > 0:
			var ang := rng.randf() * TAU
			var rr: float = sqrt(rng.randf()) * radius
			off = Vector3(cos(ang) * rr, 0, sin(ang) * rr)
		else:
			off = Vector3(rng.randf_range(-0.5, 0.5) * size3.x, rng.randf_range(-0.5, 0.5) * size3.y, rng.randf_range(-0.5, 0.5) * size3.z)
		var gp: Vector3 = pg * (center + off)  # area is in the parent's space
		var normal := Vector3.UP
		if align:
			var hit = _ground_hit(space, tri_meshes, gp, ground_nodes)
			if hit == null:
				misses += 1
				continue
			gp = hit[0]
			normal = hit[1]
			if hit[2] == "physics": hits_physics += 1
			else: hits_mesh += 1
		if min_dist > 0:
			var ok := true
			for other in xforms:
				if (other[0] as Vector3).distance_to(gp) < min_dist:
					ok = false
					break
			if not ok:
				continue
		var s := rng.randf_range(smin, smax)
		var basis := Basis.IDENTITY
		if align_normal and normal != Vector3.UP:
			var axis := Vector3.UP.cross(normal).normalized()
			basis = Basis(axis, Vector3.UP.angle_to(normal))
		if rot_y:
			basis = basis * Basis(Vector3.UP, rng.randf() * TAU)
		basis = basis * Basis.from_scale(Vector3.ONE * s)
		xforms.append([gp + normal * y_off, basis])
	if xforms.is_empty():
		return U.err("Nothing was placed (%d ground misses)." % misses, "With align_to_ground, the area must be above ground that has collision or visible meshes. Check area.center/size.")
	if align:
		ground_method = "physics" if hits_physics > 0 and hits_mesh == 0 else ("mesh" if hits_physics == 0 else "physics+mesh")
	var node: Node3D
	if mode == "multimesh":
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			var local := pg_inv * Transform3D(xforms[i][1], xforms[i][0])
			mm.set_instance_transform(i, local * mesh_xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if src_material:
			mmi.material_override = src_material
		node = mmi
	else:
		node = Node3D.new()
		for i in xforms.size():
			var child: Node3D
			if packed:
				child = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			else:
				var mi2 := MeshInstance3D.new()
				mi2.mesh = mesh
				if src_material:
					mi2.material_override = src_material
				child = mi2
			child.name = "%s%d" % [U.p_str(p, "item_name", str(child.name) if packed else "Item"), i + 1]
			child.transform = pg_inv * Transform3D(xforms[i][1], xforms[i][0])
			node.add_child(child, true)
	node.name = U.p_str(p, "name", "Scatter")
	if p.has("cast_shadow") and node is GeometryInstance3D:
		U.set_prop(node, "cast_shadow", p.cast_shadow)
	_add_nodes(parent, [node], "Scatter %d" % xforms.size())
	var out := {"path": ctx.node_path_str(node), "mode": mode, "placed": xforms.size(), "requested": count}
	if align:
		out["ground"] = ground_method
		out["misses"] = misses
	var notes := []
	if p.has("_note"):
		notes.append(str(p._note))
	if xforms.size() < count and not align:
		notes.append("Only %d fit with min_distance=%s; reduce min_distance or enlarge the area." % [xforms.size(), min_dist])
	if not notes.is_empty():
		out["note"] = " ".join(notes)
	return out


## The dummy renderer used by headless editors drops MultiMesh buffers (they'd save empty).
func _multimesh_persists() -> bool:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 1
	var t := Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))
	mm.set_instance_transform(0, t)
	return mm.get_instance_transform(0).origin.is_equal_approx(t.origin)


func _set_mesh_material(mesh: Mesh, surface: int, m: Material) -> void:
	if mesh is PrimitiveMesh:
		(mesh as PrimitiveMesh).material = m
	elif mesh is ArrayMesh:
		for s in mesh.get_surface_count():
			if surface < 0 or s == surface:
				(mesh as ArrayMesh).surface_set_material(s, m)


func _rel_xform(root: Node, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Raycasts straight down at a global XZ point and returns the LOWEST surface hit (physics
## colliders first, then visible meshes), limited to `ground` subtrees when given.
## Returns [point, normal, method] or null.
func _ground_hit(space: PhysicsDirectSpaceState3D, tri_meshes: Array, gp: Vector3, ground: Array = []):
	var from := Vector3(gp.x, gp.y + 1000.0, gp.z)
	var to := Vector3(gp.x, gp.y - 1000.0, gp.z)
	var best = null
	if space:
		var exclude: Array[RID] = []
		for i in 24:
			var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude)
			var r := space.intersect_ray(q)
			if r.is_empty():
				break
			exclude.append(r.rid)
			if not ground.is_empty() and not _in_subtrees(r.collider, ground):
				continue
			if best == null or (r.position as Vector3).y < (best[0] as Vector3).y:
				best = [r.position, r.normal, "physics"]
		if best != null:
			return best
	for tm in tri_meshes:
		var xf: Transform3D = tm[0]
		var inv := xf.affine_inverse()
		var lf: Vector3 = inv * from
		var ld: Vector3 = (inv.basis * (to - from)).normalized()
		var hit: Dictionary = (tm[1] as TriangleMesh).intersect_ray(lf, ld)
		if not hit.is_empty():
			var wp: Vector3 = xf * (hit.position as Vector3)
			if best == null or wp.y < (best[0] as Vector3).y:
				var nrm: Vector3 = (xf.basis.inverse().transposed() * (hit.normal as Vector3)).normalized()
				if nrm.y < 0:
					nrm = -nrm
				best = [wp, nrm, "mesh"]
	return best


func _in_subtrees(o: Object, roots: Array) -> bool:
	if not (o is Node):
		return false
	for r in roots:
		if r == o or (r as Node).is_ancestor_of(o):
			return true
	return false
