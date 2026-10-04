@tool
extends EditorDebuggerPlugin
## Editor side of the runtime bridge. Sends "forge:<cmd>" messages to the running game and
## waits for "forge:reply". Game logs arrive as "forge:log" and land in the shared log buffer.

const U = preload("res://addons/godot_forge/core/util.gd")

signal game_ready(info: Dictionary)
signal game_stopped

var ctx
var game_info := {}
var active_session := -1
var _replies := {}
var _next_id := 1
var _sessions_hooked := {}


func _has_capture(capture: String) -> bool:
	return capture == "forge"


func _setup_session(session_id: int) -> void:
	var s := get_session(session_id)
	if s == null or _sessions_hooked.has(session_id):
		return
	_sessions_hooked[session_id] = true
	s.started.connect(_on_started.bind(session_id))
	s.stopped.connect(_on_stopped.bind(session_id))


func _on_started(session_id: int) -> void:
	# The game may take a moment before the runtime autoload announces itself.
	if ctx:
		ctx.push_log({"source": "editor", "level": "info", "message": "[forge] game session %d started" % session_id})


func _on_stopped(session_id: int) -> void:
	if session_id == active_session:
		active_session = -1
		game_info = {}
		game_stopped.emit()
		if ctx and ctx.server:
			ctx.server.broadcast("game_stopped", {})


func _capture(message: String, data: Array, session_id: int) -> bool:
	match message:
		"forge:ready":
			var info = JSON.parse_string(str(data[0])) if data.size() > 0 else {}
			game_info = info if info is Dictionary else {}
			active_session = session_id
			game_ready.emit(game_info)
			if ctx and ctx.server:
				ctx.server.broadcast("game_started", game_info)
			return true
		"forge:reply":
			var id := int(data[0])
			var parsed = JSON.parse_string(str(data[1])) if data.size() > 1 else null
			_replies[id] = parsed
			return true
		"forge:log":
			var entries = JSON.parse_string(str(data[0])) if data.size() > 0 else []
			if entries is Array and ctx:
				for e in entries:
					if e is Dictionary:
						e["source"] = "game"
						ctx.push_log(e)
			return true
	return false


func is_running() -> bool:
	if active_session < 0:
		return false
	var s := get_session(active_session)
	return s != null and s.is_active() and not game_info.is_empty()


## Waits until the runtime announced itself (after run.play).
func wait_ready(timeout_ms: int = 15000) -> bool:
	var start := Time.get_ticks_msec()
	while not is_running() and Time.get_ticks_msec() - start < timeout_ms:
		await ctx.frame()
	return is_running()


func request(cmd: String, params: Dictionary = {}, timeout_ms: int = 15000):
	if not is_running():
		if EditorInterface.is_playing_scene():
			var ok: bool = await wait_ready(5000)
			if not ok:
				return U.err("The game is running but the Godot Forge runtime did not respond.", "Make sure the ForgeRuntime autoload is enabled (Project Settings > Autoload) and the game was started from the editor with debugging on.")
		else:
			return U.err("The game is not running.", "Start it with run.play (scene: optional).")
	var session := get_session(active_session)
	if session.is_breaked():
		return U.err("The game is paused at a breakpoint or error in the debugger.", "Check run.errors / editor.logs, then continue or stop the game (run.stop).")
	var id := _next_id
	_next_id += 1
	session.send_message("forge:" + cmd, [id, JSON.stringify(params)])
	var start := Time.get_ticks_msec()
	while not _replies.has(id):
		if Time.get_ticks_msec() - start > timeout_ms:
			return U.err("Timed out after %dms waiting for the game to answer '%s'." % [timeout_ms, cmd], "The game may be frozen, stuck at a breakpoint, or closed.")
		if not is_running():
			return U.err("The game stopped while handling '%s'." % cmd, "Check run.errors for a crash.")
		if session.is_breaked():
			ctx.flush_logs()
			var recent: Array = ctx.get_logs(0, "game", "error", 3)
			return U.err("The game hit an error while handling '%s' and the debugger paused it." % cmd, "Fix the error, then run.play again (or run.continue to resume).", {"errors": recent.map(func(x): return "%s (%s:%s)" % [x.get("message", ""), x.get("script_file", x.get("file", "")), x.get("script_line", x.get("line", ""))])})
		await ctx.frame()
	var r = _replies[id]
	_replies.erase(id)
	return r
