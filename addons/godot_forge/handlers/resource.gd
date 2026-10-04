@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Resource files (.tres/.res): create, read, edit, duplicate; list resource types.


func a_create(p: Dictionary):
	var e = U.require(p, ["path", "type"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if path.get_extension() == "":
		path += ".tres"
	if FileAccess.file_exists(path) and not U.p_bool(p, "overwrite", false):
		return U.err("'%s' already exists." % path, "Use resource.edit, or pass overwrite=true.")
	var type := U.p_str(p, "type")
	if not ClassDB.class_exists(type) or not ClassDB.is_parent_class(type, "Resource") or not ClassDB.can_instantiate(type):
		return U.err("'%s' is not an instantiable Resource type." % type, "Use resource.types to list them, or type='Resource' with script=res://my_data.gd for custom data.")
	var res: Resource = ClassDB.instantiate(type)
	if p.has("script"):
		var sp := U.res_path(U.p_str(p, "script"))
		if not ResourceLoader.exists(sp):
			return U.err("Script '%s' does not exist." % sp)
		res.set_script(load(sp))
	var pr = U.apply_props(res, U.p_dict(p, "props"))
	if U.is_err(pr): return pr
	return _save(res, path)


func _save(res: Resource, path: String):
	ctx.before_write([path])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return U.err("Failed to save '%s' (error %d)." % [path, err])
	res.take_over_path(path)
	ctx.fs().update_file(path)
	return {"path": path, "type": res.get_class(), "props": U.changed_props(res)}


func a_read(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not ResourceLoader.exists(path):
		return U.err("Resource '%s' does not exist." % path)
	var res: Resource = load(path)
	var out := {"path": path, "type": res.get_class(), "props": U.changed_props(res, U.p_bool(p, "all", false))}
	if res.get_script():
		out["script"] = res.get_script().resource_path
	if res is Texture2D:
		out["size"] = var_to_str(res.get_size())
	if res is AudioStream:
		out["length_s"] = res.get_length()
	if res is Mesh:
		out["aabb"] = var_to_str(res.get_aabb())
		out["surfaces"] = res.get_surface_count()
	return out


func a_edit(p: Dictionary):
	var e = U.require(p, ["path", "props"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not ResourceLoader.exists(path):
		return U.err("Resource '%s' does not exist." % path)
	if path.ends_with(".tscn") or path.ends_with(".gd"):
		return U.err("Use scene/node tools for scenes and script tools for scripts.")
	var res: Resource = load(path)
	var pr = U.apply_props(res, U.p_dict(p, "props"))
	if U.is_err(pr): return pr
	return _save(res, path)


func a_duplicate(p: Dictionary):
	var e = U.require(p, ["path", "to"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not ResourceLoader.exists(path):
		return U.err("Resource '%s' does not exist." % path)
	var copy: Resource = load(path).duplicate(true)
	if p.has("props"):
		var pr = U.apply_props(copy, U.p_dict(p, "props"))
		if U.is_err(pr): return pr
	return _save(copy, U.res_path(U.p_str(p, "to")))


## Assigns a resource (file or inline spec) to a node property; shorthand for node.set.
func a_assign(p: Dictionary):
	var e = U.require(p, ["path", "property", "resource"])
	if e: return e
	return await ctx.router.handlers["node"].a_set({"path": p.path, "scene": p.get("scene", ""), "props": {U.p_str(p, "property"): p.resource}})


## Saves an embedded (sub-)resource from a node property to its own file so it can be reused.
func a_extract(p: Dictionary):
	var e = U.require(p, ["path", "property", "save_path"])
	if e: return e
	var n = await node_arg(p)
	if U.is_err(n): return n
	var res = n.get(U.p_str(p, "property"))
	if not (res is Resource):
		return U.err("Property '%s' does not hold a resource." % U.p_str(p, "property"))
	var sp := U.res_path(U.p_str(p, "save_path"))
	var out = _save(res, sp)
	ctx.mark_dirty()
	return out


func a_types(p: Dictionary):
	var base := U.p_str(p, "base", "Resource")
	if not ClassDB.class_exists(base):
		return U.err("Unknown class '%s'." % base)
	var out := []
	for c in ClassDB.get_inheriters_from_class(base):
		if ClassDB.can_instantiate(c) and not str(c).begins_with("Editor"):
			out.append(str(c))
	out.sort()
	var filter := U.p_str(p, "filter", "")
	if filter != "":
		out = out.filter(func(x): return x.to_lower().contains(filter.to_lower()))
	return {"base": base, "types": out}
