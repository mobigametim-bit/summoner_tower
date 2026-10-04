@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Changesets: every AI task is recorded against a baseline so the user can review the diff,
## approve it, discard it, or roll back to checkpoints. Backed by a private "shadow" git
## repository in .godot/forge/history.git whose work tree is the project folder — the user's own
## git repository (if any) is never touched.

signal changed

const STATE_PATH := "res://.godot/forge/changes.json"
const MAX_DIFF_CHARS := 60000

var _git_ok := -1  # -1 unknown, 0 missing, 1 available
var _state := {}
var _loaded := false


# ---------------------------------------------------------------------------
# git plumbing
# ---------------------------------------------------------------------------

func _project_dir() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/")


func _git_dir() -> String:
	return ProjectSettings.globalize_path("res://.godot/forge/history.git")


func _git(args: Array, allow_fail: bool = false) -> Dictionary:
	var full := ["--git-dir=" + _git_dir(), "--work-tree=" + _project_dir(), "-c", "core.quotepath=off", "-c", "core.autocrlf=false", "-c", "core.safecrlf=false"]
	full.append_array(args)
	var out := []
	var code := OS.execute("git", PackedStringArray(full), out, true)
	var text := "".join(out)
	if code != 0 and not allow_fail:
		push_warning("Godot Forge changes: git %s failed (%d): %s" % [" ".join(args), code, text.substr(0, 400)])
	return {"code": code, "out": text}


func available() -> bool:
	if _git_ok == -1:
		var out := []
		_git_ok = 1 if OS.execute("git", PackedStringArray(["--version"]), out, true) == 0 else 0
	return _git_ok == 1


func _ensure_repo() -> bool:
	if not available():
		return false
	if DirAccess.dir_exists_absolute(_git_dir()):
		return true
	DirAccess.make_dir_recursive_absolute(_git_dir())
	var r := _git(["init", "-q"])
	if r.code != 0:
		return false
	_git(["config", "user.name", "Godot Forge"])
	_git(["config", "user.email", "forge@localhost"])
	_git(["config", "gc.auto", "0"])
	var exclude := FileAccess.open(_git_dir().path_join("info/exclude"), FileAccess.WRITE)
	if exclude == null:
		DirAccess.make_dir_recursive_absolute(_git_dir().path_join("info"))
		exclude = FileAccess.open(_git_dir().path_join("info/exclude"), FileAccess.WRITE)
	exclude.store_string(".godot/\n.import/\n*.tmp\n*.translation\n/android/build/\n/addons/godot_forge/\n.mcp.json\n")
	exclude.close()
	return true


func _snapshot(message: String) -> String:
	_git(["add", "-A"])
	_git(["commit", "-q", "--allow-empty", "--no-verify", "-m", message])
	return _git(["rev-parse", "HEAD"]).out.strip_edges()


# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------

func _load_state() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(STATE_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
		if parsed is Dictionary:
			_state = parsed
	if not _state.has("history"):
		_state["history"] = []
	if not _state.has("open"):
		_state["open"] = null


func _save_state() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/forge"))
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(_state, "  "))
	f.close()
	changed.emit()


func current() -> Variant:
	_load_state()
	return _state.open


## Called by ctx.before_write(): opens a changeset lazily before the first AI write.
func ensure_open(_paths: Array = []) -> void:
	_load_state()
	if _state.open != null:
		return
	if not _ensure_repo():
		return
	var m: String = ctx.current_method if ctx.current_method != "" else ctx.last_method
	var label: String = ("AI edits (started with %s)" % m) if m != "" else "AI edits"
	_begin(label)


func _begin(label: String) -> Dictionary:
	var base := _snapshot("baseline: " + label)
	var cs := {"id": "cs%d" % int(Time.get_unix_time_from_system()), "label": label, "base": base, "started": Time.get_datetime_string_from_system(), "checkpoints": []}
	_state.open = cs
	_save_state()
	return cs


# ---------------------------------------------------------------------------
# actions
# ---------------------------------------------------------------------------

func _require_git():
	if not available():
		return U.err("git is not installed, so changesets are unavailable.", "Install git (https://git-scm.com) and restart the editor. Editor undo (editor.undo) still works.")
	if not _ensure_repo():
		return U.err("Could not create the history repository in .godot/forge/history.git.")
	return null


func a_begin(p: Dictionary):
	var e = _require_git()
	if e: return e
	_load_state()
	if _state.open != null:
		if not U.p_bool(p, "accept_previous", true):
			return U.err("A changeset is already open ('%s')." % _state.open.label, "Approve or discard it first, or pass accept_previous=true.")
		_close("accepted")
	return _begin(U.p_str(p, "label", "AI task"))


func a_status(_p: Dictionary):
	var e = _require_git()
	if e: return e
	_load_state()
	if _state.open == null:
		return {"open": null, "note": "No pending AI changes. A changeset opens automatically on the next edit.", "recent": _state.history.slice(max(0, _state.history.size() - 5))}
	return {"open": _state.open, "files": files()}


## Changed files since the baseline: [{path, status: added|modified|deleted}]
func files(include_sidecars: bool = false) -> Array:
	_load_state()
	if _state.open == null or not available():
		return []
	_git(["add", "-A"])
	var r := _git(["diff", "--cached", "--name-status", "--no-renames", _state.open.base])
	var out := []
	for line in str(r.out).split("\n", false):
		var parts := line.split("\t")
		if parts.size() < 2:
			continue
		if not include_sidecars and (parts[1].ends_with(".uid") or parts[1].ends_with(".import")):
			continue
		var st := {"A": "added", "M": "modified", "D": "deleted"}.get(parts[0].substr(0, 1), parts[0])
		out.append({"path": "res://" + parts[1], "status": st})
	return out


func a_diff(p: Dictionary):
	var e = _require_git()
	if e: return e
	_load_state()
	var base := _base_for(p)
	if base == "":
		return {"note": "No open changeset; nothing to diff.", "files": []}
	_git(["add", "-A"])
	var args := ["diff", "--cached", "--no-renames", "--stat=160", base]
	var stat: String = _git(args).out
	var patch_args := ["diff", "--cached", "--no-renames", "-U2", base, "--"]
	if p.has("path"):
		patch_args.append(U.res_path(U.p_str(p, "path")).trim_prefix("res://"))
	else:
		# Text files only; binary diffs are noise.
		patch_args.append_array([":(exclude)*.png", ":(exclude)*.jpg", ":(exclude)*.webp", ":(exclude)*.wav", ":(exclude)*.ogg", ":(exclude)*.mp3", ":(exclude)*.glb", ":(exclude)*.res", ":(exclude)*.scn"])
	var patch: String = _git(patch_args).out
	var truncated := patch.length() > MAX_DIFF_CHARS
	return {"base": base.substr(0, 10), "files": files(), "stat": stat.strip_edges(), "patch": patch.substr(0, MAX_DIFF_CHARS), "truncated": truncated}


func _base_for(p: Dictionary) -> String:
	if p.has("checkpoint"):
		for c in _all_checkpoints():
			if c.name == U.p_str(p, "checkpoint") or str(c.commit).begins_with(U.p_str(p, "checkpoint")):
				return c.commit
		return ""
	return _state.open.base if _state.open != null else ""


func a_approve(p: Dictionary):
	var e = _require_git()
	if e: return e
	_load_state()
	if _state.open == null:
		return {"note": "Nothing to approve."}
	var fl := files()
	_close("accepted", U.p_str(p, "message", ""))
	return {"approved": fl.size(), "files": fl}


func _close(outcome: String, message: String = "") -> void:
	var cs: Dictionary = _state.open
	var commit := _snapshot("%s: %s%s" % [outcome, cs.label, (" — " + message) if message != "" else ""])
	cs["outcome"] = outcome
	cs["end"] = commit
	cs["closed"] = Time.get_datetime_string_from_system()
	_state.history.append(cs)
	if _state.history.size() > 100:
		_state.history = _state.history.slice(_state.history.size() - 100)
	_state.open = null
	_save_state()


## Restores every file to the baseline (or a checkpoint) and reloads what the editor has open.
func a_discard(p: Dictionary):
	var e = _require_git()
	if e: return e
	_load_state()
	if _state.open == null:
		return {"note": "Nothing to discard."}
	var base := _base_for(p) if p.has("checkpoint") else str(_state.open.base)
	if base == "":
		return U.err("Unknown checkpoint '%s'." % U.p_str(p, "checkpoint"))
	var restored := await _restore_to(base, [])
	if not p.has("checkpoint"):
		_close("discarded")
	else:
		_save_state()
	return {"restored": restored, "to": base.substr(0, 10)}


## Reverts selected files to the baseline.
func a_revert_files(p: Dictionary):
	var e = _require_git()
	if e: return e
	_load_state()
	if _state.open == null:
		return U.err("No open changeset.")
	var paths := U.p_arr(p, "paths")
	if paths.is_empty() and p.has("path"):
		paths = [U.p_str(p, "path")]
	if paths.is_empty():
		return U.err("Provide 'paths'.")
	var rels := []
	for x in paths:
		rels.append(U.res_path(str(x)).trim_prefix("res://"))
	var restored := await _restore_to(str(_state.open.base), rels)
	return {"reverted": restored}


func _restore_to(commit: String, only: Array) -> Array:
	_git(["add", "-A"])
	var diff_args := ["diff", "--cached", "--name-status", "--no-renames", commit]
	if not only.is_empty():
		diff_args.append("--")
		diff_args.append_array(only)
	var changes: String = _git(diff_args).out
	var restored := []
	var project_file_changed := false
	for line in changes.split("\n", false):
		var parts := line.split("\t")
		if parts.size() < 2:
			continue
		var rel: String = parts[1]
		var status: String = parts[0].substr(0, 1)
		if status == "A":
			# Added after the baseline: remove it.
			DirAccess.remove_absolute(_project_dir().path_join(rel))
			for side in [".import", ".uid"]:
				if FileAccess.file_exists("res://" + rel + side):
					DirAccess.remove_absolute(_project_dir().path_join(rel + side))
		else:
			_git(["checkout", commit, "--", rel])
		if rel == "project.godot":
			project_file_changed = true
		restored.append({"path": "res://" + rel, "was": {"A": "added", "M": "modified", "D": "deleted"}.get(status, status)})
	await _reload_editor(restored, project_file_changed)
	return restored


func _reload_editor(restored: Array, project_file_changed: bool) -> void:
	if project_file_changed:
		_reload_project_settings()
	ctx.fs().scan()
	await ctx.wait_fs()
	var open := EditorInterface.get_open_scenes()
	for r in restored:
		var path: String = r.path
		if path.ends_with(".gd") and FileAccess.file_exists(path) and ctx.router.handlers.has("script"):
			ctx.router.handlers["script"].reload_and_check(path)
		elif (path.ends_with(".tscn") or path.ends_with(".scn")) and path in open:
			if FileAccess.file_exists(path):
				EditorInterface.reload_scene_from_path(path)
		elif (path.ends_with(".tres") or path.ends_with(".gdshader")) and ResourceLoader.has_cached(path) and FileAccess.file_exists(path):
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	EditorInterface.get_script_editor().reload_open_files()


## The editor keeps project settings in memory and would write them back; re-sync them
## from the restored project.godot.
func _reload_project_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://project.godot") != OK:
		return
	var present := {}
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			var name := key if section == "" else "%s/%s" % [section, key]
			present[name] = true
			ProjectSettings.set_setting(name, cfg.get_value(section, key))
	for prop in ProjectSettings.get_property_list():
		var n: String = prop.name
		if (n.begins_with("input/") or n.begins_with("autoload/") or n.begins_with("layer_names/")) and not present.has(n):
			if not (n.begins_with("input/ui_")):
				ProjectSettings.clear(n)
	ProjectSettings.save()


func a_checkpoint(p: Dictionary):
	var e = _require_git()
	if e: return e
	_load_state()
	if _state.open == null:
		_begin(U.p_str(p, "label", "AI task"))
	var name := U.p_str(p, "name", "checkpoint %d" % (_state.open.checkpoints.size() + 1))
	var commit := _snapshot("checkpoint: " + name)
	_state.open.checkpoints.append({"name": name, "commit": commit, "time": Time.get_datetime_string_from_system(), "files": files().size()})
	_save_state()
	return {"checkpoint": name, "commit": commit.substr(0, 10)}


func _all_checkpoints() -> Array:
	var out := []
	for cs in _state.history:
		for c in cs.get("checkpoints", []):
			out.append(c)
	if _state.open != null:
		out.append_array(_state.open.checkpoints)
	return out


## Rolls the project back to a checkpoint of the open changeset (keeps the changeset open).
func a_restore(p: Dictionary):
	var e = U.require(p, ["checkpoint"])
	if e: return e
	return await a_discard(p)


func a_history(p: Dictionary):
	var e = _require_git()
	if e: return e
	_load_state()
	var hist: Array = _state.history.slice(max(0, _state.history.size() - U.p_int(p, "limit", 20)))
	return {"open": _state.open, "history": hist}


## Undo a closed (approved) changeset by restoring the files it touched to its baseline.
func a_revert_changeset(p: Dictionary):
	var e = _require_git()
	if e: return e
	_load_state()
	var id := U.p_str(p, "id")
	for cs in _state.history:
		if cs.id == id:
			if _state.open != null:
				_close("accepted")
			var touched: PackedStringArray = str(_git(["diff", "--name-only", "--no-renames", cs.base, cs.get("end", "HEAD")]).out).split("\n", false)
			_begin("revert " + cs.label)
			var restored := await _restore_to(cs.base, Array(touched))
			return {"reverted": cs.label, "files": restored, "note": "Opened a new changeset for the revert; approve or discard it."}
	return U.err("Unknown changeset '%s'." % id, "See changes.history for ids.")


## Opens a changeset if none is open (used before the MCP server writes files directly).
func a_ensure(_p: Dictionary):
	var e = _require_git()
	if e: return e
	ensure_open([])
	return {"open": current()}
