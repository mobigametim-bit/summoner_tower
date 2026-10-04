@tool
extends "res://addons/godot_forge/handlers/base.gd"
## GDScript/C# files: create from templates, validate, outline, attach, references.

const TEMPLATES := {
	"empty": "extends {extends}\n",
	"default": "extends {extends}\n\n\nfunc _ready() -> void:\n\tpass\n\n\nfunc _process(delta: float) -> void:\n\tpass\n",
	"platformer_2d": """extends CharacterBody2D

@export var speed := 300.0
@export var jump_velocity := -420.0
@export var acceleration := 2000.0
@export var friction := 2400.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

	if Input.is_action_just_pressed("{jump}") and is_on_floor():
		velocity.y = jump_velocity

	var direction := Input.get_axis("{left}", "{right}")
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	move_and_slide()
""",
	"topdown_2d": """extends CharacterBody2D

@export var speed := 250.0


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("{left}", "{right}", "{up}", "{down}")
	velocity = direction * speed
	move_and_slide()
""",
	"fps_3d": """extends CharacterBody3D

@export var speed := 5.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002

@onready var camera: Camera3D = $Camera3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("{jump}") and is_on_floor():
		velocity.y = jump_velocity
	var input_dir := Input.get_vector("{left}", "{right}", "{up}", "{down}")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	move_and_slide()
""",
	"state_machine": """class_name StateMachine
extends Node
## Minimal node based state machine. Add child nodes extending State.

signal state_changed(from: StringName, to: StringName)

@export var initial_state: Node

var current: Node


func _ready() -> void:
	for child in get_children():
		if child.has_method("enter"):
			child.set("machine", self)
	if initial_state:
		transition_to(initial_state.name)


func transition_to(state_name: StringName, msg: Dictionary = {}) -> void:
	var next := get_node_or_null(NodePath(state_name))
	if next == null:
		push_error("StateMachine: no state named %s" % state_name)
		return
	var prev := current.name if current else &""
	if current and current.has_method("exit"):
		current.exit()
	current = next
	if current.has_method("enter"):
		current.enter(msg)
	state_changed.emit(prev, state_name)


func _process(delta: float) -> void:
	if current and current.has_method("update"):
		current.update(delta)


func _physics_process(delta: float) -> void:
	if current and current.has_method("physics_update"):
		current.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current and current.has_method("handle_input"):
		current.handle_input(event)
""",
	"autoload_events": """extends Node
## Global event bus. Emit and connect to signals from anywhere: Events.player_died.emit()

signal player_died
signal score_changed(new_score: int)
signal level_completed(level: int)
""",
}


func a_templates(_p: Dictionary):
	return {"templates": TEMPLATES.keys(), "placeholders": "{extends} {jump} {left} {right} {up} {down}"}


func a_create(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not path.get_extension() in ["gd", "cs"]:
		path += ".gd"
	if FileAccess.file_exists(path) and not U.p_bool(p, "overwrite", false):
		return U.err("Script '%s' already exists." % path, "Use script.write/files.edit to change it, or pass overwrite=true.")
	var content := U.p_str(p, "content", "")
	if content == "":
		var tpl := U.p_str(p, "template", "default")
		if not TEMPLATES.has(tpl):
			return U.err("Unknown template '%s'." % tpl, "Templates: " + ", ".join(TEMPLATES.keys()))
		content = TEMPLATES[tpl]
		var names := U.p_dict(p, "actions")
		content = content.format({
			"extends": U.p_str(p, "extends", "Node"),
			"jump": names.get("jump", "ui_accept"), "left": names.get("left", "ui_left"), "right": names.get("right", "ui_right"),
			"up": names.get("up", "ui_up"), "down": names.get("down", "ui_down"),
		})
		if p.has("class_name") and not content.contains("class_name"):
			content = "class_name %s\n%s" % [U.p_str(p, "class_name"), content]
	var files = ctx.router.handlers["files"]
	var r = await files.write_text(path, content)
	if U.is_err(r): return r
	if p.has("attach_to"):
		var ar = await a_attach({"path": U.p_str(p, "attach_to"), "script": path, "scene": U.p_str(p, "scene", "")})
		if U.is_err(ar):
			r["attach_error"] = ar.message
		else:
			r["attached_to"] = ar.node
	return r


func a_read(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not FileAccess.file_exists(path):
		return U.err("Script '%s' does not exist." % path)
	var text := FileAccess.get_file_as_string(path)
	var out := {"path": path, "content": text}
	if U.p_bool(p, "outline", false):
		out["outline"] = outline_text(text)
	return out


func a_write(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	return await ctx.router.handlers["files"].write_text(path, U.p_str(p, "content"))


func a_edit(p: Dictionary):
	return await ctx.router.handlers["files"].a_edit(p)


# --- validation ----------------------------------------------------------------

## Reloads a script from disk inside the editor (like saving in the script editor) and
## returns parse/compile diagnostics captured from the engine error log.
func reload_and_check(path: String) -> Array:
	if path.get_extension() != "gd":
		return []
	ctx.flush_logs()
	var before: int = ctx.log_seq()
	var source := FileAccess.get_file_as_string(path)
	var scr: GDScript = null
	if ResourceLoader.has_cached(path):
		scr = ResourceLoader.get_cached_ref(path) if ResourceLoader.has_method("get_cached_ref") else load(path)
	if scr == null:
		scr = GDScript.new()
		scr.take_over_path(path)
	scr.source_code = source
	ctx.quiet += 1
	var err := scr.reload(true)
	ctx.flush_logs()
	ctx.quiet -= 1
	var diags := _collect_diags(before, path)
	if err != OK and diags.is_empty():
		diags.append({"severity": "error", "line": 0, "message": "Script failed to compile (error %d: %s)." % [err, error_string(err)]})
	return diags


func _collect_diags(since_seq: int, path: String) -> Array:
	var out := []
	for entry in ctx.get_logs(since_seq, "editor", "warning", 50):
		var msg := str(entry.get("message", ""))
		var file := str(entry.get("file", ""))
		if file != "" and file != path and not msg.contains(path) and entry.get("kind", "") != "script":
			continue
		var line := int(entry.get("line", 0))
		out.append({"severity": entry.get("level", "error"), "line": line, "message": msg.trim_prefix("Parse Error: ").trim_prefix("Compile Error: ")})
	return out


func a_validate(p: Dictionary):
	if p.has("content"):
		ctx.flush_logs()
		var before: int = ctx.log_seq()
		var s := GDScript.new()
		s.source_code = U.p_str(p, "content")
		ctx.quiet += 1
		var err := s.reload()
		ctx.flush_logs()
		ctx.quiet -= 1
		var d := _collect_diags(before, "")
		if err != OK and d.is_empty():
			d.append({"severity": "error", "line": 0, "message": "Failed to compile (error %d)." % err})
		return {"ok": err == OK, "diagnostics": d}
	var paths := U.p_arr(p, "paths")
	if paths.is_empty() and p.has("path"):
		paths = [U.p_str(p, "path")]
	if paths.is_empty():
		# Validate every script in the project.
		var files := []
		ctx.router.handlers["files"]._walk("res://", true, "*.gd", false, files, [], 5000)
		for f in files:
			paths.append(f.path)
	var results := {}
	var errors := 0
	for sp in paths:
		var rp := U.res_path(str(sp))
		if not FileAccess.file_exists(rp):
			results[rp] = [{"severity": "error", "line": 0, "message": "File not found."}]
			errors += 1
			continue
		var d2 := reload_and_check(rp)
		if not d2.is_empty():
			results[rp] = d2
			errors += d2.filter(func(x): return x.severity == "error").size()
	return {"ok": errors == 0, "checked": paths.size(), "error_count": errors, "problems": results}


# --- structure -------------------------------------------------------------------

func a_outline(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not FileAccess.file_exists(path):
		return U.err("Script '%s' does not exist." % path)
	return outline_text(FileAccess.get_file_as_string(path))


func outline_text(text: String) -> Dictionary:
	var out := {"extends": "", "class_name": "", "signals": [], "enums": [], "constants": [], "variables": [], "functions": [], "inner_classes": []}
	var re_func := RegEx.create_from_string("^(\\s*)(static\\s+)?func\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(([^)]*)\\)\\s*(->\\s*([^:]+))?:")
	var re_var := RegEx.create_from_string("^((?:@[A-Za-z_]+(?:\\([^)]*\\))?\\s*)*)(static\\s+)?var\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(:\\s*([^=:]+?))?\\s*(:?=\\s*(.+))?$")
	var re_const := RegEx.create_from_string("^const\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var re_signal := RegEx.create_from_string("^signal\\s+([A-Za-z_][A-Za-z0-9_]*)(\\(([^)]*)\\))?")
	var re_enum := RegEx.create_from_string("^enum\\s+([A-Za-z_][A-Za-z0-9_]*)?\\s*\\{?([^}]*)")
	var re_class := RegEx.create_from_string("^class\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var lines := text.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		var ln := i + 1
		if line.begins_with("extends "):
			out.extends = line.substr(8).strip_edges()
		elif line.begins_with("class_name "):
			var cn := line.substr(11).strip_edges().split(" ")[0]
			out.class_name = cn
			if line.contains("extends"):
				out.extends = line.split("extends")[1].strip_edges()
		var m := re_func.search(line)
		if m:
			var f := {"name": m.get_string(3), "line": ln, "args": m.get_string(4).strip_edges()}
			if m.get_string(6) != "":
				f["returns"] = m.get_string(6).strip_edges()
			if m.get_string(2) != "":
				f["static"] = true
			if m.get_string(1) != "":
				f["indented"] = true
			out.functions.append(f)
			continue
		if line.begins_with("\t") or line.begins_with(" "):
			continue
		m = re_var.search(line)
		if m:
			var v := {"name": m.get_string(3), "line": ln}
			if m.get_string(5) != "":
				v["type"] = m.get_string(5).strip_edges()
			if m.get_string(1).strip_edges() != "":
				v["annotations"] = m.get_string(1).strip_edges()
			if m.get_string(7) != "":
				v["default"] = m.get_string(7).strip_edges().substr(0, 80)
			out.variables.append(v)
			continue
		m = re_const.search(line)
		if m:
			out.constants.append({"name": m.get_string(1), "line": ln})
			continue
		m = re_signal.search(line)
		if m:
			out.signals.append({"name": m.get_string(1), "args": m.get_string(3), "line": ln})
			continue
		m = re_enum.search(line)
		if m:
			out.enums.append({"name": m.get_string(1), "values": m.get_string(2).strip_edges(), "line": ln})
			continue
		m = re_class.search(line)
		if m:
			out.inner_classes.append({"name": m.get_string(1), "line": ln})
	return out


func a_attach(p: Dictionary):
	var e = U.require(p, ["script"])
	if e: return e
	var n = await node_arg(p)
	if U.is_err(n): return n
	var sp := U.res_path(U.p_str(p, "script"))
	if not ResourceLoader.exists(sp):
		return U.err("Script '%s' does not exist." % sp, "Create it first with script.create.")
	var scr: Script = load(sp)
	if scr == null:
		return U.err("Script '%s' failed to load (parse error?)." % sp, "Run script.validate on it.")
	var base_type := scr.get_instance_base_type()
	if base_type != &"" and not n.is_class(base_type):
		return U.err("Script extends %s but node '%s' is a %s." % [base_type, n.name, n.get_class()], "Change the script's 'extends' or use node.change_type.")
	var u = ctx.begin("Attach script")
	u.add_do_method(n, "set_script", scr)
	u.add_undo_method(n, "set_script", n.get_script())
	ctx.commit()
	return {"node": ctx.node_path_str(n), "script": sp}


func a_detach(p: Dictionary):
	var n = await node_arg(p)
	if U.is_err(n): return n
	var u = ctx.begin("Detach script")
	u.add_do_method(n, "set_script", null)
	u.add_undo_method(n, "set_script", n.get_script())
	ctx.commit()
	return {"node": ctx.node_path_str(n)}


func a_references(p: Dictionary):
	var e = U.require(p, ["symbol"])
	if e: return e
	var sym := U.p_str(p, "symbol")
	return ctx.router.handlers["files"].a_search({"query": "\\b%s\\b" % sym, "regex": true, "case_sensitive": true, "limit": U.p_int(p, "limit", 100)})


func a_open(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	var scr = load(path)
	if not (scr is Script):
		return U.err("'%s' is not a script." % path)
	EditorInterface.edit_script(scr, U.p_int(p, "line", -1))
	return {"opened": path}


## Lists global script classes (class_name) in the project.
func a_classes(_p: Dictionary):
	var out := []
	for c in ProjectSettings.get_global_class_list():
		if str(c.path).begins_with("res://addons/godot_forge"):
			continue
		out.append({"class": c["class"], "extends": c.base, "path": c.path})
	return out
