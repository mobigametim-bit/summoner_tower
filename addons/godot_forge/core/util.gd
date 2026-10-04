@tool
extends RefCounted
## Shared helpers: Variant <-> JSON conversion, value coercion, errors, node lookup.

const MAX_ARRAY_ITEMS := 200
const MAX_STRING_LEN := 400000


# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------

## Returns a structured error that the router turns into a JSON-RPC style error.
static func err(message: String, hint: String = "", extra: Dictionary = {}) -> Dictionary:
	var e := {"__forge_error": true, "message": message}
	if hint != "":
		e["hint"] = hint
	for k in extra:
		e[k] = extra[k]
	return e


static func is_err(v) -> bool:
	return v is Dictionary and v.get("__forge_error", false)


# ---------------------------------------------------------------------------
# Parameter helpers
# ---------------------------------------------------------------------------

static func p_str(p: Dictionary, key: String, default: String = "") -> String:
	var v = p.get(key, null)
	if v == null:
		return default
	return str(v)


static func p_int(p: Dictionary, key: String, default: int = 0) -> int:
	var v = p.get(key, null)
	if v == null:
		return default
	return int(v)


static func p_float(p: Dictionary, key: String, default: float = 0.0) -> float:
	var v = p.get(key, null)
	if v == null:
		return default
	return float(v)


static func p_bool(p: Dictionary, key: String, default: bool = false) -> bool:
	var v = p.get(key, null)
	if v == null:
		return default
	if v is String:
		return v.to_lower() in ["true", "1", "yes", "on"]
	return bool(v)


static func p_dict(p: Dictionary, key: String) -> Dictionary:
	var v = p.get(key, null)
	return v if v is Dictionary else {}


static func p_arr(p: Dictionary, key: String) -> Array:
	var v = p.get(key, null)
	if v is Array:
		return v
	if v == null:
		return []
	return [v]


static func require(p: Dictionary, keys: Array):
	for k in keys:
		if not p.has(k) or p[k] == null or (p[k] is String and p[k] == ""):
			return err("Missing required parameter '%s'." % k)
	return null


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

## Normalises a user supplied path to a res:// path (accepts "res://x", "x", "/x", "uid://...").
static func res_path(path: String) -> String:
	path = path.strip_edges().replace("\\", "/")
	if path == "":
		return ""
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
		return path
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	var project_abs := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if path.begins_with(project_abs):
		return "res://" + path.substr(project_abs.length())
	while path.begins_with("/"):
		path = path.substr(1)
	return "res://" + path


## True if path stays inside res:// or user:// (no traversal outside the project).
static func is_safe_path(path: String) -> bool:
	if not (path.begins_with("res://") or path.begins_with("user://")):
		return false
	return not path.simplify_path().contains("..")


# ---------------------------------------------------------------------------
# Variant -> JSON
# ---------------------------------------------------------------------------

static func encode(v, depth: int = 0) -> Variant:
	if depth > 12:
		return "<max depth>"
	match typeof(v):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT:
			return v
		TYPE_FLOAT:
			if is_nan(v) or is_inf(v):
				return str(v)
			return v
		TYPE_STRING:
			if v.length() > MAX_STRING_LEN:
				return v.substr(0, MAX_STRING_LEN) + "…<truncated %d chars>" % (v.length() - MAX_STRING_LEN)
			return v
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(v)
		TYPE_OBJECT:
			return encode_object(v)
		TYPE_DICTIONARY:
			if v.get("__image", false) or v.get("__raw", false):
				return v
			var d := {}
			for k in v:
				d[str(k) if not (k is String) else k] = encode(v[k], depth + 1)
			return d
		TYPE_ARRAY:
			var a := []
			var n: int = v.size()
			for i in min(n, MAX_ARRAY_ITEMS):
				a.append(encode(v[i], depth + 1))
			if n > MAX_ARRAY_ITEMS:
				a.append("…<%d more>" % (n - MAX_ARRAY_ITEMS))
			return a
		TYPE_PACKED_BYTE_ARRAY:
			return "PackedByteArray(size=%d)" % v.size()
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var a2 := []
			var n2: int = v.size()
			for i in min(n2, MAX_ARRAY_ITEMS):
				a2.append(encode(v[i], depth + 1))
			if n2 > MAX_ARRAY_ITEMS:
				a2.append("…<%d more>" % (n2 - MAX_ARRAY_ITEMS))
			return a2
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			var a3 := []
			var n3: int = v.size()
			for i in min(n3, MAX_ARRAY_ITEMS):
				a3.append(var_to_str(v[i]))
			if n3 > MAX_ARRAY_ITEMS:
				a3.append("…<%d more>" % (n3 - MAX_ARRAY_ITEMS))
			return a3
		TYPE_CALLABLE:
			return "Callable(%s)" % str(v)
		TYPE_SIGNAL:
			return "Signal(%s)" % str(v)
		TYPE_RID:
			return "RID"
		_:
			# Vectors, Color, Rect2, Transform, Basis, Quaternion, Plane, AABB, Projection...
			return var_to_str(v)


static func encode_object(o) -> Variant:
	if o == null or not is_instance_valid(o):
		return null
	if o is Node:
		var n: Node = o
		var d := {"node": str(n.get_path()) if n.is_inside_tree() else n.name, "type": n.get_class()}
		return d
	if o is Resource:
		var r: Resource = o
		var d2 := {"type": r.get_class()}
		if r.resource_path != "" and not r.resource_path.contains("::"):
			d2["path"] = r.resource_path
		else:
			d2["embedded"] = true
			var props := {}
			for pi in r.get_property_list():
				if not (pi.usage & PROPERTY_USAGE_STORAGE) or not (pi.usage & PROPERTY_USAGE_EDITOR):
					continue
				var pname: String = pi.name
				if pname in ["resource_name", "resource_path", "resource_local_to_scene", "script"]:
					continue
				var val = r.get(pname)
				var def = ClassDB.class_get_property_default_value(r.get_class(), pname) if ClassDB.class_exists(r.get_class()) else null
				if def != null and typeof(def) == typeof(val) and def == val:
					continue
				if val is Object:
					props[pname] = {"type": val.get_class()} if val else null
				else:
					props[pname] = encode(val, 8)
				if props.size() > 30:
					break
			if not props.is_empty():
				d2["props"] = props
		if r.resource_name != "":
			d2["name"] = r.resource_name
		return d2
	return {"object": o.get_class(), "id": o.get_instance_id()}


# ---------------------------------------------------------------------------
# JSON -> Variant (coercion using the target property type)
# ---------------------------------------------------------------------------

## Converts a JSON-ish value into a Variant of the given type. `hint`/`hint_string`
## come from the property info and are used for enums and resource classes.
static func coerce(value, target_type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = "") -> Variant:
	if value == null:
		return null
	match target_type:
		TYPE_NIL:
			return _auto(value)
		TYPE_BOOL:
			if value is String:
				return value.to_lower() in ["true", "1", "yes", "on"]
			return bool(value)
		TYPE_INT:
			if value is String:
				if hint == PROPERTY_HINT_ENUM or hint == PROPERTY_HINT_FLAGS:
					var e = _enum_value(value, hint_string, hint == PROPERTY_HINT_FLAGS)
					if e != null:
						return e
				if value.is_valid_int():
					return value.to_int()
				if value.is_valid_float():
					return int(value.to_float())
				return err("Cannot convert '%s' to int." % value, _enum_hint(hint, hint_string))
			if value is Array and hint == PROPERTY_HINT_FLAGS:
				var bits := 0
				for item in value:
					var b = _enum_value(str(item), hint_string, true) if item is String else int(item)
					if b != null:
						bits |= int(b)
				return bits
			return int(value)
		TYPE_FLOAT:
			if value is String:
				if value.is_valid_float() or value.is_valid_int():
					return value.to_float()
				if value.to_lower() in ["inf", "infinity"]:
					return INF
				return err("Cannot convert '%s' to a number." % value, "Pass a number, e.g. 250.")
			if value is bool:
				return 1.0 if value else 0.0
			return float(value)
		TYPE_STRING:
			return str(value) if not (value is Dictionary or value is Array) else JSON.stringify(value)
		TYPE_STRING_NAME:
			return StringName(str(value))
		TYPE_NODE_PATH:
			if value is Dictionary and value.has("node"):
				return NodePath(str(value.node))
			return NodePath(str(value))
		TYPE_COLOR:
			if value is String and not is_color_string(value):
				return err("'%s' is not a color." % value, "Use a hex string like '#ff8800', a named color like 'red', [r, g, b(, a)] or 'Color(1, 0.5, 0, 1)'.")
			return to_color(value)
		TYPE_OBJECT:
			return to_object(value, hint_string)
		TYPE_ARRAY:
			if value is String:
				var parsed = str_to_var(value)
				return parsed if parsed is Array else [value]
			if value is Array:
				var out := []
				# typed arrays: hint_string like "2/0:" or "24/17:Texture2D" or just a class name
				var elem_type := TYPE_NIL
				var elem_hint_str := ""
				if hint == PROPERTY_HINT_ARRAY_TYPE and hint_string != "":
					if ClassDB.class_exists(hint_string):
						elem_type = TYPE_OBJECT
						elem_hint_str = hint_string
					else:
						var parts := hint_string.split(":", true, 1)
						var head := parts[0].split("/")
						elem_type = int(head[0])
						if parts.size() > 1:
							elem_hint_str = parts[1]
				for item in value:
					out.append(coerce(item, elem_type, PROPERTY_HINT_NONE, elem_hint_str) if elem_type != TYPE_NIL else _auto(item))
				return out
			return [value]
		TYPE_DICTIONARY:
			if value is String:
				var parsed2 = str_to_var(value)
				return parsed2 if parsed2 is Dictionary else {}
			if value is Dictionary:
				var d := {}
				for k in value:
					d[k] = _auto(value[k])
				return d
			return {}
		TYPE_PACKED_STRING_ARRAY:
			return PackedStringArray(value if value is Array else [str(value)])
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array(value if value is Array else [])
		TYPE_PACKED_INT64_ARRAY:
			return PackedInt64Array(value if value is Array else [])
		TYPE_PACKED_FLOAT32_ARRAY:
			return PackedFloat32Array(value if value is Array else [])
		TYPE_PACKED_FLOAT64_ARRAY:
			return PackedFloat64Array(value if value is Array else [])
		TYPE_PACKED_BYTE_ARRAY:
			if value is String:
				return Marshalls.base64_to_raw(value)
			return PackedByteArray(value if value is Array else [])
		TYPE_PACKED_VECTOR2_ARRAY:
			var pv2 := PackedVector2Array()
			if value is String:
				var sv = str_to_var(value)
				if sv is PackedVector2Array:
					return sv
			for item in (value if value is Array else []):
				pv2.append(to_vector(item, TYPE_VECTOR2))
			return pv2
		TYPE_PACKED_VECTOR3_ARRAY:
			var pv3 := PackedVector3Array()
			for item in (value if value is Array else []):
				pv3.append(to_vector(item, TYPE_VECTOR3))
			return pv3
		TYPE_PACKED_COLOR_ARRAY:
			var pc := PackedColorArray()
			for item in (value if value is Array else []):
				pc.append(to_color(item))
			return pc
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I:
			if value is String and not is_vector_string(value):
				return err("'%s' is not a %s." % [value, type_string(target_type)], "Use an array like [1, 2], an object {x, y, ...} or '%s(...)'." % type_string(target_type))
			return to_vector(value, target_type)
		_:
			# Rect2, Transform2D, Transform3D, Basis, Quaternion, AABB, Plane, Projection
			return to_math(value, target_type)


## Best-effort conversion when the target type is unknown.
static func _auto(value) -> Variant:
	if value is String:
		var s: String = value
		if s.begins_with("res://") or s.begins_with("uid://"):
			if ResourceLoader.exists(res_path(s)) and not s.ends_with(".gd") and not s.ends_with(".cs"):
				return load(res_path(s))
			return s
		if s.begins_with("#") and s.length() in [4, 5, 7, 9] and Color.html_is_valid(s):
			return Color.html(s)
		for prefix in ["Vector2", "Vector3", "Vector4", "Color(", "Rect2", "Transform", "Basis(", "Quaternion(", "AABB(", "Plane(", "NodePath(", "StringName(", "Packed"]:
			if s.begins_with(prefix):
				var parsed = str_to_var(s)
				if parsed != null:
					return parsed
		return s
	if value is Dictionary:
		if value.has("type") and ClassDB.class_exists(str(value.type)) and ClassDB.is_parent_class(str(value.type), "Resource"):
			return to_object(value, "")
		if value.has("path") and value.size() <= 2 and str(value.path).begins_with("res://"):
			return to_object(value, "")
		var d := {}
		for k in value:
			d[k] = _auto(value[k])
		return d
	if value is Array:
		var a := []
		for item in value:
			a.append(_auto(item))
		return a
	if value is float and value == floor(value) and abs(value) < 9007199254740992.0:
		return int(value)
	return value


static func is_color_string(s: String) -> bool:
	s = s.strip_edges()
	if s.begins_with("Color(") or Color.html_is_valid(s):
		return true
	var sentinel := Color(0.123, 0.456, 0.789, 0.5)
	return Color.from_string(s, sentinel) != sentinel


static func is_vector_string(s: String) -> bool:
	var parsed = str_to_var(s)
	if parsed != null and typeof(parsed) in [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I]:
		return true
	var cleaned := s.replace("(", " ").replace(")", " ").replace(",", " ").replace("[", " ").replace("]", " ")
	var parts := cleaned.split(" ", false)
	if parts.is_empty():
		return false
	for part in parts:
		if not part.is_valid_float():
			return false
	return true


static func to_color(value) -> Color:
	if value is Color:
		return value
	if value is String:
		var s: String = value.strip_edges()
		if s.begins_with("Color("):
			var c = str_to_var(s)
			if c is Color:
				return c
		if Color.html_is_valid(s):
			return Color.html(s)
		return Color.from_string(s, Color.MAGENTA)
	if value is Array:
		var a: Array = value
		var scale := 255.0 if a.any(func(x): return float(x) > 1.0) else 1.0
		var r := float(a[0]) / scale if a.size() > 0 else 0.0
		var g := float(a[1]) / scale if a.size() > 1 else 0.0
		var b := float(a[2]) / scale if a.size() > 2 else 0.0
		var al := float(a[3]) / (scale if a.size() > 3 and float(a[3]) > 1.0 else 1.0) if a.size() > 3 else 1.0
		return Color(r, g, b, al)
	if value is Dictionary:
		return Color(float(value.get("r", 0)), float(value.get("g", 0)), float(value.get("b", 0)), float(value.get("a", 1)))
	return Color.MAGENTA


static func to_vector(value, t: int) -> Variant:
	var comps := []
	if value is String:
		var parsed = str_to_var(value)
		if parsed != null and typeof(parsed) in [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I]:
			value = parsed
		else:
			var cleaned: String = value.replace("(", " ").replace(")", " ").replace(",", " ")
			for part in cleaned.split(" ", false):
				if part.is_valid_float():
					comps.append(part.to_float())
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			comps = [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			comps = [value.x, value.y, value.z]
		TYPE_VECTOR4, TYPE_VECTOR4I:
			comps = [value.x, value.y, value.z, value.w]
		TYPE_ARRAY:
			comps = value
		TYPE_DICTIONARY:
			for k in ["x", "y", "z", "w"]:
				if value.has(k):
					comps.append(value[k])
		TYPE_INT, TYPE_FLOAT:
			comps = [value, value, value, value]
	while comps.size() < 4:
		comps.append(0)
	match t:
		TYPE_VECTOR2: return Vector2(float(comps[0]), float(comps[1]))
		TYPE_VECTOR2I: return Vector2i(int(comps[0]), int(comps[1]))
		TYPE_VECTOR3: return Vector3(float(comps[0]), float(comps[1]), float(comps[2]))
		TYPE_VECTOR3I: return Vector3i(int(comps[0]), int(comps[1]), int(comps[2]))
		TYPE_VECTOR4: return Vector4(float(comps[0]), float(comps[1]), float(comps[2]), float(comps[3]))
		TYPE_VECTOR4I: return Vector4i(int(comps[0]), int(comps[1]), int(comps[2]), int(comps[3]))
	return null


static func to_math(value, t: int) -> Variant:
	if value is String:
		var parsed = str_to_var(value)
		if typeof(parsed) == t:
			return parsed
	match t:
		TYPE_RECT2, TYPE_RECT2I:
			var pos
			var size
			if value is Array and value.size() >= 4:
				pos = [value[0], value[1]]; size = [value[2], value[3]]
			elif value is Dictionary:
				pos = value.get("position", [value.get("x", 0), value.get("y", 0)])
				size = value.get("size", [value.get("w", value.get("width", 0)), value.get("h", value.get("height", 0))])
			else:
				return null
			if t == TYPE_RECT2:
				return Rect2(to_vector(pos, TYPE_VECTOR2), to_vector(size, TYPE_VECTOR2))
			return Rect2i(to_vector(pos, TYPE_VECTOR2I), to_vector(size, TYPE_VECTOR2I))
		TYPE_TRANSFORM2D:
			if value is Dictionary:
				var tr := Transform2D(deg_to_rad(float(value.get("rotation_degrees", 0))) if value.has("rotation_degrees") else float(value.get("rotation", 0)), to_vector(value.get("scale", [1, 1]), TYPE_VECTOR2), 0.0, to_vector(value.get("origin", value.get("position", [0, 0])), TYPE_VECTOR2))
				return tr
		TYPE_TRANSFORM3D:
			if value is Dictionary:
				var basis := Basis.IDENTITY
				if value.has("rotation_degrees"):
					var r: Vector3 = to_vector(value.rotation_degrees, TYPE_VECTOR3)
					basis = Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
				elif value.has("rotation"):
					basis = Basis.from_euler(to_vector(value.rotation, TYPE_VECTOR3))
				if value.has("scale"):
					basis = basis.scaled(to_vector(value.scale, TYPE_VECTOR3))
				return Transform3D(basis, to_vector(value.get("origin", value.get("position", [0, 0, 0])), TYPE_VECTOR3))
		TYPE_BASIS:
			if value is Dictionary and value.has("rotation_degrees"):
				var r2: Vector3 = to_vector(value.rotation_degrees, TYPE_VECTOR3)
				return Basis.from_euler(Vector3(deg_to_rad(r2.x), deg_to_rad(r2.y), deg_to_rad(r2.z)))
		TYPE_QUATERNION:
			if value is Array and value.size() == 4:
				return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
			if value is Array and value.size() == 3:
				return Quaternion.from_euler(Vector3(deg_to_rad(float(value[0])), deg_to_rad(float(value[1])), deg_to_rad(float(value[2]))))
		TYPE_AABB:
			if value is Dictionary:
				return AABB(to_vector(value.get("position", [0, 0, 0]), TYPE_VECTOR3), to_vector(value.get("size", [1, 1, 1]), TYPE_VECTOR3))
			if value is Array and value.size() >= 6:
				return AABB(Vector3(value[0], value[1], value[2]), Vector3(value[3], value[4], value[5]))
		TYPE_PLANE:
			if value is Array and value.size() == 4:
				return Plane(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return err("Cannot convert %s to %s." % [JSON.stringify(value), type_string(t)], "Pass the value as a Godot literal string, e.g. \"%s(...)\"." % type_string(t))


## Loads or builds an Object (normally a Resource) from a JSON description:
##  "res://path.tres" | {"path": "res://..."} | {"type": "RectangleShape2D", "size": [32, 32]}
static func to_object(value, hint_class: String = "") -> Variant:
	if value is Object:
		return value
	if value is String:
		var s: String = value
		if s == "" or s == "null":
			return null
		var rp := res_path(s)
		if ResourceLoader.exists(rp):
			return load(rp)
		if ClassDB.class_exists(s) and ClassDB.can_instantiate(s) and ClassDB.is_parent_class(s, "Resource"):
			return ClassDB.instantiate(s)
		return err("Resource not found: '%s'." % s, "Use a res:// path to an existing resource, or {\"type\": \"ClassName\", ...props} to create one inline.")
	if value is Dictionary:
		var d: Dictionary = value
		if d.has("path") and not d.has("type"):
			return to_object(str(d.path), hint_class)
		var cls := str(d.get("type", d.get("class", hint_class)))
		if cls.contains(","):
			cls = cls.split(",")[0]
		if cls == "" or not ClassDB.class_exists(cls):
			return err("Unknown resource type '%s'." % cls, "Give {\"type\": \"<ResourceClass>\"}. Expected class: %s" % hint_class)
		if not ClassDB.can_instantiate(cls):
			return err("Type '%s' is abstract and cannot be instantiated." % cls, "Pick a concrete subclass of %s." % cls)
		var obj: Object = ClassDB.instantiate(cls)
		var res = apply_props(obj, d, ["type", "class", "path"])
		if is_err(res):
			return res
		return obj
	return err("Cannot convert %s to an object." % JSON.stringify(value))


## Sets several properties on an object, coercing each value to the property type.
## Returns an error dict or null.
static func apply_props(obj: Object, props: Dictionary, skip: Array = []):
	var infos := prop_infos(obj)
	for key in props:
		if key in skip:
			continue
		var r = set_prop(obj, key, props[key], infos)
		if is_err(r):
			return r
	return null


static func prop_infos(obj: Object) -> Dictionary:
	var infos := {}
	for pi in obj.get_property_list():
		if pi.usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		infos[pi.name] = pi
	return infos


## Sets one property with coercion. Supports "a:b" sub-property paths (e.g. "position:x").
static func set_prop(obj: Object, key: String, value, infos: Dictionary = {}):
	if infos.is_empty():
		infos = prop_infos(obj)
	var base_key := key.split(":")[0]
	if not infos.has(base_key):
		var suggestion := suggest(base_key, infos.keys())
		var hint := "Did you mean '%s'?" % suggestion if suggestion != "" else "Use introspect.class to list properties of %s." % obj.get_class()
		return err("Property '%s' not found on %s." % [base_key, obj.get_class()], hint)
	var pi: Dictionary = infos[base_key]
	var v
	if key.contains(":"):
		v = _auto(value) if not (value is float) else value
		obj.set_indexed(NodePath(key), v)
		return null
	v = coerce(value, pi.type, pi.hint, pi.hint_string)
	if is_err(v):
		return v
	if pi.type == TYPE_OBJECT and v != null and pi.hint == PROPERTY_HINT_RESOURCE_TYPE and pi.hint_string != "":
		var ok := false
		for allowed in pi.hint_string.split(","):
			if v.is_class(allowed) or (v.get_script() and v.get_script().get_global_name() == allowed):
				ok = true
		if not ok:
			return err("Property '%s' expects %s but got %s." % [key, pi.hint_string, v.get_class()])
	obj.set(key, v)
	return null


static func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


## Matches enum labels loosely: "Word (Smart)" == "word_smart", "Group With Children" ==
## "SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN" (constant names with a class prefix).
static func _enum_value(name: String, hint_string: String, _flags: bool):
	var n := _norm(name)
	if n == "":
		return null
	var idx := 0
	var labels := {}
	for part in hint_string.split(","):
		var kv := part.split(":")
		var val := int(kv[1]) if kv.size() > 1 else idx
		labels[_norm(kv[0])] = val
		idx += 1
	if labels.has(n):
		return labels[n]
	var best = null
	var best_len := 0
	for lab in labels:
		if lab == "":
			continue
		var singular: String = lab.trim_suffix("s")
		if (n.ends_with(lab) or n.ends_with(singular) or n.replace("s", "").ends_with(lab.replace("s", ""))) and lab.length() > best_len:
			best = labels[lab]
			best_len = lab.length()
	if best != null:
		return best
	for lab in labels:
		if lab.similarity(n) > 0.8:
			return labels[lab]
	return null


static func _enum_hint(hint: int, hint_string: String) -> String:
	if hint == PROPERTY_HINT_ENUM or hint == PROPERTY_HINT_FLAGS:
		return "Valid values: %s" % hint_string
	return ""


## Closest string by similarity (for "did you mean" hints).
static func _levenshtein(a: String, b: String) -> int:
	var prev := []
	for j in b.length() + 1:
		prev.append(j)
	for i in range(1, a.length() + 1):
		var cur := [i]
		for j in range(1, b.length() + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			cur.append(mini(mini(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost))
		prev = cur
	return prev[b.length()]


static func suggest(word: String, candidates: Array) -> String:
	var s := _suggest_similar(word, candidates)
	if s != "":
		return s
	# Fall back to edit distance for short typos ("speeed" -> "speed").
	var best := ""
	var best_d := 3 if word.length() > 4 else 2
	var lw := word.to_lower()
	for c in candidates:
		var cs := str(c).to_lower()
		if absi(cs.length() - lw.length()) >= best_d:
			continue
		var d := _levenshtein(lw, cs)
		if d < best_d:
			best_d = d
			best = str(c)
	return best


static func _suggest_similar(word: String, candidates: Array) -> String:
	var best := ""
	var best_score := 0.45
	var lw := word.to_lower()
	for c in candidates:
		var s := str(c)
		var score := lw.similarity(s.to_lower())
		if s.to_lower().contains(lw) or lw.contains(s.to_lower()):
			score += 0.25
		if score > best_score:
			best_score = score
			best = s
	return best


# ---------------------------------------------------------------------------
# Property listing
# ---------------------------------------------------------------------------

static func describe_property(pi: Dictionary) -> Dictionary:
	var d := {"name": pi.name, "type": type_string(pi.type) if pi.type != TYPE_OBJECT else (pi.hint_string if pi.hint_string != "" else pi.class_name if pi.class_name != "" else "Object")}
	if pi.hint == PROPERTY_HINT_ENUM:
		d["enum"] = pi.hint_string
	elif pi.hint == PROPERTY_HINT_FLAGS or pi.hint in [PROPERTY_HINT_LAYERS_2D_PHYSICS, PROPERTY_HINT_LAYERS_3D_PHYSICS, PROPERTY_HINT_LAYERS_2D_RENDER, PROPERTY_HINT_LAYERS_3D_RENDER]:
		d["flags"] = pi.hint_string if pi.hint_string != "" else "layers"
	elif pi.hint == PROPERTY_HINT_RANGE:
		d["range"] = pi.hint_string
	elif pi.type == TYPE_INT and pi.class_name != "":
		d["enum"] = pi.class_name
	return d


## Properties of an object that differ from class defaults (what you'd see bold in the inspector).
static func changed_props(obj: Object, include_all: bool = false) -> Dictionary:
	var out := {}
	var cls := obj.get_class()
	for pi in obj.get_property_list():
		if not (pi.usage & PROPERTY_USAGE_EDITOR):
			continue
		if pi.usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		var pname: String = pi.name
		if pname == "script" or pname.begins_with("metadata/"):
			continue
		var val = obj.get(pname)
		if not include_all:
			var def = ClassDB.class_get_property_default_value(cls, pname)
			if def == null and val == null:
				continue
			if def != null and typeof(def) == typeof(val) and def == val:
				continue
			if def == null and (pi.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 and not ClassDB.class_has_method(cls, "get_" + pname) and not (val is Object):
				pass
		out[pname] = encode(val)
	return out


# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

## Encodes an image as base64 PNG (or JPG), scaled so the longest side is <= max_size.
static func image_to_b64(img: Image, max_size: int = 1280, fmt: String = "png") -> Dictionary:
	if img == null or img.is_empty():
		return err("Empty image.")
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var longest := maxi(w, h)
	if max_size > 0 and longest > max_size:
		var s := float(max_size) / float(longest)
		img.resize(maxi(1, int(w * s)), maxi(1, int(h * s)), Image.INTERPOLATE_BILINEAR)
	var buf: PackedByteArray
	var mime := "image/png"
	if fmt == "jpg" or fmt == "jpeg":
		buf = img.save_jpg_to_buffer(0.85)
		mime = "image/jpeg"
	else:
		if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGBA8)
		buf = img.save_png_to_buffer()
	return {"__image": true, "mime": mime, "data": Marshalls.raw_to_base64(buf), "width": img.get_width(), "height": img.get_height(), "original_width": w, "original_height": h}


# ---------------------------------------------------------------------------
# Snippets
# ---------------------------------------------------------------------------

## Wraps a runtime snippet into a script with `func run(tree: SceneTree, scene: Node)`.
static func game_snippet_source(code: String) -> String:
	if not code.contains("func run"):
		var body := ""
		for line in code.split("\n"):
			body += "\t" + line + "\n"
		return "extends RefCounted\n\nfunc run(tree: SceneTree, scene: Node):\n" + body + "\treturn null\n"
	if not code.begins_with("extends"):
		return "extends RefCounted\n" + code
	return code


# ---------------------------------------------------------------------------
# Node trees
# ---------------------------------------------------------------------------

## Serialises a node subtree. opts: depth (int), props (bool: include changed properties),
## filter_type (String), include_internal (bool), max_nodes (int).
static func node_tree(n: Node, root: Node, opts: Dictionary, state: Dictionary = {}) -> Dictionary:
	if not state.has("count"):
		state["count"] = 0
	state.count += 1
	var d := {"name": str(n.name), "type": n.get_class()}
	if n != root:
		d["path"] = str(root.get_path_to(n))
	var scr: Script = n.get_script()
	if scr:
		d["script"] = scr.resource_path
		var gname := scr.get_global_name()
		if gname != "":
			d["class_name"] = str(gname)
	if n.scene_file_path != "" and n != root:
		d["instance"] = n.scene_file_path
	var groups := []
	for g in n.get_groups():
		if not str(g).begins_with("_"):
			groups.append(str(g))
	if not groups.is_empty():
		d["groups"] = groups
	if n is Node2D:
		d["position"] = var_to_str(n.position)
	elif n is Node3D:
		d["position"] = var_to_str(n.position)
	elif n is Control:
		d["rect"] = var_to_str(Rect2(n.position, n.size))
	if n is CanvasItem and not n.visible:
		d["visible"] = false
	if opts.get("props", false):
		d["props"] = changed_props(n)
	var depth: int = opts.get("depth", 99)
	var max_nodes: int = opts.get("max_nodes", 500)
	var children := n.get_children(opts.get("include_internal", false))
	if opts.get("owned_only", false):
		# Hide editor-internal helpers (e.g. dummy players created while editing an AnimationTree).
		children = children.filter(func(c): return c.owner != null or c.scene_file_path != "")
	# Don't descend into instanced sub-scenes unless asked; they are summarised by "instance".
	var descend: bool = depth > 0 and (n == root or n.scene_file_path == "" or opts.get("expand_instances", false))
	if not children.is_empty():
		if descend and state.count < max_nodes:
			var arr := []
			for c in children:
				if state.count >= max_nodes:
					arr.append({"truncated": "%d more children" % (children.size() - arr.size())})
					break
				var sub_opts := opts.duplicate()
				sub_opts["depth"] = depth - 1
				arr.append(node_tree(c, root, sub_opts, state))
			d["children"] = arr
		else:
			d["child_count"] = children.size()
	return d


## Screen/viewport position of a CanvasItem or Node3D (for clicking and annotation).
static func screen_pos(n: Node) -> Variant:
	if n is Control:
		var c: Control = n
		var xf := c.get_global_transform_with_canvas()
		return xf * (c.size / 2.0)
	if n is Node2D:
		return (n as Node2D).get_global_transform_with_canvas().origin
	if n is Node3D:
		var cam := n.get_viewport().get_camera_3d()
		if cam and not cam.is_position_behind((n as Node3D).global_position):
			return cam.unproject_position((n as Node3D).global_position)
	return null
