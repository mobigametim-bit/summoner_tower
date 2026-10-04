@tool
extends RefCounted
## Parses compact input specs into InputEvents. Shared by the editor (input map) and the
## runtime (input simulation).
##   "key:W"  "key:Space"  "key:Ctrl+S"  "W"            keyboard (physical + logical keycode)
##   "mouse:left" "mouse:right" "mouse:wheel_up"         mouse buttons
##   "joy:a" "joy_button:0" "joy:dpad_up"                gamepad buttons
##   "joy_axis:left_x+" "joy_axis:1-"                   gamepad axes (sign = direction)

const JOY_BUTTONS := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"back": JOY_BUTTON_BACK, "select": JOY_BUTTON_BACK, "guide": JOY_BUTTON_GUIDE, "start": JOY_BUTTON_START,
	"left_stick": JOY_BUTTON_LEFT_STICK, "right_stick": JOY_BUTTON_RIGHT_STICK,
	"left_shoulder": JOY_BUTTON_LEFT_SHOULDER, "lb": JOY_BUTTON_LEFT_SHOULDER,
	"right_shoulder": JOY_BUTTON_RIGHT_SHOULDER, "rb": JOY_BUTTON_RIGHT_SHOULDER,
	"dpad_up": JOY_BUTTON_DPAD_UP, "dpad_down": JOY_BUTTON_DPAD_DOWN,
	"dpad_left": JOY_BUTTON_DPAD_LEFT, "dpad_right": JOY_BUTTON_DPAD_RIGHT,
}
const JOY_AXES := {
	"left_x": JOY_AXIS_LEFT_X, "left_y": JOY_AXIS_LEFT_Y, "right_x": JOY_AXIS_RIGHT_X, "right_y": JOY_AXIS_RIGHT_Y,
	"trigger_left": JOY_AXIS_TRIGGER_LEFT, "lt": JOY_AXIS_TRIGGER_LEFT,
	"trigger_right": JOY_AXIS_TRIGGER_RIGHT, "rt": JOY_AXIS_TRIGGER_RIGHT,
}
const MOUSE_BUTTONS := {
	"left": MOUSE_BUTTON_LEFT, "right": MOUSE_BUTTON_RIGHT, "middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP, "wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
	"wheel_left": MOUSE_BUTTON_WHEEL_LEFT, "wheel_right": MOUSE_BUTTON_WHEEL_RIGHT,
	"xbutton1": MOUSE_BUTTON_XBUTTON1, "xbutton2": MOUSE_BUTTON_XBUTTON2,
}


## Returns an InputEvent or a String error message.
static func parse(spec) -> Variant:
	if spec is Dictionary:
		return _parse_dict(spec)
	var s := str(spec).strip_edges()
	if s == "":
		return "Empty input spec."
	var kind := "key"
	var value := s
	var colon := s.find(":")
	if colon > 0:
		kind = s.substr(0, colon).to_lower()
		value = s.substr(colon + 1).strip_edges()
	match kind:
		"key", "keyboard":
			return key_event(value)
		"mouse", "mouse_button":
			var mb := MouseButton.MOUSE_BUTTON_NONE
			if MOUSE_BUTTONS.has(value.to_lower()):
				mb = MOUSE_BUTTONS[value.to_lower()]
			elif value.is_valid_int():
				mb = int(value)
			else:
				return "Unknown mouse button '%s'. Use one of %s." % [value, ", ".join(MOUSE_BUTTONS.keys())]
			var me := InputEventMouseButton.new()
			me.button_index = mb
			me.pressed = true
			return me
		"joy", "joy_button", "gamepad", "pad":
			var jb := -1
			if JOY_BUTTONS.has(value.to_lower()):
				jb = JOY_BUTTONS[value.to_lower()]
			elif value.is_valid_int():
				jb = int(value)
			else:
				return "Unknown joypad button '%s'. Use one of %s or an index." % [value, ", ".join(JOY_BUTTONS.keys())]
			var je := InputEventJoypadButton.new()
			je.button_index = jb
			je.pressed = true
			je.device = -1
			return je
		"joy_axis", "axis":
			var sign := 1.0
			var name := value
			if name.ends_with("+"):
				name = name.substr(0, name.length() - 1)
			elif name.ends_with("-"):
				name = name.substr(0, name.length() - 1)
				sign = -1.0
			var axis := -1
			if JOY_AXES.has(name.to_lower()):
				axis = JOY_AXES[name.to_lower()]
			elif name.is_valid_int():
				axis = int(name)
			else:
				return "Unknown joypad axis '%s'. Use one of %s." % [name, ", ".join(JOY_AXES.keys())]
			var ja := InputEventJoypadMotion.new()
			ja.axis = axis
			ja.axis_value = sign
			ja.device = -1
			return ja
	return "Unknown input kind '%s'. Use key:, mouse:, joy: or joy_axis:." % kind


static func _parse_dict(d: Dictionary) -> Variant:
	if d.has("key"):
		return key_event(str(d.key))
	if d.has("mouse"):
		return parse("mouse:" + str(d.mouse))
	if d.has("joy"):
		return parse("joy:" + str(d.joy))
	if d.has("axis"):
		return parse("joy_axis:" + str(d.axis))
	return "Unrecognised input spec %s." % JSON.stringify(d)


static func key_event(value: String) -> Variant:
	var parts := value.split("+")
	var key_name := parts[parts.size() - 1].strip_edges()
	if key_name == "" and value.ends_with("+"):
		key_name = "Plus"
	var code := OS.find_keycode_from_string(key_name)
	if code == KEY_NONE:
		var aliases := {"esc": "Escape", "return": "Enter", "del": "Delete", "ins": "Insert", "pgup": "PageUp", "pgdown": "PageDown", "ctrl": "Ctrl", "control": "Ctrl", "arrowup": "Up", "arrowdown": "Down", "arrowleft": "Left", "arrowright": "Right", "spacebar": "Space"}
		if aliases.has(key_name.to_lower()):
			code = OS.find_keycode_from_string(aliases[key_name.to_lower()])
	if code == KEY_NONE:
		return "Unknown key '%s'. Examples: W, Space, Enter, Escape, Up, F5, Shift, Ctrl+S." % key_name
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	for i in parts.size() - 1:
		match parts[i].strip_edges().to_lower():
			"ctrl", "control": ev.ctrl_pressed = true
			"shift": ev.shift_pressed = true
			"alt": ev.alt_pressed = true
			"meta", "cmd", "command", "super", "win": ev.meta_pressed = true
	if code < 128 and not ev.ctrl_pressed and not ev.alt_pressed:
		var ch := key_name if key_name.length() == 1 else ""
		if code == KEY_SPACE:
			ch = " "
		if ch != "":
			ev.unicode = (ch.to_upper() if ev.shift_pressed else ch.to_lower()).unicode_at(0)
	return ev


## Human readable form of an event, e.g. "key:W", "joy:a".
static func describe(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		var mods := ""
		if ev.ctrl_pressed: mods += "Ctrl+"
		if ev.shift_pressed: mods += "Shift+"
		if ev.alt_pressed: mods += "Alt+"
		if ev.meta_pressed: mods += "Meta+"
		return "key:" + mods + OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		for k in MOUSE_BUTTONS:
			if MOUSE_BUTTONS[k] == ev.button_index:
				return "mouse:" + k
		return "mouse:%d" % ev.button_index
	if ev is InputEventJoypadButton:
		for k in JOY_BUTTONS:
			if JOY_BUTTONS[k] == ev.button_index:
				return "joy:" + k
		return "joy:%d" % ev.button_index
	if ev is InputEventJoypadMotion:
		for k in JOY_AXES:
			if JOY_AXES[k] == ev.axis:
				return "joy_axis:%s%s" % [k, "+" if ev.axis_value >= 0 else "-"]
		return "joy_axis:%d%s" % [ev.axis, "+" if ev.axis_value >= 0 else "-"]
	return ev.as_text()
