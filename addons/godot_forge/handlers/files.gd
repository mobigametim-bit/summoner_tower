@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Project file access limited to res:// (and user://). Keeps the editor filesystem in sync.

const TEXT_EXT := ["gd", "cs", "tscn", "tres", "godot", "cfg", "gdshader", "gdshaderinc", "md", "txt", "json", "csv", "import", "gdextension", "xml", "html", "yaml", "yml", "ini", "svg", "uid", "tsv", "glsl"]
const IMAGE_EXT := ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]
const SKIP_DIRS := [".godot", ".git", ".import", "node_modules", ".vs", ".vscode"]


func _checked_path(p: Dictionary, key: String = "path"):
	var raw := U.p_str(p, key)
	if raw == "":
		return U.err("Missing required parameter '%s'." % key)
	var path := U.res_path(raw)
	if not U.is_safe_path(path):
		return U.err("Path '%s' is outside the project." % raw, "Only res:// and user:// paths are allowed.")
	return path


# --- listing -----------------------------------------------------------------

func a_list(p: Dictionary):
	var base = _checked_path({"path": U.p_str(p, "path", "res://")})
	if U.is_err(base): return base
	var recursive := U.p_bool(p, "recursive", true)
	var pattern := U.p_str(p, "pattern", "")
	var include_addons := U.p_bool(p, "include_addons", false)
	var limit := U.p_int(p, "limit", 500)
	var out := []
	var dirs := []
	_walk(base, recursive, pattern, include_addons, out, dirs, limit)
	var res := {"path": base, "files": out}
	if not recursive:
		res["dirs"] = dirs
	if out.size() >= limit:
		res["truncated"] = true
	return res


func _walk(dir: String, recursive: bool, pattern: String, include_addons: bool, out: Array, dirs: Array, limit: int) -> void:
	if out.size() >= limit:
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = false
	for f in da.get_files():
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		var full := dir.path_join(f)
		if pattern != "" and not (f.match(pattern) or full.match(pattern)):
			continue
		var type := ctx.fs().get_file_type(full) if dir.begins_with("res://") else ""
		out.append({"path": full, "type": type} if type != "" else {"path": full})
		if out.size() >= limit:
			return
	for d in da.get_directories():
		if d in SKIP_DIRS or d.begins_with("."):
			continue
		if d == "addons" and dir == "res://" and not include_addons:
			dirs.append(dir.path_join(d) + "/ (skipped, pass include_addons)")
			continue
		dirs.append(dir.path_join(d))
		if recursive:
			_walk(dir.path_join(d), recursive, pattern, include_addons, out, [], limit)


# --- search ------------------------------------------------------------------

func a_search(p: Dictionary):
	var e = U.require(p, ["query"])
	if e: return e
	var query := U.p_str(p, "query")
	var use_regex := U.p_bool(p, "regex", false)
	var case_sensitive := U.p_bool(p, "case_sensitive", false)
	var glob := U.p_str(p, "glob", "")
	var limit := U.p_int(p, "limit", 100)
	var re: RegEx = null
	if use_regex:
		re = RegEx.new()
		if re.compile(("(?i)" if not case_sensitive else "") + query) != OK:
			return U.err("Invalid regex '%s'." % query)
	var files := []
	_walk(U.res_path(U.p_str(p, "path", "res://")), true, glob, U.p_bool(p, "include_addons", false), files, [], 20000)
	var matches := []
	var q := query if case_sensitive else query.to_lower()
	for fi in files:
		var path: String = fi.path
		if not path.get_extension().to_lower() in TEXT_EXT or path.get_extension() == "svg":
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var line_no := 0
		while not f.eof_reached():
			var line := f.get_line()
			line_no += 1
			var hit := false
			if re:
				hit = re.search(line) != null
			else:
				hit = (line if case_sensitive else line.to_lower()).contains(q)
			if hit:
				matches.append({"path": path, "line": line_no, "text": line.strip_edges().substr(0, 240)})
				if matches.size() >= limit:
					return {"matches": matches, "truncated": true}
	return {"matches": matches}


# --- read / write --------------------------------------------------------------

func a_read(p: Dictionary):
	var path = _checked_path(p)
	if U.is_err(path): return path
	if not FileAccess.file_exists(path):
		var s := U.suggest(path.get_file(), _all_names())
		return U.err("File '%s' does not exist." % path, "Did you mean '%s'?" % s if s != "" else "Use files.list or files.search to find files.")
	var ext: String = path.get_extension().to_lower()
	if ext in IMAGE_EXT and ext != "svg" or (ext == "svg" and U.p_bool(p, "as_image", false)):
		var img := Image.new()
		var tex = load(path)
		if tex is Texture2D:
			img = tex.get_image()
		else:
			img.load(ProjectSettings.globalize_path(path))
		if img == null or img.is_empty():
			return U.err("Could not decode image '%s'." % path)
		var shot := U.image_to_b64(img, U.p_int(p, "max_size", 512))
		shot["path"] = path
		return shot
	if not (ext in TEXT_EXT):
		var fa := FileAccess.open(path, FileAccess.READ)
		return {"path": path, "binary": true, "size": fa.get_length() if fa else 0, "type": ctx.fs().get_file_type(path)}
	var text := FileAccess.get_file_as_string(path)
	var offset := U.p_int(p, "offset", 0)
	var limit := U.p_int(p, "limit", 0)
	var lines := text.split("\n")
	var total := lines.size()
	if offset > 0 or limit > 0:
		var start := maxi(0, offset - 1) if offset > 0 else 0
		var end := total if limit <= 0 else mini(total, start + limit)
		text = "\n".join(lines.slice(start, end))
		return {"path": path, "content": text, "from_line": start + 1, "to_line": end, "total_lines": total}
	return {"path": path, "content": text, "total_lines": total}


func _all_names() -> Array:
	var files := []
	_walk("res://", true, "", false, files, [], 3000)
	return files.map(func(f): return f.path.get_file())


func a_write(p: Dictionary):
	var path = _checked_path(p)
	if U.is_err(path): return path
	if not p.has("content"):
		return U.err("Missing required parameter 'content'.")
	var exists := FileAccess.file_exists(path)
	if exists and not U.p_bool(p, "overwrite", true):
		return U.err("File '%s' already exists." % path, "Pass overwrite=true or use files.edit.")
	return await write_text(path, U.p_str(p, "content"))


## Writes a text file, keeps the editor in sync (reloads scripts, rescans) and returns
## script diagnostics for .gd files.
func write_text(path: String, content: String):
	ctx.before_write([path])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var existed := FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return U.err("Cannot write '%s' (error %d)." % [path, FileAccess.get_open_error()])
	f.store_string(content)
	f.close()
	var result := {"path": path, "created": not existed, "bytes": content.to_utf8_buffer().size()}
	await _after_write(path, result)
	return result


func _after_write(path: String, result: Dictionary) -> void:
	var ext := path.get_extension().to_lower()
	ctx.fs().update_file(path)
	if ext == "gd":
		var diag = ctx.router.handlers["script"].reload_and_check(path) if ctx.router.handlers.has("script") else null
		if diag != null:
			result["diagnostics"] = diag
			result["ok"] = diag.is_empty() or diag.all(func(d): return d.get("severity") != "error")
	elif ext in ["tscn", "tres"]:
		# Refresh open scenes that were edited on disk.
		if path in EditorInterface.get_open_scenes():
			EditorInterface.reload_scene_from_path(path)
		elif ResourceLoader.has_cached(path):
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	elif ext == "gdshader":
		if ResourceLoader.has_cached(path):
			var sh = load(path)
			if sh is Shader:
				sh.code = FileAccess.get_file_as_string(path)
	elif not (ext in TEXT_EXT) or ext in IMAGE_EXT:
		ctx.fs().scan()
	if ctx.router.handlers.has("script"):
		EditorInterface.get_script_editor().reload_open_files()


## Exact string replacement edits: [{old, new, replace_all?}]
func a_edit(p: Dictionary):
	var path = _checked_path(p)
	if U.is_err(path): return path
	if not FileAccess.file_exists(path):
		return U.err("File '%s' does not exist." % path)
	var edits := U.p_arr(p, "edits")
	if edits.is_empty() and p.has("old"):
		edits = [{"old": p.old, "new": p.get("new", ""), "replace_all": p.get("replace_all", false)}]
	if edits.is_empty():
		return U.err("Provide 'edits': [{old, new}] or 'old' and 'new'.")
	var text := FileAccess.get_file_as_string(path)
	var applied := 0
	for ed in edits:
		var old := str(ed.get("old", ""))
		var new := str(ed.get("new", ""))
		if old == "":
			return U.err("Edit %d has an empty 'old' string." % applied)
		var count := text.count(old)
		if count == 0:
			var hint := "The text must match exactly, including indentation%s." % (" (GDScript uses tabs)" if path.ends_with(".gd") else "")
			var first_line := old.split("\n")[0].strip_edges()
			if first_line != "" and text.contains(first_line):
				hint += " The first line was found; check whitespace in the following lines."
			return U.err("Edit %d: 'old' text not found in %s." % [applied, path], hint, {"applied_before_failure": applied})
		if count > 1 and not bool(ed.get("replace_all", false)):
			return U.err("Edit %d: 'old' text occurs %d times in %s." % [applied, count, path], "Include more surrounding context to make it unique, or set replace_all=true.")
		text = text.replace(old, new)
		applied += 1
	var r = await write_text(path, text)
	if U.is_err(r): return r
	r["edits_applied"] = applied
	return r


# --- file management -----------------------------------------------------------

func a_mkdir(p: Dictionary):
	var path = _checked_path(p)
	if U.is_err(path): return path
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	ctx.fs().scan()
	return {"path": path, "ok": err == OK}


func a_delete(p: Dictionary):
	var path = _checked_path(p)
	if U.is_err(path): return path
	if path == "res://" or path == "res://project.godot" or path.begins_with("res://addons/godot_forge"):
		return U.err("Refusing to delete '%s'." % path)
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(abs_path):
		return U.err("'%s' does not exist." % path)
	ctx.before_write([path])
	var err := OS.move_to_trash(abs_path)
	if err != OK:
		err = DirAccess.remove_absolute(abs_path)
	for side in [".import", ".uid"]:
		if FileAccess.file_exists(path + side):
			DirAccess.remove_absolute(abs_path + side)
	if path in EditorInterface.get_open_scenes():
		pass
	ctx.fs().scan()
	return {"deleted": path, "ok": err == OK, "note": "Moved to the OS trash when possible."}


## Moves/renames a file or folder and rewrites res:// references to it in text resources.
func a_move(p: Dictionary):
	var src = _checked_path(p, "from")
	if U.is_err(src): return src
	var dst = _checked_path(p, "to")
	if U.is_err(dst): return dst
	var src_abs := ProjectSettings.globalize_path(src)
	var dst_abs := ProjectSettings.globalize_path(dst)
	var is_dir := DirAccess.dir_exists_absolute(src_abs)
	if not is_dir and not FileAccess.file_exists(src):
		return U.err("'%s' does not exist." % src)
	if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst_abs):
		return U.err("'%s' already exists." % dst)
	ctx.before_write([src, dst])
	DirAccess.make_dir_recursive_absolute(dst_abs.get_base_dir())
	var err := DirAccess.rename_absolute(src_abs, dst_abs)
	if err != OK:
		return U.err("Move failed (error %d)." % err)
	for side in [".import", ".uid"]:
		if FileAccess.file_exists(src + side):
			DirAccess.rename_absolute(src_abs + side, dst_abs + side)
	# Rewrite textual references (preload paths, ext_resource paths).
	var updated := []
	if U.p_bool(p, "update_references", true):
		var files := []
		_walk("res://", true, "", true, files, [], 20000)
		for fi in files:
			var fp: String = fi.path
			if not fp.get_extension() in ["gd", "tscn", "tres", "godot", "cfg", "gdshader", "cs"]:
				continue
			if fp.begins_with("res://addons/godot_forge/"):
				continue
			var text := FileAccess.get_file_as_string(fp)
			var needle: String = src if not is_dir else src.trim_suffix("/") + "/"
			if text.contains(needle):
				var repl: String = dst if not is_dir else dst.trim_suffix("/") + "/"
				var f := FileAccess.open(fp, FileAccess.WRITE)
				f.store_string(text.replace(needle, repl))
				f.close()
				updated.append(fp)
	ctx.fs().scan()
	await ctx.wait_fs()
	for sp in updated:
		if sp in EditorInterface.get_open_scenes():
			EditorInterface.reload_scene_from_path(sp)
	return {"from": src, "to": dst, "references_updated": updated}


func a_copy(p: Dictionary):
	var src = _checked_path(p, "from")
	if U.is_err(src): return src
	var dst = _checked_path(p, "to")
	if U.is_err(dst): return dst
	if not FileAccess.file_exists(src):
		return U.err("'%s' does not exist." % src)
	ctx.before_write([dst])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst).get_base_dir())
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
	ctx.fs().scan()
	return {"from": src, "to": dst, "ok": err == OK}


func a_exists(p: Dictionary):
	var path = _checked_path(p)
	if U.is_err(path): return path
	return {"path": path, "exists": FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)), "type": ctx.fs().get_file_type(path)}


## Re-imports assets (after replacing files outside the editor) and waits for the scan.
func a_rescan(p: Dictionary):
	var paths := U.p_arr(p, "reimport")
	if not paths.is_empty():
		var rp := PackedStringArray()
		for x in paths:
			rp.append(U.res_path(str(x)))
		ctx.fs().reimport_files(rp)
	else:
		ctx.fs().scan()
	await ctx.wait_fs(60000)
	return {"ok": true}


## Lists what depends on a resource and what it depends on.
func a_dependencies(p: Dictionary):
	var path = _checked_path(p)
	if U.is_err(path): return path
	var deps := []
	for d in ResourceLoader.get_dependencies(path):
		var parts := str(d).split("::")
		deps.append(parts[parts.size() - 1] if parts.size() > 0 else str(d))
	var dependents := []
	var files := []
	_walk("res://", true, "", false, files, [], 20000)
	for fi in files:
		var fp: String = fi.path
		if fp.get_extension() in ["tscn", "tres", "gd"]:
			if FileAccess.get_file_as_string(fp).contains(path):
				dependents.append(fp)
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID:
		var uid_text := ResourceUID.id_to_text(uid)
		for fi in files:
			var fp2: String = fi.path
			if fp2.get_extension() in ["tscn", "tres"] and not fp2 in dependents and FileAccess.get_file_as_string(fp2).contains(uid_text):
				dependents.append(fp2)
	return {"path": path, "depends_on": deps, "used_by": dependents}
