@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Animation: AnimationPlayer animations (tracks + keys in one call), SpriteFrames for
## AnimatedSprite2D/3D, and AnimationTree state machines / blend spaces / blend trees.

const TRACK_TYPES := {
	"value": Animation.TYPE_VALUE, "property": Animation.TYPE_VALUE,
	"position_3d": Animation.TYPE_POSITION_3D, "rotation_3d": Animation.TYPE_ROTATION_3D, "scale_3d": Animation.TYPE_SCALE_3D,
	"blend_shape": Animation.TYPE_BLEND_SHAPE, "method": Animation.TYPE_METHOD, "call": Animation.TYPE_METHOD,
	"bezier": Animation.TYPE_BEZIER, "audio": Animation.TYPE_AUDIO, "animation": Animation.TYPE_ANIMATION,
}
const TRACK_NAMES := ["value", "position_3d", "rotation_3d", "scale_3d", "blend_shape", "method", "bezier", "audio", "animation"]
const LOOP_NAMES := ["none", "linear", "pingpong"]
const INTERP_NAMES := ["nearest", "linear", "cubic", "linear_angle", "cubic_angle"]
const UPDATE_NAMES := ["continuous", "discrete", "capture"]
const EASINGS := {"linear": 1.0, "ease_in": 2.0, "ease_out": 0.5, "ease_in_out": -2.0, "ease_out_in": -0.5, "in": 2.0, "out": 0.5, "in_out": -2.0, "constant": 0.0, "step": 0.0}
const SWITCH_MODES := {"immediate": 0, "sync": 1, "at_end": 2}
const TREE_NODE_TYPES := {
	"animation": "AnimationNodeAnimation", "blend2": "AnimationNodeBlend2", "blend3": "AnimationNodeBlend3",
	"add2": "AnimationNodeAdd2", "add3": "AnimationNodeAdd3", "sub2": "AnimationNodeSub2",
	"one_shot": "AnimationNodeOneShot", "time_scale": "AnimationNodeTimeScale", "time_seek": "AnimationNodeTimeSeek",
	"transition": "AnimationNodeTransition", "state_machine": "AnimationNodeStateMachine",
	"blend_space_1d": "AnimationNodeBlendSpace1D", "blend_space_2d": "AnimationNodeBlendSpace2D", "blend_tree": "AnimationNodeBlendTree",
}


# ---------------------------------------------------------------------------
# Lookup helpers
# ---------------------------------------------------------------------------

func _all_of(root: Node, cls: String) -> Array:
	var out := []
	if root.is_class(cls):
		out.append(root)
	out.append_array(root.find_children("*", cls, true, true))
	return out


## Resolves the AnimationPlayer from p.path (a player, an AnimationTree using one, or a node with
## one player child). Without path: the only AnimationPlayer in the scene.
func _player(p: Dictionary):
	if p.has("scene") and str(p.scene) != "":
		var r = await ensure_scene(str(p.scene))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var path := U.p_str(p, "path", "")
	if path != "":
		var n: Node = ctx.find_node(path)
		if n == null:
			return ctx.node_not_found(path)
		if n is AnimationPlayer:
			return n
		if n is AnimationTree and str(n.anim_player) != "":
			var ap = n.get_node_or_null(n.anim_player)
			if ap is AnimationPlayer:
				return ap
		var kids := n.find_children("*", "AnimationPlayer", false, true)
		if kids.size() == 1:
			return kids[0]
		return U.err("'%s' is a %s, not an AnimationPlayer." % [path, n.get_class()], "Pass the AnimationPlayer's path. Players in this scene: %s" % _names(_all_of(root, "AnimationPlayer")))
	var all := _all_of(root, "AnimationPlayer")
	if all.size() == 1:
		return all[0]
	if all.is_empty():
		return U.err("There is no AnimationPlayer in this scene.", "Create one with animation.create (it adds an AnimationPlayer when 'path' doesn't exist).")
	return U.err("The scene has %d AnimationPlayers; say which one with 'path'." % all.size(), "Players: %s" % _names(all))


func _names(nodes: Array) -> String:
	var out := []
	for n in nodes:
		out.append(ctx.node_path_str(n))
	return ", ".join(out) if not out.is_empty() else "(none)"


## [library, animation] from p.name ("walk" or "lib/walk") and p.library.
func _split_name(p: Dictionary, key: String = "name") -> Array:
	var name := U.p_str(p, key, "")
	var lib := U.p_str(p, "library", "")
	if name.contains("/") and not p.has("library"):
		lib = name.get_slice("/", 0)
		name = name.substr(lib.length() + 1)
	return [lib, name]


func _full(lib: String, anim: String) -> String:
	return anim if lib == "" else "%s/%s" % [lib, anim]


func _get_anim(player: AnimationPlayer, p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var parts := _split_name(p)
	var full := _full(parts[0], parts[1])
	if not player.has_animation(full):
		var names := Array(player.get_animation_list())
		var s := U.suggest(full, names)
		return U.err("Animation '%s' not found on '%s'." % [full, ctx.node_path_str(player)], ("Did you mean '%s'? " % s if s != "" else "") + "Animations: %s" % (", ".join(names) if not names.is_empty() else "(none; create one with animation.create)"))
	return {"lib": parts[0], "name": parts[1], "full": full, "anim": player.get_animation(full), "library": player.get_animation_library(parts[0])}


## Imported libraries (from .glb/.fbx...) are read-only; .tres libraries are saved after edits.
func _lib_writable(lib: AnimationLibrary, lib_name: String):
	var rp := lib.resource_path
	if rp != "" and not rp.contains("::") and not (rp.get_extension() in ["tres", "res"]):
		return U.err("Animation library '%s' comes from the imported file '%s' and is read-only." % [lib_name, rp], "Put new animations in another library (library='custom'), or make the imported scene local / extract its animations in the import settings.")
	return null


func _is_external(lib: AnimationLibrary) -> bool:
	var rp := lib.resource_path
	return rp != "" and not rp.contains("::") and rp.get_extension() in ["tres", "res"]


func _persist(lib: AnimationLibrary) -> void:
	if _is_external(lib):
		var rp := lib.resource_path
		ctx.before_write([rp])
		ResourceSaver.save(lib, rp)
		ctx.fs().update_file(rp)


## Registers re-saving an external .tres library on undo/redo, so the file follows Ctrl+Z.
func _persist_ops(u, lib: AnimationLibrary) -> void:
	if _is_external(lib):
		u.add_do_method(self, "_save_lib_deferred", lib)
		u.add_undo_method(self, "_save_lib_deferred", lib)


func _save_lib_deferred(lib: AnimationLibrary) -> void:
	# Deferred: runs after every do/undo operation of the action has been applied.
	_save_lib_now.call_deferred(lib)


func _save_lib_now(lib: AnimationLibrary) -> void:
	if _is_external(lib):
		ResourceSaver.save(lib, lib.resource_path)
		ctx.fs().update_file(lib.resource_path)


## Replaces (or adds) an animation in a library as one undoable action (plus missing RESET tracks when reset_anims is given).
func _swap_anim(player: AnimationPlayer, lib_name: String, anim_name: String, new_anim: Animation, action: String, reset_anims: Array = []) -> int:
	var lib: AnimationLibrary = player.get_animation_library(lib_name)
	var old: Animation = lib.get_animation(anim_name) if lib.has_animation(anim_name) else null
	var u = ctx.begin(action)
	u.add_do_method(lib, "add_animation", anim_name, new_anim)
	if old:
		u.add_undo_method(lib, "add_animation", anim_name, old)
	else:
		u.add_undo_method(lib, "remove_animation", anim_name)
	u.add_do_reference(new_anim)
	_persist_ops(u, lib)
	var added := 0
	if not reset_anims.is_empty():
		added = _reset_ops(u, player, reset_anims, _anim_root(player))
	ctx.commit()
	_persist(lib)
	if added > 0 and player.has_animation_library(""):
		_persist(player.get_animation_library(""))
	return added


## A RESET animation for the default library: the existing RESET plus a key with the current value for every
## value/bezier/3D-transform track of `anims` that RESET doesn't cover yet. null when nothing is missing.
## (The editor applies RESET before saving, so previewing animations / an active AnimationTree can't leak into the scene.)
func _build_reset(rlib: AnimationLibrary, anims: Array, aroot: Node) -> Animation:
	if aroot == null:
		return null
	var has_old := rlib != null and rlib.has_animation("RESET")
	var ra: Animation = rlib.get_animation("RESET").duplicate(true) if has_old else Animation.new()
	if not has_old:
		ra.length = 0.001
	var added := 0
	for anim: Animation in anims:
		if anim == null or anim.resource_name == "RESET":
			continue
		for i in anim.get_track_count():
			var tt := anim.track_get_type(i)
			if not (tt in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER, Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]):
				continue
			var tp := anim.track_get_path(i)
			if ra.find_track(tp, tt) >= 0:
				continue
			var nm := str(tp.get_concatenated_names())
			var tn: Node = aroot if nm in ["", "."] else aroot.get_node_or_null(NodePath(nm))
			if tn == null:
				continue
			var subs := str(tp.get_concatenated_subnames())
			var cur = tn.get_indexed(NodePath(subs)) if subs != "" else null
			if tt in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER] and cur == null:
				continue
			if tt == Animation.TYPE_BEZIER and not (cur is float or cur is int):
				continue
			if tt in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] and not (tn is Node3D):
				continue
			var ri := ra.add_track(tt)
			ra.track_set_path(ri, tp)
			match tt:
				Animation.TYPE_VALUE:
					ra.value_track_set_update_mode(ri, anim.value_track_get_update_mode(i))
					ra.track_insert_key(ri, 0.0, cur)
				Animation.TYPE_BEZIER:
					ra.bezier_track_insert_key(ri, 0.0, float(cur))
				Animation.TYPE_POSITION_3D:
					ra.position_track_insert_key(ri, 0.0, (tn as Node3D).position)
				Animation.TYPE_ROTATION_3D:
					ra.rotation_track_insert_key(ri, 0.0, (tn as Node3D).quaternion)
				Animation.TYPE_SCALE_3D:
					ra.scale_track_insert_key(ri, 0.0, (tn as Node3D).scale)
			added += 1
	return ra if added > 0 else null


## Adds undoable ops that put missing RESET tracks for `anims` into the player's default ("") library
## (creating it if needed; `default_lib` = a default library that is being added in the same action). Returns tracks added.
func _reset_ops(u, player: AnimationPlayer, anims: Array, aroot: Node, default_lib: AnimationLibrary = null) -> int:
	var rlib: AnimationLibrary = default_lib
	if rlib == null and player.has_animation_library(""):
		rlib = player.get_animation_library("")
	if rlib and _lib_writable(rlib, "") != null:
		return 0
	var ra := _build_reset(rlib, anims, aroot)
	if ra == null:
		return 0
	var before := rlib.get_animation("RESET").get_track_count() if rlib and rlib.has_animation("RESET") else 0
	if rlib == null:
		rlib = AnimationLibrary.new()
		rlib.add_animation("RESET", ra)
		u.add_do_method(player, "add_animation_library", "", rlib)
		u.add_undo_method(player, "remove_animation_library", "")
		u.add_do_reference(rlib)
	else:
		var old: Animation = rlib.get_animation("RESET") if rlib.has_animation("RESET") else null
		u.add_do_method(rlib, "add_animation", "RESET", ra)
		if old:
			u.add_undo_method(rlib, "add_animation", "RESET", old)
		else:
			u.add_undo_method(rlib, "remove_animation", "RESET")
		u.add_do_reference(ra)
		if _is_external(rlib):
			ctx.before_write([rlib.resource_path])
		_persist_ops(u, rlib)
	return ra.get_track_count() - before


func _anim_root(player: AnimationPlayer) -> Node:
	if player.is_inside_tree():
		return player.get_node_or_null(player.root_node)
	return null


# ---------------------------------------------------------------------------
# Value parsing
# ---------------------------------------------------------------------------

func _loop_mode(v) -> int:
	if v == null:
		return -1
	if v is bool:
		return Animation.LOOP_LINEAR if v else Animation.LOOP_NONE
	if v is float or v is int:
		return clampi(int(v), 0, 2)
	var s := str(v).to_lower().replace("-", "_").replace(" ", "_")
	match s:
		"none", "false", "off", "no", "once":
			return Animation.LOOP_NONE
		"linear", "loop", "true", "on", "yes", "repeat":
			return Animation.LOOP_LINEAR
		"pingpong", "ping_pong":
			return Animation.LOOP_PINGPONG
	return -2


## Key transition (Godot ease curve) from 'easing' / 'transition': a name or a number. Returns float or error.
func _transition(k: Dictionary):
	for key in ["easing", "transition"]:
		if not k.has(key) or k[key] == null:
			continue
		var t = k[key]
		if t is float or t is int:
			return float(t)
		var s := str(t).strip_edges().to_lower().replace("-", "_").replace(" ", "_")
		if EASINGS.has(s):
			return EASINGS[s]
		if s.is_valid_float():
			return s.to_float()
		return U.err("Unknown %s '%s'." % [key, t], "Use linear, ease_in, ease_out, ease_in_out, ease_out_in, constant, or a number (Godot ease curve: 1 = linear, >1 = ease in, 0..1 = ease out, <0 = ease in-out, 0 = constant/no interpolation).")
	return 1.0


func _key_time(k: Dictionary):
	var t = k.get("time", 0.0)
	if t is String and t.strip_edges().is_valid_float():
		t = t.to_float()
	if not (t is float or t is int):
		return U.err("Key time must be a number of seconds, got %s." % JSON.stringify(t), "Keys look like {\"time\": 0.5, \"value\": ...}.")
	if float(t) < 0:
		return U.err("Key time must be >= 0 (got %s)." % t)
	return float(t)


const VEC_TYPES := [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I]


## True if `v` can be read as a vector: [x, y(, z)], {x, y}, "Vector2(1, 2)", "1, 2" (or a number when allow_scalar).
func _vec_like(v, allow_scalar: bool = false) -> bool:
	if typeof(v) in VEC_TYPES:
		return true
	if v is float or v is int:
		return allow_scalar
	if v is Array:
		return v.size() >= 2 and v.all(func(x): return x is float or x is int or (x is String and x.is_valid_float()))
	if v is Dictionary:
		return v.has("x") and v.has("y")
	if v is String:
		if typeof(str_to_var(v)) in VEC_TYPES:
			return true
		var n := 0
		for part in v.replace("(", " ").replace(")", " ").replace(",", " ").split(" ", false):
			if part.is_valid_float():
				n += 1
			elif not part.begins_with("Vector"):
				return false
		return n >= 2 or (allow_scalar and n == 1)
	return false


func _vec_or_err(v, t: int, what: String, allow_scalar: bool = false):
	if not _vec_like(v, allow_scalar):
		return U.err("Cannot read %s from %s." % [what, JSON.stringify(v)], "Use [x, y%s]%s." % [", z" if t in [TYPE_VECTOR3, TYPE_VECTOR3I] else "", " or one number for a uniform value" if allow_scalar else ""])
	return U.to_vector(v, t)


func _color_like(v) -> bool:
	if v is Color or v is Array or v is Dictionary:
		return true
	if v is String:
		var s: String = v.strip_edges()
		return s.begins_with("Color(") or Color.html_is_valid(s) or Color.from_string(s, Color(0, 0, 0, 0.123)) != Color(0, 0, 0, 0.123)
	return false


func _to_quat(v) -> Variant:
	if v is Quaternion:
		return v
	if v is String:
		var parsed = str_to_var(v)
		if parsed is Quaternion:
			return parsed
		if parsed is Vector3:
			return Quaternion.from_euler(Vector3(deg_to_rad(parsed.x), deg_to_rad(parsed.y), deg_to_rad(parsed.z)))
	if v is Array and v.size() == 4:
		return Quaternion(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	if v is Array and v.size() == 3:
		return Quaternion.from_euler(Vector3(deg_to_rad(float(v[0])), deg_to_rad(float(v[1])), deg_to_rad(float(v[2]))))
	if v is Dictionary and v.has("x"):
		return Quaternion.from_euler(Vector3(deg_to_rad(float(v.get("x", 0))), deg_to_rad(float(v.get("y", 0))), deg_to_rad(float(v.get("z", 0)))))
	return U.err("Cannot read rotation %s." % JSON.stringify(v), "rotation_3d keys take euler degrees [x, y, z] or a quaternion [x, y, z, w].")


## Value for a property whose type is unknown (node not created yet): number lists become vectors.
func _guess(v) -> Variant:
	if v is Array and v.size() in [2, 3] and v.all(func(x): return x is float or x is int):
		return Vector2(v[0], v[1]) if v.size() == 2 else Vector3(v[0], v[1], v[2])
	return U._auto(v)


func _enum_pick(v, names: Array, what: String):
	if v is float or v is int:
		return int(v)
	var s := str(v).to_lower().replace(" ", "_")
	var i := names.find(s)
	if i < 0:
		return U.err("Unknown %s '%s'." % [what, v], "Valid: %s" % ", ".join(names))
	return i


# ---------------------------------------------------------------------------
# Tracks
# ---------------------------------------------------------------------------

## Checks a track path against the animation root. Returns info {node, vtype, hint, hint_string} or error.
func _resolve_target(aroot: Node, tpath: String, ttype: int, validate: bool, warnings: Array):
	var info := {"node": null, "vtype": TYPE_NIL, "hint": PROPERTY_HINT_NONE, "hint_string": "", "known": false}
	var np := NodePath(tpath)
	var names := str(np.get_concatenated_names())
	var subs := str(np.get_concatenated_subnames())
	if ttype in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER, Animation.TYPE_BLEND_SHAPE] and subs == "":
		return U.err("Track path '%s' needs a property after ':'." % tpath, "e.g. 'Sprite2D:modulate', 'Sprite2D:position:y' or '.:visible' for the root node itself.")
	if ttype in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO, Animation.TYPE_ANIMATION] and subs != "":
		return U.err("%s track paths point at a node, without ':property' (got '%s')." % [TRACK_NAMES[ttype], tpath], "Use e.g. 'Player' for a method track, 'SFX' (an AudioStreamPlayer) for an audio track.")
	if aroot == null:
		return info
	var n: Node = aroot.get_node_or_null(NodePath(names)) if names != "" and names != "." else aroot
	if n == null:
		if not validate:
			warnings.append("Track '%s': node '%s' doesn't exist yet." % [tpath, names])
			return info
		var cands := []
		for c in aroot.find_children("*", "", true, true):
			cands.append(str(aroot.get_path_to(c)))
		var s := U.suggest(names, cands)
		var in_scene: Node = ctx.find_node(names)
		if in_scene:
			# The node exists but relative to the scene root, not the animation root.
			s = str(aroot.get_path_to(in_scene)) + (":" + subs if subs != "" else "")
		return U.err("Track path '%s': node '%s' not found under the animation root '%s'." % [tpath, names, ctx.node_path_str(aroot)], ("Did you mean '%s'? " % s if s != "" else "") + "Track paths are relative to the AnimationPlayer's root_node (default: the player's parent). Pass validate=false to animate nodes you'll add later.")
	info.node = n
	match ttype:
		Animation.TYPE_VALUE, Animation.TYPE_BEZIER:
			var base := subs.split(":")[0]
			var infos := U.prop_infos(n)
			if not infos.has(base) and n.has_method(base):
				return U.err("Track path '%s': '%s' is a method of %s, not a property." % [tpath, base, n.get_class()], "Call it from a method track: {\"type\": \"method\", \"path\": \"%s\", \"keys\": [{\"time\": 0, \"method\": \"%s\", \"args\": []}]}." % [names if names != "" else ".", base])
			if subs.contains(":") and infos.has(base) and n.get_indexed(NodePath(subs)) == null:
				var bv = n.get(base)
				var comps := "x, y" + (", z" if typeof(bv) in [TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4] else "") + (", w" if typeof(bv) == TYPE_VECTOR4 else "")
				return U.err("Track path '%s': '%s' has no part '%s'." % [tpath, base, subs.substr(base.length() + 1)], ("%s is %s; its parts are %s." % [base, type_string(typeof(bv)), comps]) if typeof(bv) in VEC_TYPES else ("Colors have r, g, b, a." if bv is Color else "Animate '%s' itself instead." % base))
			if not infos.has(base):
				var cur0 = n.get_indexed(NodePath(subs))
				if cur0 == null:
					if not validate:
						warnings.append("Track '%s': %s has no property '%s'." % [tpath, n.get_class(), base])
						return info
					var s2 := U.suggest(base, infos.keys())
					return U.err("Track path '%s': %s has no property '%s'." % [tpath, n.get_class(), base], ("Did you mean '%s'? " % s2 if s2 != "" else "") + "Use introspect.class '%s' to list properties." % n.get_class())
				info.vtype = typeof(cur0)
			elif subs.contains(":"):
				info.vtype = typeof(n.get_indexed(NodePath(subs)))
			else:
				var pi: Dictionary = infos[base]
				info.vtype = pi.type
				info.hint = pi.hint
				info.hint_string = pi.hint_string
				if info.vtype == TYPE_NIL:
					info.vtype = typeof(n.get(base))
			info.known = true
			if ttype == Animation.TYPE_BEZIER and not (info.vtype in [TYPE_FLOAT, TYPE_INT]):
				return U.err("Bezier tracks animate a single number, but '%s' is %s." % [subs, type_string(info.vtype)], "Point at one component, e.g. 'Sprite2D:position:y', or use a value track.")
		Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D:
			if not (n is Node3D):
				return U.err("%s tracks need a Node3D, but '%s' is %s." % [TRACK_NAMES[ttype], names, n.get_class()], "For 2D use a value track on 'position' / 'rotation' / 'scale'.")
		Animation.TYPE_BLEND_SHAPE:
			if not (n is MeshInstance3D):
				return U.err("Blend shape tracks need a MeshInstance3D, got %s." % n.get_class())
		Animation.TYPE_AUDIO:
			if not (n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D):
				warnings.append("Audio track '%s' should point at an AudioStreamPlayer(2D/3D), got %s." % [tpath, n.get_class()])
		Animation.TYPE_ANIMATION:
			if not (n is AnimationPlayer):
				return U.err("Animation tracks must point at another AnimationPlayer, got %s." % n.get_class())
	return info


## Adds one track from a spec {type, path, keys, interpolation?, update?, loop_wrap?, enabled?}. Returns index or error.
func _add_track(anim: Animation, spec, aroot: Node, validate: bool, warnings: Array):
	if not (spec is Dictionary):
		return U.err("Each track must be an object {type, path, keys}.")
	var tname := U.p_str(spec, "type", "value").to_lower()
	if tname in ["position", "rotation", "scale"]:
		tname += "_3d"
	if not TRACK_TYPES.has(tname):
		var s := U.suggest(tname, TRACK_TYPES.keys())
		return U.err("Unknown track type '%s'." % tname, ("Did you mean '%s'? " % s if s != "" else "") + "Valid: value, method, bezier, audio, animation, position_3d, rotation_3d, scale_3d, blend_shape. For 2D position/rotation use a value track like 'Sprite2D:position'.")
	var ttype: int = TRACK_TYPES[tname]
	var tpath := U.p_str(spec, "path", "")
	if tpath == "":
		return U.err("A %s track is missing 'path'." % tname, "e.g. 'Sprite2D:modulate' (node path relative to the AnimationPlayer's root node, then ':property').")
	var target = _resolve_target(aroot, tpath, ttype, validate, warnings)
	if U.is_err(target): return target
	var idx := anim.add_track(ttype)
	anim.track_set_path(idx, NodePath(tpath))
	if ttype == Animation.TYPE_VALUE:
		var um := Animation.UPDATE_CONTINUOUS
		if target.known and target.vtype in [TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH, TYPE_OBJECT]:
			um = Animation.UPDATE_DISCRETE
		if spec.has("update"):
			var uv = _enum_pick(spec.update, UPDATE_NAMES, "update mode")
			if U.is_err(uv):
				anim.remove_track(idx)
				return uv
			um = uv
		anim.value_track_set_update_mode(idx, um)
	if spec.has("interpolation"):
		var iv = _enum_pick(spec.interpolation, INTERP_NAMES, "interpolation")
		if U.is_err(iv):
			anim.remove_track(idx)
			return iv
		anim.track_set_interpolation_type(idx, iv)
	if spec.has("loop_wrap"):
		anim.track_set_interpolation_loop_wrap(idx, U.p_bool(spec, "loop_wrap", true))
	if spec.has("enabled"):
		anim.track_set_enabled(idx, U.p_bool(spec, "enabled", true))
	var r = _insert_keys(anim, idx, U.p_arr(spec, "keys"), target, warnings)
	if U.is_err(r):
		anim.remove_track(idx)
		r["message"] = "Track '%s': %s" % [tpath, r.message]
		return r
	return idx


func _insert_keys(anim: Animation, idx: int, keys: Array, target: Dictionary, warnings: Array):
	var ttype := anim.track_get_type(idx)
	for k in keys:
		if not (k is Dictionary):
			return U.err("Each key must be an object like {\"time\": 0.5, \"value\": ...}, got %s." % JSON.stringify(k))
		var t = _key_time(k)
		if U.is_err(t): return t
		var tr = _transition(k)
		if U.is_err(tr): return tr
		var ki := -1
		if ttype in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER, Animation.TYPE_BLEND_SHAPE, Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_ROTATION_3D] and not k.has("value"):
			return U.err("Key at %ss has no 'value'." % t, "Keys look like {\"time\": 0.5, \"value\": ..., \"easing\"?: \"ease_in_out\"}.")
		match ttype:
			Animation.TYPE_VALUE:
				var v = null
				if target.known:
					if target.vtype in VEC_TYPES and not _vec_like(k.value):
						return U.err("Key at %ss: expected %s like [x, y%s], got %s." % [t, type_string(target.vtype), ", z" if target.vtype in [TYPE_VECTOR3, TYPE_VECTOR3I] else "", JSON.stringify(k.value)])
					if target.vtype == TYPE_COLOR and not _color_like(k.value):
						return U.err("Key at %ss: expected a color, got %s." % [t, JSON.stringify(k.value)], "Use '#ff8800', '#ff880080' (with alpha), a color name like 'red', or [r, g, b, a].")
					v = U.coerce(k.value, target.vtype, target.hint, target.hint_string)
				else:
					v = _guess(k.value)
				if U.is_err(v): return v
				ki = anim.track_insert_key(idx, t, v, tr)
			Animation.TYPE_BEZIER:
				var bv = k.value
				if bv is String and bv.is_valid_float():
					bv = bv.to_float()
				if not (bv is float or bv is int):
					return U.err("Bezier key at %ss needs a number 'value', got %s." % [t, JSON.stringify(k.value)])
				ki = anim.bezier_track_insert_key(idx, t, float(bv), U.to_vector(k.get("in_handle", [-0.25, 0]), TYPE_VECTOR2), U.to_vector(k.get("out_handle", [0.25, 0]), TYPE_VECTOR2))
			Animation.TYPE_POSITION_3D:
				var pv = _vec_or_err(k.value, TYPE_VECTOR3, "a position")
				if U.is_err(pv): return pv
				ki = anim.position_track_insert_key(idx, t, pv)
			Animation.TYPE_SCALE_3D:
				var sv = _vec_or_err(k.value, TYPE_VECTOR3, "a scale", true)
				if U.is_err(sv): return sv
				ki = anim.scale_track_insert_key(idx, t, sv)
			Animation.TYPE_ROTATION_3D:
				var q = _to_quat(k.value)
				if U.is_err(q): return q
				ki = anim.rotation_track_insert_key(idx, t, q)
			Animation.TYPE_BLEND_SHAPE:
				if not (k.value is float or k.value is int):
					return U.err("Blend shape key at %ss needs a number 'value' (0..1)." % t)
				ki = anim.blend_shape_track_insert_key(idx, t, float(k.value))
			Animation.TYPE_METHOD:
				var m := str(k.get("method", ""))
				if m == "":
					return U.err("Method key at %s needs 'method' (and optional 'args': [...])." % t)
				var args := []
				for a in (k.get("args", []) if k.get("args", []) is Array else [k.args]):
					args.append(U._auto(a))
				ki = anim.track_insert_key(idx, t, {"method": StringName(m), "args": args})
				var node = target.get("node")
				if node is Node and not node.has_method(m):
					warnings.append("Method key '%s' at %ss: %s '%s' has no such method (yet)." % [m, t, node.get_class(), node.name])
			Animation.TYPE_AUDIO:
				var st = U.to_object(k.get("stream", k.get("value", "")), "AudioStream")
				if U.is_err(st): return st
				if not (st is AudioStream):
					return U.err("Audio key at %s needs 'stream': a res:// audio file." % t)
				ki = anim.audio_track_insert_key(idx, t, st, float(k.get("start_offset", 0.0)), float(k.get("end_offset", 0.0)))
			Animation.TYPE_ANIMATION:
				var an := str(k.get("animation", k.get("value", "")))
				if an == "":
					return U.err("Animation key at %s needs 'animation': the name to play ('[stop]' stops)." % t)
				ki = anim.animation_track_insert_key(idx, t, StringName(an))
		if ki >= 0 and ttype != Animation.TYPE_VALUE and (k.has("transition") or k.has("easing")):
			anim.track_set_key_transition(idx, ki, tr)
	return null


func _max_key_time(anim: Animation) -> float:
	var m := 0.0
	for i in anim.get_track_count():
		var c := anim.track_get_key_count(i)
		if c > 0:
			m = maxf(m, anim.track_get_key_time(i, c - 1))
	return m


func _find_track(anim: Animation, p: Dictionary):
	var t = p.get("track", null)
	if t == null:
		return U.err("Missing 'track': a track index or its path (e.g. 'Sprite2D:modulate').")
	if t is float or t is int or (t is String and t.is_valid_int()):
		var i := int(t)
		if i < 0 or i >= anim.get_track_count():
			return U.err("Track index %d out of range (the animation has %d tracks)." % [i, anim.get_track_count()], "Use animation.get to list tracks.")
		return i
	var paths := []
	for i in anim.get_track_count():
		var tp := str(anim.track_get_path(i))
		paths.append(tp)
		if tp == str(t) and (not p.has("type") or TRACK_NAMES[anim.track_get_type(i)] == U.p_str(p, "type")):
			return i
	var s := U.suggest(str(t), paths)
	return U.err("No track with path '%s'." % t, ("Did you mean '%s'? " % s if s != "" else "") + "Tracks: %s" % (", ".join(paths) if not paths.is_empty() else "(none)"))


# ---------------------------------------------------------------------------
# Describing
# ---------------------------------------------------------------------------

func _track_summary(anim: Animation, i: int) -> String:
	return "%s %s (%d keys)" % [TRACK_NAMES[anim.track_get_type(i)], anim.track_get_path(i), anim.track_get_key_count(i)]


func _anim_summary(anim: Animation) -> Dictionary:
	var tracks := []
	for i in anim.get_track_count():
		tracks.append(_track_summary(anim, i))
	return {"length": snappedf(anim.length, 0.0001), "loop": LOOP_NAMES[anim.loop_mode], "tracks": tracks}


func _anim_detail(anim: Animation) -> Dictionary:
	var tracks := []
	for i in anim.get_track_count():
		var ttype := anim.track_get_type(i)
		var tr := {"index": i, "type": TRACK_NAMES[ttype], "path": str(anim.track_get_path(i)), "interpolation": INTERP_NAMES[anim.track_get_interpolation_type(i)]}
		if not anim.track_is_enabled(i):
			tr["enabled"] = false
		if ttype == Animation.TYPE_VALUE:
			tr["update"] = UPDATE_NAMES[anim.value_track_get_update_mode(i)]
		var keys := []
		for k in anim.track_get_key_count(i):
			var kd := {"time": snappedf(anim.track_get_key_time(i, k), 0.0001)}
			match ttype:
				Animation.TYPE_METHOD:
					kd["method"] = str(anim.method_track_get_name(i, k))
					kd["args"] = U.encode(anim.method_track_get_params(i, k))
				Animation.TYPE_BEZIER:
					kd["value"] = anim.bezier_track_get_key_value(i, k)
					kd["in_handle"] = var_to_str(anim.bezier_track_get_key_in_handle(i, k))
					kd["out_handle"] = var_to_str(anim.bezier_track_get_key_out_handle(i, k))
				Animation.TYPE_AUDIO:
					kd["stream"] = U.encode(anim.audio_track_get_key_stream(i, k))
					kd["start_offset"] = anim.audio_track_get_key_start_offset(i, k)
					kd["end_offset"] = anim.audio_track_get_key_end_offset(i, k)
				Animation.TYPE_ANIMATION:
					kd["animation"] = str(anim.animation_track_get_key_animation(i, k))
				Animation.TYPE_ROTATION_3D:
					var q: Quaternion = anim.track_get_key_value(i, k)
					var e := q.get_euler()
					kd["value"] = var_to_str(q)
					kd["euler_degrees"] = var_to_str(Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)).snappedf(0.01))
				_:
					kd["value"] = U.encode(anim.track_get_key_value(i, k))
			var tt := anim.track_get_key_transition(i, k)
			if tt != 1.0:
				kd["transition"] = tt
			keys.append(kd)
		tr["keys"] = keys
		tracks.append(tr)
	return {"length": snappedf(anim.length, 0.0001), "loop": LOOP_NAMES[anim.loop_mode], "step": snappedf(anim.step, 0.0001), "tracks": tracks}


# ---------------------------------------------------------------------------
# AnimationPlayer actions
# ---------------------------------------------------------------------------

## Builds an Animation with tracks and keys in one call; creates the AnimationPlayer if missing.
func a_create(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	if p.has("scene") and str(p.scene) != "":
		var r = await ensure_scene(str(p.scene))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var parts := _split_name(p)
	var lib_name: String = parts[0]
	var anim_name: String = parts[1]
	if anim_name == "" or anim_name.contains(",") or anim_name.contains("[") or anim_name.contains(":"):
		return U.err("Invalid animation name '%s'." % anim_name, "Use a plain name like 'walk'; 'lib/walk' puts it in library 'lib'.")
	# Find or create the player.
	var player: AnimationPlayer = null
	var parent: Node = null
	var path := U.p_str(p, "path", "")
	var existing: Node = ctx.find_node(path) if path != "" else null
	if path != "" and existing == null:
		var ppath := U.p_str(p, "parent", path.get_base_dir() if path.contains("/") else ".")
		parent = ctx.find_node(ppath)
		if parent == null:
			return ctx.node_not_found(ppath)
	elif path != "":
		var pl = await _player(p)
		if U.is_err(pl): return pl
		player = pl
	elif p.has("parent") or p.has("player"):
		parent = ctx.find_node(U.p_str(p, "parent", "."))
		if parent == null:
			return ctx.node_not_found(U.p_str(p, "parent"))
		var want := U.p_str(p, "player", "")
		for c in parent.get_children():
			if c is AnimationPlayer and (want == "" or str(c.name) == want):
				player = c
				break
	else:
		var all := _all_of(root, "AnimationPlayer")
		if all.size() == 1:
			player = all[0]
		elif all.size() > 1:
			return U.err("The scene has %d AnimationPlayers; say which one with 'path'." % all.size(), "Players: %s" % _names(all))
		else:
			parent = root
	var new_player: AnimationPlayer = null
	if player == null:
		new_player = AnimationPlayer.new()
		new_player.name = U.p_str(p, "player", path.get_file() if path != "" else "AnimationPlayer")
		player = new_player
	var aroot: Node = parent if new_player else _anim_root(player)
	var validate := U.p_bool(p, "validate", true)
	var warnings := []
	# Build the animation.
	var anim := Animation.new()
	anim.resource_name = anim_name
	var tracks := U.p_arr(p, "tracks")
	for spec in tracks:
		var r2 = _add_track(anim, spec, aroot, validate, warnings)
		if U.is_err(r2):
			if new_player: new_player.free()
			return r2
	var lm := _loop_mode(p.get("loop", null))
	if lm == -2:
		if new_player: new_player.free()
		return U.err("Unknown loop mode '%s'." % p.loop, "Use none, linear or pingpong (or true/false).")
	if lm >= 0:
		anim.loop_mode = lm
	var max_t := _max_key_time(anim)
	anim.length = U.p_float(p, "length", maxf(max_t, 0.1) if max_t > 0 else 1.0)
	if max_t > anim.length + 0.0001:
		warnings.append("Keys go up to %ss but length is %ss; later keys never play." % [max_t, anim.length])
	if p.has("step"):
		anim.step = U.p_float(p, "step")
	# Library.
	var lib: AnimationLibrary = null
	var new_lib := false
	if player.has_animation_library(lib_name):
		lib = player.get_animation_library(lib_name)
		var we = _lib_writable(lib, lib_name)
		if we:
			if new_player: new_player.free()
			return we
	else:
		lib = AnimationLibrary.new()
		new_lib = true
	var replaced := lib.has_animation(anim_name)
	if replaced and not U.p_bool(p, "overwrite", true):
		if new_player: new_player.free()
		return U.err("Animation '%s' already exists." % _full(lib_name, anim_name), "Pass overwrite=true to replace it, or edit it with animation.add_track / set_keys.")
	var old: Animation = lib.get_animation(anim_name) if replaced else null
	var old_autoplay := str(player.autoplay)
	var full := _full(lib_name, anim_name)
	var u = ctx.begin("Create animation " + full)
	if new_player:
		lib.add_animation(anim_name, anim)
		new_player.add_animation_library(lib_name, lib)
		if U.p_bool(p, "autoplay", false): new_player.autoplay = full
		u.add_do_method(parent, "add_child", new_player, true)
		u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", new_player, root)
		u.add_do_reference(new_player)
		u.add_undo_method(parent, "remove_child", new_player)
	elif new_lib:
		lib.add_animation(anim_name, anim)
		u.add_do_method(player, "add_animation_library", lib_name, lib)
		u.add_undo_method(player, "remove_animation_library", lib_name)
		u.add_do_reference(lib)
	else:
		u.add_do_method(lib, "add_animation", anim_name, anim)
		if old: u.add_undo_method(lib, "add_animation", anim_name, old)
		else: u.add_undo_method(lib, "remove_animation", anim_name)
		u.add_do_reference(anim)
		_persist_ops(u, lib)
	# RESET tracks with the current values (default library), like the editor's "Create RESET Track(s)":
	# AnimationTree blending needs them, and the editor applies RESET on save so previews don't leak into the scene.
	var reset_added := 0
	if U.p_bool(p, "reset", true) and aroot:
		reset_added = _reset_ops(u, player, [anim], aroot, lib if (new_lib and lib_name == "") else null)
	if not new_player and p.has("autoplay"):
		u.add_do_property(player, "autoplay", full if U.p_bool(p, "autoplay") else ("" if old_autoplay == full else old_autoplay))
		u.add_undo_property(player, "autoplay", old_autoplay)
	ctx.commit()
	if not new_lib and not new_player:
		_persist(lib)
	if reset_added > 0 and player.has_animation_library("") and player.get_animation_library("") != lib:
		_persist(player.get_animation_library(""))
	var out := {"player": ctx.node_path_str(player), "animation": full, "replaced": replaced, "created_player": new_player != null}
	out.merge(_anim_summary(anim))
	if reset_added > 0:
		out["reset_tracks_added"] = reset_added
	if str(player.autoplay) != "":
		out["autoplay"] = str(player.autoplay)
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


## Lists animations of one player (path) or of every AnimationPlayer in the scene.
func a_list(p: Dictionary):
	var players := []
	if U.p_str(p, "path", "") != "":
		var pl = await _player(p)
		if U.is_err(pl): return pl
		players.append(pl)
	else:
		if p.has("scene") and str(p.scene) != "":
			var r = await ensure_scene(str(p.scene))
			if U.is_err(r): return r
		var root = root_or_err()
		if U.is_err(root): return root
		players = _all_of(root, "AnimationPlayer")
	var out := []
	for player: AnimationPlayer in players:
		var anims := {}
		for full in player.get_animation_list():
			anims[str(full)] = _anim_summary(player.get_animation(full))
		var libs := {}
		for ln in player.get_animation_library_list():
			var lib := player.get_animation_library(ln)
			libs[str(ln) if str(ln) != "" else "(default)"] = lib.resource_path if lib.resource_path != "" and not lib.resource_path.contains("::") else "embedded"
		var aroot := _anim_root(player)
		out.append({"player": ctx.node_path_str(player), "root_node": ctx.node_path_str(aroot) if aroot else str(player.root_node), "autoplay": str(player.autoplay), "libraries": libs, "animations": anims})
	if out.is_empty():
		return {"players": [], "hint": "No AnimationPlayer in this scene; animation.create adds one."}
	return out[0] if out.size() == 1 and U.p_str(p, "path", "") != "" else {"players": out}


## Full tracks and keys of one animation.
func a_get(p: Dictionary):
	var player = await _player(p)
	if U.is_err(player): return player
	var a = _get_anim(player, p)
	if U.is_err(a): return a
	var out := {"player": ctx.node_path_str(player), "animation": a.full}
	out.merge(_anim_detail(a.anim))
	if str(player.autoplay) == a.full:
		out["autoplay"] = true
	return out


## Changes length / loop / step of an animation.
func a_edit(p: Dictionary):
	var player = await _player(p)
	if U.is_err(player): return player
	var a = _get_anim(player, p)
	if U.is_err(a): return a
	var we = _lib_writable(a.library, a.lib)
	if we: return we
	var anim: Animation = a.anim.duplicate(true)
	if p.has("loop"):
		var lm := _loop_mode(p.loop)
		if lm < 0:
			return U.err("Unknown loop mode '%s'." % p.loop, "Use none, linear or pingpong.")
		anim.loop_mode = lm
	if p.has("length"):
		anim.length = maxf(0.001, U.p_float(p, "length"))
	if p.has("step"):
		anim.step = U.p_float(p, "step")
	_swap_anim(player, a.lib, a.name, anim, "Edit animation " + a.full)
	return {"animation": a.full, "length": snappedf(anim.length, 0.0001), "loop": LOOP_NAMES[anim.loop_mode], "step": snappedf(anim.step, 0.0001)}


## Adds tracks to an existing animation: {track: {...}} or {tracks: [...]}.
func a_add_track(p: Dictionary):
	var player = await _player(p)
	if U.is_err(player): return player
	var a = _get_anim(player, p)
	if U.is_err(a): return a
	var we = _lib_writable(a.library, a.lib)
	if we: return we
	var specs: Array = U.p_arr(p, "tracks") if p.has("tracks") else ([p.track] if p.get("track") is Dictionary else [])
	if specs.is_empty():
		return U.err("Provide 'tracks': [{type, path, keys}] (or a single 'track' object).", "e.g. {\"type\": \"value\", \"path\": \"Sprite2D:modulate\", \"keys\": [{\"time\": 0, \"value\": \"#ffffff\"}, {\"time\": 0.5, \"value\": \"#ff0000\"}]}")
	var anim: Animation = a.anim.duplicate(true)
	var warnings := []
	var added := []
	for spec in specs:
		var r = _add_track(anim, spec, _anim_root(player), U.p_bool(p, "validate", true), warnings)
		if U.is_err(r): return r
		added.append(r)
	var max_t := _max_key_time(anim)
	if max_t > anim.length and U.p_bool(p, "extend", true):
		warnings.append("Length extended from %s to %s to fit the new keys." % [anim.length, max_t])
		anim.length = max_t
	var reset_added := _swap_anim(player, a.lib, a.name, anim, "Add track to " + a.full, [anim] if U.p_bool(p, "reset", true) else [])
	var out := {"animation": a.full, "added": added.map(func(i): return _track_summary(anim, i)), "length": anim.length}
	if reset_added > 0:
		out["reset_tracks_added"] = reset_added
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


## Replaces (or merges) the keys of one track.
func a_set_keys(p: Dictionary):
	var e = U.require(p, ["keys"])
	if e: return e
	var player = await _player(p)
	if U.is_err(player): return player
	var a = _get_anim(player, p)
	if U.is_err(a): return a
	var we = _lib_writable(a.library, a.lib)
	if we: return we
	var anim: Animation = a.anim.duplicate(true)
	var idx = _find_track(anim, p)
	if U.is_err(idx): return idx
	var warnings := []
	var target = _resolve_target(_anim_root(player), str(anim.track_get_path(idx)), anim.track_get_type(idx), false, warnings)
	if U.is_err(target): return target
	if U.p_bool(p, "replace", true):
		while anim.track_get_key_count(idx) > 0:
			anim.track_remove_key(idx, 0)
	else:
		for k in U.p_arr(p, "keys"):
			if k is Dictionary:
				var existing := anim.track_find_key(idx, float(k.get("time", 0.0)), Animation.FIND_MODE_APPROX)
				if existing >= 0:
					anim.track_remove_key(idx, existing)
	var r = _insert_keys(anim, idx, U.p_arr(p, "keys"), target, warnings)
	if U.is_err(r): return r
	var max_t := _max_key_time(anim)
	if max_t > anim.length and U.p_bool(p, "extend", true):
		warnings.append("Length extended from %s to %s." % [anim.length, max_t])
		anim.length = max_t
	_swap_anim(player, a.lib, a.name, anim, "Set keys in " + a.full)
	var out := {"animation": a.full, "track": _track_summary(anim, idx)}
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


func a_remove_track(p: Dictionary):
	var player = await _player(p)
	if U.is_err(player): return player
	var a = _get_anim(player, p)
	if U.is_err(a): return a
	var we = _lib_writable(a.library, a.lib)
	if we: return we
	var anim: Animation = a.anim.duplicate(true)
	var idx = _find_track(anim, p)
	if U.is_err(idx): return idx
	var desc := _track_summary(anim, idx)
	anim.remove_track(idx)
	_swap_anim(player, a.lib, a.name, anim, "Remove track from " + a.full)
	return {"animation": a.full, "removed": desc, "tracks_left": anim.get_track_count()}


func a_delete(p: Dictionary):
	var player = await _player(p)
	if U.is_err(player): return player
	var a = _get_anim(player, p)
	if U.is_err(a): return a
	var we = _lib_writable(a.library, a.lib)
	if we: return we
	var lib: AnimationLibrary = a.library
	var u = ctx.begin("Delete animation " + a.full)
	u.add_do_method(lib, "remove_animation", a.name)
	u.add_undo_method(lib, "add_animation", a.name, a.anim)
	u.add_undo_reference(a.anim)
	_persist_ops(u, lib)
	if str(player.autoplay) == a.full:
		u.add_do_property(player, "autoplay", "")
		u.add_undo_property(player, "autoplay", a.full)
	ctx.commit()
	_persist(lib)
	return {"deleted": a.full, "remaining": Array(player.get_animation_list())}


func a_rename(p: Dictionary):
	var e = U.require(p, ["new_name"])
	if e: return e
	var player = await _player(p)
	if U.is_err(player): return player
	var a = _get_anim(player, p)
	if U.is_err(a): return a
	var we = _lib_writable(a.library, a.lib)
	if we: return we
	var nn := U.p_str(p, "new_name")
	if nn.contains("/") or nn.contains(":") or nn.contains(",") or nn.contains("["):
		return U.err("Invalid animation name '%s'." % nn, "Names can't contain / : , [ (the library is kept).")
	var lib: AnimationLibrary = a.library
	if lib.has_animation(nn):
		return U.err("Animation '%s' already exists in that library." % nn, "Pick another name, or delete/rename the existing one first.")
	var new_full := _full(a.lib, nn)
	var u = ctx.begin("Rename animation %s -> %s" % [a.full, new_full])
	u.add_do_method(lib, "rename_animation", a.name, nn)
	u.add_undo_method(lib, "rename_animation", nn, a.name)
	_persist_ops(u, lib)
	if str(player.autoplay) == a.full:
		u.add_do_property(player, "autoplay", new_full)
		u.add_undo_property(player, "autoplay", a.full)
	# AnimationTrees playing the old name follow the rename.
	var updated := []
	var root: Node = ctx.edited_root()
	for tree: AnimationTree in _all_of(root, "AnimationTree"):
		if tree.get_node_or_null(tree.anim_player) != player or tree.tree_root == null:
			continue
		var nodes := []
		_anim_nodes(tree.tree_root, nodes)
		for an: AnimationNodeAnimation in nodes:
			if str(an.animation) == a.full:
				u.add_do_property(an, "animation", StringName(new_full))
				u.add_undo_property(an, "animation", StringName(a.full))
				if not ctx.node_path_str(tree) in updated:
					updated.append(ctx.node_path_str(tree))
	ctx.commit()
	_persist(lib)
	var out := {"renamed": a.full, "to": new_full}
	if not updated.is_empty():
		out["updated_trees"] = updated
	return out


func _anim_nodes(n: AnimationNode, out: Array) -> void:
	if n is AnimationNodeAnimation:
		out.append(n)
	elif n is AnimationNodeStateMachine or n is AnimationNodeBlendTree:
		for nm in n.get_node_list():
			if not (str(nm) in ["Start", "End", "output"]):
				_anim_nodes(n.get_node(nm), out)
	elif n is AnimationNodeBlendSpace1D or n is AnimationNodeBlendSpace2D:
		for i in n.get_blend_point_count():
			_anim_nodes(n.get_blend_point_node(i), out)


func a_set_autoplay(p: Dictionary):
	var player = await _player(p)
	if U.is_err(player): return player
	var full := ""
	if U.p_str(p, "name", "") != "":
		var a = _get_anim(player, p)
		if U.is_err(a): return a
		full = a.full
	var u = ctx.begin("Set autoplay")
	u.add_do_property(player, "autoplay", full)
	u.add_undo_property(player, "autoplay", player.autoplay)
	ctx.commit()
	return {"player": ctx.node_path_str(player), "autoplay": full if full != "" else null}


# ---------------------------------------------------------------------------
# SpriteFrames
# ---------------------------------------------------------------------------

func _load_texture(path: String):
	var rp := U.res_path(path)
	if not ResourceLoader.exists(rp):
		if FileAccess.file_exists(rp):
			return U.err("'%s' exists but hasn't been imported yet." % rp, "Run files.rescan, then retry.")
		var dir := rp.get_base_dir()
		var cands := []
		var da := DirAccess.open(dir)
		if da:
			for f in da.get_files():
				if not f.ends_with(".import"):
					cands.append(dir.path_join(f))
		var s := U.suggest(rp, cands)
		return U.err("Texture '%s' not found." % rp, "Did you mean '%s'?" % s if s != "" else "Check the path with files.list.")
	var t = load(rp)
	if not (t is Texture2D):
		return U.err("'%s' is not a texture (it's %s)." % [rp, t.get_class() if t else "unloadable"])
	return t


## Expands "res://player/run_*.png" into sorted matching files.
func _glob(pattern: String) -> Array:
	var rp := U.res_path(pattern)
	var dir := rp.get_base_dir()
	var mask := rp.get_file()
	var out := []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		if f.matchn(mask):
			out.append(dir.path_join(f))
	out.sort_custom(func(x, y): return x.naturalnocasecmp_to(y) < 0)
	return out


## Returns [[Texture2D, duration], ...] from {frames: [...]} or {sheet: {...}}.
func _frames_from_spec(aname: String, spec: Dictionary):
	var out := []
	if spec.has("frames"):
		for f in U.p_arr(spec, "frames"):
			var fpath := ""
			var dur := 1.0
			if f is Dictionary:
				fpath = str(f.get("texture", f.get("path", "")))
				dur = float(f.get("duration", 1.0))
			else:
				fpath = str(f)
			if fpath.contains("*"):
				var matches := _glob(fpath)
				if matches.is_empty():
					return U.err("Animation '%s': no files match '%s'." % [aname, fpath], "Check the folder with files.list.")
				for m in matches:
					var t = _load_texture(m)
					if U.is_err(t): return t
					out.append([t, dur])
				continue
			var tex = _load_texture(fpath)
			if U.is_err(tex): return tex
			out.append([tex, dur])
	elif spec.has("sheet"):
		var sh = spec.sheet
		if sh is String:
			sh = {"texture": sh}
		if not (sh is Dictionary) or not sh.has("texture"):
			return U.err("Animation '%s': 'sheet' needs {texture, hframes, vframes} (or frame_size: [w, h])." % aname)
		var tex = _load_texture(str(sh.texture))
		if U.is_err(tex): return tex
		var size: Vector2 = tex.get_size()
		var hf := int(sh.get("hframes", 1))
		var vf := int(sh.get("vframes", 1))
		var fw := size.x / maxi(1, hf)
		var fh := size.y / maxi(1, vf)
		if sh.has("frame_size"):
			var fs: Vector2 = U.to_vector(sh.frame_size, TYPE_VECTOR2)
			if fs.x <= 0 or fs.y <= 0:
				return U.err("frame_size must be positive, got %s." % fs)
			fw = fs.x
			fh = fs.y
			hf = int(size.x / fw)
			vf = int(size.y / fh)
		if hf < 1 or vf < 1:
			return U.err("Animation '%s': sheet slicing gives no frames (texture %s)." % [aname, size])
		var total := hf * vf
		var indices := []
		if sh.has("frames"):
			indices = U.p_arr(sh, "frames")
		elif sh.has("row"):
			var row := int(sh.row)
			if row < 0 or row >= vf:
				return U.err("Animation '%s': row %d out of range (the sheet has %d rows)." % [aname, row, vf], "Rows are 0-based; check hframes/vframes or frame_size against the image size (%s)." % var_to_str(size))
			for c in hf:
				indices.append(row * hf + c)
		else:
			for i in total:
				indices.append(i)
		if sh.has("start") or sh.has("count"):
			var st := int(sh.get("start", 0))
			indices = indices.slice(st, st + int(sh.get("count", indices.size())))
		var margin: Vector2 = U.to_vector(sh.get("margin", [0, 0]), TYPE_VECTOR2)
		var sep: Vector2 = U.to_vector(sh.get("separation", [0, 0]), TYPE_VECTOR2)
		if sh.has("frame_size") and (margin != Vector2.ZERO or sep != Vector2.ZERO):
			hf = int((size.x - margin.x + sep.x) / (fw + sep.x))
			vf = int((size.y - margin.y + sep.y) / (fh + sep.y))
			total = hf * vf
		for idx in indices:
			var i := int(idx)
			if i < 0 or i >= total:
				return U.err("Animation '%s': frame index %d out of range (sheet has %dx%d = %d frames)." % [aname, i, hf, vf, total], "Indices are 0-based, row by row: index = row * hframes + column.")
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(margin.x + (i % hf) * (fw + sep.x), margin.y + int(i / hf) * (fh + sep.y), fw, fh)
			out.append([at, float(sh.get("duration", 1.0))])
	else:
		return U.err("Animation '%s' needs 'frames': [res:// images] or 'sheet': {texture, hframes, vframes}." % aname)
	if out.is_empty():
		return U.err("Animation '%s' has no frames." % aname)
	return out


## Creates SpriteFrames from images or a sliced sprite sheet and assigns it (or saves a .tres).
func a_sprite_frames(p: Dictionary):
	var e = U.require(p, ["path", "animations"])
	if e: return e
	var anims = p.animations
	if anims is Array:
		var d := {}
		for item in anims:
			if item is Dictionary and item.has("name"):
				d[str(item.name)] = item
		anims = d
	if not (anims is Dictionary) or anims.is_empty():
		return U.err("'animations' must be {name: {frames: [...] | sheet: {...}, fps?, loop?}}.")
	var path := U.p_str(p, "path")
	var replace := U.p_bool(p, "replace", false)
	var node: Node = null
	var file_path := ""
	var sf: SpriteFrames = null
	var existing_file: SpriteFrames = null  # the loaded .tres, updated in place once everything succeeded
	if path.begins_with("res://") or path.ends_with(".tres") or path.ends_with(".res"):
		file_path = U.res_path(path)
		if file_path.get_extension() == "":
			file_path += ".tres"
		if not file_path.get_extension() in ["tres", "res"]:
			return U.err("'%s' is not a .tres/.res file." % file_path, "Pass an AnimatedSprite2D/3D node path, or a res://*.tres path for a SpriteFrames file.")
		if ResourceLoader.exists(file_path):
			var ex = load(file_path)
			if not (ex is SpriteFrames):
				return U.err("'%s' is a %s, not SpriteFrames." % [file_path, ex.get_class() if ex else "unloadable file"])
			existing_file = ex
	else:
		var n = await node_arg(p)
		if U.is_err(n): return n
		node = n
		if not ("sprite_frames" in node):
			return U.err("'%s' is a %s; SpriteFrames go on an AnimatedSprite2D or AnimatedSprite3D." % [path, node.get_class()], "Add one with node.add {type: 'AnimatedSprite2D'}, or change the type with node.change_type.")
		var cur = node.get("sprite_frames")
		if cur is SpriteFrames and cur.resource_path.get_extension() in ["tres", "res"] and not cur.resource_path.contains("::") and U.p_str(p, "save_path", "") == "":
			# The sprite uses a SpriteFrames file: edit that file (the node keeps pointing at it).
			file_path = cur.resource_path
			existing_file = cur
		elif cur is SpriteFrames and not replace:
			sf = cur.duplicate()
	if existing_file and not replace:
		sf = existing_file.duplicate()
	if sf == null:
		sf = SpriteFrames.new()
		if sf.has_animation("default") and not anims.has("default"):
			sf.remove_animation("default")
	var summary := {}
	for aname in anims:
		var spec = anims[aname]
		if spec is Array:
			spec = {"frames": spec}
		if not (spec is Dictionary):
			return U.err("Animation '%s' must be an object {frames | sheet, fps?, loop?}." % aname)
		var frames = _frames_from_spec(str(aname), spec)
		if U.is_err(frames): return frames
		if sf.has_animation(aname):
			sf.clear(aname)
		else:
			sf.add_animation(aname)
		sf.set_animation_speed(aname, float(spec.get("fps", spec.get("speed", 10.0))))
		var lm := _loop_mode(spec.get("loop", true))
		if lm < 0:
			return U.err("Animation '%s': unknown loop '%s'." % [aname, spec.loop], "Use true/false, none, linear or pingpong.")
		if sf.has_method("set_animation_loop_mode"):
			sf.call("set_animation_loop_mode", aname, lm)
		else:
			sf.set_animation_loop(aname, lm != Animation.LOOP_NONE)
		for f in frames:
			sf.add_frame(aname, f[0], f[1])
		summary[str(aname)] = {"frames": frames.size(), "fps": sf.get_animation_speed(aname), "loop": LOOP_NAMES[lm], "frame_size": var_to_str(frames[0][0].get_size())}
	# Which animation the sprite shows / autoplays (validated before anything is written).
	var first := str(anims.keys()[0])
	var autoplay_name := ""
	var ap = p.get("autoplay", null)
	if ap is bool:
		autoplay_name = (U.p_str(p, "play", first)) if ap else ""
	elif ap != null:
		autoplay_name = str(ap)
	var play := U.p_str(p, "play", autoplay_name)
	for nm in [play, autoplay_name]:
		if nm != "" and not sf.has_animation(nm):
			var s := U.suggest(nm, Array(sf.get_animation_names()))
			return U.err("'%s' is not one of the SpriteFrames animations." % nm, ("Did you mean '%s'? " % s if s != "" else "") + "Animations: %s. (autoplay takes an animation name, or true for the first one.)" % ", ".join(sf.get_animation_names()))
	var save_path := file_path if file_path != "" else (U.res_path(U.p_str(p, "save_path")) if U.p_str(p, "save_path", "") != "" else "")
	if save_path != "":
		if not save_path.get_extension() in ["tres", "res"]:
			return U.err("save_path must end in .tres or .res (got '%s')." % save_path)
		ctx.before_write([save_path])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
		if existing_file and save_path == file_path:
			existing_file.set("animations", sf.get("animations"))
			sf = existing_file
		var serr := ResourceSaver.save(sf, save_path)
		if serr != OK:
			return U.err("Failed to save '%s' (error %d)." % [save_path, serr])
		sf.take_over_path(save_path)
		ctx.fs().update_file(save_path)
	var out := {"animations": summary, "all_animations": Array(sf.get_animation_names())}
	if save_path != "":
		out["saved"] = save_path
	if node:
		var cur_anim := str(node.get("animation"))
		var want := play if play != "" else (cur_anim if sf.has_animation(cur_anim) else first)
		var u = ctx.begin("Set SpriteFrames")
		u.add_do_property(node, "sprite_frames", sf)
		u.add_undo_property(node, "sprite_frames", node.get("sprite_frames"))
		u.add_do_property(node, "animation", StringName(want))
		u.add_undo_property(node, "animation", node.get("animation"))
		if ap != null:
			u.add_do_property(node, "autoplay", autoplay_name)
			u.add_undo_property(node, "autoplay", node.get("autoplay"))
		u.add_do_reference(sf)
		ctx.commit()
		out["node"] = ctx.node_path_str(node)
		out["animation"] = want
		if ap != null:
			out["autoplay"] = autoplay_name
	elif ap != null or play != "":
		out["note"] = "autoplay/play only apply when 'path' is an AnimatedSprite node; set them on the sprite that uses this file."
	return out


# ---------------------------------------------------------------------------
# AnimationTree
# ---------------------------------------------------------------------------

func _state_pos(i: int) -> Vector2:
	return Vector2(300 + (i % 4) * 220, 100 + int(i / 4) * 140)


## Builds an AnimationRootNode from a spec {type, states, transitions, points, nodes, connections, ...}.
func _build_tree_node(spec: Dictionary, anims: Array, warnings: Array):
	var type := U.p_str(spec, "type", "animation" if spec.has("animation") else "state_machine").to_lower().replace("blendspace", "blend_space").replace("-", "_")
	if type in ["blend_space1d", "blend_space_1"]: type = "blend_space_1d"
	if type in ["blend_space2d", "blend_space_2"]: type = "blend_space_2d"
	if not TREE_NODE_TYPES.has(type):
		var s := U.suggest(type, TREE_NODE_TYPES.keys())
		return U.err("Unknown AnimationTree node type '%s'." % type, ("Did you mean '%s'? " % s if s != "" else "") + "Valid: %s" % ", ".join(TREE_NODE_TYPES.keys()))
	var node: AnimationNode = ClassDB.instantiate(TREE_NODE_TYPES[type])
	match type:
		"animation":
			var an := U.p_str(spec, "animation", U.p_str(spec, "name", ""))
			if an == "":
				return U.err("An animation node needs 'animation' (the AnimationPlayer animation to play): %s" % JSON.stringify(spec), "e.g. {\"animation\": \"run\", \"pos\": 1}.")
			node.animation = an
			anims.append(an)
		"transition":
			# Inputs by name: {type: transition, inputs: ["idle", "run"]} (or input_count).
			var ins := U.p_arr(spec, "inputs")
			node.input_count = ins.size() if not ins.is_empty() else U.p_int(spec, "input_count", 0)
			for i in ins.size():
				node.set_input_name(i, str(ins[i]))
		"state_machine":
			var r = _build_state_machine(node, spec, anims, warnings)
			if U.is_err(r): return r
		"blend_space_1d", "blend_space_2d":
			var r2 = _build_blend_space(node, spec, type == "blend_space_2d", anims, warnings)
			if U.is_err(r2): return r2
		"blend_tree":
			var r3 = _build_blend_tree(node, spec, anims, warnings)
			if U.is_err(r3): return r3
	var props := U.p_dict(spec, "props")
	if not props.is_empty():
		var pr = U.apply_props(node, props)
		if U.is_err(pr): return pr
	return node


## A state is "name" (plays the animation of that name) or {name, animation?} or {name, type: blend_space_2d, ...}.
func _state_spec(s) -> Dictionary:
	if s is String:
		return {"name": s, "type": "animation", "animation": s}
	if s is Dictionary:
		var d: Dictionary = s.duplicate()
		if not d.has("type"):
			d["type"] = "animation"
		if d.type == "animation" and not d.has("animation"):
			d["animation"] = d.get("name", "")
		return d
	return {}


func _build_state_machine(sm: AnimationNodeStateMachine, spec: Dictionary, anims: Array, warnings: Array):
	var states := U.p_arr(spec, "states")
	if states.is_empty():
		return U.err("A state_machine needs 'states': ['idle', 'run'] or [{name, animation}].")
	var names := []
	var i := 0
	for s in states:
		var st := _state_spec(s)
		var sname := U.p_str(st, "name", "")
		if sname == "":
			return U.err("Every state needs a name: %s" % JSON.stringify(s))
		if sname in names or sname in ["Start", "End"]:
			return U.err("Duplicate or reserved state name '%s'." % sname)
		var child = _build_tree_node(st, anims, warnings)
		if U.is_err(child): return child
		sm.add_node(sname, child, U.to_vector(st.position, TYPE_VECTOR2) if st.has("position") else _state_pos(i))
		names.append(sname)
		i += 1
	if spec.has("state_machine_type"):
		var t = _enum_pick(spec.state_machine_type, ["root", "nested", "grouped"], "state_machine_type")
		if U.is_err(t): return t
		sm.state_machine_type = t
	if spec.has("allow_transition_to_self"):
		sm.allow_transition_to_self = U.p_bool(spec, "allow_transition_to_self")
	var start := U.p_str(spec, "start", names[0])
	if not start in names:
		return U.err("Start state '%s' is not one of the states." % start, "States: %s" % ", ".join(names))
	var st_tr := AnimationNodeStateMachineTransition.new()
	st_tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition("Start", start, st_tr)
	sm.set_node_position("Start", Vector2(60, 100))
	sm.set_node_position("End", Vector2(300 + mini(names.size(), 4) * 220, 100))
	var all_names := names + ["Start", "End"]
	for t in U.p_arr(spec, "transitions"):
		if not (t is Dictionary):
			return U.err("Each transition must be {from, to, ...}.")
		var froms: Array = t.from if t.get("from") is Array else [str(t.get("from", ""))]
		var to := str(t.get("to", ""))
		if "*" in froms:
			# "Any state": every state except the target.
			froms = names.filter(func(x): return x != to)
		for from in froms:
			from = str(from)
			for nm in [from, to]:
				if not nm in all_names:
					var s2 := U.suggest(nm, all_names)
					return U.err("Transition %s -> %s: unknown state '%s'." % [from, to, nm], ("Did you mean '%s'? " % s2 if s2 != "" else "") + "States: %s" % ", ".join(names))
			if sm.has_transition(from, to):
				warnings.append("Duplicate transition %s -> %s ignored." % [from, to])
				continue
			var tr := AnimationNodeStateMachineTransition.new()
			var sw = t.get("switch_mode", "immediate")
			if sw is String:
				if not SWITCH_MODES.has(sw.to_lower()):
					return U.err("Transition %s -> %s: unknown switch_mode '%s'." % [from, to, sw], "Use immediate, sync or at_end.")
				tr.switch_mode = SWITCH_MODES[sw.to_lower()]
			else:
				tr.switch_mode = int(sw)
			var cond := str(t.get("advance_condition", t.get("condition", "")))
			var expr := str(t.get("advance_expression", t.get("expression", "")))
			if cond != "":
				tr.advance_condition = cond
			if expr != "":
				tr.advance_expression = expr
			if t.has("auto") or cond != "" or expr != "":
				tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO if (U.p_bool(t, "auto", true)) else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			if t.has("disabled") and U.p_bool(t, "disabled"):
				tr.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
			tr.xfade_time = float(t.get("xfade", t.get("xfade_time", 0.0)))
			if t.has("priority"): tr.priority = int(t.priority)
			if t.has("reset"): tr.reset = U.p_bool(t, "reset")
			if t.has("break_loop_at_end"): tr.break_loop_at_end = U.p_bool(t, "break_loop_at_end")
			sm.add_transition(from, to, tr)
	return null


func _build_blend_space(bs: AnimationRootNode, spec: Dictionary, is_2d: bool, anims: Array, warnings: Array):
	var points := U.p_arr(spec, "blend_points") if spec.has("blend_points") else U.p_arr(spec, "points")
	if points.is_empty():
		return U.err("A blend space needs 'blend_points': [{animation, pos}] (pos is a number for 1D, [x, y] for 2D).")
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var parsed := []
	for pt in points:
		if not (pt is Dictionary) or not pt.has("pos"):
			return U.err("Blend point %s needs 'pos' and 'animation' (or a nested {type, ...})." % JSON.stringify(pt))
		var pos := Vector2.ZERO
		if is_2d:
			if not _vec_like(pt.pos):
				return U.err("Blend point %s: 2D positions are [x, y]." % JSON.stringify(pt))
			pos = U.to_vector(pt.pos, TYPE_VECTOR2)
		else:
			var pv = pt.pos[0] if pt.pos is Array and pt.pos.size() == 1 else pt.pos
			if pv is String and pv.is_valid_float():
				pv = pv.to_float()
			if not (pv is float or pv is int):
				return U.err("Blend point %s: 1D positions are a number, e.g. 'pos': 0.5." % JSON.stringify(pt))
			pos = Vector2(float(pv), 0)
		mn = mn.min(pos)
		mx = mx.max(pos)
		var sub: Dictionary = pt.duplicate()
		sub.erase("pos")
		if not sub.has("type"):
			sub["type"] = "animation"
		var child = _build_tree_node(sub, anims, warnings)
		if U.is_err(child): return child
		var pname := str(pt.get("name", pt.get("animation", "point")))
		var taken := parsed.map(func(x): return x[2])
		if pname in taken:
			pname = "%s_%d" % [pname, parsed.size()]
		parsed.append([child, pos, pname])
	# Space bounds: explicit, else from the points (at least -1..1).
	if is_2d:
		var b: AnimationNodeBlendSpace2D = bs
		b.min_space = U.to_vector(spec.min_space, TYPE_VECTOR2) if spec.has("min_space") else mn.min(Vector2(-1, -1))
		b.max_space = U.to_vector(spec.max_space, TYPE_VECTOR2) if spec.has("max_space") else mx.max(Vector2(1, 1))
		if spec.has("x_label"): b.x_label = str(spec.x_label)
		if spec.has("y_label"): b.y_label = str(spec.y_label)
	else:
		var b1: AnimationNodeBlendSpace1D = bs
		b1.min_space = float(spec.min_space) if spec.has("min_space") else minf(mn.x, -1.0)
		b1.max_space = float(spec.max_space) if spec.has("max_space") else maxf(mx.x, 1.0)
		if spec.has("value_label"): b1.value_label = str(spec.value_label)
	if spec.has("blend_mode"):
		var bm = _enum_pick(spec.blend_mode, ["interpolated", "discrete", "discrete_carry"], "blend_mode")
		if U.is_err(bm): return bm
		bs.set("blend_mode", bm)
	if spec.has("sync"):
		bs.set("sync", U.p_bool(spec, "sync"))
	for item in parsed:
		if is_2d:
			(bs as AnimationNodeBlendSpace2D).add_blend_point(item[0], item[1], -1, item[2])
		else:
			(bs as AnimationNodeBlendSpace1D).add_blend_point(item[0], item[1].x, -1, item[2])
	if is_2d and parsed.size() < 3:
		warnings.append("A 2D blend space needs at least 3 points to form triangles.")
	return null


func _build_blend_tree(bt: AnimationNodeBlendTree, spec: Dictionary, anims: Array, warnings: Array):
	var nodes := U.p_arr(spec, "nodes")
	if nodes.is_empty():
		return U.err("A blend_tree needs 'nodes': [{name, type, animation?}] and 'connections': [{from, to, port?}] ('to': 'output' for the result).")
	var names := ["output"]
	var i := 0
	for nd in nodes:
		if not (nd is Dictionary) or U.p_str(nd, "name", "") == "":
			return U.err("Each blend_tree node needs {name, type}.")
		var child = _build_tree_node(nd, anims, warnings)
		if U.is_err(child): return child
		var nm := U.p_str(nd, "name")
		bt.add_node(nm, child, U.to_vector(nd.position, TYPE_VECTOR2) if nd.has("position") else Vector2(i * 220, 80 * (i % 2)))
		names.append(nm)
		i += 1
	bt.set_node_position("output", Vector2(i * 220 + 100, 0))
	var conns := U.p_arr(spec, "connections")
	if conns.is_empty() and nodes.size() == 1:
		conns = [{"from": U.p_str(nodes[0], "name"), "to": "output"}]
	for c in conns:
		if not (c is Dictionary):
			return U.err("Each connection must be {from, to, port?}.")
		var from := str(c.get("from", ""))
		var to := str(c.get("to", "output"))
		for nm in [from, to]:
			if not nm in names:
				var s := U.suggest(nm, names)
				return U.err("Connection %s -> %s: unknown node '%s'." % [from, to, nm], ("Did you mean '%s'? " % s if s != "" else "") + "Nodes: %s" % ", ".join(names))
		var dest: AnimationNode = bt.get_node(to)
		var port_v = c.get("port", 0)
		var port := -1
		if port_v is float or port_v is int or (port_v is String and port_v.is_valid_int()):
			port = int(port_v)
		elif dest:
			port = dest.find_input(str(port_v))
		var n_in: int = 1 if to == "output" else dest.get_input_count()
		if port < 0 or port >= n_in:
			var in_names := []
			if dest:
				for ii in n_in:
					in_names.append(dest.get_input_name(ii))
			return U.err("Connection %s -> %s: input %s doesn't exist (%s has %d inputs%s)." % [from, to, JSON.stringify(port_v), "output" if to == "output" else dest.get_class().replace("AnimationNode", ""), n_in, (": " + ", ".join(in_names)) if not in_names.is_empty() else ""], "Ports count from 0 (or use the input name). blend2/add2/one_shot: 0 = main input, 1 = blend/add/shot input. A transition node needs 'inputs': [\"idle\", \"run\"].")
		bt.connect_node(to, port, from)
	return null


func _tree_param_value(key: String, value) -> Variant:
	if key.begins_with("parameters/conditions/"):
		return U.coerce(value, TYPE_BOOL)
	if key.ends_with("/blend_position") or key == "blend_position":
		if value is Array or (value is String and value.begins_with("Vector2")):
			return U.to_vector(value, TYPE_VECTOR2)
		return float(value)
	if key.ends_with("blend_amount") or key.ends_with("/scale") or key.ends_with("seek_request") or key.ends_with("add_amount"):
		return float(value) if (value is float or value is int or (value is String and value.is_valid_float())) else U.err("Parameter '%s' takes a number, got %s." % [key, JSON.stringify(value)])
	if key.ends_with("/request") and value is String:
		var i := ["none", "fire", "abort", "fade_out"].find(value.to_lower().replace(" ", "_"))
		if i < 0:
			return U.err("One-shot request '%s' is not valid." % value, "Use fire, abort, fade_out or none.")
		return i
	return U._auto(value)


func _param_key(k: String) -> String:
	return k if k.begins_with("parameters/") else "parameters/" + k


## Builds a complete AnimationTree (state machine / blend space / blend tree) in one call.
func a_tree(p: Dictionary):
	if p.has("scene") and str(p.scene) != "":
		var r = await ensure_scene(str(p.scene))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var path := U.p_str(p, "path", "")
	var tree: AnimationTree = null
	var parent: Node = null
	if path != "":
		var n: Node = ctx.find_node(path)
		if n is AnimationTree:
			tree = n
		elif n != null:
			return U.err("'%s' is a %s, not an AnimationTree." % [path, n.get_class()], "Give the path of a new node to create one, e.g. '%s/AnimationTree'." % path)
		else:
			var pp := U.p_str(p, "parent", path.get_base_dir() if path.contains("/") else ".")
			parent = ctx.find_node(pp)
			if parent == null:
				return ctx.node_not_found(pp)
	else:
		parent = ctx.find_node(U.p_str(p, "parent", "."))
		if parent == null:
			return ctx.node_not_found(U.p_str(p, "parent"))
		var want := U.p_str(p, "name", "AnimationTree")
		var ex := parent.get_node_or_null(NodePath(want))
		if ex is AnimationTree:
			tree = ex
			parent = null
	# The AnimationPlayer.
	var player: AnimationPlayer = null
	if U.p_str(p, "anim_player", "") != "":
		var pn: Node = ctx.find_node(U.p_str(p, "anim_player"))
		if pn == null:
			return ctx.node_not_found(U.p_str(p, "anim_player"))
		if not (pn is AnimationPlayer):
			return U.err("anim_player '%s' is a %s, not an AnimationPlayer." % [U.p_str(p, "anim_player"), pn.get_class()], "Players in this scene: %s" % _names(_all_of(root, "AnimationPlayer")))
		player = pn
	elif tree and str(tree.anim_player) != "":
		player = tree.get_node_or_null(tree.anim_player) as AnimationPlayer
	if player == null:
		var all := _all_of(root, "AnimationPlayer")
		if all.size() == 1:
			player = all[0]
		elif all.is_empty():
			return U.err("No AnimationPlayer found for the tree.", "Create animations first with animation.create, then pass anim_player.")
		else:
			return U.err("Several AnimationPlayers; pass anim_player.", "Players: %s" % _names(all))
	# Root node spec.
	var spec := p.duplicate()
	var type := U.p_str(p, "type", "state_machine")
	spec["type"] = type
	for k in ["path", "scene", "parent", "name", "anim_player", "parameters", "props", "active"]:
		spec.erase(k)
	if p.has("root_props"):
		spec["props"] = p.root_props
	var anims := []
	var warnings := []
	var tree_root = _build_tree_node(spec, anims, warnings)
	if U.is_err(tree_root): return tree_root
	for an in anims:
		if an != "" and not player.has_animation(an):
			var s := U.suggest(an, Array(player.get_animation_list()))
			warnings.append("Animation '%s' doesn't exist on %s%s." % [an, ctx.node_path_str(player), (" (did you mean '%s'?)" % s) if s != "" else ""])
	# Paths relative to the tree.
	var host: Node = parent if tree == null else tree
	var rel_player := _rel_path(host, player, tree == null)
	var proot: Node = _anim_root(player)
	var rel_root := _rel_path(host, proot, tree == null) if proot else NodePath("..")
	# Validate everything before opening the undo action.
	var params := U.p_dict(p, "parameters")
	var param_values := {}
	for k in params:
		var key := _param_key(str(k))
		var pv = _tree_param_value(key, params[k])
		if U.is_err(pv): return pv
		param_values[key] = pv
	var tree_props := {}
	if not U.p_dict(p, "props").is_empty():
		var probe := AnimationTree.new()
		var pr = U.apply_props(probe, U.p_dict(p, "props"))
		if U.is_err(pr):
			probe.free()
			return pr
		for k in U.p_dict(p, "props"):
			tree_props[str(k)] = probe.get(str(k))
		probe.free()
	var new_tree: AnimationTree = null
	if tree == null:
		new_tree = AnimationTree.new()
		new_tree.name = path.get_file() if path != "" else U.p_str(p, "name", "AnimationTree")
		tree = new_tree
	var u = ctx.begin("Build AnimationTree")
	if new_tree:
		new_tree.anim_player = rel_player
		new_tree.root_node = rel_root
		new_tree.tree_root = tree_root
		new_tree.active = U.p_bool(p, "active", true)
		for k in tree_props:
			new_tree.set(k, tree_props[k])
		u.add_do_method(parent, "add_child", new_tree, true)
		u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", new_tree, root)
		u.add_do_reference(new_tree)
		u.add_undo_method(parent, "remove_child", new_tree)
	else:
		u.add_do_property(tree, "anim_player", rel_player)
		u.add_undo_property(tree, "anim_player", tree.anim_player)
		u.add_do_property(tree, "root_node", rel_root)
		u.add_undo_property(tree, "root_node", tree.root_node)
		u.add_do_property(tree, "tree_root", tree_root)
		u.add_undo_property(tree, "tree_root", tree.tree_root)
		u.add_do_reference(tree_root)
		if p.has("active"):
			u.add_do_property(tree, "active", U.p_bool(p, "active"))
			u.add_undo_property(tree, "active", tree.active)
		for k in tree_props:
			u.add_do_property(tree, k, tree_props[k])
			u.add_undo_property(tree, k, tree.get(k))
	for key in param_values:
		u.add_do_method(tree, "set", key, param_values[key])
	# RESET tracks for everything the tree animates, so the editor restores the scene on save
	# (an active AnimationTree plays in the editor and would otherwise leave its current pose in the .tscn).
	var reset_added := 0
	if U.p_bool(p, "reset", true):
		var used := []
		for an in anims:
			if an != "" and player.has_animation(an):
				used.append(player.get_animation(an))
		reset_added = _reset_ops(u, player, used, proot)
	ctx.commit()
	if reset_added > 0 and player.has_animation_library(""):
		_persist(player.get_animation_library(""))
	var out := {"path": ctx.node_path_str(tree), "created": new_tree != null, "anim_player": str(tree.anim_player), "root_node": str(tree.root_node)}
	out.merge(_describe_tree_node(tree.tree_root))
	out["parameters"] = _tree_params(tree)
	if reset_added > 0:
		out["reset_tracks_added"] = reset_added
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


## NodePath from `host` (or from a not-yet-added child of `host` when as_child) to `target`.
func _rel_path(host: Node, target: Node, as_child: bool) -> NodePath:
	var rel := str(host.get_path_to(target))
	if not as_child:
		return NodePath(rel)
	if rel == ".":
		return NodePath("..")
	return NodePath("../" + rel)


func _describe_tree_node(n: AnimationNode) -> Dictionary:
	if n == null:
		return {"type": null}
	var d := {"type": n.get_class().replace("AnimationNode", "")}
	if n is AnimationNodeAnimation:
		d["animation"] = str(n.animation)
	elif n is AnimationNodeStateMachine:
		var sm: AnimationNodeStateMachine = n
		var states := []
		for nm in sm.get_node_list():
			if str(nm) in ["Start", "End"]:
				continue
			var sd := {"name": str(nm)}
			sd.merge(_describe_tree_node(sm.get_node(nm)))
			states.append(sd)
		d["states"] = states
		var trs := []
		for i in sm.get_transition_count():
			var t: AnimationNodeStateMachineTransition = sm.get_transition(i)
			var td := {"from": str(sm.get_transition_from(i)), "to": str(sm.get_transition_to(i)), "switch_mode": SWITCH_MODES.find_key(t.switch_mode), "advance_mode": ["disabled", "enabled", "auto"][t.advance_mode]}
			if str(t.advance_condition) != "":
				td["condition"] = str(t.advance_condition)
			if t.advance_expression != "":
				td["expression"] = t.advance_expression
			if t.xfade_time > 0:
				td["xfade"] = snappedf(t.xfade_time, 0.0001)
			if td.from == "Start":
				d["start"] = td.to
			trs.append(td)
		d["transitions"] = trs
	elif n is AnimationNodeBlendSpace1D or n is AnimationNodeBlendSpace2D:
		var pts := []
		for i in n.get_blend_point_count():
			var pd := {"pos": U.encode(n.get_blend_point_position(i))}
			pd.merge(_describe_tree_node(n.get_blend_point_node(i)))
			pts.append(pd)
		d["blend_points"] = pts
		d["min_space"] = U.encode(n.min_space)
		d["max_space"] = U.encode(n.max_space)
	elif n is AnimationNodeBlendTree:
		var bt: AnimationNodeBlendTree = n
		var nodes := []
		for nm in bt.get_node_list():
			if str(nm) == "output":
				continue
			var nd := {"name": str(nm)}
			nd.merge(_describe_tree_node(bt.get_node(nm)))
			nodes.append(nd)
		d["nodes"] = nodes
		var conns := []
		var raw = bt.get("node_connections")
		if raw is Array:
			for i in range(0, raw.size() - 2, 3):
				conns.append({"to": str(raw[i]), "port": raw[i + 1], "from": str(raw[i + 2])})
		d["connections"] = conns
	return d


## Read-only playback state that is just noise for an assistant.
func _param_noise(nm: String) -> bool:
	for suf in ["/current_length", "/current_position", "/current_delta", "/closest", "/backward", "/time", "/active", "/internal_active", "_remaining", "/time_to_restart", "/current_index", "/current_state", "/prev_index", "/prev_xfading", "/current"]:
		if nm.ends_with(suf):
			return true
	return nm.begins_with("parameters/Start/") or nm.begins_with("parameters/End/") or nm.contains("/Start/") or nm.contains("/End/")


func _tree_params(tree: AnimationTree) -> Dictionary:
	var out := {}
	for pi in tree.get_property_list():
		var nm: String = pi.name
		if not nm.begins_with("parameters/") or _param_noise(nm):
			continue
		var v = tree.get(nm)
		if v is AnimationNodeStateMachinePlayback:
			out[nm] = "StateMachinePlayback (runtime: get it and call travel('state'))"
			continue
		if v is Object:
			continue
		out[nm] = U.encode(v)
	return out


func _tree_arg(p: Dictionary):
	var root = root_or_err()
	if U.is_err(root): return root
	if U.p_str(p, "path", "") == "":
		var all := _all_of(root, "AnimationTree")
		if all.size() == 1:
			return all[0]
		return U.err("Pass 'path' of the AnimationTree." if not all.is_empty() else "There is no AnimationTree in this scene.", "Trees: %s" % _names(all) if not all.is_empty() else "Build one with animation.tree.")
	var n = await node_arg(p)
	if U.is_err(n): return n
	if not (n is AnimationTree):
		return U.err("'%s' is a %s, not an AnimationTree." % [U.p_str(p, "path"), n.get_class()], "Build one with animation.tree, or pass the AnimationTree node path.")
	return n


## Describes an AnimationTree: structure, transitions, parameters and problems.
func a_tree_info(p: Dictionary):
	if p.has("scene") and str(p.scene) != "":
		var r = await ensure_scene(str(p.scene))
		if U.is_err(r): return r
	var tree = await _tree_arg(p)
	if U.is_err(tree): return tree
	var out := {"path": ctx.node_path_str(tree), "active": tree.active, "anim_player": str(tree.anim_player), "root_node": str(tree.root_node)}
	out.merge(_describe_tree_node(tree.tree_root))
	out["parameters"] = _tree_params(tree)
	var problems := []
	var player = tree.get_node_or_null(tree.anim_player) if str(tree.anim_player) != "" else null
	if not (player is AnimationPlayer):
		problems.append("anim_player '%s' doesn't point at an AnimationPlayer." % tree.anim_player)
	elif tree.tree_root:
		var anims := []
		_collect_anims(tree.tree_root, anims)
		for an in anims:
			if an != "" and not player.has_animation(an):
				problems.append("Animation '%s' is used by the tree but missing from %s." % [an, ctx.node_path_str(player)])
	if tree.tree_root == null:
		problems.append("tree_root is empty.")
	if not problems.is_empty():
		out["problems"] = problems
	return out


func _collect_anims(n: AnimationNode, out: Array) -> void:
	if n is AnimationNodeAnimation:
		out.append(str(n.animation))
	elif n is AnimationNodeStateMachine or n is AnimationNodeBlendTree:
		for nm in n.get_node_list():
			if str(nm) in ["Start", "End", "output"]:
				continue
			_collect_anims(n.get_node(nm), out)
	elif n is AnimationNodeBlendSpace1D or n is AnimationNodeBlendSpace2D:
		for i in n.get_blend_point_count():
			_collect_anims(n.get_blend_point_node(i), out)


## Sets AnimationTree parameters: {name, value} or {parameters: {name: value}}.
func a_set_parameter(p: Dictionary):
	if p.has("scene") and str(p.scene) != "":
		var r = await ensure_scene(str(p.scene))
		if U.is_err(r): return r
	var tree = await _tree_arg(p)
	if U.is_err(tree): return tree
	var params := U.p_dict(p, "parameters")
	if params.is_empty():
		var e = U.require(p, ["name"])
		if e: return U.err("Provide {name, value} or {parameters: {name: value}}.", "e.g. name='conditions/moving', value=true, or name='blend_position', value=[1, 0].")
		params = {U.p_str(p, "name"): p.get("value")}
	var existing := {}
	for pi in tree.get_property_list():
		if str(pi.name).begins_with("parameters/"):
			existing[pi.name] = pi
	var plan := []
	for k in params:
		var key := _param_key(str(k))
		if not existing.has(key):
			var useful := existing.keys().filter(func(x): return not _param_noise(x) and x != "parameters/playback")
			var s := U.suggest(key, useful)
			return U.err("AnimationTree has no parameter '%s'." % key, ("Did you mean '%s'? " % s if s != "" else "") + "Parameters: %s" % ", ".join(useful))
		var pi: Dictionary = existing[key]
		var cur = tree.get(key)
		var t: int = pi.type if pi.type != TYPE_NIL else typeof(cur)
		var v = U.coerce(params[k], t, pi.hint, pi.hint_string) if t != TYPE_NIL else _tree_param_value(key, params[k])
		if U.is_err(v): return v
		plan.append([key, v, cur])
	var u = ctx.begin("Set AnimationTree parameters")
	for item in plan:
		u.add_do_property(tree, item[0], item[1])
		u.add_undo_property(tree, item[0], item[2])
	ctx.commit()
	var out := {}
	for item in plan:
		out[item[0]] = U.encode(tree.get(item[0]))
	return {"path": ctx.node_path_str(tree), "set": out}
