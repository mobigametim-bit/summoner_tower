@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Project health checks and image comparison used by the test tool.


## Checks every scene for missing dependencies and common setup mistakes, and every script
## for compile errors.
func a_lint(p: Dictionary):
	var files := []
	ctx.router.handlers["files"]._walk(U.res_path(U.p_str(p, "path", "res://")), true, "", false, files, [], 5000)
	var problems := []
	var scenes := 0
	var node_h = ctx.router.handlers["node"]
	for f in files:
		var path: String = f.path
		if not path.ends_with(".tscn"):
			continue
		scenes += 1
		for dep in ResourceLoader.get_dependencies(path):
			var parts := str(dep).split("::")
			var dep_path := parts[parts.size() - 1]
			if dep_path.begins_with("uid://"):
				var id := ResourceUID.text_to_id(dep_path)
				if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
					problems.append({"file": path, "severity": "error", "message": "Broken reference to %s" % dep})
					continue
				dep_path = ResourceUID.get_id_path(id)
			if dep_path != "" and not ResourceLoader.exists(dep_path) and not FileAccess.file_exists(dep_path):
				problems.append({"file": path, "severity": "error", "message": "Missing dependency %s" % dep_path})
		var packed = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if packed == null:
			problems.append({"file": path, "severity": "error", "message": "Scene failed to load."})
			continue
		var inst: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		if inst == null:
			problems.append({"file": path, "severity": "error", "message": "Scene failed to instantiate."})
			continue
		for w in node_h.configuration_warnings(inst):
			problems.append({"file": path, "severity": "warning", "message": w})
		inst.free()
	if U.p_bool(p, "editor_first", true):
		for f in files:
			var fp: String = f.path
			if fp.ends_with(".gd"):
				for w in _code_built_nodes(fp):
					problems.append(w)
	var scripts = ctx.router.handlers["script"].a_validate({})
	for sp in scripts.problems:
		for d in scripts.problems[sp]:
			problems.append({"file": sp, "line": d.line, "severity": d.severity, "message": d.message})
	var main := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main == "":
		problems.append({"file": "project.godot", "severity": "warning", "message": "No main scene set."})
	elif not ResourceLoader.exists(main):
		problems.append({"file": "project.godot", "severity": "error", "message": "Main scene %s does not exist." % main})
	var errors := problems.filter(func(x): return x.severity == "error").size()
	return {"ok": errors == 0, "scenes": scenes, "scripts": scripts.checked, "errors": errors, "warnings": problems.size() - errors, "problems": problems}


## Compares an image (base64 PNG or res:// path) against a baseline PNG.
## Saves the image as the new baseline when none exists or update=true.
func a_compare_image(p: Dictionary):
	var e = U.require(p, ["baseline"])
	if e: return e
	var img := Image.new()
	if p.has("image_b64"):
		if img.load_png_from_buffer(Marshalls.base64_to_raw(U.p_str(p, "image_b64"))) != OK:
			return U.err("Could not decode image_b64 as PNG.")
	elif p.has("image_path"):
		if img.load(ProjectSettings.globalize_path(U.res_path(U.p_str(p, "image_path")))) != OK:
			return U.err("Could not load %s." % U.p_str(p, "image_path"))
	else:
		return U.err("Provide image_b64 or image_path.")
	var baseline := U.res_path(U.p_str(p, "baseline"))
	var abs_path := ProjectSettings.globalize_path(baseline)
	if not FileAccess.file_exists(baseline) or U.p_bool(p, "update", false):
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		ctx.before_write([baseline])
		img.save_png(abs_path)
		return {"baseline_saved": baseline, "match": true, "note": "New baseline recorded."}
	var base := Image.new()
	base.load(abs_path)
	if base.get_size() != img.get_size():
		img.resize(base.get_width(), base.get_height(), Image.INTERPOLATE_BILINEAR)
	base.convert(Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	var tol := U.p_float(p, "pixel_tolerance", 0.08)
	var diff := Image.create(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8)
	var differing := 0
	var total := base.get_width() * base.get_height()
	var step := 1 if total < 400000 else 2
	var sampled := 0
	for y in range(0, base.get_height(), step):
		for x in range(0, base.get_width(), step):
			sampled += 1
			var a := base.get_pixel(x, y)
			var b := img.get_pixel(x, y)
			var d := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
			if d > tol:
				differing += 1
				diff.set_pixel(x, y, Color.RED)
			else:
				diff.set_pixel(x, y, Color(a.r, a.g, a.b, 0.25))
	var ratio := float(differing) / maxf(1.0, float(sampled))
	var threshold := U.p_float(p, "threshold", 0.01)
	var out := {"match": ratio <= threshold, "diff_ratio": snappedf(ratio, 0.0001), "threshold": threshold, "baseline": baseline}
	if ratio > threshold:
		out["diff_image"] = U.image_to_b64(diff, 640)
	return out


const SETUP_FUNCS := ["_ready", "_init", "_enter_tree"]


## Editor-first check: flags scripts that create Node instances in setup functions and add them
## to the tree — static content that should live in the .tscn where humans can see and edit it.
func _code_built_nodes(path: String) -> Array:
	var out := []
	var rx_func := RegEx.create_from_string("^func +([A-Za-z_0-9]+)")
	var rx_new := RegEx.create_from_string("([A-Z][A-Za-z0-9_]*)[.]new[(]")
	var current := ""
	var created := {}
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		var line: String = lines[i]
		var fm := rx_func.search(line)
		if fm:
			current = fm.get_string(1)
			continue
		if not (current in SETUP_FUNCS):
			continue
		for m in rx_new.search_all(line):
			var cls := m.get_string(1)
			if ClassDB.class_exists(cls) and ClassDB.is_parent_class(cls, "Node"):
				created[cls] = i + 1
	if created.is_empty():
		return out
	var text := FileAccess.get_file_as_string(path)
	if not text.contains("add_child("):
		return out
	for cls in created:
		out.append({"file": path, "line": created[cls], "severity": "warning", "kind": "editor_first",
			"message": "%s.new() + add_child() in a setup function builds scene content in code. If it is static, create it in the scene with node.add (visible/editable in the editor); if it is spawned at runtime, instance a PackedScene designed in the editor." % cls})
	return out
