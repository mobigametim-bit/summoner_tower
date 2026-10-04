@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Node editing inside the edited scene. Every mutation goes through EditorUndoRedoManager.


## Adds a node (or a whole subtree via "children") to the edited scene.
## type: class name ("Sprite2D"), global script class ("Player"), "res://x.gd" or "res://x.tscn".
func a_add(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var parent: Node = ctx.find_node(U.p_str(p, "parent", "."))
	if parent == null:
		return ctx.node_not_found(U.p_str(p, "parent"))
	var specs: Array = U.p_arr(p, "nodes") if p.has("nodes") else [p]
	var created := []
	var u = ctx.begin("Add node" if specs.size() == 1 else "Add %d nodes" % specs.size())
	for spec in specs:
		var n = build(spec)
		if U.is_err(n):
			for c in created:
				c.node.free()
			u.commit_action(false)
			return n
		created.append({"node": n, "spec": spec})
	for item in created:
		var n: Node = item.node
		u.add_do_method(parent, "add_child", n, true)
		if item.spec.has("index"):
			u.add_do_method(parent, "move_child", n, int(item.spec.index))
		u.add_do_method(self, "set_owner_rec", n, root)
		u.add_do_reference(n)
		u.add_undo_method(parent, "remove_child", n)
	ctx.commit()
	var out := []
	for item in created:
		var n2: Node = item.node
		var info := {"path": ctx.node_path_str(n2), "type": n2.get_class()}
		var warnings := configuration_warnings(n2)
		if not warnings.is_empty():
			info["warnings"] = warnings
		out.append(info)
	return out[0] if out.size() == 1 else {"added": out}


## Builds a detached node from a spec {type, name, props, script, groups, children}.
func build(spec: Dictionary):
	var type := U.p_str(spec, "type", "Node")
	var n: Node = null
	if type.ends_with(".tscn") or type.ends_with(".scn"):
		var sp := U.res_path(type)
		if not ResourceLoader.exists(sp):
			return U.err("Scene '%s' does not exist." % sp)
		n = (load(sp) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	else:
		n = ctx.router.handlers["scene"]._instantiate_type(type if not type.ends_with(".gd") else U.res_path(type))
		if n == null:
			return ctx.router.handlers["scene"]._bad_type(type)
	if spec.has("name"):
		n.name = U.p_str(spec, "name")
	else:
		n.name = type.get_file().get_basename() if type.contains("/") else type
	if spec.has("script"):
		var scp := U.res_path(U.p_str(spec, "script"))
		if not ResourceLoader.exists(scp):
			n.free()
			return U.err("Script '%s' does not exist." % scp)
		n.set_script(load(scp))
	if spec.has("props"):
		var pr = U.apply_props(n, U.p_dict(spec, "props"))
		if U.is_err(pr):
			n.free()
			pr["message"] = "%s (on new %s '%s')" % [pr.message, type, spec.get("name", type)]
			return pr
	for g in U.p_arr(spec, "groups"):
		n.add_to_group(str(g), true)
	for child_spec in U.p_arr(spec, "children"):
		if not (child_spec is Dictionary):
			continue
		var c = build(child_spec)
		if U.is_err(c):
			n.free()
			return c
		n.add_child(c, true)
	return n


func set_owner_rec(n: Node, owner: Node) -> void:
	n.owner = owner
	if n.scene_file_path != "" and n != owner:
		return  # children of an instanced scene belong to that scene
	for c in n.get_children():
		set_owner_rec(c, owner)


## Common setup mistakes (the engine's own configuration warnings aren't script accessible).
func configuration_warnings(n: Node, recursive: bool = true) -> Array:
	var out := []
	_warn(n, out, recursive, 0)
	return out


func _warn(n: Node, out: Array, recursive: bool, depth: int) -> void:
	var label := ctx.node_path_str(n) if n.is_inside_tree() else str(n.name)
	if n is CollisionObject2D or n is CollisionObject3D:
		var has_shape := false
		for c in n.get_children():
			if c is CollisionShape2D or c is CollisionPolygon2D or c is CollisionShape3D or c is CollisionPolygon3D:
				has_shape = true
		if not has_shape:
			out.append("%s: %s has no CollisionShape child, so it won't collide or detect anything." % [label, n.get_class()])
	if n is CollisionShape2D or n is CollisionShape3D:
		if n.shape == null:
			out.append("%s: CollisionShape has no shape; set 'shape' e.g. {\"type\": \"RectangleShape2D\", \"size\": [32, 32]}." % label)
		var par := n.get_parent()
		if par and not (par is CollisionObject2D or par is CollisionObject3D):
			out.append("%s: CollisionShape must be a direct child of a physics body or Area." % label)
	if n is Sprite2D and n.texture == null:
		out.append("%s: Sprite2D has no texture." % label)
	if n is AnimatedSprite2D and n.sprite_frames == null:
		out.append("%s: AnimatedSprite2D has no sprite_frames." % label)
	if n is Sprite3D and n.texture == null:
		out.append("%s: Sprite3D has no texture." % label)
	if n is MeshInstance3D and n.mesh == null:
		out.append("%s: MeshInstance3D has no mesh." % label)
	if n is AnimationTree and str(n.anim_player) == "":
		out.append("%s: AnimationTree needs anim_player set to an AnimationPlayer path." % label)
	if n.is_class("TileMapLayer") and n.get("tile_set") == null:
		out.append("%s: TileMapLayer has no tile_set." % label)
	if n is Camera3D or n is Camera2D:
		pass
	var scr = n.get_script()
	if scr and scr is Script and scr.is_tool() and n.has_method("_get_configuration_warnings"):
		for w in n._get_configuration_warnings():
			out.append("%s: %s" % [label, w])
	if recursive and depth < 6:
		for c in n.get_children():
			_warn(c, out, recursive, depth + 1)


func a_delete(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var paths: Array = U.p_arr(p, "paths") if p.has("paths") else [U.p_str(p, "path")]
	var nodes := []
	for path in paths:
		var n: Node = ctx.find_node(str(path))
		if n == null:
			return ctx.node_not_found(str(path))
		if n == root:
			return U.err("Cannot delete the scene root.", "Create a new scene or change the root with node.change_type.")
		nodes.append(n)
	var u = ctx.begin("Delete %d node(s)" % nodes.size())
	for n in nodes:
		var parent: Node = n.get_parent()
		u.add_do_method(parent, "remove_child", n)
		u.add_undo_method(parent, "add_child", n, true)
		u.add_undo_method(parent, "move_child", n, n.get_index())
		u.add_undo_method(self, "set_owner_rec", n, root)
		u.add_undo_reference(n)
	ctx.commit()
	return {"deleted": paths}


func a_duplicate(p: Dictionary):
	var n = await node_arg(p)
	if U.is_err(n): return n
	var root: Node = ctx.edited_root()
	if n == root:
		return U.err("Cannot duplicate the scene root.")
	var count := maxi(1, U.p_int(p, "count", 1))
	var parent: Node = ctx.find_node(U.p_str(p, "parent")) if p.has("parent") else n.get_parent()
	if parent == null:
		return ctx.node_not_found(U.p_str(p, "parent"))
	var offset = p.get("offset", null)
	var u = ctx.begin("Duplicate node")
	var out := []
	for i in count:
		# Instanced scenes bring their own internal connections; copying signals would duplicate them.
		var flags := Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION
		if n.scene_file_path == "":
			flags |= Node.DUPLICATE_SIGNALS
		var d: Node = n.duplicate(flags)
		if p.has("name"):
			d.name = U.p_str(p, "name") if count == 1 else "%s%d" % [U.p_str(p, "name"), i + 1]
		if offset != null:
			if d is Node2D:
				d.position += U.to_vector(offset, TYPE_VECTOR2) * (i + 1)
			elif d is Node3D:
				d.position += U.to_vector(offset, TYPE_VECTOR3) * (i + 1)
			elif d is Control:
				d.position += U.to_vector(offset, TYPE_VECTOR2) * (i + 1)
		u.add_do_method(parent, "add_child", d, true)
		u.add_do_method(self, "set_owner_rec", d, root)
		u.add_do_reference(d)
		u.add_undo_method(parent, "remove_child", d)
		out.append(d)
	ctx.commit()
	return {"created": out.map(func(x): return ctx.node_path_str(x))}


## Moves a node under a new parent and/or to a new index.
func a_move(p: Dictionary):
	var n = await node_arg(p)
	if U.is_err(n): return n
	var root: Node = ctx.edited_root()
	if n == root:
		return U.err("Cannot move the scene root.")
	var old_parent := n.get_parent()
	var old_index := n.get_index()
	var new_parent: Node = ctx.find_node(U.p_str(p, "new_parent")) if p.has("new_parent") else old_parent
	if new_parent == null:
		return ctx.node_not_found(U.p_str(p, "new_parent"))
	if new_parent == n or n.is_ancestor_of(new_parent):
		return U.err("Cannot move a node under itself.")
	var keep := U.p_bool(p, "keep_global_transform", true)
	var u = ctx.begin("Move node")
	if new_parent != old_parent:
		u.add_do_method(n, "reparent", new_parent, keep)
		u.add_do_method(self, "set_owner_rec", n, root)
		u.add_undo_method(n, "reparent", old_parent, keep)
		u.add_undo_method(old_parent, "move_child", n, old_index)
		u.add_undo_method(self, "set_owner_rec", n, root)
	if p.has("index"):
		u.add_do_method(new_parent, "move_child", n, U.p_int(p, "index"))
		if new_parent == old_parent:
			u.add_undo_method(old_parent, "move_child", n, old_index)
	ctx.commit()
	return {"path": ctx.node_path_str(n), "index": n.get_index()}


func a_rename(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var n = await node_arg(p)
	if U.is_err(n): return n
	var new_name := U.p_str(p, "name")
	if not new_name.validate_node_name() == new_name:
		return U.err("Invalid node name '%s'." % new_name, "Names cannot contain . : @ / \" %%")
	var u = ctx.begin("Rename node")
	u.add_do_property(n, "name", new_name)
	u.add_undo_property(n, "name", n.name)
	ctx.commit()
	return {"path": ctx.node_path_str(n)}


## Reads node info. With props=[...] returns just those; otherwise all non-default props.
func a_get(p: Dictionary):
	var n = await node_arg(p)
	if U.is_err(n): return n
	var out := {"path": ctx.node_path_str(n), "type": n.get_class(), "name": str(n.name)}
	var inherits := []
	var c := n.get_class()
	while c != "" and c != "Object":
		inherits.append(c)
		c = ClassDB.get_parent_class(c)
	out["inherits"] = inherits
	var scr: Script = n.get_script()
	if scr:
		out["script"] = scr.resource_path
	if n.scene_file_path != "" and n != ctx.edited_root():
		out["instance"] = n.scene_file_path
	var props := U.p_arr(p, "props")
	if props.is_empty():
		out["props"] = U.changed_props(n, U.p_bool(p, "all", false))
	else:
		var vals := {}
		for prop in props:
			vals[prop] = U.encode(n.get_indexed(NodePath(str(prop))))
		out["props"] = vals
	var groups := []
	for g in n.get_groups():
		if not str(g).begins_with("_"):
			groups.append(str(g))
	out["groups"] = groups
	out["children"] = n.get_children().map(func(ch): return "%s (%s)" % [ch.name, ch.get_class()])
	var conns := []
	for sig in n.get_signal_list():
		for conn in n.get_signal_connection_list(sig.name):
			if conn.flags & CONNECT_PERSIST:
				conns.append({"signal": sig.name, "to": ctx.node_path_str(conn.callable.get_object()) if conn.callable.get_object() is Node else str(conn.callable.get_object()), "method": conn.callable.get_method()})
	if not conns.is_empty():
		out["connections"] = conns
	var warnings := configuration_warnings(n)
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


## Sets properties on one or more nodes: {path|paths, props: {name: value}}.
## Values are coerced: "#ff0000", [x, y], "Vector2(1, 2)", "res://tex.png", {"type": "CircleShape2D", "radius": 8}.
func a_set(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var props := U.p_dict(p, "props")
	if props.is_empty() and p.has("property"):
		props = {U.p_str(p, "property"): p.get("value")}
	if props.is_empty():
		return U.err("Provide 'props': {name: value}.")
	var paths: Array = U.p_arr(p, "paths") if p.has("paths") else [U.p_str(p, "path", ".")]
	var nodes := []
	for path in paths:
		var n: Node = ctx.find_node(str(path))
		if n == null:
			return ctx.node_not_found(str(path))
		nodes.append(n)
	# Validate & coerce everything first so a bad value doesn't leave a half-applied action.
	var plan := []
	for n in nodes:
		var infos := U.prop_infos(n)
		for key in props:
			var base_key := str(key).split(":")[0]
			if not infos.has(base_key):
				var s := U.suggest(base_key, infos.keys())
				return U.err("Property '%s' not found on %s ('%s')." % [base_key, n.get_class(), n.name], ("Did you mean '%s'? " % s if s != "" else "") + "Use introspect.class '%s' to list properties." % n.get_class())
			var val
			if str(key).contains(":"):
				val = U._auto(props[key])
			else:
				var pi: Dictionary = infos[base_key]
				val = U.coerce(props[key], pi.type, pi.hint, pi.hint_string)
				if U.is_err(val):
					val["message"] = "%s: %s" % [key, val.message]
					return val
			plan.append([n, str(key), val])
	var u = ctx.begin("Set %s" % ", ".join(props.keys()))
	for item in plan:
		var n: Node = item[0]
		var key: String = item[1]
		if key.contains(":"):
			u.add_do_method(n, "set_indexed", NodePath(key), item[2])
			u.add_undo_method(n, "set_indexed", NodePath(key), n.get_indexed(NodePath(key)))
		else:
			u.add_do_property(n, key, item[2])
			u.add_undo_property(n, key, n.get(key))
	ctx.commit()
	var result := {}
	for n in nodes:
		var vals := {}
		for key in props:
			vals[key] = U.encode(n.get_indexed(NodePath(str(key))))
		result[ctx.node_path_str(n)] = vals
	return {"set": result}


## Calls a method on a node in the editor (e.g. Path2D curve helpers, @tool methods).
func a_call(p: Dictionary):
	var e = U.require(p, ["method"])
	if e: return e
	var n = await node_arg(p)
	if U.is_err(n): return n
	var target: Object = n
	if p.has("property"):
		target = n.get(U.p_str(p, "property"))
		if not (target is Object):
			return U.err("Property '%s' is not an object." % U.p_str(p, "property"))
	var method := U.p_str(p, "method")
	if not target.has_method(method):
		var names := target.get_method_list().map(func(m): return m.name)
		var s := U.suggest(method, names)
		return U.err("%s has no method '%s'." % [target.get_class(), method], "Did you mean '%s'?" % s if s != "" else "")
	var args := []
	for a in U.p_arr(p, "args"):
		args.append(U._auto(a))
	ctx.before_write()
	var r = target.callv(method, args)
	ctx.mark_dirty()
	EditorInterface.mark_scene_as_unsaved()
	return {"result": U.encode(r)}


## Finds nodes in the edited scene by name pattern, type, group or script.
func a_find(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var under: Node = ctx.find_node(U.p_str(p, "under", "."))
	if under == null:
		return ctx.node_not_found(U.p_str(p, "under"))
	var pattern := U.p_str(p, "name", "*")
	if not pattern.contains("*") and not pattern.contains("?"):
		pattern = "*" + pattern + "*"
	var type := U.p_str(p, "type", "")
	var group := U.p_str(p, "group", "")
	var script := U.p_str(p, "script", "")
	var out := []
	var stack: Array = [under]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var ok := str(n.name).matchn(pattern)
		if ok and type != "":
			ok = n.is_class(type) or (n.get_script() and n.get_script().get_global_name() == type)
		if ok and group != "":
			ok = n.is_in_group(group)
		if ok and script != "":
			ok = n.get_script() != null and n.get_script().resource_path.contains(script)
		if ok and n != under:
			out.append({"path": ctx.node_path_str(n), "type": n.get_class()})
		if out.size() >= U.p_int(p, "limit", 200):
			break
		var kids := n.get_children()
		kids.reverse()
		for c in kids:
			if c.owner == root or c == root or n.scene_file_path == "" or n == root:
				stack.append(c)
	return {"matches": out}


func a_add_to_group(p: Dictionary):
	var e = U.require(p, ["group"])
	if e: return e
	var n = await node_arg(p)
	if U.is_err(n): return n
	var g := U.p_str(p, "group")
	var u = ctx.begin("Add to group " + g)
	u.add_do_method(n, "add_to_group", g, true)
	u.add_undo_method(n, "remove_from_group", g)
	ctx.commit()
	return {"path": ctx.node_path_str(n), "group": g}


func a_remove_from_group(p: Dictionary):
	var e = U.require(p, ["group"])
	if e: return e
	var n = await node_arg(p)
	if U.is_err(n): return n
	var g := U.p_str(p, "group")
	var u = ctx.begin("Remove from group " + g)
	u.add_do_method(n, "remove_from_group", g)
	u.add_undo_method(n, "add_to_group", g, true)
	ctx.commit()
	return {"path": ctx.node_path_str(n), "group": g}


## Replaces a node with a node of another type, keeping name, children and compatible props.
func a_change_type(p: Dictionary):
	var e = U.require(p, ["type"])
	if e: return e
	var n = await node_arg(p)
	if U.is_err(n): return n
	var type := U.p_str(p, "type")
	var root: Node = ctx.edited_root()
	if n == root:
		return await _change_root_type(root, type)
	var nn: Node = ctx.router.handlers["scene"]._instantiate_type(type)
	if nn == null:
		return ctx.router.handlers["scene"]._bad_type(type)
	var new_infos := U.prop_infos(nn)
	var copied := []
	for pi in n.get_property_list():
		if not (pi.usage & PROPERTY_USAGE_STORAGE) or pi.name in ["script", "owner"]:
			continue
		if new_infos.has(pi.name) and new_infos[pi.name].type == pi.type:
			nn.set(pi.name, n.get(pi.name))
			copied.append(pi.name)
	nn.name = n.name
	var scr = n.get_script()
	if scr and U.p_bool(p, "keep_script", false):
		nn.set_script(scr)
	var u = ctx.begin("Change type to " + type)
	u.add_do_method(n, "replace_by", nn, true)
	u.add_do_method(self, "set_owner_rec", nn, root)
	u.add_undo_method(nn, "replace_by", n, true)
	u.add_undo_method(self, "set_owner_rec", n, root)
	u.add_do_reference(nn)
	u.add_undo_reference(n)
	ctx.commit()
	return {"path": ctx.node_path_str(nn), "type": nn.get_class(), "copied_props": copied.size()}


## The scene root can't be swapped in place, so rewrite the root entry of the .tscn and reload.
func _change_root_type(root: Node, type: String):
	if not ClassDB.class_exists(type) or not ClassDB.is_parent_class(type, "Node"):
		return U.err("Root type must be a built-in Node class, got '%s'." % type, "To use a script class, change to its base type and attach the script with script.attach.")
	var path := root.scene_file_path
	if path == "":
		return U.err("Save the scene first (scene.save with a path).")
	ctx.before_write([path])
	EditorInterface.save_scene()
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var rx := RegEx.create_from_string("^\\[node name=\"([^\"]+)\" type=\"([^\"]+)\"")
	var changed := false
	for i in lines.size():
		var line: String = lines[i]
		if line.begins_with("[node ") and not line.contains(" parent="):
			var m := rx.search(line)
			if m == null:
				return U.err("The root is an inherited/instanced scene; its type comes from the base scene.")
			lines[i] = line.replace('type="%s"' % m.get_string(2), 'type="%s"' % type)
			changed = true
			break
	if not changed:
		return U.err("Could not find the root node entry in %s." % path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	EditorInterface.reload_scene_from_path(path)
	await ctx.frame()
	var new_root: Node = ctx.edited_root()
	return {"path": ".", "type": new_root.get_class() if new_root else type, "note": "Root type changed by rewriting the scene file; properties that don't exist on %s were dropped on reload." % type}


## Selects nodes in the editor (and optionally focuses the inspector on the first one).
func a_select(p: Dictionary):
	var sel := EditorInterface.get_selection()
	sel.clear()
	var paths: Array = U.p_arr(p, "paths") if p.has("paths") else [U.p_str(p, "path", ".")]
	var done := []
	for path in paths:
		var n: Node = ctx.find_node(str(path))
		if n:
			sel.add_node(n)
			done.append(ctx.node_path_str(n))
	if not done.is_empty():
		EditorInterface.edit_node(ctx.find_node(str(paths[0])))
	return {"selected": done}


func a_selection(_p: Dictionary):
	var out := []
	for n in EditorInterface.get_selection().get_selected_nodes():
		out.append({"path": ctx.node_path_str(n), "type": n.get_class()})
	return {"selected": out}
