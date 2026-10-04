@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Scene files: create, open, save, tree inspection, instancing, packing branches.


func a_current(_p: Dictionary):
	var root: Node = ctx.edited_root()
	return {
		"edited_scene": root.scene_file_path if root else null,
		"root": {"name": str(root.name), "type": root.get_class()} if root else null,
		"open_scenes": EditorInterface.get_open_scenes(),
		"unsaved": EditorInterface.get_unsaved_scenes() if EditorInterface.has_method("get_unsaved_scenes") else [],
	}


func a_create(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not path.ends_with(".tscn") and not path.ends_with(".scn"):
		path += ".tscn"
	if FileAccess.file_exists(path) and not U.p_bool(p, "overwrite", false):
		return U.err("Scene '%s' already exists." % path, "Open it with scene.open, or pass overwrite=true.")
	var root: Node
	var inherits := U.p_str(p, "inherits", "")
	if inherits != "":
		var base_path := U.res_path(inherits)
		if not ResourceLoader.exists(base_path):
			return U.err("Base scene '%s' does not exist." % base_path)
		var base: PackedScene = load(base_path)
		root = base.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
	else:
		var type := U.p_str(p, "root_type", "Node2D")
		root = _instantiate_type(type)
		if root == null:
			return _bad_type(type)
	root.name = U.p_str(p, "root_name", path.get_file().get_basename().to_pascal_case())
	if p.has("props"):
		var pr = U.apply_props(root, U.p_dict(p, "props"))
		if U.is_err(pr):
			root.free()
			return pr
	if p.has("script"):
		var sp := U.res_path(U.p_str(p, "script"))
		if ResourceLoader.exists(sp):
			root.set_script(load(sp))
	var packed := PackedScene.new()
	var perr := packed.pack(root)
	if perr != OK:
		root.free()
		return U.err("Failed to pack scene (error %d)." % perr)
	ctx.before_write([path])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var serr := ResourceSaver.save(packed, path)
	root.free()
	if serr != OK:
		return U.err("Failed to save scene '%s' (error %d)." % [path, serr])
	ctx.fs().update_file(path)
	await ctx.wait_fs()
	if U.p_bool(p, "open", true):
		EditorInterface.open_scene_from_path(path)
		await ctx.frame()
	if U.p_bool(p, "set_main", false) or str(ProjectSettings.get_setting("application/run/main_scene", "")) == "":
		ProjectSettings.set_setting("application/run/main_scene", path)
		ProjectSettings.save()
	return {"path": path, "root_type": U.p_str(p, "root_type", "Node2D") if inherits == "" else "inherits " + inherits, "opened": U.p_bool(p, "open", true), "main_scene": ProjectSettings.get_setting("application/run/main_scene", "")}


func _instantiate_type(type: String) -> Node:
	if type.begins_with("res://") and type.ends_with(".gd"):
		var scr = load(type)
		if scr is Script:
			var base: StringName = scr.get_instance_base_type()
			var n: Node = ClassDB.instantiate(base)
			n.set_script(scr)
			return n
		return null
	if ClassDB.class_exists(type):
		if not ClassDB.is_parent_class(type, "Node") or not ClassDB.can_instantiate(type):
			return null
		return ClassDB.instantiate(type)
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == type:
			var scr2: Script = load(c.path)
			var n2: Node = ClassDB.instantiate(scr2.get_instance_base_type())
			n2.set_script(scr2)
			return n2
	return null


func _bad_type(type: String) -> Dictionary:
	var names := ClassDB.get_inheriters_from_class("Node")
	var s := U.suggest(type, Array(names))
	return U.err("'%s' is not an instantiable Node type." % type, ("Did you mean '%s'? " % s if s != "" else "") + "Use introspect.search to find node classes.")


func a_open(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var r = await ensure_scene(U.p_str(p, "path"))
	if U.is_err(r): return r
	return {"opened": r.scene_file_path, "root": {"name": str(r.name), "type": r.get_class()}}


func a_save(p: Dictionary):
	var root = root_or_err()
	if U.is_err(root): return root
	var as_path := U.p_str(p, "path", "")
	if as_path != "":
		var rp := U.res_path(as_path)
		ctx.before_write([rp])
		EditorInterface.save_scene_as(rp)
		await ctx.frame()
		return {"saved": rp}
	if root.scene_file_path == "":
		return U.err("The scene has never been saved.", "Pass 'path' to save it as a new file.")
	ctx.before_write([root.scene_file_path])
	var err := EditorInterface.save_scene()
	return {"saved": root.scene_file_path, "ok": err == OK}


func a_save_all(_p: Dictionary):
	ctx.before_write(EditorInterface.get_open_scenes())
	EditorInterface.save_all_scenes()
	return {"saved": EditorInterface.get_open_scenes()}


func a_close(p: Dictionary):
	if p.has("path"):
		var r = await ensure_scene(U.p_str(p, "path"))
		if U.is_err(r): return r
	var root: Node = ctx.edited_root()
	if root == null:
		return U.err("No scene is open.")
	var path := root.scene_file_path
	if U.p_bool(p, "save", true) and path != "":
		ctx.before_write([path])
		EditorInterface.save_scene()
	EditorInterface.close_scene()
	await ctx.frame()
	return {"closed": path}


func a_reload(p: Dictionary):
	var root: Node = ctx.edited_root()
	var path := U.res_path(U.p_str(p, "path", root.scene_file_path if root else ""))
	if path == "":
		return U.err("No scene to reload.")
	EditorInterface.reload_scene_from_path(path)
	await ctx.frame()
	return {"reloaded": path}


func a_tree(p: Dictionary):
	if p.has("scene") and U.p_str(p, "scene") != "":
		var sp := U.res_path(U.p_str(p, "scene"))
		var root_now: Node = ctx.edited_root()
		if not (root_now and root_now.scene_file_path == sp) and not U.p_bool(p, "open", false):
			# Read a scene without switching the editor's tab.
			if not ResourceLoader.exists(sp):
				return U.err("Scene '%s' does not exist." % sp)
			var packed: PackedScene = load(sp)
			var inst := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			var t := U.node_tree(inst, inst, _tree_opts(p))
			inst.free()
			return {"scene": sp, "tree": t, "note": "Read from disk (scene not open in the editor)."}
		var r = await ensure_scene(sp)
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var start: Node = root
	if p.has("path") and U.p_str(p, "path") not in ["", "."]:
		start = ctx.find_node(U.p_str(p, "path"))
		if start == null:
			return ctx.node_not_found(U.p_str(p, "path"))
	var tree := U.node_tree(start, root, _tree_opts(p))
	return {"scene": root.scene_file_path, "tree": tree}


func _tree_opts(p: Dictionary) -> Dictionary:
	return {"depth": U.p_int(p, "depth", 12), "props": U.p_bool(p, "props", false), "max_nodes": U.p_int(p, "max_nodes", 400), "expand_instances": U.p_bool(p, "expand_instances", false), "owned_only": true}


## Instances a PackedScene as a child in the edited scene.
func a_instance(p: Dictionary):
	var e = U.require(p, ["scene_path"])
	if e: return e
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var sp := U.res_path(U.p_str(p, "scene_path"))
	if not ResourceLoader.exists(sp):
		return U.err("Scene '%s' does not exist." % sp)
	if sp == root.scene_file_path:
		return U.err("Cannot instance a scene inside itself.")
	var parent: Node = ctx.find_node(U.p_str(p, "parent", "."))
	if parent == null:
		return ctx.node_not_found(U.p_str(p, "parent"))
	var packed: PackedScene = load(sp)
	var inst := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if p.has("name"):
		inst.name = U.p_str(p, "name")
	if p.has("props"):
		var pr = U.apply_props(inst, U.p_dict(p, "props"))
		if U.is_err(pr):
			inst.free()
			return pr
	var u = ctx.begin("Instance " + sp.get_file())
	u.add_do_method(parent, "add_child", inst, true)
	u.add_do_method(inst, "set_owner", root)
	u.add_do_reference(inst)
	u.add_undo_method(parent, "remove_child", inst)
	ctx.commit()
	return {"path": ctx.node_path_str(inst), "instance_of": sp, "type": inst.get_class()}


## Saves a node branch as its own scene file and replaces it with an instance.
func a_pack_branch(p: Dictionary):
	var e = U.require(p, ["path", "save_path"])
	if e: return e
	var n = await node_arg(p)
	if U.is_err(n): return n
	var root: Node = ctx.edited_root()
	if n == root:
		return U.err("Cannot pack the scene root; use scene.save with a path instead.")
	var save_path := U.res_path(U.p_str(p, "save_path"))
	if not save_path.ends_with(".tscn"):
		save_path += ".tscn"
	var copy: Node = n.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	_set_owner_rec(copy, copy)
	if copy is Node2D:
		copy.position = Vector2.ZERO
	elif copy is Node3D:
		copy.position = Vector3.ZERO
	var packed := PackedScene.new()
	packed.pack(copy)
	copy.free()
	ctx.before_write([save_path])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
	if ResourceSaver.save(packed, save_path) != OK:
		return U.err("Failed to save '%s'." % save_path)
	ctx.fs().update_file(save_path)
	await ctx.wait_fs()
	var loaded: PackedScene = load(save_path)
	var inst := loaded.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	inst.name = n.name
	if n is Node2D:
		inst.transform = n.transform
	elif n is Node3D:
		inst.transform = n.transform
	var parent := n.get_parent()
	var idx := n.get_index()
	var u = ctx.begin("Pack branch as scene")
	u.add_do_method(parent, "remove_child", n)
	u.add_do_method(parent, "add_child", inst, true)
	u.add_do_method(parent, "move_child", inst, idx)
	u.add_do_method(inst, "set_owner", root)
	u.add_do_reference(inst)
	u.add_undo_method(parent, "remove_child", inst)
	u.add_undo_method(parent, "add_child", n, true)
	u.add_undo_method(parent, "move_child", n, idx)
	u.add_undo_method(self, "_set_owner_rec", n, root)
	u.add_undo_reference(n)
	ctx.commit()
	return {"saved": save_path, "replaced": ctx.node_path_str(inst)}


func _set_owner_rec(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			_set_owner_rec(c, owner)


## Returns the raw .tscn text (useful to review exactly what will be committed).
func a_source(p: Dictionary):
	var root: Node = ctx.edited_root()
	var path := U.res_path(U.p_str(p, "path", root.scene_file_path if root else ""))
	if path == "" or not FileAccess.file_exists(path):
		return U.err("Scene file not found.")
	return {"path": path, "content": FileAccess.get_file_as_string(path)}


## Lists every scene in the project with its root type (quick project overview).
func a_list(p: Dictionary):
	var files := []
	ctx.router.handlers["files"]._walk(U.res_path(U.p_str(p, "path", "res://")), true, "*.tscn", false, files, [], 2000)
	var out := []
	for f in files:
		var entry := {"path": f.path}
		var fa := FileAccess.open(f.path, FileAccess.READ)
		if fa:
			for i in 40:
				if fa.eof_reached():
					break
				var line := fa.get_line()
				if line.begins_with("[node ") and not line.contains("parent="):
					var rx := RegEx.create_from_string("name=\"([^\"]+)\"(?: type=\"([^\"]+)\")?")
					var m := rx.search(line)
					if m:
						entry["root"] = m.get_string(1)
						entry["type"] = m.get_string(2) if m.get_string(2) != "" else "(instance/inherited)"
					break
		out.append(entry)
	return {"scenes": out, "main_scene": ProjectSettings.get_setting("application/run/main_scene", "")}
