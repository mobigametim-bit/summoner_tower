@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Signals: list, connect (with optional handler stub generation), disconnect, project graph.


func a_list(p: Dictionary):
	var n = await node_arg(p)
	if U.is_err(n): return n
	var out := []
	var only_connected := U.p_bool(p, "connected_only", false)
	for sig in n.get_signal_list():
		var conns := []
		for c in n.get_signal_connection_list(sig.name):
			var target = c.callable.get_object()
			conns.append({"to": ctx.node_path_str(target) if target is Node else str(target), "method": c.callable.get_method(), "persistent": bool(c.flags & CONNECT_PERSIST)})
		if only_connected and conns.is_empty():
			continue
		var args := []
		for a in sig.args:
			args.append("%s: %s" % [a.name, type_string(a.type) if a.type != TYPE_OBJECT else (a.class_name if a.class_name != "" else "Object")])
		var entry := {"signal": sig.name, "args": ", ".join(args)}
		if not conns.is_empty():
			entry["connections"] = conns
		out.append(entry)
	return {"node": ctx.node_path_str(n), "signals": out}


## Connects from.signal -> to.method persistently (saved in the scene). If the target's script
## lacks the method and create_method is true (default), a handler stub is appended.
func a_connect(p: Dictionary):
	var e = U.require(p, ["from", "signal", "to"])
	if e: return e
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var src: Node = ctx.find_node(U.p_str(p, "from"))
	if src == null: return ctx.node_not_found(U.p_str(p, "from"))
	var dst: Node = ctx.find_node(U.p_str(p, "to"))
	if dst == null: return ctx.node_not_found(U.p_str(p, "to"))
	var sig := U.p_str(p, "signal")
	if not src.has_signal(sig):
		var names := src.get_signal_list().map(func(s): return s.name)
		var s := U.suggest(sig, names)
		return U.err("%s has no signal '%s'." % [src.get_class(), sig], ("Did you mean '%s'? " % s if s != "" else "") + "Signals: " + ", ".join(names.slice(0, 40)))
	var method := U.p_str(p, "method", "_on_%s_%s" % [str(src.name).to_snake_case(), sig])
	var created_stub := false
	if not dst.has_method(method):
		if not U.p_bool(p, "create_method", true):
			return U.err("Target '%s' has no method '%s'." % [dst.name, method], "Pass create_method=true to generate a stub, or add it to the script.")
		var scr: Script = dst.get_script()
		if scr == null or not (scr is GDScript):
			return U.err("Target '%s' has no GDScript to add '%s' to." % [dst.name, method], "Attach a script first (script.create with attach_to).")
		var sig_info := {}
		for s2 in src.get_signal_list():
			if s2.name == sig:
				sig_info = s2
		var args := []
		for a in sig_info.get("args", []):
			var t: String = type_string(a.type) if a.type != TYPE_OBJECT else (a.class_name if a.class_name != "" else "Object")
			args.append("%s: %s" % [a.name, t] if a.type != TYPE_NIL else a.name)
		var binds := U.p_arr(p, "binds")
		for i in binds.size():
			args.append("extra_arg_%d" % i)
		var body := U.p_str(p, "body", "pass")
		var body_lines := ""
		for line in body.split("\n"):
			body_lines += "\t" + line + "\n"
		var stub := "\n\nfunc %s(%s) -> void:\n%s" % [method, ", ".join(args), body_lines]
		var path := scr.resource_path
		var text := FileAccess.get_file_as_string(path).rstrip("\n") + stub
		var wr = await ctx.router.handlers["files"].write_text(path, text)
		if U.is_err(wr): return wr
		created_stub = true
	var flags := CONNECT_PERSIST
	if U.p_bool(p, "deferred", false): flags |= CONNECT_DEFERRED
	if U.p_bool(p, "one_shot", false): flags |= CONNECT_ONE_SHOT
	var callable := Callable(dst, method)
	var binds2 := U.p_arr(p, "binds")
	if not binds2.is_empty():
		callable = callable.bindv(binds2.map(func(b): return U._auto(b)))
	if src.is_connected(sig, callable):
		return {"already_connected": true, "from": ctx.node_path_str(src), "signal": sig, "to": ctx.node_path_str(dst), "method": method}
	var u = ctx.begin("Connect %s.%s" % [src.name, sig])
	u.add_do_method(src, "connect", sig, callable, flags)
	u.add_undo_method(src, "disconnect", sig, callable)
	ctx.commit()
	return {"from": ctx.node_path_str(src), "signal": sig, "to": ctx.node_path_str(dst), "method": method, "created_stub": created_stub}


func a_disconnect(p: Dictionary):
	var e = U.require(p, ["from", "signal", "to", "method"])
	if e: return e
	var src: Node = ctx.find_node(U.p_str(p, "from"))
	if src == null: return ctx.node_not_found(U.p_str(p, "from"))
	var dst: Node = ctx.find_node(U.p_str(p, "to"))
	if dst == null: return ctx.node_not_found(U.p_str(p, "to"))
	var sig := U.p_str(p, "signal")
	for c in src.get_signal_connection_list(sig):
		if c.callable.get_object() == dst and c.callable.get_method() == U.p_str(p, "method"):
			var u = ctx.begin("Disconnect %s.%s" % [src.name, sig])
			u.add_do_method(src, "disconnect", sig, c.callable)
			u.add_undo_method(src, "connect", sig, c.callable, c.flags)
			ctx.commit()
			return {"disconnected": true}
	return U.err("No such connection.")


## Connection graph: for the edited scene (live) or for every scene + script in the project.
func a_graph(p: Dictionary):
	if U.p_str(p, "scope", "scene") == "project":
		return _project_graph()
	var root = root_or_err()
	if U.is_err(root): return root
	var edges := []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for sig in n.get_signal_list():
			for c in n.get_signal_connection_list(sig.name):
				if c.flags & CONNECT_PERSIST:
					var t = c.callable.get_object()
					edges.append({"from": ctx.node_path_str(n), "signal": sig.name, "to": ctx.node_path_str(t) if t is Node else str(t), "method": c.callable.get_method()})
		for ch in n.get_children():
			stack.append(ch)
	return {"scene": root.scene_file_path, "connections": edges}


func _project_graph():
	var files := []
	ctx.router.handlers["files"]._walk("res://", true, "", false, files, [], 5000)
	var scene_edges := []
	var code_edges := []
	var emits := []
	var rx_conn := RegEx.create_from_string("\\[connection signal=\"([^\"]+)\" from=\"([^\"]*)\" to=\"([^\"]*)\" method=\"([^\"]+)\"")
	var rx_code := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_\\.\\$%/]*)\\.([a-z_][a-z0-9_]*)\\.connect\\(([^)]*)\\)")
	var rx_emit := RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_\\.]*\\.)?([a-z_][a-z0-9_]*)\\.emit\\(")
	for f in files:
		var path: String = f.path
		if path.ends_with(".tscn"):
			for m in rx_conn.search_all(FileAccess.get_file_as_string(path)):
				scene_edges.append({"scene": path, "signal": m.get_string(1), "from": m.get_string(2), "to": m.get_string(3), "method": m.get_string(4)})
		elif path.ends_with(".gd"):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				for m in rx_code.search_all(lines[i]):
					code_edges.append({"script": path, "line": i + 1, "source": m.get_string(1), "signal": m.get_string(2), "handler": m.get_string(3).strip_edges()})
				for m2 in rx_emit.search_all(lines[i]):
					emits.append({"script": path, "line": i + 1, "signal": (m2.get_string(1) + m2.get_string(2))})
	return {"scene_connections": scene_edges, "code_connections": code_edges, "emits": emits}
