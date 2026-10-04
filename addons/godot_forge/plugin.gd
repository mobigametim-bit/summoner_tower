@tool
extends EditorPlugin
## Godot Forge editor plugin: hosts the loopback WebSocket that the MCP server connects to,
## routes requests to handlers, bridges to the running game through the debugger, and
## provides the review dock.

const Ctx = preload("res://addons/godot_forge/core/context.gd")
const Router = preload("res://addons/godot_forge/core/router.gd")
const WsServer = preload("res://addons/godot_forge/core/ws_server.gd")
const DebuggerBridge = preload("res://addons/godot_forge/runtime/debugger_bridge.gd")

const DEFAULT_PORT := 6550
const AUTOLOAD_NAME := "ForgeRuntime"
const AUTOLOAD_PATH := "res://addons/godot_forge/runtime/forge_runtime.gd"

const HANDLERS := {
	"project": "res://addons/godot_forge/handlers/project.gd",
	"files": "res://addons/godot_forge/handlers/files.gd",
	"editor": "res://addons/godot_forge/handlers/editor.gd",
	"scene": "res://addons/godot_forge/handlers/scene.gd",
	"node": "res://addons/godot_forge/handlers/node.gd",
	"signal": "res://addons/godot_forge/handlers/signal.gd",
	"script": "res://addons/godot_forge/handlers/script.gd",
	"resource": "res://addons/godot_forge/handlers/resource.gd",
	"introspect": "res://addons/godot_forge/handlers/introspect.gd",
	"run": "res://addons/godot_forge/handlers/run.gd",
	"view": "res://addons/godot_forge/handlers/view.gd",
	"game": "res://addons/godot_forge/handlers/game.gd",
	"exec": "res://addons/godot_forge/handlers/exec.gd",
	"animation": "res://addons/godot_forge/handlers/animation.gd",
	"tiles": "res://addons/godot_forge/handlers/tiles.gd",
	"shader": "res://addons/godot_forge/handlers/shader.gd",
	"world3d": "res://addons/godot_forge/handlers/world3d.gd",
	"physics": "res://addons/godot_forge/handlers/physics.gd",
	"navigation": "res://addons/godot_forge/handlers/navigation.gd",
	"ui": "res://addons/godot_forge/handlers/ui.gd",
	"audio": "res://addons/godot_forge/handlers/audio.gd",
	"particles": "res://addons/godot_forge/handlers/particles.gd",
	"assets": "res://addons/godot_forge/handlers/assets.gd",
	"changes": "res://addons/godot_forge/handlers/changes.gd",
	"export": "res://addons/godot_forge/handlers/export.gd",
	"test": "res://addons/godot_forge/handlers/test.gd",
}

var ctx
var router
var server
var debugger
var dock: Control
var agent_dock: Control
var _editor_logger
var _session_paths: Array = []
var _parent_pid := 0
var _watchdog_t := 0.0
var _had_client := false
var _boost_until := 0
var _saved_sleep := -1


func _enter_tree() -> void:
	if OS.get_environment("GODOT_FORGE_NO_SERVER") == "1":
		return  # CLI export/import/doctool run started by the MCP server
	_parent_pid = int(OS.get_environment("GODOT_FORGE_PARENT_PID")) if OS.get_environment("GODOT_FORGE_PARENT_PID").is_valid_int() else 0
	ctx = Ctx.new(self)
	router = Router.new(ctx)
	ctx.router = router
	for domain in HANDLERS:
		var path: String = HANDLERS[domain]
		if not ResourceLoader.exists(path):
			continue
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			push_warning("Godot Forge: failed to load handler " + path)
			continue
		router.register(domain, script.new())
	if router.handlers.has("changes"):
		ctx.changes = router.handlers["changes"]

	server = WsServer.new(router)
	ctx.server = server
	var port := int(OS.get_environment("GODOT_FORGE_PORT")) if OS.get_environment("GODOT_FORGE_PORT") != "" else DEFAULT_PORT
	if not server.start(port):
		push_error("Godot Forge: could not open a WebSocket port in range %d-%d." % [port, port + 30])
	else:
		_publish_when_ready()

	debugger = DebuggerBridge.new()
	debugger.ctx = ctx
	ctx.runtime = debugger
	add_debugger_plugin(debugger)

	_ensure_autoload()
	_install_logger()

	if ResourceLoader.exists("res://addons/godot_forge/ui/review_dock.gd") and DisplayServer.get_name() != "headless":
		dock = load("res://addons/godot_forge/ui/review_dock.gd").new()
		dock.ctx = ctx
		dock.name = "Forge"
		add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)
	if ResourceLoader.exists("res://addons/godot_forge/ui/agent_dock.gd") and DisplayServer.get_name() != "headless":
		agent_dock = load("res://addons/godot_forge/ui/agent_dock.gd").new()
		agent_dock.ctx = ctx
		agent_dock.name = "Forge Agent"
		add_control_to_bottom_panel(agent_dock, "Forge Agent")
	# Editors launched headless by the MCP server exit when that server process goes away
	# (on Windows the server can be terminated without running its shutdown code).
	set_process(true)


func _exit_tree() -> void:
	set_process(false)
	if server:
		server.stop()
	_remove_session()
	if debugger:
		remove_debugger_plugin(debugger)
		debugger = null
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
	if agent_dock:
		remove_control_from_bottom_panel(agent_dock)
		agent_dock.queue_free()
	if _editor_logger and OS.has_method("remove_logger"):
		OS.call("remove_logger", _editor_logger)
		_editor_logger = null


func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)


func _process(delta: float) -> void:
	if server:
		server.poll()
		_update_boost()
	if ctx:
		ctx.flush_logs()
	# An editor the MCP server launched headless lives only as long as some client uses it:
	# after its clients are gone for a while (server exited or was killed), it closes itself.
	# (OS.is_process_running can't watch non-child processes on Windows, so use the socket.)
	if _parent_pid > 0 and server:
		if server.client_count() > 0:
			_had_client = true
			_watchdog_t = 0.0
		else:
			_watchdog_t += delta
			var limit := 15.0 if _had_client else 180.0
			if _watchdog_t > limit:
				print("Godot Forge: no MCP client for %ds; closing this headless editor." % int(limit))
				_parent_pid = 0
				_remove_session()
				server.stop()
				get_tree().quit()


## Unfocused editors throttle to ~10 fps (low processor mode), which makes every AI request
## that awaits a few frames slow. While requests flow, run at full speed; restore afterwards.
func _update_boost() -> void:
	var now := Time.get_ticks_msec()
	if server.activity_msec > 0 and now - server.activity_msec < 3000:
		if _saved_sleep < 0:
			_saved_sleep = OS.low_processor_usage_mode_sleep_usec
		OS.low_processor_usage_mode_sleep_usec = 1000
	elif _saved_sleep >= 0:
		OS.low_processor_usage_mode_sleep_usec = _saved_sleep
		_saved_sleep = -1


func _ensure_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _install_logger() -> void:
	if not ClassDB.class_exists("Logger") or not OS.has_method("add_logger"):
		return
	var script = load("res://addons/godot_forge/core/logger_capture.gd")
	if script == null:
		return
	_editor_logger = script.new()
	_editor_logger.sink = ctx
	_editor_logger.source = "editor"
	OS.call("add_logger", _editor_logger)


# --- session discovery -----------------------------------------------------

func _session_data() -> Dictionary:
	var v := Engine.get_version_info()
	return {
		"port": server.port,
		"token": server.token,
		"pid": OS.get_process_id(),
		"project_path": ProjectSettings.globalize_path("res://").trim_suffix("/"),
		"project_name": str(ProjectSettings.get_setting("application/config/name", "")),
		"godot_version": "%d.%d.%d" % [v.major, v.minor, v.patch],
		"plugin_version": ctx.PLUGIN_VERSION,
		"headless": DisplayServer.get_name() == "headless",
		"started_at": Time.get_unix_time_from_system(),
		"lsp_port": _lsp_port(),
		"parent_pid": _parent_pid,
	}


## Clients discover the editor through the session file; only publish it once the first
## filesystem scan/import is done so requests never hit a half-loaded project.
func _publish_when_ready() -> void:
	await get_tree().process_frame
	var start := Time.get_ticks_msec()
	while EditorInterface.get_resource_filesystem().is_scanning() and Time.get_ticks_msec() - start < 300000:
		await get_tree().process_frame
	if server == null:
		return
	_write_session()
	print_rich("[color=#6cf]Godot Forge[/color] listening on 127.0.0.1:%d" % server.port)


func _lsp_port() -> int:
	# The engine consumes --lsp-port, so launchers also pass it in GODOT_FORGE_LSP_PORT.
	var env := OS.get_environment("GODOT_FORGE_LSP_PORT")
	if env.is_valid_int():
		return int(env)
	if DisplayServer.get_name() == "headless":
		return 0  # the language server only runs headless when --lsp-port is given
	var es := EditorInterface.get_editor_settings()
	return int(es.get_setting("network/language_server/remote_port")) if es.has_setting("network/language_server/remote_port") else 6005


func _write_session() -> void:
	var data := JSON.stringify(_session_data(), "  ")
	var local_dir := ProjectSettings.globalize_path("res://.godot/forge")
	DirAccess.make_dir_recursive_absolute(local_dir)
	_write_file(local_dir.path_join("session.json"), data)
	var home := OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	if home != "":
		var global_dir := home.path_join(".godot-forge").path_join("sessions")
		DirAccess.make_dir_recursive_absolute(global_dir)
		_write_file(global_dir.path_join("%d.json" % OS.get_process_id()), data)


func _write_file(path: String, data: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(data)
		f.close()
		_session_paths.append(path)


func _remove_session() -> void:
	for p in _session_paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	_session_paths.clear()
