@tool
extends VBoxContainer
## "Forge Agent" bottom panel: chat with Claude inside the Godot editor. Runs Claude Code
## headless (`claude -p --input-format stream-json --output-format stream-json`) with the Godot
## Forge MCP server attached, so the agent can see and edit this project while you watch.
## Every change it makes lands in the Forge dock's changeset (Approve / Discard).

var ctx

const SYSTEM_APPEND := "You are running inside the Godot editor's Forge Agent panel, connected to this project through the Godot Forge MCP tools (mcp__godot__*). The user sees the editor live. Prefer the Godot tools over generic file tools. Build editor-first: real nodes, inspector properties, resources and scene signal connections the user can edit by hand, not scenes constructed in _ready(). Verify gameplay changes by running the game. Keep replies short: what you did and what to try."

var _log: RichTextLabel
var _input: TextEdit
var _send: Button
var _stop: Button
var _model: OptionButton
var _allow_edits: CheckBox
var _status: Label

var _pid := -1
var _io: FileAccess
var _err_io: FileAccess
var _buf := ""
var _session_id := ""
var _busy := false


func _ready() -> void:
	name = "Forge Agent"
	custom_minimum_size = Vector2(0, 220)
	var top := HBoxContainer.new()
	add_child(top)
	_status = Label.new()
	_status.text = "Claude + Godot Forge"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_status)
	_model = OptionButton.new()
	for m in ["default", "opus", "sonnet", "haiku"]:
		_model.add_item(m)
	_model.tooltip_text = "Model (default = your Claude Code default)"
	top.add_child(_model)
	_allow_edits = CheckBox.new()
	_allow_edits.text = "Allow shell/file tools"
	_allow_edits.tooltip_text = "Also allow Claude Code's own Edit/Write/Bash tools (off: only Godot Forge tools + read-only file tools)."
	top.add_child(_allow_edits)
	var new_chat := Button.new()
	new_chat.text = "New chat"
	new_chat.pressed.connect(_new_chat)
	top.add_child(new_chat)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 120)
	add_child(_log)

	var row := HBoxContainer.new()
	add_child(row)
	_input = TextEdit.new()
	_input.placeholder_text = "Ask for a feature, a fix or a playtest... (Ctrl+Enter to send)"
	_input.custom_minimum_size = Vector2(0, 54)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_input.gui_input.connect(_on_input_key)
	row.add_child(_input)
	var col := VBoxContainer.new()
	row.add_child(col)
	_send = Button.new()
	_send.text = "Send"
	_send.pressed.connect(_on_send)
	col.add_child(_send)
	_stop = Button.new()
	_stop.text = "Stop"
	_stop.disabled = true
	_stop.pressed.connect(_kill)
	col.add_child(_stop)
	_append("[color=#8ab4f8]Forge Agent[/color] — describe what you want. The agent edits this project through Godot Forge; review its changes in the Forge dock.\n")
	set_process(true)


func _exit_tree() -> void:
	_kill()


func _on_input_key(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ENTER and (ev.ctrl_pressed or ev.meta_pressed):
		_on_send()
		accept_event()


func _append(bb: String) -> void:
	_log.append_text(bb)


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _new_chat() -> void:
	_kill()
	_session_id = ""
	_log.clear()
	_append("[color=#8ab4f8]New chat.[/color]\n")


# ---------------------------------------------------------------------------
# Process management
# ---------------------------------------------------------------------------

func _setting(key: String, default):
	var es := EditorInterface.get_editor_settings()
	var full := "godot_forge/agent/" + key
	if not es.has_setting(full):
		es.set_setting(full, default)
		es.set_initial_value(full, default, false)
	return es.get_setting(full)


## Figures out how to launch the MCP server: project .mcp.json entry, else editor setting.
func _mcp_config_path() -> String:
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var command := ""
	var args := []
	var mcp_json := project.path_join(".mcp.json")
	if FileAccess.file_exists(mcp_json):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(mcp_json))
		if parsed is Dictionary and parsed.get("mcpServers", {}).has("godot"):
			var entry: Dictionary = parsed.mcpServers.godot
			command = str(entry.get("command", ""))
			args = Array(entry.get("args", []))
	if command == "":
		var cmdline := str(_setting("mcp_command", "npx -y godot-forge-mcp@latest"))
		var parts := cmdline.split(" ", false)
		command = parts[0]
		args = Array(parts.slice(1))
	if not "--project" in args:
		args.append_array(["--project", project])
	if not "--launch" in args:
		args.append_array(["--launch", "none"])
	var cfg := {"mcpServers": {"godot": {"command": command, "args": args}}}
	var out := ProjectSettings.globalize_path("res://.godot/forge/agent-mcp.json")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(cfg, "  "))
	f.close()
	return out


func _start() -> bool:
	var claude := str(_setting("claude_path", "claude"))
	var args := ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
		"--mcp-config", _mcp_config_path(), "--strict-mcp-config", "--append-system-prompt", SYSTEM_APPEND]
	var allowed := ["mcp__godot", "Read", "Glob", "Grep"]
	if _allow_edits.button_pressed:
		allowed.append_array(["Edit", "Write", "Bash"])
	args.append("--allowedTools")
	args.append(",".join(allowed))
	var model := _model.get_item_text(_model.selected)
	if model != "default":
		args.append_array(["--model", model])
	if _session_id != "":
		args.append_array(["--resume", _session_id])
	var exe := claude
	var run_args := args
	var r: Dictionary = OS.execute_with_pipe(exe, PackedStringArray(run_args), false)
	if r.is_empty() and OS.get_name() == "Windows":
		# npm installs ship claude.cmd, which needs cmd.exe.
		run_args = ["/c", claude] + args
		r = OS.execute_with_pipe("cmd.exe", PackedStringArray(run_args), false)
	if r.is_empty():
		_append("[color=#f28b82]Could not start Claude Code ('%s'). Install it (https://claude.com/claude-code) or set Editor Settings > godot_forge/agent/claude_path.[/color]\n" % claude)
		return false
	_pid = int(r.pid)
	_io = r.stdio
	_err_io = r.stderr
	_buf = ""
	return true


func _kill() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	_io = null
	_err_io = null
	_set_busy(false)


func _set_busy(b: bool) -> void:
	_busy = b
	if _send:
		_send.disabled = b
		_stop.disabled = not b
		_status.text = "Working..." if b else "Claude + Godot Forge" + (" (session %s)" % _session_id.substr(0, 8) if _session_id != "" else "")


# ---------------------------------------------------------------------------
# Messages
# ---------------------------------------------------------------------------

func _context_prefix() -> String:
	var parts := []
	var root := EditorInterface.get_edited_scene_root()
	if root:
		parts.append("edited scene: " + root.scene_file_path)
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if not sel.is_empty() and root:
		parts.append("selected: " + ", ".join(sel.map(func(n): return str(root.get_path_to(n)) if root.is_ancestor_of(n) or n == root else str(n.name))))
	var script := EditorInterface.get_script_editor().get_current_script()
	if script and EditorInterface.get_editor_main_screen().get_children().any(func(c): return c.visible and c.get_class() == "ScriptEditor"):
		parts.append("open script: " + script.resource_path)
	return "[Editor context — %s]\n" % "; ".join(parts) if not parts.is_empty() else ""


func _on_send() -> void:
	var text := _input.text.strip_edges()
	if text == "" or _busy:
		return
	_input.text = ""
	_append("\n[b][color=#fdd663]You:[/color][/b] %s\n" % _esc(text))
	if _pid <= 0 or not OS.is_process_running(_pid):
		if not _start():
			return
	var msg := {"type": "user", "message": {"role": "user", "content": _context_prefix() + text}}
	_io.store_string(JSON.stringify(msg) + "\n")
	_io.flush()
	_set_busy(true)


func _process(_d: float) -> void:
	if _io == null:
		return
	var chunk := _io.get_buffer(65536)
	if chunk.size() > 0:
		_buf += chunk.get_string_from_utf8()
		var lines := _buf.split("\n")
		_buf = lines[lines.size() - 1]
		for i in lines.size() - 1:
			var line := lines[i].strip_edges()
			if line != "":
				_handle_line(line)
	if _err_io:
		var e := _err_io.get_buffer(8192)
		if e.size() > 0:
			var t := e.get_string_from_utf8().strip_edges()
			if t != "":
				_append("[color=#999999]%s[/color]\n" % _esc(t.substr(0, 400)))
	if _pid > 0 and not OS.is_process_running(_pid):
		if _busy:
			_append("[color=#f28b82]Claude Code exited.[/color]\n")
		_pid = -1
		_io = null
		_set_busy(false)


func _handle_line(line: String) -> void:
	var ev = JSON.parse_string(line)
	if not (ev is Dictionary):
		return
	match str(ev.get("type", "")):
		"system":
			if ev.get("subtype") == "init":
				_session_id = str(ev.get("session_id", _session_id))
				var tools: Array = ev.get("tools", [])
				var godot_tools := tools.filter(func(t): return str(t).begins_with("mcp__godot"))
				if godot_tools.is_empty():
					_append("[color=#f28b82]Warning: Godot Forge MCP tools are not available to the agent. Check Editor Settings > godot_forge/agent/mcp_command.[/color]\n")
		"assistant":
			for block in ev.get("message", {}).get("content", []):
				match str(block.get("type", "")):
					"text":
						_append("[b][color=#8ab4f8]Claude:[/color][/b] %s\n" % _esc(str(block.text)))
					"tool_use":
						var tname := str(block.get("name", "")).replace("mcp__godot__", "")
						var input: Dictionary = block.get("input", {})
						var summary := str(input.get("action", ""))
						for k in ["path", "scene", "name", "type", "query"]:
							if input.has(k):
								summary += " %s" % str(input[k]).substr(0, 50)
						_append("[color=#81c995]  → %s %s[/color]\n" % [_esc(tname), _esc(summary)])
		"user":
			for block in ev.get("message", {}).get("content", []):
				if block is Dictionary and block.get("type") == "tool_result" and block.get("is_error", false):
					var content = block.get("content", "")
					var txt := str(content[0].get("text", "")) if content is Array and not content.is_empty() and content[0] is Dictionary else str(content)
					_append("[color=#f28b82]    ✗ %s[/color]\n" % _esc(txt.substr(0, 200)))
		"result":
			var cost := float(ev.get("total_cost_usd", 0.0))
			var turns := int(ev.get("num_turns", 0))
			_append("[color=#999999]  done in %d turns%s[/color]\n" % [turns, (", $%.3f" % cost) if cost > 0.0 else ""])
			if ev.get("is_error", false):
				_append("[color=#f28b82]%s[/color]\n" % _esc(str(ev.get("result", "error"))))
			_set_busy(false)
