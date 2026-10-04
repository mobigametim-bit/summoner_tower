@tool
extends RefCounted
## Shared state for all handlers: editor plugin, undo/redo, log buffers, settings, runtime link.

const U = preload("res://addons/godot_forge/core/util.gd")
const PLUGIN_VERSION := "0.1.0"
const MAX_LOGS := 3000

signal log_added(entry: Dictionary)
signal activity_added(entry: Dictionary)

var plugin: EditorPlugin
var server
var router
var runtime  # debugger bridge (EditorDebuggerPlugin)
var changes  # changeset handler, used for auto-checkpoints
var current_method := ""
var last_method := ""

var settings := {
	"autosave": true,           # save the edited scene after every mutating request
	"auto_changeset": true,     # open a changeset automatically before the first write
	"screenshot_max_size": 1280,
	"mute_game_audio": false,   # mute games started by the AI (always on for headless/test editors)
}

var activity: Array = []  # recent requests from AI clients, shown in the Forge dock
var logs: Array = []
var _log_seq := 0
var _log_mutex := Mutex.new()
var _pending_logs: Array = []
## >0 while a handler runs a check whose engine errors are expected (returned in its result,
## not broadcast to clients as live errors).
var quiet := 0

var _dirty_scene := false
var _batch_depth := 0
var _committed: Array = []  # history ids of committed actions, for batch rollback


func _init(p_plugin: EditorPlugin) -> void:
	plugin = p_plugin
	var es := EditorInterface.get_editor_settings()
	for key in settings:
		var full: String = "godot_forge/" + str(key)
		if es.has_setting(full):
			settings[key] = es.get_setting(full)
		else:
			es.set_setting(full, settings[key])
			es.set_initial_value(full, settings[key], false)


# ---------------------------------------------------------------------------
# Undo/redo
# ---------------------------------------------------------------------------

func ur() -> EditorUndoRedoManager:
	return plugin.get_undo_redo()


## Starts an undoable editor action. Always pair with commit().
func begin(action_name: String, context: Object = null) -> EditorUndoRedoManager:
	var u := ur()
	var ctx_obj: Object = context if context != null else EditorInterface.get_edited_scene_root()
	u.create_action("AI: " + action_name, UndoRedo.MERGE_DISABLE, ctx_obj)
	return u


func commit(context: Object = null) -> void:
	var u := ur()
	u.commit_action()
	var ctx_obj: Object = context if context != null else EditorInterface.get_edited_scene_root()
	if ctx_obj:
		_committed.append(u.get_object_history_id(ctx_obj))
	mark_dirty()


func mark_dirty() -> void:
	_dirty_scene = true


func begin_batch() -> int:
	_batch_depth += 1
	return _committed.size()


func end_batch() -> void:
	_batch_depth = max(0, _batch_depth - 1)
	if _batch_depth == 0:
		_committed.clear()


func rollback_batch(marker: int) -> bool:
	var u := ur()
	var done := false
	while _committed.size() > marker:
		var hid: int = _committed.pop_back()
		var h := u.get_history_undo_redo(hid)
		if h and h.has_undo():
			h.undo()
			done = true
	return done


## Called after every top level request: persists the edited scene so files on disk match
## what the assistant just did (scripts, tests and diffs read files, not editor memory).
func flush_after_request() -> void:
	if _batch_depth > 0:
		return
	if not _dirty_scene:
		return
	_dirty_scene = false
	if not settings.autosave:
		return
	var root := EditorInterface.get_edited_scene_root()
	if root and root.scene_file_path != "":
		before_write([root.scene_file_path])
		EditorInterface.save_scene()


## Hook run before anything writes project files; opens an automatic changeset.
func before_write(paths: Array = []) -> void:
	if changes and settings.auto_changeset:
		changes.ensure_open(paths)


# ---------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------

func edited_root() -> Node:
	return EditorInterface.get_edited_scene_root()


## Resolves a node path relative to the edited scene root. Accepts "", ".", root name,
## "Player/Sprite", "%UniqueName", "/root/Scene/Player".
func find_node(path: String) -> Node:
	var root := edited_root()
	if root == null:
		return null
	path = path.strip_edges()
	if path == "" or path == "." or path == root.name or path == "/" + root.name:
		return root
	if path.begins_with("/root/"):
		path = path.substr(6)
		var slash := path.find("/")
		if slash < 0:
			return root if path == root.name else null
		path = path.substr(slash + 1)
	elif path.begins_with(root.name + "/"):
		var n := root.get_node_or_null(path.substr(root.name.length() + 1))
		if n:
			return n
	if path.begins_with("%"):
		return root.get_node_or_null(path)
	return root.get_node_or_null(path)


func node_path_str(n: Node) -> String:
	var root := edited_root()
	if n == root:
		return "."
	if root and root.is_ancestor_of(n):
		return str(root.get_path_to(n))
	return str(n.get_path())


func node_not_found(path: String) -> Dictionary:
	var root := edited_root()
	if root == null:
		return U.err("No scene is open in the editor.", "Open one with scene.open or create one with scene.create.")
	var names := []
	_collect_paths(root, root, names, 400)
	var s := U.suggest(path, names)
	return U.err("Node '%s' not found in scene '%s'." % [path, root.scene_file_path], ("Did you mean '%s'? " % s if s != "" else "") + "Use scene.get_tree to list nodes. Paths are relative to the scene root, e.g. 'Player/Sprite2D'.")


func _collect_paths(root: Node, n: Node, out: Array, limit: int) -> void:
	if out.size() >= limit:
		return
	if n != root:
		out.append(str(root.get_path_to(n)))
	for c in n.get_children():
		_collect_paths(root, c, out, limit)


# ---------------------------------------------------------------------------
# Activity feed
# ---------------------------------------------------------------------------

const READ_ONLY_ACTIONS := ["info", "get", "tree", "list", "read", "search", "status", "logs", "errors", "output", "outline", "current", "class", "member", "node_types", "selection", "input_actions", "autoloads", "layers", "plugins", "exists", "dependencies", "source", "diff", "history", "perf", "sample", "eval", "templates", "classes", "types", "check_parent", "uid", "get_setting", "list_settings", "screenshot", "game", "editor", "render", "preview"]


func record_activity(method: String, params: Dictionary, result) -> void:
	var action := method.substr(method.find(".") + 1)
	var entry := {
		"time": Time.get_time_string_from_system(),
		"method": method,
		"ok": not U.is_err(result),
		"write": not (action in READ_ONLY_ACTIONS),
		"summary": _summarize(params),
	}
	if U.is_err(result):
		entry["error"] = str(result.get("message", ""))
	activity.append(entry)
	if activity.size() > 300:
		activity = activity.slice(activity.size() - 300)
	activity_added.emit(entry)


func _summarize(p: Dictionary) -> String:
	var parts := []
	for k in ["path", "scene", "name", "type", "from", "signal", "to", "action", "expression", "query"]:
		if p.has(k) and str(p[k]) != "":
			parts.append("%s=%s" % [k, str(p[k]).substr(0, 40)])
	if p.has("props") and p.props is Dictionary:
		parts.append("props=" + ",".join(p.props.keys()).substr(0, 60))
	return " ".join(parts)


# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

## Thread safe; loggers may call this from any thread. Entries are flushed on the main thread.
func push_log(entry: Dictionary) -> void:
	# Headless editors use a dummy renderer that complains about every texture; that's noise.
	var file := str(entry.get("file", ""))
	if file.contains("rendering/dummy"):
		return
	if entry.has("message"):
		entry["message"] = _strip_control(str(entry.message))
	_log_mutex.lock()
	_pending_logs.append(entry)
	_log_mutex.unlock()


static var _ansi_re: RegEx


## Removes ANSI color codes and other control characters (they break JSON consumers).
func _strip_control(t: String) -> String:
	if _ansi_re == null:
		_ansi_re = RegEx.create_from_string(char(27) + "[[][0-9;?]*[A-Za-z]")
	t = _ansi_re.sub(t, "", true)
	var out := ""
	for i in t.length():
		var c := t.unicode_at(i)
		if c >= 32 or c == 10 or c == 9:
			out += t[i]
	return out


func flush_logs() -> void:
	_log_mutex.lock()
	var pending := _pending_logs
	_pending_logs = []
	_log_mutex.unlock()
	for e in pending:
		_log_seq += 1
		e["seq"] = _log_seq
		if not e.has("time"):
			e["time"] = Time.get_unix_time_from_system()
		logs.append(e)
		if quiet > 0:
			e["quiet"] = true
		elif server and e.get("level", "") in ["error", "warning"]:
			server.broadcast("log", e)
		log_added.emit(e)
	if logs.size() > MAX_LOGS:
		logs = logs.slice(logs.size() - MAX_LOGS)


func log_seq() -> int:
	return _log_seq


func get_logs(since_seq: int = 0, source: String = "", level: String = "", limit: int = 200) -> Array:
	var out := []
	for e in logs:
		if e.seq <= since_seq:
			continue
		if source != "" and e.get("source", "") != source:
			continue
		if level != "":
			if level == "error" and e.get("level") != "error":
				continue
			if level == "warning" and not (e.get("level") in ["error", "warning"]):
				continue
		out.append(e)
	if out.size() > limit:
		out = out.slice(out.size() - limit)
	return out


# ---------------------------------------------------------------------------
# Filesystem
# ---------------------------------------------------------------------------

func fs() -> EditorFileSystem:
	return EditorInterface.get_resource_filesystem()


## Waits until the editor finished scanning and importing.
func wait_fs(timeout_ms: int = 30000) -> void:
	var start := Time.get_ticks_msec()
	await plugin.get_tree().process_frame
	while (fs().is_scanning() or fs().is_importing()) and Time.get_ticks_msec() - start < timeout_ms:
		await plugin.get_tree().process_frame


## Makes sure a file just written to disk is imported and loadable (new folders need a scan,
## existing ones an update + reimport). Returns true when ResourceLoader can load it.
func import_file(path: String, timeout_ms: int = 30000) -> bool:
	var start := Time.get_ticks_msec()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path.get_base_dir())) and fs().get_filesystem_path(path.get_base_dir()) != null:
		fs().update_file(path)
		fs().reimport_files(PackedStringArray([path]))
	else:
		fs().scan()
	await wait_fs(timeout_ms)
	while not ResourceLoader.exists(path) and Time.get_ticks_msec() - start < timeout_ms:
		if not fs().is_scanning():
			fs().scan()
		await plugin.get_tree().process_frame
		await wait_fs(timeout_ms)
	return ResourceLoader.exists(path)


func frame() -> Signal:
	return plugin.get_tree().process_frame
