@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Project level information and settings: settings, autoloads, input map, layers, plugins.

const InputSpec = preload("res://addons/godot_forge/core/input_spec.gd")


func a_info(_p: Dictionary):
	var v := Engine.get_version_info()
	var root: Node = ctx.edited_root()
	var counts := {"scenes": 0, "scripts": 0, "resources": 0, "images": 0, "audio": 0, "models": 0}
	_count(ctx.fs().get_filesystem(), counts)
	var autoloads := {}
	for prop in ProjectSettings.get_property_list():
		var n: String = prop.name
		if n.begins_with("autoload/"):
			autoloads[n.substr(9)] = U.res_path(str(ProjectSettings.get_setting(n)).trim_prefix("*"))
	var actions := []
	for prop in ProjectSettings.get_property_list():
		var n2: String = prop.name
		if n2.begins_with("input/") and not n2.begins_with("input/ui_"):
			actions.append(n2.substr(6))
	return {
		"name": ProjectSettings.get_setting("application/config/name", ""),
		"path": ProjectSettings.globalize_path("res://").trim_suffix("/"),
		"godot_version": "%d.%d.%d" % [v.major, v.minor, v.patch],
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
		"viewport": {
			"width": ProjectSettings.get_setting("display/window/size/viewport_width", 1152),
			"height": ProjectSettings.get_setting("display/window/size/viewport_height", 648),
			"stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode", "disabled"),
		},
		"features": ProjectSettings.get_setting("application/config/features", PackedStringArray()),
		"autoloads": autoloads,
		"input_actions": actions,
		"file_counts": counts,
		"open_scenes": EditorInterface.get_open_scenes(),
		"edited_scene": root.scene_file_path if root else null,
		"playing": EditorInterface.is_playing_scene(),
		"dotnet": ClassDB.class_exists("CSharpScript"),
		"has_ai_memory_file": FileAccess.file_exists("res://GODOT_AI.md"),
	}


func _count(dir: EditorFileSystemDirectory, counts: Dictionary) -> void:
	if dir == null:
		return
	for i in dir.get_file_count():
		var t := dir.get_file_type(i)
		var f := dir.get_file(i)
		if t == "PackedScene":
			counts.scenes += 1
		elif t in ["GDScript", "CSharpScript"]:
			counts.scripts += 1
		elif t in ["CompressedTexture2D", "Texture2D", "Image"]:
			counts.images += 1
		elif t.begins_with("Audio"):
			counts.audio += 1
		elif f.get_extension() in ["glb", "gltf", "fbx", "obj", "blend"]:
			counts.models += 1
		else:
			counts.resources += 1
	for j in dir.get_subdir_count():
		if dir.get_subdir(j).get_name() == "addons":
			continue
		_count(dir.get_subdir(j), counts)


# --- settings --------------------------------------------------------------

func a_get_setting(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var name := U.p_str(p, "name")
	if not ProjectSettings.has_setting(name):
		return U.err("Setting '%s' not found." % name, "Use project.list_settings with a prefix, e.g. 'display/window'.")
	return {"name": name, "value": ProjectSettings.get_setting(name)}


func a_list_settings(p: Dictionary):
	var prefix := U.p_str(p, "prefix", "")
	var out := {}
	for prop in ProjectSettings.get_property_list():
		var n: String = prop.name
		if prefix != "" and not n.begins_with(prefix):
			continue
		if not (prop.usage & PROPERTY_USAGE_EDITOR) and prefix == "":
			continue
		out[n] = ProjectSettings.get_setting(n)
		if out.size() >= U.p_int(p, "limit", 300):
			break
	return out


func a_set_setting(p: Dictionary):
	var settings := U.p_dict(p, "settings")
	if settings.is_empty():
		var e = U.require(p, ["name"])
		if e: return e
		settings = {U.p_str(p, "name"): p.get("value")}
	ctx.before_write(["res://project.godot"])
	var applied := {}
	for name in settings:
		var value = settings[name]
		var v = value
		if ProjectSettings.has_setting(name):
			var cur = ProjectSettings.get_setting(name)
			var info := _setting_info(name)
			v = U.coerce(value, typeof(cur) if cur != null else TYPE_NIL, info.get("hint", 0), info.get("hint_string", ""))
		else:
			v = U._auto(value)
		if U.is_err(v):
			return v
		if v is Resource and (v as Resource).resource_path != "":
			v = (v as Resource).resource_path
		ProjectSettings.set_setting(name, v)
		applied[name] = v
	var err := ProjectSettings.save()
	if err != OK:
		return U.err("Failed to save project.godot (error %d)." % err)
	return {"applied": applied}


func a_set_main_scene(p: Dictionary):
	var e = U.require(p, ["scene"])
	if e: return e
	var sp := U.res_path(U.p_str(p, "scene"))
	if not ResourceLoader.exists(sp):
		return U.err("Scene '%s' does not exist." % sp)
	ctx.before_write(["res://project.godot"])
	ProjectSettings.set_setting("application/run/main_scene", sp)
	ProjectSettings.save()
	return {"main_scene": sp}


func _setting_info(name: String) -> Dictionary:
	for prop in ProjectSettings.get_property_list():
		if prop.name == name:
			return prop
	return {}


# --- autoloads -------------------------------------------------------------

func a_autoloads(_p: Dictionary):
	var out := []
	for prop in ProjectSettings.get_property_list():
		var n: String = prop.name
		if n.begins_with("autoload/"):
			var v := str(ProjectSettings.get_setting(n))
			out.append({"name": n.substr(9), "path": U.res_path(v.trim_prefix("*")), "enabled": v.begins_with("*")})
	return out


func a_add_autoload(p: Dictionary):
	var e = U.require(p, ["name", "path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not FileAccess.file_exists(path):
		return U.err("File '%s' does not exist." % path, "Autoloads must be a .gd/.cs script or a .tscn scene.")
	ctx.before_write(["res://project.godot"])
	ctx.plugin.add_autoload_singleton(U.p_str(p, "name"), path)
	return {"name": U.p_str(p, "name"), "path": path}


func a_remove_autoload(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var name := U.p_str(p, "name")
	if not ProjectSettings.has_setting("autoload/" + name):
		return U.err("Autoload '%s' not found." % name)
	ctx.before_write(["res://project.godot"])
	ctx.plugin.remove_autoload_singleton(name)
	return {"removed": name}


# --- input map -------------------------------------------------------------

func a_input_actions(p: Dictionary):
	var include_builtin := U.p_bool(p, "include_builtin", false)
	var out := {}
	for prop in ProjectSettings.get_property_list():
		var n: String = prop.name
		if not n.begins_with("input/"):
			continue
		var action := n.substr(6)
		if action.begins_with("ui_") and not include_builtin:
			continue
		var d = ProjectSettings.get_setting(n)
		var evs := []
		if d is Dictionary:
			for ev in d.get("events", []):
				if ev is InputEvent:
					evs.append(InputSpec.describe(ev))
		out[action] = {"events": evs, "deadzone": d.get("deadzone", 0.5) if d is Dictionary else 0.5}
	return out


## Adds or replaces an input action. events: ["key:W", "key:Up", "joy:a", "joy_axis:left_x+"]
func a_add_input_action(p: Dictionary):
	var actions := U.p_dict(p, "actions")
	if actions.is_empty():
		var e = U.require(p, ["name"])
		if e: return e
		actions = {U.p_str(p, "name"): U.p_arr(p, "events")}
	ctx.before_write(["res://project.godot"])
	var result := {}
	for action in actions:
		var key := "input/" + str(action)
		var existing = ProjectSettings.get_setting(key, null)
		var evs: Array = []
		if U.p_bool(p, "append", false) and existing is Dictionary:
			evs = existing.get("events", []).duplicate()
		var specs = actions[action]
		for spec in (specs if specs is Array else [specs]):
			var ev = InputSpec.parse(spec)
			if ev is String:
				return U.err("Action '%s': %s" % [action, ev])
			if "pressed" in ev:
				ev.pressed = false
			if ev is InputEventKey:
				ev.keycode = KEY_NONE  # physical keys are layout independent, like the editor default
			evs.append(ev)
		ProjectSettings.set_setting(key, {"deadzone": U.p_float(p, "deadzone", 0.2), "events": evs})
		var descr := []
		for ev2 in evs:
			descr.append(InputSpec.describe(ev2))
		result[action] = descr
	ProjectSettings.save()
	return {"actions": result, "note": "Input actions are saved to project.godot; the running game picks them up on next launch."}


func a_remove_input_action(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var key := "input/" + U.p_str(p, "name")
	if not ProjectSettings.has_setting(key):
		return U.err("Input action '%s' not found." % U.p_str(p, "name"))
	ctx.before_write(["res://project.godot"])
	ProjectSettings.clear(key)
	ProjectSettings.save()
	return {"removed": U.p_str(p, "name")}


# --- layers ----------------------------------------------------------------

const LAYER_KINDS := ["2d_physics", "2d_render", "2d_navigation", "3d_physics", "3d_render", "3d_navigation", "avoidance"]


func a_layers(p: Dictionary):
	var kinds: Array = [U.p_str(p, "kind")] if p.has("kind") else LAYER_KINDS
	var out := {}
	for kind in kinds:
		var names := {}
		for i in range(1, 33):
			var key := "layer_names/%s/layer_%d" % [kind, i]
			var n := str(ProjectSettings.get_setting(key, ""))
			if n != "":
				names[i] = n
		out[kind] = names
	return out


func a_set_layer_name(p: Dictionary):
	var e = U.require(p, ["kind", "layer", "name"])
	if e: return e
	var kind := U.p_str(p, "kind")
	if not kind in LAYER_KINDS:
		return U.err("Unknown layer kind '%s'." % kind, "Use one of " + ", ".join(LAYER_KINDS))
	var layer := U.p_int(p, "layer")
	if layer < 1 or layer > 32:
		return U.err("Layer must be 1..32.")
	ctx.before_write(["res://project.godot"])
	ProjectSettings.set_setting("layer_names/%s/layer_%d" % [kind, layer], U.p_str(p, "name"))
	ProjectSettings.save()
	return {"kind": kind, "layer": layer, "name": U.p_str(p, "name"), "bit_value": 1 << (layer - 1)}


# --- plugins ---------------------------------------------------------------

func a_plugins(_p: Dictionary):
	var out := []
	var dir := DirAccess.open("res://addons")
	if dir == null:
		return out
	for sub in dir.get_directories():
		var cfg_path := "res://addons/%s/plugin.cfg" % sub
		if FileAccess.file_exists(cfg_path):
			var cfg := ConfigFile.new()
			cfg.load(cfg_path)
			out.append({"name": sub, "title": cfg.get_value("plugin", "name", sub), "version": cfg.get_value("plugin", "version", ""), "enabled": EditorInterface.is_plugin_enabled(sub)})
	return out


func a_set_plugin_enabled(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var name := U.p_str(p, "name")
	if name == "godot_forge":
		return U.err("Refusing to toggle Godot Forge itself over its own connection.")
	EditorInterface.set_plugin_enabled(name, U.p_bool(p, "enabled", true))
	return {"name": name, "enabled": EditorInterface.is_plugin_enabled(name)}


# --- uid -------------------------------------------------------------------

func a_uid(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var s := U.p_str(p, "path")
	if s.begins_with("uid://"):
		var id := ResourceUID.text_to_id(s)
		if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
			return U.err("Unknown UID '%s'." % s)
		return {"uid": s, "path": ResourceUID.get_id_path(id)}
	var rp := U.res_path(s)
	var id2 := ResourceLoader.get_resource_uid(rp)
	if id2 == ResourceUID.INVALID_ID:
		return U.err("No UID for '%s'." % rp, "Only imported/saved resources have UIDs.")
	return {"path": rp, "uid": ResourceUID.id_to_text(id2)}
