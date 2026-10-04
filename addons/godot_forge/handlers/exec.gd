@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Escape hatch: runs a GDScript snippet inside the editor. The snippet is the body of
##   func run(editor: EditorInterface, scene: Node, forge) -> Variant
## `scene` is the edited scene root; `forge` gives access to helpers (forge.find_node(path),
## forge.begin(name)/forge.commit() for undoable actions). Return a value to see it.
## Anything it writes to disk is covered by the current changeset.


func a_editor(p: Dictionary):
	var e = U.require(p, ["code"])
	if e: return e
	var code := U.p_str(p, "code")
	var src := code
	if not code.contains("func run"):
		var body := ""
		for line in code.split("\n"):
			body += "\t" + line + "\n"
		src = "@tool\nextends RefCounted\n\nfunc run(editor: EditorInterface, scene: Node, forge) -> Variant:\n" + body + "\treturn null\n"
	elif not code.contains("extends"):
		src = "@tool\nextends RefCounted\n" + code
	ctx.flush_logs()
	var before: int = ctx.log_seq()
	var s := GDScript.new()
	s.source_code = src
	var err := s.reload()
	if err != OK:
		ctx.flush_logs()
		var errs: Array = ctx.get_logs(before, "editor", "error", 10)
		return U.err("Snippet failed to compile.", "The snippet is the body of func run(editor, scene, forge). Indent with tabs or spaces consistently.", {"errors": errs.map(func(x): return "line %s: %s" % [int(x.get("line", 0)) - 4, x.get("message", "")])})
	ctx.before_write()
	var obj = s.new()
	var result = await obj.run(EditorInterface, ctx.edited_root(), ctx)
	ctx.mark_dirty()
	ctx.flush_logs()
	var out := {"result": U.encode(result)}
	var new_errors: Array = ctx.get_logs(before, "editor", "error", 10)
	if not new_errors.is_empty():
		out["errors"] = new_errors
	return out


## Evaluates a single expression in the editor with the edited scene root as `self`.
func a_eval(p: Dictionary):
	var e = U.require(p, ["expression"])
	if e: return e
	var base: Node = ctx.find_node(U.p_str(p, "path", ".")) if ctx.edited_root() else null
	var ex := Expression.new()
	if ex.parse(U.p_str(p, "expression"), ["scene"]) != OK:
		return U.err("Parse error: " + ex.get_error_text())
	var v = ex.execute([ctx.edited_root()], base, false)
	if ex.has_execute_failed():
		return U.err("Execution failed: " + ex.get_error_text())
	return {"value": U.encode(v)}
