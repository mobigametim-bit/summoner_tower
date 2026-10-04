extends Node
## Godot Forge runtime agent. Autoloaded into the game; only activates when the game was
## launched from the editor with the debugger attached, so exported builds are unaffected.
## Talks to the editor through EngineDebugger messages ("forge:*"), no extra ports.

const U = preload("res://addons/godot_forge/core/util.gd")
const InputSpec = preload("res://addons/godot_forge/core/input_spec.gd")

var _active := false
var _logger
var _log_mutex := Mutex.new()
var _pending_logs: Array = []
var _log_seq := 0
var _recent_errors: Array = []
var _flushing := false

var _recording := false
var _record_start_ms := 0
var _recorded: Array = []
var _record_motion := false
var _held_actions := {}

var _last_shot_size := Vector2i.ZERO


func _ready() -> void:
	if Engine.is_editor_hint() or not EngineDebugger.is_active():
		set_process(false)
		return
	_active = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_flags()
	EngineDebugger.register_message_capture("forge", _on_message)
	_install_logger()
	get_tree().root.window_input.connect(_on_window_input)
	# Defer so the main scene exists when the editor asks for it.
	_announce.call_deferred()


func _exit_tree() -> void:
	if _active:
		if EngineDebugger.has_capture("forge"):
			EngineDebugger.unregister_message_capture("forge")
		if _logger and OS.has_method("remove_logger"):
			OS.call("remove_logger", _logger)


## Startup flags written by the editor's run.play (e.g. mute audio for AI playtests).
func _apply_flags() -> void:
	var path := "res://.godot/forge/runtime_flags.json"
	if not FileAccess.file_exists(path):
		return
	var flags = JSON.parse_string(FileAccess.get_file_as_string(path))
	if flags is Dictionary and flags.get("mute", false):
		AudioServer.set_bus_mute(0, true)


func c_audio(p: Dictionary):
	if p.has("mute"):
		AudioServer.set_bus_mute(0, U.p_bool(p, "mute"))
	if p.has("volume_db"):
		AudioServer.set_bus_volume_db(0, U.p_float(p, "volume_db"))
	var playing := []
	for n in get_tree().root.find_children("*", "AudioStreamPlayer", true, false) + get_tree().root.find_children("*", "AudioStreamPlayer2D", true, false) + get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		if n.playing:
			playing.append(str(get_tree().current_scene.get_path_to(n)) if get_tree().current_scene else str(n.get_path()))
	return {"master_muted": AudioServer.is_bus_mute(0), "master_volume_db": AudioServer.get_bus_volume_db(0), "playing": playing}


func _announce() -> void:
	EngineDebugger.send_message("forge:ready", [JSON.stringify(_info())])


func _info() -> Dictionary:
	var scene := get_tree().current_scene
	return {
		"pid": OS.get_process_id(),
		"scene": scene.scene_file_path if scene else "",
		"scene_root": str(scene.name) if scene else "",
		"viewport_size": var_to_str(get_viewport().get_visible_rect().size),
		"window_size": var_to_str(DisplayServer.window_get_size()),
		"renderer": RenderingServer.get_current_rendering_method(),
		"headless": DisplayServer.get_name() == "headless",
		"time_scale": Engine.time_scale,
		"paused": get_tree().paused,
		"fps": Engine.get_frames_per_second(),
		"frame": Engine.get_process_frames(),
		"uptime_s": Time.get_ticks_msec() / 1000.0,
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}


func _process(_delta: float) -> void:
	_flush_logs()


# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

func _install_logger() -> void:
	if not ClassDB.class_exists("Logger") or not OS.has_method("add_logger"):
		return
	var script = load("res://addons/godot_forge/core/logger_capture.gd")
	if script == null:
		return
	_logger = script.new()
	_logger.sink = self
	_logger.source = "game"
	OS.call("add_logger", _logger)


## Called by the logger from any thread.
func push_log(entry: Dictionary) -> void:
	_log_mutex.lock()
	entry["time"] = Time.get_unix_time_from_system()
	entry["frame"] = Engine.get_process_frames()
	_pending_logs.append(entry)
	_log_mutex.unlock()
	# Errors can be followed by a debugger break that stalls _process, so send them now.
	if entry.get("level") == "error" and not _flushing and OS.get_thread_caller_id() == OS.get_main_thread_id():
		_flush_logs()


func _flush_logs() -> void:
	if not _active:
		return
	_log_mutex.lock()
	var pending := _pending_logs
	_pending_logs = []
	_log_mutex.unlock()
	if pending.is_empty():
		return
	_flushing = true
	for e in pending:
		_log_seq += 1
		if e.get("level") == "error":
			_recent_errors.append(e)
	if _recent_errors.size() > 50:
		_recent_errors = _recent_errors.slice(_recent_errors.size() - 50)
	EngineDebugger.send_message("forge:log", [JSON.stringify(pending)])
	_flushing = false


# ---------------------------------------------------------------------------
# Messages
# ---------------------------------------------------------------------------

func _on_message(message: String, data: Array) -> bool:
	var cmd := message.trim_prefix("forge:")
	var id = data[0] if data.size() > 0 else 0
	var params = JSON.parse_string(data[1]) if data.size() > 1 and data[1] is String else {}
	if not (params is Dictionary):
		params = {}
	_handle(cmd, id, params)
	return true


func _reply(id, result) -> void:
	var payload
	if U.is_err(result):
		payload = result
	else:
		payload = U.encode(result)
	EngineDebugger.send_message("forge:reply", [id, JSON.stringify(payload)])


func _handle(cmd: String, id, p: Dictionary) -> void:
	var fn := "c_" + cmd
	if not has_method(fn):
		_reply(id, U.err("Unknown runtime command '%s'." % cmd))
		return
	var errors_before := _recent_errors.size()
	var result = await call(fn, p)
	# Attach errors raised while the command ran (eval/exec/call usually).
	_flush_logs()
	if _recent_errors.size() > errors_before and result is Dictionary and not U.is_err(result):
		result["errors"] = _recent_errors.slice(errors_before)
	_reply(id, result)


func _scene_root() -> Node:
	var s := get_tree().current_scene
	return s if s else get_tree().root


func _find(path: String) -> Node:
	var root := _scene_root()
	path = path.strip_edges()
	if path == "" or path == ".":
		return root
	if path.begins_with("/root"):
		return get_tree().root.get_node_or_null(path)
	var n := root.get_node_or_null(path)
	if n == null:
		n = get_tree().root.get_node_or_null(path)
	if n == null and not path.contains("/"):
		# Fall back to a search by name, handy for spawned nodes with generated paths.
		n = root.find_child(path, true, false)
	return n


func _not_found(path: String) -> Dictionary:
	return U.err("Node '%s' not found in the running game." % path, "Use game.tree to list nodes. Paths are relative to the current scene root; use /root/... for autoloads.")


# ---------------------------------------------------------------------------
# Commands: state
# ---------------------------------------------------------------------------

func c_info(_p: Dictionary):
	return _info()


func c_tree(p: Dictionary):
	var start: Node = _find(U.p_str(p, "path", "")) if p.has("path") else (_scene_root() if not U.p_bool(p, "whole_tree", false) else get_tree().root)
	if start == null:
		return _not_found(U.p_str(p, "path"))
	var opts := {"depth": U.p_int(p, "depth", 6), "props": U.p_bool(p, "props", false), "expand_instances": true, "max_nodes": U.p_int(p, "max_nodes", 400)}
	var tree := U.node_tree(start, start, opts)
	return {"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene else "", "tree": tree}


func c_get(p: Dictionary):
	var n := _find(U.p_str(p, "path", ""))
	if n == null:
		return _not_found(U.p_str(p, "path"))
	var props := U.p_arr(p, "props")
	var out := {"path": str(n.get_path()), "type": n.get_class()}
	if props.is_empty():
		out["props"] = U.changed_props(n)
		if n is Node2D or n is Node3D:
			out["props"]["global_position"] = U.encode(n.global_position)
		if n is CharacterBody2D or n is CharacterBody3D:
			out["props"]["velocity"] = U.encode(n.velocity)
			out["props"]["is_on_floor"] = n.is_on_floor()
	else:
		var vals := {}
		for prop in props:
			vals[prop] = U.encode(n.get_indexed(NodePath(str(prop))))
		out["props"] = vals
	var sp = U.screen_pos(n)
	if sp != null:
		out["screen_position"] = var_to_str(sp)
	return out


func c_set(p: Dictionary):
	var n := _find(U.p_str(p, "path", ""))
	if n == null:
		return _not_found(U.p_str(p, "path"))
	var props := U.p_dict(p, "props")
	var infos := U.prop_infos(n)
	for k in props:
		var r = U.set_prop(n, k, props[k], infos)
		if U.is_err(r):
			return r
	return {"path": str(n.get_path()), "set": props.keys()}


func c_call(p: Dictionary):
	var n := _find(U.p_str(p, "path", ""))
	if n == null:
		return _not_found(U.p_str(p, "path"))
	var method := U.p_str(p, "method")
	if not n.has_method(method):
		var names := []
		for m in n.get_method_list():
			names.append(m.name)
		var s := U.suggest(method, names)
		return U.err("%s has no method '%s'." % [n.get_class(), method], "Did you mean '%s'?" % s if s != "" else "")
	var args := []
	for a in U.p_arr(p, "args"):
		args.append(U._auto(a))
	var r = n.callv(method, args)
	return {"result": U.encode(r)}


func c_eval(p: Dictionary):
	var base := _find(U.p_str(p, "path", ""))
	if base == null:
		return _not_found(U.p_str(p, "path"))
	var exprs: Array = U.p_arr(p, "expressions") if p.has("expressions") else [U.p_str(p, "expression")]
	var results := {}
	for src in exprs:
		var e := Expression.new()
		var perr := e.parse(str(src), ["tree", "root", "scene"])
		if perr != OK:
			results[str(src)] = {"error": e.get_error_text()}
			continue
		var v = e.execute([get_tree(), get_tree().root, get_tree().current_scene], base, false)
		if e.has_execute_failed():
			results[str(src)] = {"error": e.get_error_text() if e.get_error_text() != "" else "Execution failed."}
		else:
			results[str(src)] = U.encode(v)
	if exprs.size() == 1:
		var only = results.values()[0]
		if only is Dictionary and only.has("error"):
			return U.err("Expression failed: " + str(only.error), "Expressions run with the node at 'path' as self. Available names: tree, root, scene.")
		return {"value": only}
	return {"values": results}


## Runs a GDScript snippet inside the game. The snippet is the body of
## `func run(tree: SceneTree, scene: Node)`; `return` a value to get it back.
func c_exec(p: Dictionary):
	var src := U.game_snippet_source(U.p_str(p, "code"))
	var s := GDScript.new()
	s.source_code = src
	var err := s.reload()
	if err != OK:
		await get_tree().process_frame
		_flush_logs()
		return U.err("GDScript failed to compile (error %d)." % err, "Check the 'errors' in the game log (game.logs). The snippet is the body of func run(tree, scene).", {"errors": _recent_errors.slice(max(0, _recent_errors.size() - 5))})
	var obj = s.new()
	var r = await obj.run(get_tree(), get_tree().current_scene)
	return {"result": U.encode(r)}


func c_perf(_p: Dictionary):
	var m := {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_memory_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"physics_2d_active_objects": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		"physics_3d_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
	}
	var sample_s := U.p_float(_p, "sample_seconds", 0.0)
	if sample_s > 0.0:
		var frames := 0
		var worst := 0.0
		var total := 0.0
		var t0 := Time.get_ticks_usec()
		var last := t0
		while Time.get_ticks_usec() - t0 < int(sample_s * 1000000.0):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1000.0
			last = now
			frames += 1
			total += dt
			worst = max(worst, dt)
		m["sample"] = {"frames": frames, "avg_frame_ms": total / max(1, frames), "worst_frame_ms": worst}
	return m


# ---------------------------------------------------------------------------
# Commands: time
# ---------------------------------------------------------------------------

func c_time(p: Dictionary):
	if p.has("time_scale"):
		Engine.time_scale = U.p_float(p, "time_scale", 1.0)
	if p.has("paused"):
		get_tree().paused = U.p_bool(p, "paused")
	var steps := U.p_int(p, "step_frames", 0)
	if steps > 0:
		var was_paused := get_tree().paused
		get_tree().paused = false
		for i in steps:
			await get_tree().physics_frame
		get_tree().paused = was_paused
	return {"time_scale": Engine.time_scale, "paused": get_tree().paused, "frame": Engine.get_process_frames()}


## Waits for a condition: {seconds}, {condition: "expr"}, {node: "path"}, {signal: "name", path}.
func c_wait(p: Dictionary):
	var timeout := U.p_float(p, "timeout", 10.0)
	var start := Time.get_ticks_msec()
	if p.has("seconds") and not (p.has("condition") or p.has("node") or p.has("signal")):
		await get_tree().create_timer(U.p_float(p, "seconds"), true, false, false).timeout
		return {"waited_s": (Time.get_ticks_msec() - start) / 1000.0}
	if p.has("signal"):
		var n := _find(U.p_str(p, "path", ""))
		if n == null:
			return _not_found(U.p_str(p, "path"))
		var sig := U.p_str(p, "signal")
		if not n.has_signal(sig):
			return U.err("%s has no signal '%s'." % [n.get_class(), sig])
		var fired := [false, []]
		var cb := func(a = null, b = null, c = null, d = null):
			fired[0] = true
			fired[1] = [a, b, c, d].filter(func(x): return x != null)
		n.connect(sig, cb, CONNECT_ONE_SHOT)
		while not fired[0] and Time.get_ticks_msec() - start < timeout * 1000.0:
			await get_tree().process_frame
		if not fired[0]:
			if n.is_connected(sig, cb):
				n.disconnect(sig, cb)
			return U.err("Timed out after %.1fs waiting for signal '%s'." % [timeout, sig])
		return {"fired": true, "args": U.encode(fired[1]), "waited_s": (Time.get_ticks_msec() - start) / 1000.0}
	if p.has("node"):
		var np := U.p_str(p, "node")
		var gone := U.p_bool(p, "gone", false)
		while Time.get_ticks_msec() - start < timeout * 1000.0:
			var exists := _find(np) != null
			if exists != gone:
				return {"ok": true, "waited_s": (Time.get_ticks_msec() - start) / 1000.0}
			await get_tree().process_frame
		return U.err("Timed out after %.1fs waiting for node '%s' to %s." % [timeout, np, "disappear" if gone else "exist"])
	if p.has("condition"):
		var base := _find(U.p_str(p, "path", ""))
		var e := Expression.new()
		if e.parse(U.p_str(p, "condition"), ["tree", "root", "scene"]) != OK:
			return U.err("Bad condition: " + e.get_error_text())
		var last = null
		while Time.get_ticks_msec() - start < timeout * 1000.0:
			last = e.execute([get_tree(), get_tree().root, get_tree().current_scene], base, false)
			if not e.has_execute_failed() and bool(last):
				return {"ok": true, "waited_s": (Time.get_ticks_msec() - start) / 1000.0}
			await get_tree().process_frame
		return U.err("Timed out after %.1fs; condition '%s' last evaluated to %s." % [timeout, U.p_str(p, "condition"), str(last)])
	return U.err("wait needs one of: seconds, condition, node, signal.")


## Records property values over time: {path, props: [...], seconds, interval}.
func c_sample(p: Dictionary):
	var n := _find(U.p_str(p, "path", ""))
	if n == null:
		return _not_found(U.p_str(p, "path"))
	var props := U.p_arr(p, "props")
	if props.is_empty():
		props = ["global_position"] if (n is Node2D or n is Node3D) else ["position"]
	var seconds := U.p_float(p, "seconds", 1.0)
	var interval := maxf(0.016, U.p_float(p, "interval", 0.1))
	var samples := []
	var start := Time.get_ticks_msec()
	var next_t := 0.0
	while true:
		var t := (Time.get_ticks_msec() - start) / 1000.0
		if t >= next_t:
			if not is_instance_valid(n):
				samples.append({"t": snappedf(t, 0.001), "freed": true})
				break
			var row := {"t": snappedf(t, 0.001)}
			for prop in props:
				row[prop] = U.encode(n.get_indexed(NodePath(str(prop))))
			samples.append(row)
			next_t += interval
		if t >= seconds:
			break
		await get_tree().process_frame
	return {"samples": samples}


# ---------------------------------------------------------------------------
# Commands: screenshots
# ---------------------------------------------------------------------------

func c_screenshot(p: Dictionary):
	if DisplayServer.get_name() == "headless":
		return U.err("The game runs headless, there is nothing to capture.", "Run the editor with a display (not --headless) to use screenshots.")
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return U.err("Could not read the viewport image.")
	var vis := vp.get_visible_rect().size
	if U.p_bool(p, "annotate", false):
		_annotate(img, vis, U.p_arr(p, "annotate_groups"), U.p_str(p, "annotate_path", ""))
	var shot := U.image_to_b64(img, U.p_int(p, "max_size", 1280), U.p_str(p, "format", "png"))
	_last_shot_size = Vector2i(shot.width, shot.height)
	shot["viewport_size"] = var_to_str(vis)
	shot["coord_scale"] = vis.x / float(shot.width)
	return shot


## Draws labelled markers for nodes onto the image so the model can map pixels to nodes.
func _annotate(img: Image, vis: Vector2, groups: Array, under: String) -> void:
	var root: Node = _find(under) if under != "" else _scene_root()
	if root == null:
		return
	img.convert(Image.FORMAT_RGBA8)
	var sx := img.get_width() / vis.x
	var sy := img.get_height() / vis.y
	var nodes := []
	_collect_annotatable(root, nodes, groups, 0)
	var palette := [Color.RED, Color.YELLOW, Color.CYAN, Color.MAGENTA, Color.LIME, Color.ORANGE]
	var i := 0
	for n in nodes:
		var col: Color = palette[i % palette.size()]
		i += 1
		if n is Control and (n as Control).is_visible_in_tree():
			var xf: Transform2D = n.get_global_transform_with_canvas()
			var r := Rect2(xf.origin * Vector2(sx, sy), n.size * xf.get_scale() * Vector2(sx, sy))
			_rect_outline(img, Rect2i(r), col)
		else:
			var sp = U.screen_pos(n)
			if sp != null:
				var c := Vector2i(int(sp.x * sx), int(sp.y * sy))
				_cross(img, c, 6, col)


func _collect_annotatable(n: Node, out: Array, groups: Array, depth: int) -> void:
	if depth > 8 or out.size() > 60:
		return
	var include := false
	if groups.is_empty():
		include = (n is Node2D or n is Node3D or n is Control) and depth > 0
	else:
		for g in groups:
			if n.is_in_group(g):
				include = true
	if include:
		out.append(n)
	for c in n.get_children():
		_collect_annotatable(c, out, groups, depth + 1)


func _rect_outline(img: Image, r: Rect2i, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for x in range(max(0, r.position.x), min(w, r.end.x)):
		for y in [r.position.y, r.end.y - 1]:
			if y >= 0 and y < h:
				img.set_pixel(x, y, col)
	for y in range(max(0, r.position.y), min(h, r.end.y)):
		for x in [r.position.x, r.end.x - 1]:
			if x >= 0 and x < w:
				img.set_pixel(x, y, col)


func _cross(img: Image, c: Vector2i, size: int, col: Color) -> void:
	for d in range(-size, size + 1):
		for t in [-1, 0, 1]:
			var a := Vector2i(c.x + d, c.y + t)
			var b := Vector2i(c.x + t, c.y + d)
			if a.x >= 0 and a.y >= 0 and a.x < img.get_width() and a.y < img.get_height():
				img.set_pixelv(a, col)
			if b.x >= 0 and b.y >= 0 and b.x < img.get_width() and b.y < img.get_height():
				img.set_pixelv(b, col)


# ---------------------------------------------------------------------------
# Commands: input simulation
# ---------------------------------------------------------------------------

## One input step. Supported forms:
##  {action: "jump", hold: 0.2} / {action: "move_right", pressed: true} / {action, strength}
##  {key: "Space", hold: 0.1} / {key: "Ctrl+S"}
##  {click: [x, y], button: "left", double: false} / {click_node: "UI/StartButton"}
##  {mouse_move: [x, y]} / {drag: [[x1, y1], [x2, y2]], seconds: 0.3}
##  {joy: "a"} / {axis: "left_x", value: 1.0, hold: 0.5}
##  {text: "hello"} / {wait: 0.5} / {release_all: true}
func c_input(p: Dictionary):
	var steps: Array = U.p_arr(p, "steps") if p.has("steps") else [p]
	var done := []
	for step in steps:
		if not (step is Dictionary):
			return U.err("Each input step must be an object.")
		var r = await _input_step(step)
		if U.is_err(r):
			r["completed_steps"] = done.size()
			return r
		done.append(r)
	return {"steps": done.size(), "results": done}


func _input_step(s: Dictionary):
	var hold := U.p_float(s, "hold", -1.0)
	if s.has("wait"):
		await _sleep(U.p_float(s, "wait"))
		return "waited %.2fs" % U.p_float(s, "wait")
	if s.has("release_all"):
		for a in _held_actions.keys():
			_send_action(a, false, 0.0)
		_held_actions.clear()
		return "released all"
	if s.has("action"):
		var action := U.p_str(s, "action")
		if not InputMap.has_action(action):
			var names := []
			for a2 in InputMap.get_actions():
				names.append(str(a2))
			var sug := U.suggest(action, names)
			return U.err("Input action '%s' does not exist." % action, ("Did you mean '%s'? " % sug if sug != "" else "") + "Define it with project.add_input_action.")
		var strength := U.p_float(s, "strength", 1.0)
		if s.has("pressed") and hold < 0.0:
			_send_action(action, U.p_bool(s, "pressed"), strength)
			return "%s %s" % [action, "pressed" if U.p_bool(s, "pressed") else "released"]
		_send_action(action, true, strength)
		await _sleep(hold if hold >= 0.0 else 0.1)
		_send_action(action, false, 0.0)
		return "tapped %s for %.2fs" % [action, hold if hold >= 0.0 else 0.1]
	if s.has("key"):
		var ev = InputSpec.key_event(U.p_str(s, "key"))
		if ev is String:
			return U.err(ev)
		if s.has("pressed") and hold < 0.0:
			ev.pressed = U.p_bool(s, "pressed")
			Input.parse_input_event(ev)
			return "key %s %s" % [U.p_str(s, "key"), "down" if ev.pressed else "up"]
		Input.parse_input_event(ev)
		await _sleep(hold if hold >= 0.0 else 0.08)
		var up: InputEventKey = ev.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		return "key %s" % U.p_str(s, "key")
	if s.has("click") or s.has("click_node") or s.has("click_text"):
		var pos: Vector2
		if s.has("click_text"):
			var target := _control_with_text(U.p_str(s, "click_text"))
			if target == null:
				return U.err("No visible button/control with text '%s'." % U.p_str(s, "click_text"), "Visible texts: " + ", ".join(_visible_texts().slice(0, 30)))
			pos = U.screen_pos(target)
		elif s.has("click_node"):
			var n := _find(U.p_str(s, "click_node"))
			if n == null:
				return _not_found(U.p_str(s, "click_node"))
			var sp = U.screen_pos(n)
			if sp == null:
				return U.err("Node '%s' has no screen position (not a visible CanvasItem/Node3D)." % U.p_str(s, "click_node"))
			pos = sp
		else:
			pos = U.to_vector(s.click, TYPE_VECTOR2)
			if U.p_str(s, "space", "viewport") == "screenshot" and _last_shot_size != Vector2i.ZERO:
				pos *= get_viewport().get_visible_rect().size / Vector2(_last_shot_size)
		var btn: int = InputSpec.MOUSE_BUTTONS.get(U.p_str(s, "button", "left"), MOUSE_BUTTON_LEFT)
		_mouse_motion(pos, Vector2.ZERO)
		await get_tree().process_frame
		_mouse_button(pos, btn, true, U.p_bool(s, "double", false))
		await _sleep(hold if hold >= 0.0 else 0.05)
		_mouse_button(pos, btn, false, false)
		await get_tree().process_frame
		return "clicked at %s" % var_to_str(pos)
	if s.has("mouse_move"):
		var mp: Vector2 = U.to_vector(s.mouse_move, TYPE_VECTOR2)
		_mouse_motion(mp, Vector2.ZERO)
		return "mouse at %s" % var_to_str(mp)
	if s.has("drag"):
		var pts: Array = s.drag
		if pts.size() < 2:
			return U.err("drag needs two points.")
		var a: Vector2 = U.to_vector(pts[0], TYPE_VECTOR2)
		var b: Vector2 = U.to_vector(pts[1], TYPE_VECTOR2)
		var secs := U.p_float(s, "seconds", 0.3)
		var btn2: int = InputSpec.MOUSE_BUTTONS.get(U.p_str(s, "button", "left"), MOUSE_BUTTON_LEFT)
		_mouse_motion(a, Vector2.ZERO)
		_mouse_button(a, btn2, true, false)
		var steps_n := maxi(2, int(secs * 60))
		var prev := a
		for i in range(1, steps_n + 1):
			var cur := a.lerp(b, float(i) / steps_n)
			_mouse_motion(cur, cur - prev, btn2)
			prev = cur
			await get_tree().process_frame
		_mouse_button(b, btn2, false, false)
		return "dragged %s -> %s" % [var_to_str(a), var_to_str(b)]
	if s.has("joy"):
		var jev = InputSpec.parse("joy:" + U.p_str(s, "joy"))
		if jev is String:
			return U.err(jev)
		jev.device = 0
		Input.parse_input_event(jev)
		await _sleep(hold if hold >= 0.0 else 0.08)
		var jup: InputEventJoypadButton = jev.duplicate()
		jup.pressed = false
		Input.parse_input_event(jup)
		return "joy %s" % U.p_str(s, "joy")
	if s.has("axis"):
		var aev = InputSpec.parse("joy_axis:" + U.p_str(s, "axis"))
		if aev is String:
			return U.err(aev)
		aev.device = 0
		aev.axis_value = U.p_float(s, "value", 1.0)
		Input.parse_input_event(aev)
		if hold >= 0.0:
			await _sleep(hold)
			var rel: InputEventJoypadMotion = aev.duplicate()
			rel.axis_value = 0.0
			Input.parse_input_event(rel)
		return "axis %s=%.2f" % [U.p_str(s, "axis"), U.p_float(s, "value", 1.0)]
	if s.has("text"):
		for ch in U.p_str(s, "text"):
			var kev := InputEventKey.new()
			kev.unicode = ch.unicode_at(0)
			kev.keycode = OS.find_keycode_from_string(ch.to_upper()) if ch.length() == 1 else KEY_NONE
			kev.pressed = true
			Input.parse_input_event(kev)
			var kup: InputEventKey = kev.duplicate()
			kup.pressed = false
			Input.parse_input_event(kup)
			await get_tree().process_frame
		return "typed %d chars" % U.p_str(s, "text").length()
	return U.err("Unrecognised input step %s." % JSON.stringify(s), "Use action, key, click, click_node, click_text, mouse_move, drag, joy, axis, text, wait or release_all.")


## Visible Control whose text matches (exact, case-insensitive; then substring). Buttons first.
func _control_with_text(text: String) -> Control:
	var want := text.strip_edges().to_lower()
	var partial: Control = null
	var controls := get_tree().root.find_children("*", "Control", true, false)
	controls.sort_custom(func(a, b): return int(a is BaseButton) > int(b is BaseButton))
	for c in controls:
		var ctl := c as Control
		if not ctl.is_visible_in_tree() or not ("text" in ctl):
			continue
		var t := str(ctl.get("text")).strip_edges().to_lower()
		if t == "":
			continue
		if t == want:
			return ctl
		if partial == null and t.contains(want):
			partial = ctl
	return partial


func _visible_texts() -> Array:
	var out := []
	for c in get_tree().root.find_children("*", "BaseButton", true, false):
		if (c as Control).is_visible_in_tree() and "text" in c and str(c.get("text")) != "":
			out.append(str(c.get("text")))
	return out


func _send_action(action: String, pressed: bool, strength: float) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = strength if pressed else 0.0
	Input.parse_input_event(ev)
	if pressed:
		_held_actions[action] = true
	else:
		_held_actions.erase(action)


func _mouse_button(pos: Vector2, btn: int, pressed: bool, double: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	ev.double_click = double
	ev.position = pos
	ev.global_position = pos
	if pressed:
		ev.button_mask = 1 << (btn - 1)
	get_viewport().push_input(ev, true)


func _mouse_motion(pos: Vector2, rel: Vector2, btn: int = 0) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	if btn > 0:
		ev.button_mask = 1 << (btn - 1)
	get_viewport().push_input(ev, true)


func _sleep(seconds: float) -> void:
	if seconds <= 0.0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(seconds, true, false, true).timeout


# ---------------------------------------------------------------------------
# Commands: record / replay
# ---------------------------------------------------------------------------

func _on_window_input(ev: InputEvent) -> void:
	if not _recording:
		return
	if ev is InputEventMouseMotion and not _record_motion:
		return
	if ev is InputEventKey and ev.echo:
		return
	var t := (Time.get_ticks_msec() - _record_start_ms) / 1000.0
	_recorded.append({"t": snappedf(t, 0.001), "event": var_to_str(ev)})


func c_record(p: Dictionary):
	var mode := U.p_str(p, "mode", "start")
	if mode == "start":
		_recorded.clear()
		_recording = true
		_record_motion = U.p_bool(p, "include_mouse_motion", false)
		_record_start_ms = Time.get_ticks_msec()
		return {"recording": true}
	_recording = false
	return {"recording": false, "duration_s": (Time.get_ticks_msec() - _record_start_ms) / 1000.0, "events": _recorded.duplicate()}


func c_replay(p: Dictionary):
	var events: Array = U.p_arr(p, "events")
	var speed := maxf(0.05, U.p_float(p, "speed", 1.0))
	var start := Time.get_ticks_msec()
	var played := 0
	for e in events:
		var target_ms := float(e.get("t", 0.0)) * 1000.0 / speed
		while Time.get_ticks_msec() - start < target_ms:
			await get_tree().process_frame
		var ev = str_to_var(str(e.get("event", "")))
		if ev is InputEvent:
			if ev is InputEventMouse:
				get_viewport().push_input(ev, true)
			else:
				Input.parse_input_event(ev)
			played += 1
	return {"played": played}


# ---------------------------------------------------------------------------
# Commands: physics queries
# ---------------------------------------------------------------------------

func c_raycast(p: Dictionary):
	var root := _scene_root()
	var from_v = p.get("from")
	var to_v = p.get("to")
	var is3d: bool = (from_v is Array and from_v.size() == 3) or (from_v is String and str(from_v).begins_with("Vector3"))
	if is3d:
		var w3 := root.get_viewport().world_3d
		if w3 == null:
			return U.err("No 3D world.")
		var q3 := PhysicsRayQueryParameters3D.create(U.to_vector(from_v, TYPE_VECTOR3), U.to_vector(to_v, TYPE_VECTOR3), U.p_int(p, "mask", 0xFFFFFFFF))
		q3.collide_with_areas = U.p_bool(p, "areas", false)
		var r3 := w3.direct_space_state.intersect_ray(q3)
		if r3.is_empty():
			return {"hit": false}
		return {"hit": true, "position": var_to_str(r3.position), "normal": var_to_str(r3.normal), "collider": U.encode(r3.collider)}
	var w2 := root.get_viewport().world_2d
	var q2 := PhysicsRayQueryParameters2D.create(U.to_vector(from_v, TYPE_VECTOR2), U.to_vector(to_v, TYPE_VECTOR2), U.p_int(p, "mask", 0xFFFFFFFF))
	q2.collide_with_areas = U.p_bool(p, "areas", false)
	var r2 := w2.direct_space_state.intersect_ray(q2)
	if r2.is_empty():
		return {"hit": false}
	return {"hit": true, "position": var_to_str(r2.position), "normal": var_to_str(r2.normal), "collider": U.encode(r2.collider)}


func c_quit(p: Dictionary):
	get_tree().quit.call_deferred(U.p_int(p, "code", 0))
	return {"quitting": true}


func c_change_scene(p: Dictionary):
	var path := U.res_path(U.p_str(p, "scene"))
	if not ResourceLoader.exists(path):
		return U.err("Scene '%s' does not exist." % path)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	return {"scene": path}


func c_logs(p: Dictionary):
	return {"recent_errors": _recent_errors.slice(max(0, _recent_errors.size() - U.p_int(p, "limit", 20)))}
