@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Editor state: logs, undo/redo, main screen, editor settings, status.


func a_status(_p: Dictionary):
	var root: Node = ctx.edited_root()
	var errors := 0
	var warnings := 0
	for e in ctx.logs:
		if e.get("level") == "error":
			errors += 1
		elif e.get("level") == "warning":
			warnings += 1
	return {
		"edited_scene": root.scene_file_path if root else null,
		"open_scenes": EditorInterface.get_open_scenes(),
		"selected": EditorInterface.get_selection().get_selected_nodes().map(func(n): return ctx.node_path_str(n)),
		"playing": EditorInterface.is_playing_scene(),
		"playing_scene": EditorInterface.get_playing_scene(),
		"game_connected": ctx.runtime.is_running() if ctx.runtime else false,
		"clients": ctx.server.clients() if ctx.server else [],
		"log_counts": {"errors": errors, "warnings": warnings, "last_seq": ctx.log_seq()},
		"settings": ctx.settings,
		"headless": DisplayServer.get_name() == "headless",
	}


## Logs from the editor and the running game. level: "error" | "warning" | "" (all).
func a_logs(p: Dictionary):
	ctx.flush_logs()
	var entries: Array = ctx.get_logs(U.p_int(p, "since", 0), U.p_str(p, "source", ""), U.p_str(p, "level", ""), U.p_int(p, "limit", 100))
	if not U.p_bool(p, "include_forge", false):
		entries = entries.filter(func(e): return not str(e.get("message", "")).contains("Godot Forge") and not str(e.get("message", "")).begins_with("[forge]"))
	return {"entries": entries, "last_seq": ctx.log_seq()}


func a_clear_logs(_p: Dictionary):
	ctx.logs.clear()
	return {"cleared": true, "last_seq": ctx.log_seq()}


func a_undo(p: Dictionary):
	return await _history(p, true)


func a_redo(p: Dictionary):
	return await _history(p, false)


func _history(p: Dictionary, undo: bool):
	var root: Node = ctx.edited_root()
	var u := ctx.ur()
	var hid := u.get_object_history_id(root) if root else EditorUndoRedoManager.GLOBAL_HISTORY
	var h: UndoRedo = u.get_history_undo_redo(hid)
	var steps := maxi(1, U.p_int(p, "steps", 1))
	var names := []
	for i in steps:
		if undo and not h.has_undo():
			break
		if not undo and not h.has_redo():
			break
		var version := h.get_version()
		var global_h: UndoRedo = u.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
		var global_version := global_h.get_version()
		if undo:
			names.append(h.get_current_action_name())
		# Go through the editor's own Undo/Redo shortcut so its history bookkeeping stays consistent.
		var ev := InputEventKey.new()
		ev.keycode = KEY_Z if undo else KEY_Y
		ev.command_or_control_autoremap = true
		ev.pressed = true
		EditorInterface.get_base_control().get_viewport().push_input(ev)
		var rel: InputEventKey = ev.duplicate()
		rel.pressed = false
		EditorInterface.get_base_control().get_viewport().push_input(rel)
		await ctx.frame()
		if h.get_version() == version and global_h.get_version() == global_version:
			# Shortcut not handled (focus in a text field, custom keymap...): fall back.
			if undo: h.undo()
			else: h.redo()
		if not undo:
			names.append(h.get_current_action_name())
	ctx.mark_dirty()
	return {"undone" if undo else "redone": names, "can_undo": h.has_undo(), "can_redo": h.has_redo()}


func a_main_screen(p: Dictionary):
	var name := U.p_str(p, "name", "2D")
	EditorInterface.set_main_screen_editor(name)
	return {"main_screen": name}


func a_get_setting(p: Dictionary):
	var es := EditorInterface.get_editor_settings()
	var name := U.p_str(p, "name")
	if not es.has_setting(name):
		return U.err("Editor setting '%s' not found." % name)
	return {"name": name, "value": es.get_setting(name)}


func a_set_setting(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var es := EditorInterface.get_editor_settings()
	var name := U.p_str(p, "name")
	var cur = es.get_setting(name) if es.has_setting(name) else null
	var v = U.coerce(p.get("value"), typeof(cur) if cur != null else TYPE_NIL)
	if U.is_err(v): return v
	es.set_setting(name, v)
	if name.begins_with("godot_forge/"):
		ctx.settings[name.substr(12)] = v
	return {"name": name, "value": v}


## Godot Forge behaviour switches (autosave, auto_changeset, screenshot_max_size).
func a_forge_settings(p: Dictionary):
	var es := EditorInterface.get_editor_settings()
	for k in U.p_dict(p, "set"):
		if ctx.settings.has(k):
			ctx.settings[k] = U._auto(p.set[k])
			es.set_setting("godot_forge/" + k, ctx.settings[k])
	return ctx.settings


func a_restart(p: Dictionary):
	ctx.before_write(EditorInterface.get_open_scenes())
	EditorInterface.restart_editor.call_deferred(U.p_bool(p, "save", true))
	return {"restarting": true, "note": "The connection drops; the MCP server reconnects automatically."}


func a_notify(p: Dictionary):
	var msg := U.p_str(p, "message")
	if EditorInterface.has_method("get_editor_toaster") and DisplayServer.get_name() != "headless":
		EditorInterface.get_editor_toaster().push_toast(msg, EditorToaster.SEVERITY_INFO)
	print_rich("[color=#6cf][AI][/color] " + msg)
	return {"shown": msg}
