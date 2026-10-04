@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Running the game from the editor and collecting its output/errors.


## scene: "main" (default) | "current" | "res://path.tscn"
func a_play(p: Dictionary):
	var target := U.p_str(p, "scene", "main")
	if EditorInterface.is_playing_scene():
		if not U.p_bool(p, "restart", true):
			return U.err("The game is already running.", "Pass restart=true or call run.stop first.")
		EditorInterface.stop_playing_scene()
		var t0 := Time.get_ticks_msec()
		while EditorInterface.is_playing_scene() and Time.get_ticks_msec() - t0 < 5000:
			await ctx.frame()
		await ctx.frame()
	ctx.flush_logs()
	var since: int = ctx.log_seq()
	# Flags the runtime autoload reads at startup (before any scene plays a sound).
	var mute := U.p_bool(p, "mute", bool(ctx.settings.get("mute_game_audio", false)) or OS.get_environment("GODOT_FORGE_MUTE") == "1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/forge"))
	var flags := FileAccess.open("res://.godot/forge/runtime_flags.json", FileAccess.WRITE)
	if flags:
		flags.store_string(JSON.stringify({"mute": mute}))
		flags.close()
	# Unsaved edits would otherwise not be in the build that runs.
	var root: Node = ctx.edited_root()
	if root and root.scene_file_path != "":
		ctx.before_write(EditorInterface.get_open_scenes())
		EditorInterface.save_all_scenes()
	match target:
		"main", "":
			var main := str(ProjectSettings.get_setting("application/run/main_scene", ""))
			if main == "":
				return U.err("No main scene is set.", "Set one with project.set_main_scene, or pass scene='current' or a path.")
			EditorInterface.play_main_scene()
		"current":
			if root == null:
				return U.err("No scene is open.")
			EditorInterface.play_current_scene()
		_:
			var sp := U.res_path(target)
			if not ResourceLoader.exists(sp):
				return U.err("Scene '%s' does not exist." % sp)
			EditorInterface.play_custom_scene(sp)
	var timeout_ms := int(U.p_float(p, "timeout", 20.0) * 1000)
	var ready: bool = await ctx.runtime.wait_ready(timeout_ms)
	var settle := U.p_float(p, "settle", 0.5)
	if ready and settle > 0.0:
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < settle * 1000.0:
			await ctx.frame()
	ctx.flush_logs()
	var errors: Array = ctx.get_logs(since, "", "error", 30)
	var out := {"playing": EditorInterface.is_playing_scene(), "connected": ready, "scene": target, "muted": mute}
	if ready:
		out["game"] = ctx.runtime.game_info
	elif EditorInterface.is_playing_scene():
		out["note"] = "The game started but the runtime did not report in. It may have hit an error at startup."
	else:
		out["note"] = "The game exited immediately. Check the errors."
	if _breaked():
		out["paused_on_error"] = true
		out["hint"] = "The debugger stopped the game at an error. Fix it, then run.play again (or run.continue to resume)."
	if not errors.is_empty():
		out["errors"] = errors
	return out


func _breaked() -> bool:
	if ctx.runtime == null:
		return false
	for s in ctx.runtime.get_sessions():
		if s.is_active() and s.is_breaked():
			return true
	return false


func a_stop(_p: Dictionary):
	var was := EditorInterface.is_playing_scene()
	EditorInterface.stop_playing_scene()
	var t0 := Time.get_ticks_msec()
	while EditorInterface.is_playing_scene() and Time.get_ticks_msec() - t0 < 5000:
		await ctx.frame()
	return {"stopped": was}


func a_status(_p: Dictionary):
	ctx.flush_logs()
	var out := {"playing": EditorInterface.is_playing_scene(), "connected": ctx.runtime.is_running(), "paused_on_error": _breaked()}
	if ctx.runtime.is_running():
		var info = await ctx.runtime.request("info", {}, 3000)
		if not U.is_err(info):
			out["game"] = info
	return out


## Resumes after the debugger stopped on an error/breakpoint.
func a_continue(_p: Dictionary):
	for s in ctx.runtime.get_sessions():
		if s.is_active() and s.is_breaked():
			s.send_message("continue", [])
			return {"continued": true}
	return {"continued": false, "note": "The game was not paused."}


## Errors (and warnings with level="warning") from the game and editor since `since`.
func a_errors(p: Dictionary):
	ctx.flush_logs()
	var entries: Array = ctx.get_logs(U.p_int(p, "since", 0), U.p_str(p, "source", ""), U.p_str(p, "level", "error"), U.p_int(p, "limit", 50))
	entries = entries.filter(func(e): return not str(e.get("message", "")).begins_with("[forge]"))
	return {"entries": entries, "last_seq": ctx.log_seq()}


## Everything the game printed (print(), push_warning, errors).
func a_output(p: Dictionary):
	ctx.flush_logs()
	var entries: Array = ctx.get_logs(U.p_int(p, "since", 0), "game", "", U.p_int(p, "limit", 200))
	return {"entries": entries, "last_seq": ctx.log_seq()}
