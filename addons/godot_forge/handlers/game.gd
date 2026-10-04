@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Forwards requests to the running game (runtime autoload) over the debugger channel.
## Every action maps to a runtime command of the same name.

const COMMANDS := ["info", "tree", "get", "set", "call", "eval", "exec", "wait", "sample", "time", "perf", "raycast", "screenshot", "input", "record", "replay", "change_scene", "logs", "quit"]


func _forward(cmd: String, p: Dictionary):
	var timeout := 15000
	for key in ["seconds", "timeout", "hold", "sample_seconds"]:
		if p.has(key):
			timeout = maxi(timeout, int(U.p_float(p, key) * 1000.0) + 10000)
	if p.has("steps"):
		var total := 0.0
		for s in U.p_arr(p, "steps"):
			if s is Dictionary:
				total += U.p_float(s, "hold", 0.1) + U.p_float(s, "wait", 0.0) + U.p_float(s, "seconds", 0.0)
		timeout = maxi(timeout, int(total * 1000.0) + 10000)
	if p.has("events"):
		var last := 0.0
		for ev in U.p_arr(p, "events"):
			if ev is Dictionary:
				last = maxf(last, U.p_float(ev, "t", 0.0))
		timeout = maxi(timeout, int(last / maxf(0.05, U.p_float(p, "speed", 1.0)) * 1000.0) + 10000)
	return await ctx.runtime.request(cmd, p, timeout)


func a_info(p): return await _forward("info", p)
func a_tree(p): return await _forward("tree", p)
func a_get(p): return await _forward("get", p)
func a_set(p): return await _forward("set", p)
func a_call(p): return await _forward("call", p)
func a_eval(p): return await _forward("eval", p)
## Compiles the snippet in the editor first: a parse error inside the running game would make
## the debugger pause it (and the request would hang).
func a_exec(p):
	var src := U.game_snippet_source(U.p_str(p, "code"))
	ctx.flush_logs()
	var before: int = ctx.log_seq()
	ctx.quiet += 1
	var s := GDScript.new()
	s.source_code = src
	var err := s.reload()
	ctx.flush_logs()
	ctx.quiet -= 1
	if err != OK:
		var errs: Array = ctx.get_logs(before, "editor", "error", 10)
		return U.err("The snippet does not compile.", "It runs as the body of func run(tree: SceneTree, scene: Node). Fix the error and retry.", {"errors": errs.map(func(x): return "line %d: %s" % [int(x.get("line", 0)) - 3, str(x.get("message", "")).trim_prefix("Parse Error: ")])})
	return await _forward("exec", p)
func a_wait(p): return await _forward("wait", p)
func a_sample(p): return await _forward("sample", p)
func a_time(p): return await _forward("time", p)
func a_perf(p): return await _forward("perf", p)
func a_raycast(p): return await _forward("raycast", p)
func a_screenshot(p): return await _forward("screenshot", p)
func a_input(p): return await _forward("input", p)
func a_record(p): return await _forward("record", p)
func a_replay(p): return await _forward("replay", p)
func a_change_scene(p): return await _forward("change_scene", p)
func a_logs(p): return await _forward("logs", p)
func a_quit(p): return await _forward("quit", p)
func a_audio(p): return await _forward("audio", p)
