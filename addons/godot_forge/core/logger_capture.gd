extends Logger
## Captures engine/script messages and errors (Godot 4.5+) and forwards them to a sink with
## push_log(entry). Loaded dynamically so older engines never parse it.

var sink
var source := "editor"
const KINDS := ["error", "warning", "script", "shader"]


func _log_message(message: String, error: bool) -> void:
	if sink == null:
		return
	var m := message.strip_edges(false, true)
	if m == "":
		return
	sink.push_log({"source": source, "level": "error" if error else "info", "message": m})


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
	if sink == null:
		return
	var stack := []
	for bt in script_backtraces:
		if bt == null:
			continue
		for i in bt.get_frame_count():
			stack.append({"function": bt.get_frame_function(i), "file": bt.get_frame_file(i), "line": bt.get_frame_line(i)})
	var msg := rationale if rationale != "" else code
	var entry := {
		"source": source,
		"level": "warning" if error_type == ERROR_TYPE_WARNING else "error",
		"kind": KINDS[error_type] if error_type < KINDS.size() else "error",
		"message": msg,
		"code": code,
		"file": file,
		"line": line,
		"function": function,
	}
	if not stack.is_empty():
		entry["stack"] = stack
		# Point at the first script frame outside Godot Forge: that's where the user can fix things.
		# (When Forge simulated the input that led here, its frames sit on top of the stack.)
		for fr in stack:
			if not str(fr.file).begins_with("res://addons/godot_forge/"):
				entry["script_file"] = fr.file
				entry["script_line"] = fr.line
				break
	sink.push_log(entry)
