@tool
extends VBoxContainer
## "Forge" dock: shows AI connection status, the pending changeset (files the AI changed since
## the last approval) with Approve / Discard / Revert / Checkpoint / Diff, and a live activity feed.

var ctx

var _status: Label
var _changes_label: Label
var _tree: Tree
var _activity: ItemList
var _diff_dialog: AcceptDialog
var _diff_text: CodeEdit
var _timer: Timer
var _last_activity_count := -1
var _busy := false
var _files_key := ""
var _files_time := 0


func _ready() -> void:
	name = "Forge"
	custom_minimum_size = Vector2(220, 300)
	add_theme_constant_override("separation", 6)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	add_child(HSeparator.new())
	_changes_label = Label.new()
	_changes_label.text = "AI changes"
	_changes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_changes_label)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_MULTI
	_tree.custom_minimum_size = Vector2(0, 140)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_activated.connect(_on_item_activated)
	add_child(_tree)

	var row1 := HBoxContainer.new()
	row1.add_child(_button("Approve all", "Keep every change and start a fresh changeset", _on_approve))
	row1.add_child(_button("Discard all", "Restore every file to how it was before the AI started", _on_discard))
	add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_child(_button("Revert selected", "Restore only the selected files", _on_revert_selected))
	row2.add_child(_button("Diff", "Show the text diff of all pending changes", _on_diff))
	row2.add_child(_button("Checkpoint", "Save a restore point inside this changeset", _on_checkpoint))
	add_child(row2)

	add_child(HSeparator.new())
	var act_label := Label.new()
	act_label.text = "Activity"
	add_child(act_label)
	_activity = ItemList.new()
	_activity.custom_minimum_size = Vector2(0, 160)
	_activity.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_activity.auto_height = false
	add_child(_activity)

	_diff_dialog = AcceptDialog.new()
	_diff_dialog.title = "Pending AI changes"
	_diff_dialog.min_size = Vector2i(900, 600)
	_diff_text = CodeEdit.new()
	_diff_text.editable = false
	_diff_text.custom_minimum_size = Vector2(880, 540)
	_diff_dialog.add_child(_diff_text)
	add_child(_diff_dialog)

	_timer = Timer.new()
	_timer.wait_time = 1.5
	_timer.autostart = true
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	if ctx:
		ctx.activity_added.connect(func(_e): _refresh_activity())
	_refresh.call_deferred()


func _button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _changes():
	return ctx.changes if ctx else null


func _refresh() -> void:
	if not is_visible_in_tree() or ctx == null or _busy:
		return
	var clients: Array = ctx.server.clients() if ctx.server else []
	if clients.is_empty():
		_status.text = "No AI connected. Port %d. Add the Godot Forge MCP server to Claude Code / Cursor / Codex." % (ctx.server.port if ctx.server else 0)
	else:
		_status.text = "● %d AI client(s) connected (%s)%s" % [clients.size(), ", ".join(clients.map(func(c): return str(c.client))), "  — game running" if ctx.runtime and ctx.runtime.is_running() else ""]
	var ch = _changes()
	if ch == null or not ch.available():
		_changes_label.text = "AI changes: unavailable (install git to enable review & rollback)."
		_tree.clear()
	else:
		var cs = ch.current()
		# Listing files runs git; only do it when something happened (or every 15 s for user edits).
		var key := "%s|%d" % [str(cs.id) if cs != null else "", ctx.activity.size()]
		if key == _files_key and Time.get_ticks_msec() - _files_time < 15000:
			_refresh_activity()
			return
		_files_key = key
		_files_time = Time.get_ticks_msec()
		_tree.clear()
		var root := _tree.create_item()
		if cs == null:
			_changes_label.text = "AI changes: none pending."
		else:
			var files: Array = ch.files()
			_changes_label.text = "AI changes: %d file(s) since %s — %s" % [files.size(), str(cs.started).substr(11, 5), cs.label]
			for f in files:
				var it := _tree.create_item(root)
				var mark := {"added": "+ ", "modified": "~ ", "deleted": "- "}.get(f.status, "? ")
				it.set_text(0, mark + str(f.path).trim_prefix("res://"))
				it.set_metadata(0, f.path)
				it.set_custom_color(0, {"added": Color(0.5, 0.9, 0.5), "modified": Color(0.95, 0.8, 0.4), "deleted": Color(0.95, 0.45, 0.45)}.get(f.status, Color.WHITE))
				it.set_tooltip_text(0, "%s (%s). Double-click to open." % [f.path, f.status])
	_refresh_activity()


func _refresh_activity() -> void:
	if ctx == null or ctx.activity.size() == _last_activity_count:
		return
	_last_activity_count = ctx.activity.size()
	_activity.clear()
	var items: Array = ctx.activity.slice(max(0, ctx.activity.size() - 80))
	items.reverse()
	for e in items:
		var text := "%s  %s  %s" % [str(e.time).substr(0, 8), e.method, e.summary]
		if not e.ok:
			text += "  ✗ " + str(e.get("error", ""))
		var idx := _activity.add_item(text)
		if not e.ok:
			_activity.set_item_custom_fg_color(idx, Color(0.95, 0.45, 0.45))
		elif not e.write:
			_activity.set_item_custom_fg_color(idx, Color(0.65, 0.65, 0.7))
		_activity.set_item_tooltip(idx, text)


func _on_item_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var path: String = it.get_metadata(0)
	if not FileAccess.file_exists(path):
		return
	if path.ends_with(".tscn") or path.ends_with(".scn"):
		EditorInterface.open_scene_from_path(path)
	elif path.ends_with(".gd"):
		EditorInterface.edit_script(load(path))
	else:
		EditorInterface.select_file(path)


func _force_refresh() -> void:
	_files_key = ""
	_refresh()


func _on_approve() -> void:
	var ch = _changes()
	if ch and ch.current() != null:
		ch.a_approve({})
		_toast("Approved AI changes.")
	_force_refresh()


func _on_discard() -> void:
	var ch = _changes()
	if ch == null or ch.current() == null:
		return
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Discard all pending AI changes?\nEvery changed file is restored to how it was when the changeset started; files the AI created are deleted."
	confirm.ok_button_text = "Discard"
	add_child(confirm)
	confirm.confirmed.connect(func():
		_busy = true
		await ch.a_discard({})
		_busy = false
		_toast("Discarded AI changes.")
		_force_refresh()
		confirm.queue_free())
	confirm.canceled.connect(confirm.queue_free)
	confirm.popup_centered()


func _on_revert_selected() -> void:
	var ch = _changes()
	if ch == null or ch.current() == null:
		return
	var paths := []
	var it := _tree.get_next_selected(null)
	while it:
		paths.append(it.get_metadata(0))
		it = _tree.get_next_selected(it)
	if paths.is_empty():
		return
	_busy = true
	await ch.a_revert_files({"paths": paths})
	_busy = false
	_toast("Reverted %d file(s)." % paths.size())
	_force_refresh()


func _on_checkpoint() -> void:
	var ch = _changes()
	if ch:
		var r = ch.a_checkpoint({})
		if r is Dictionary and r.has("checkpoint"):
			_toast("Checkpoint saved: " + str(r.checkpoint))
	_force_refresh()


func _on_diff() -> void:
	var ch = _changes()
	if ch == null or ch.current() == null:
		return
	var d = ch.a_diff({})
	_diff_text.text = (str(d.get("stat", "")) + "\n\n" + str(d.get("patch", ""))) if d is Dictionary else str(d)
	_diff_dialog.popup_centered()


func _toast(msg: String) -> void:
	if EditorInterface.has_method("get_editor_toaster"):
		EditorInterface.get_editor_toaster().push_toast(msg)
