@tool
extends RefCounted
## Routes "domain.action" requests to handler objects. A handler exposes actions as
## methods named `a_<action>(params: Dictionary)`. Handlers may be coroutines.

const U = preload("res://addons/godot_forge/core/util.gd")

var ctx
var handlers := {}


func _init(p_ctx) -> void:
	ctx = p_ctx


func register(domain: String, handler) -> void:
	handler.ctx = ctx
	handlers[domain] = handler


func hello_info() -> Dictionary:
	var v := Engine.get_version_info()
	return {
		"plugin_version": ctx.PLUGIN_VERSION,
		"godot_version": "%d.%d.%d" % [v.major, v.minor, v.patch],
		"godot_version_full": v.string,
		"project_name": str(ProjectSettings.get_setting("application/config/name", "")),
		"project_path": ProjectSettings.globalize_path("res://").trim_suffix("/"),
		"headless": DisplayServer.get_name() == "headless",
		"dotnet": ClassDB.class_exists("CSharpScript"),
		"domains": describe(),
	}


func describe() -> Dictionary:
	var out := {}
	for domain in handlers:
		var actions := []
		for m in handlers[domain].get_method_list():
			var n: String = m.name
			if n.begins_with("a_"):
				actions.append(n.substr(2))
		actions.sort()
		out[domain] = actions
	return out


func dispatch(method: String, params: Dictionary):
	if method == "ping":
		return {"pong": true, "time": Time.get_unix_time_from_system()}
	if method == "describe":
		return describe()
	if method == "batch":
		return await _batch(params)
	var result = await _call(method, params)
	await ctx.flush_after_request()
	ctx.record_activity(method, params, result)
	return result


func _call(method: String, params: Dictionary):
	var dot := method.find(".")
	if dot < 0:
		return U.err("Malformed method '%s'. Expected 'domain.action'." % method)
	var domain := method.substr(0, dot)
	var action := method.substr(dot + 1)
	var h = handlers.get(domain)
	if h == null:
		var s := U.suggest(domain, handlers.keys())
		return U.err("Unknown domain '%s'." % domain, ("Did you mean '%s'? " % s if s != "" else "") + "Domains: " + ", ".join(handlers.keys()))
	var fn := "a_" + action
	if not h.has_method(fn):
		var names := []
		for m in h.get_method_list():
			if str(m.name).begins_with("a_"):
				names.append(str(m.name).substr(2))
		var s2 := U.suggest(action, names)
		return U.err("Unknown action '%s.%s'." % [domain, action], ("Did you mean '%s'? " % s2 if s2 != "" else "") + "Actions: " + ", ".join(names))
	ctx.current_method = method
	ctx.last_method = method
	ctx.flush_logs()
	var before: int = ctx.log_seq()
	var result = await h.call(fn, params)
	ctx.current_method = ""
	if result == null:
		ctx.flush_logs()
		for e in ctx.get_logs(before, "editor", "error", 20):
			var where := str(e.get("script_file", e.get("file", "")))
			if where.begins_with("res://addons/godot_forge/"):
				return U.err("Godot Forge hit an internal error in %s: %s" % [method, e.get("message", "")], "This is a bug in Godot Forge (%s:%s). Try another way (e.g. exec.editor) and report it." % [where, e.get("script_line", e.get("line", 0))])
	return result


## Runs several operations in order. With atomic=true, stops at the first error and undoes
## every editor action that the batch committed.
func _batch(params: Dictionary):
	var ops: Array = U.p_arr(params, "operations")
	var atomic := U.p_bool(params, "atomic", true)
	var results := []
	var start_marker: int = ctx.begin_batch()
	var failed := false
	for i in ops.size():
		var op = ops[i]
		if not (op is Dictionary) or not op.has("method"):
			results.append({"index": i, "error": {"message": "Each operation needs 'method' and optional 'params'."}})
			failed = true
			break
		var op_params = op.get("params", {})
		var r = await _call(str(op.method), op_params if op_params is Dictionary else {})
		if U.is_err(r):
			var e: Dictionary = r.duplicate()
			e.erase("__forge_error")
			results.append({"index": i, "method": op.method, "error": e})
			failed = true
			if atomic:
				break
		else:
			results.append({"index": i, "method": op.method, "result": U.encode(r)})
	var rolled_back := false
	if failed and atomic:
		rolled_back = ctx.rollback_batch(start_marker)
	ctx.end_batch()
	await ctx.flush_after_request()
	ctx.record_activity("batch.run", {"name": "%d operations" % ops.size()}, null if not failed else U.err("batch failed"))
	return {"ok": not failed, "rolled_back": rolled_back, "results": results}
