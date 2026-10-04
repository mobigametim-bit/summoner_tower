@tool
extends "res://addons/godot_forge/handlers/base.gd"
## User interfaces (Control nodes): build whole UI trees from one spec, anchor presets,
## theme overrides, Theme resources, fonts, focus navigation, a main-menu template and a
## layout inspector for debugging.

const PRESETS := {
	"top_left": Control.PRESET_TOP_LEFT, "top_right": Control.PRESET_TOP_RIGHT,
	"bottom_left": Control.PRESET_BOTTOM_LEFT, "bottom_right": Control.PRESET_BOTTOM_RIGHT,
	"center_left": Control.PRESET_CENTER_LEFT, "center_top": Control.PRESET_CENTER_TOP,
	"center_right": Control.PRESET_CENTER_RIGHT, "center_bottom": Control.PRESET_CENTER_BOTTOM,
	"center": Control.PRESET_CENTER, "left_wide": Control.PRESET_LEFT_WIDE, "top_wide": Control.PRESET_TOP_WIDE,
	"right_wide": Control.PRESET_RIGHT_WIDE, "bottom_wide": Control.PRESET_BOTTOM_WIDE,
	"vcenter_wide": Control.PRESET_VCENTER_WIDE, "hcenter_wide": Control.PRESET_HCENTER_WIDE,
	"full_rect": Control.PRESET_FULL_RECT,
}
const PRESET_ALIASES := {
	"full": "full_rect", "fill": "full_rect", "full_screen": "full_rect", "fullscreen": "full_rect", "rect": "full_rect", "stretch": "full_rect",
	"top": "center_top", "bottom": "center_bottom", "left": "center_left", "right": "center_right",
	"top_center": "center_top", "bottom_center": "center_bottom", "left_center": "center_left", "right_center": "center_right",
	"middle": "center", "centre": "center", "top_full": "top_wide", "bottom_full": "bottom_wide",
	"hcenter": "hcenter_wide", "vcenter": "vcenter_wide", "left_full": "left_wide", "right_full": "right_wide",
}
const RESIZE_MODES := {"minsize": Control.PRESET_MODE_MINSIZE, "keep_width": Control.PRESET_MODE_KEEP_WIDTH, "keep_height": Control.PRESET_MODE_KEEP_HEIGHT, "keep_size": Control.PRESET_MODE_KEEP_SIZE}
const SIZE_FLAGS := {
	"shrink_begin": 0, "begin": 0, "shrink": 0, "none": 0, "fill": Control.SIZE_FILL, "expand": Control.SIZE_EXPAND,
	"expand_fill": Control.SIZE_EXPAND_FILL, "fill_expand": Control.SIZE_EXPAND_FILL,
	"shrink_center": Control.SIZE_SHRINK_CENTER, "center": Control.SIZE_SHRINK_CENTER,
	"shrink_end": Control.SIZE_SHRINK_END, "end": Control.SIZE_SHRINK_END,
}
const OVERRIDE_KINDS := {
	"colors": "theme_override_colors/", "constants": "theme_override_constants/", "font_sizes": "theme_override_font_sizes/",
	"fonts": "theme_override_fonts/", "styles": "theme_override_styles/", "icons": "theme_override_icons/",
}
const KIND_ALIASES := {"color": "colors", "constant": "constants", "font_size": "font_sizes", "font": "fonts", "style": "styles", "styleboxes": "styles", "stylebox": "styles", "icon": "icons"}
const MOUSE_FILTERS := ["stop", "pass", "ignore"]
## Spec keys handled by the builder itself (everything else must be a property or theme item).
const SPEC_KEYS := ["type", "name", "props", "children", "layout", "layout_margin", "resize", "theme_overrides", "overrides",
	"theme", "script", "groups", "size_flags", "min_size", "align", "valign", "font_size", "font_color", "color",
	"separation", "margin", "texture", "icon", "tooltip", "unique", "text", "placeholder", "stylebox", "panel"]


# ---------------------------------------------------------------------------
# build
# ---------------------------------------------------------------------------

## Builds a whole Control tree in one undoable action.
## p: parent?, scene?, spec: {type, name?, layout?, props?, theme_overrides?, text?, children: [...]}
## (spec may also be an array of sibling specs).
func a_build(p: Dictionary):
	var spec = p.get("spec", null)
	if spec == null and (p.has("type") or p.has("children")):
		spec = p.duplicate()
		for k in ["parent", "scene", "spec"]:
			spec.erase(k)
	if spec == null:
		return U.err("Missing 'spec'.", "Pass spec: {\"type\": \"VBoxContainer\", \"layout\": \"center\", \"children\": [{\"type\": \"Label\", \"text\": \"Hello\"}, {\"type\": \"Button\", \"text\": \"Play\"}]}.")
	if spec is String:
		spec = {"type": spec}
	var specs: Array = spec if spec is Array else [spec]
	return await build_specs(p, specs, "Build UI")


## Shared by build and menu_template. Returns {path, nodes, warnings} or an error.
func build_specs(p: Dictionary, specs: Array, action_name: String):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var parent: Node = ctx.find_node(U.p_str(p, "parent", "."))
	if parent == null:
		return ctx.node_not_found(U.p_str(p, "parent"))
	var state := {"layouts": [], "warnings": []}
	var built := []
	for s in specs:
		if not (s is Dictionary):
			for b in built: b.free()
			return U.err("Each spec must be an object like {\"type\": \"Label\", \"text\": \"Hi\"}.")
		var n = _build(s, state, parent)
		if U.is_err(n):
			for b in built: b.free()
			return n
		built.append(n)
	var u = ctx.begin(action_name)
	# A Control scene root created with scene.create has zero size, which makes every anchor
	# preset collapse to a point. Stretch it to the viewport when the new UI relies on anchors.
	if parent == root and root is Control and not (root is Container) and root.size == Vector2.ZERO and _guess_preset(root) == "top_left":
		var needs := false
		for item in state.layouts:
			if item[0].get_parent() == null or item[0] in built:
				needs = needs or item[1] != Control.PRESET_TOP_LEFT
		if needs:
			for k in LAYOUT_PROPS:
				u.add_undo_property(root, k, root.get(k))
			u.add_do_method(self, "set_preset", root, Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)
			state["root_fixed"] = true
	for n in built:
		u.add_do_method(parent, "add_child", n, true)
		u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", n, root)
		u.add_do_reference(n)
		u.add_undo_method(parent, "remove_child", n)
	u.add_do_method(self, "_apply_layouts", state.layouts)
	ctx.commit()
	var nodes := []
	for n in built:
		_collect_created(n, nodes)
	var out := {"path": ctx.node_path_str(built[0]), "nodes": nodes}
	if state.get("root_fixed", false):
		out["note"] = "The scene root '%s' had zero size; it was set to full_rect so anchor presets work." % root.name
	if built.size() > 1:
		out["paths"] = built.map(func(x): return ctx.node_path_str(x))
	for item in state.layouts:
		var c: Control = item[0]
		if c.get_parent() is Container:
			state.warnings.append("%s: 'layout' ignored because its parent %s is a Container (containers position their children; use size_flags / min_size instead)." % [ctx.node_path_str(c), c.get_parent().get_class()])
	var warn: Array = state.warnings
	for n in built:
		warn.append_array(_layout_warnings(n))
	if not warn.is_empty():
		out["warnings"] = warn
	return out


func _collect_created(n: Node, out: Array) -> void:
	if out.size() >= 150:
		return
	var d := {"path": ctx.node_path_str(n), "type": n.get_class()}
	if n is BaseButton:
		d["signal"] = "pressed"
	out.append(d)
	if n.scene_file_path != "":
		return
	for c in n.get_children():
		_collect_created(c, out)


## Applies anchor presets once nodes are inside the tree (sizes/min sizes are known then).
func _apply_layouts(list: Array) -> void:
	for item in list:
		var c: Control = item[0]
		if not is_instance_valid(c) or not c.is_inside_tree():
			continue
		if c.get_parent() is Container:
			continue
		set_preset(c, item[1], item[2], item[3])


## Applies an anchor preset the way the editor toolbar does (layout_mode = Anchors, so the
## inspector shows the preset), then fixes offsets for the resize mode / margin.
func set_preset(c: Control, preset: int, resize_mode: int = Control.PRESET_MODE_MINSIZE, margin: int = 0) -> void:
	if int(c.get("layout_mode")) != 3:  # keep "uncontrolled" (scene roots / non-Control parents)
		c.set("layout_mode", 1)
	c.set("anchors_preset", preset)
	c.set_anchors_and_offsets_preset(preset, resize_mode, margin)


## Builds one detached node (recursively). parent_hint is the node it will be added under.
func _build(spec: Dictionary, state: Dictionary, parent_hint: Node):
	var type := U.p_str(spec, "type", "Control")
	var n: Node = null
	if type.ends_with(".tscn") or type.ends_with(".scn"):
		var sp := U.res_path(type)
		if not ResourceLoader.exists(sp):
			return U.err("Scene '%s' does not exist." % sp)
		n = (load(sp) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	else:
		n = ctx.router.handlers["scene"]._instantiate_type(U.res_path(type) if type.ends_with(".gd") else type)
		if n == null:
			var common := ["Control", "Label", "Button", "TextureRect", "TextureButton", "ProgressBar", "TextureProgressBar", "LineEdit", "TextEdit", "RichTextLabel", "VBoxContainer", "HBoxContainer", "GridContainer", "MarginContainer", "CenterContainer", "PanelContainer", "Panel", "ColorRect", "NinePatchRect", "ScrollContainer", "CheckBox", "CheckButton", "OptionButton", "HSlider", "VSlider", "SpinBox", "ItemList", "TabContainer", "CanvasLayer"]
			var s := U.suggest(type, common)
			if s == "":
				s = U.suggest(type, Array(ClassDB.get_inheriters_from_class("Control")))
			return U.err("'%s' is not an instantiable node type." % type, ("Did you mean '%s'? " % s if s != "" else "") + "Common UI types: Control, Label, Button, TextureRect, ProgressBar, LineEdit, VBoxContainer, HBoxContainer, GridContainer, MarginContainer, CenterContainer, PanelContainer, Panel, ColorRect, RichTextLabel, CanvasLayer.")
	n.name = U.p_str(spec, "name", type.get_file().get_basename() if type.contains("/") else type)
	var r = _configure(n, spec, state)
	if U.is_err(r):
		n.free()
		r["message"] = "%s (in %s '%s')" % [r.message, type, n.name if is_instance_valid(n) else spec.get("name", type)]
		return r
	for child_spec in U.p_arr(spec, "children"):
		if child_spec is String:
			child_spec = {"type": "Label", "text": child_spec}
		if not (child_spec is Dictionary):
			continue
		var c = _build(child_spec, state, n)
		if U.is_err(c):
			n.free()
			return c
		n.add_child(c, true)
	if spec.has("layout") and n is Control:
		var pr = _preset(spec.layout)
		if U.is_err(pr):
			n.free()
			return pr
		var rm = _resize_mode(U.p_str(spec, "resize", "minsize"))
		if U.is_err(rm):
			n.free()
			return rm
		var margin := U.p_int(spec, "layout_margin", U.p_int(spec, "margin", 0) if not (n is MarginContainer) else 0)
		state.layouts.append([n, pr, rm, margin])
	elif spec.has("layout"):
		state.warnings.append("%s: 'layout' only applies to Control nodes (this is a %s)." % [n.name, n.get_class()])
	return n


## Applies everything except children/layout to a node.
func _configure(n: Node, spec: Dictionary, state: Dictionary):
	if spec.has("script"):
		var scp := U.res_path(U.p_str(spec, "script"))
		if not ResourceLoader.exists(scp):
			return U.err("Script '%s' does not exist." % scp, "Create it with script.create first.")
		n.set_script(load(scp))
	if spec.has("props"):
		var props: Dictionary = _prep_props(U.p_dict(spec, "props"), n)
		if props.has("__forge_error"):
			return props
		var pr = U.apply_props(n, props)
		if U.is_err(pr): return pr
	var infos := U.prop_infos(n)
	var overrides := {}
	# Friendly shortcuts.
	if spec.has("text"):
		if not infos.has("text"):
			return U.err("%s has no 'text'." % n.get_class(), "Use a Label, Button, LineEdit or RichTextLabel for text.")
		n.set("text", U.p_str(spec, "text"))
	if spec.has("placeholder"):
		var pr2 = U.set_prop(n, "placeholder_text", spec.placeholder, infos)
		if U.is_err(pr2): return pr2
	if spec.has("tooltip"):
		n.set("tooltip_text", U.p_str(spec, "tooltip"))
	if spec.has("unique"):
		n.unique_name_in_owner = U.p_bool(spec, "unique")
	for g in U.p_arr(spec, "groups"):
		n.add_to_group(str(g), true)
	if n is Control:
		var c: Control = n
		if spec.has("min_size"):
			c.custom_minimum_size = U.to_vector(spec.min_size, TYPE_VECTOR2)
		if spec.has("size_flags"):
			var sf = spec.size_flags
			var h = sf.get("h", sf.get("horizontal", null)) if sf is Dictionary else (sf[0] if sf is Array and sf.size() == 2 and not _is_flag_list(sf) else sf)
			var v = sf.get("v", sf.get("vertical", null)) if sf is Dictionary else (sf[1] if sf is Array and sf.size() == 2 and not _is_flag_list(sf) else sf)
			if h != null:
				var hv = size_flags_value(h)
				if U.is_err(hv): return hv
				c.size_flags_horizontal = hv
			if v != null:
				var vv = size_flags_value(v)
				if U.is_err(vv): return vv
				c.size_flags_vertical = vv
		if spec.has("align"):
			var key := "alignment" if (n is BoxContainer or n is FlowContainer) else "horizontal_alignment"
			var pr3 = U.set_prop(n, key, _align_name(spec.align, key), infos)
			if U.is_err(pr3): return pr3
		if spec.has("valign"):
			var pr4 = U.set_prop(n, "vertical_alignment", _align_name(spec.valign, "vertical_alignment"), infos)
			if U.is_err(pr4): return pr4
		if spec.has("texture"):
			var tkey := "texture_normal" if n is TextureButton else "texture"
			if not infos.has(tkey):
				return U.err("%s has no texture property." % n.get_class(), "Use TextureRect, TextureButton, NinePatchRect or Sprite nodes for images.")
			var pr5 = U.set_prop(n, tkey, spec.texture, infos)
			if U.is_err(pr5): return pr5
			if n is TextureRect and not (spec.get("props", {}) as Dictionary).has("expand_mode"):
				n.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				n.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if spec.has("icon"):
			var pr6 = U.set_prop(n, "icon", spec.icon, infos)
			if U.is_err(pr6): return pr6
		if spec.has("color"):
			if infos.has("color"):
				var col = parse_color(spec.color)
				if U.is_err(col): return col
				n.set("color", col)
			elif (n is Panel or n is PanelContainer) and not (spec.has("panel") or spec.has("stylebox")):
				overrides["panel"] = {"bg_color": spec.color}
			else:
				overrides["font_color"] = spec.color
		if spec.has("font_color"):
			overrides["font_color"] = spec.font_color
		if spec.has("font_size"):
			overrides["font_size"] = spec.font_size
		if spec.has("separation"):
			overrides["separation"] = spec.separation
		if spec.has("margin") and n is MarginContainer:
			overrides["margin"] = spec.margin
		if spec.has("panel") or spec.has("stylebox"):
			var style_name := "panel" if (n is Panel or n is PanelContainer) else "normal"
			overrides[style_name] = spec.get("panel", spec.get("stylebox"))
		if spec.has("theme"):
			var th = U.to_object(spec.theme, "Theme")
			if U.is_err(th): return th
			if not (th is Theme):
				return U.err("'theme' must be a Theme resource (res://....tres).")
			c.theme = th
	# Other keys: node properties or theme items.
	for key in spec:
		if key in SPEC_KEYS:
			continue
		if infos.has(key):
			var val = _fix_enum(infos, str(key), spec[key])
			if key == "mouse_filter" and val is String and str(val).to_lower() in MOUSE_FILTERS:
				val = MOUSE_FILTERS.find(str(val).to_lower())
			if key in ["size_flags_horizontal", "size_flags_vertical"]:
				val = size_flags_value(val)
				if U.is_err(val): return val
			var pr7 = U.set_prop(n, key, val, infos)
			if U.is_err(pr7): return pr7
		elif n is Control:
			overrides[key] = spec[key]
		else:
			state.warnings.append("%s: ignored unknown key '%s'." % [n.name, key])
	for k in ["theme_overrides", "overrides"]:
		if spec.has(k):
			if not (spec[k] is Dictionary):
				return U.err("'%s' must be an object, e.g. {\"font_size\": 32, \"font_color\": \"#ffcc00\"}." % k)
			overrides.merge(spec[k], true)
	if not overrides.is_empty():
		if not (n is Control):
			return U.err("Theme overrides only apply to Control nodes (%s is a %s)." % [n.name, n.get_class()])
		var ov = parse_overrides(n, overrides)
		if U.is_err(ov): return ov
		for prop in ov:
			n.set(prop, ov[prop])
	return null


func _is_flag_list(a: Array) -> bool:
	# ["expand", "fill"] is one flag combination; ["expand_fill", "shrink_center"] is [h, v].
	for x in a:
		var s := str(x).to_lower()
		if s in ["expand", "fill"]:
			continue
		return false
	return true


## Maps friendly alignment words to the enum labels of the target property.
func _align_name(v, target: String) -> Variant:
	if not (v is String):
		return v
	var s: String = v.to_lower().strip_edges()
	if s in ["middle", "centre", "center"]:
		return "center"
	var start := s in ["start", "begin", "left", "top"]
	var finish := s in ["end", "right", "bottom"]
	match target:
		"alignment":
			return "begin" if start else ("end" if finish else s)
		"horizontal_alignment":
			return "left" if start else ("right" if finish else s)
		"vertical_alignment":
			return "top" if start else ("bottom" if finish else s)
	return s


## Resolves size flags from "expand_fill" | "shrink_center" | ["expand", "fill"] | "expand|fill" | int.
func size_flags_value(v):
	if v is int or v is float:
		return int(v)
	var parts := []
	if v is Array:
		parts = v
	else:
		parts = Array(str(v).to_lower().replace(" ", "").replace("+", "|").replace(",", "|").split("|", false))
	var bits := 0
	for part in parts:
		var s := str(part).to_lower().strip_edges().replace("size_", "").replace(" ", "_")
		if not SIZE_FLAGS.has(s):
			var sug := U.suggest(s, SIZE_FLAGS.keys())
			return U.err("Unknown size flag '%s'." % s, ("Did you mean '%s'? " % sug if sug != "" else "") + "Valid: fill, expand, expand_fill, shrink_begin, shrink_center, shrink_end.")
		bits |= int(SIZE_FLAGS[s])
	return bits


func size_flags_names(bits: int) -> String:
	var names := []
	if bits & Control.SIZE_FILL: names.append("fill")
	if bits & Control.SIZE_EXPAND: names.append("expand")
	if bits & Control.SIZE_SHRINK_CENTER: names.append("shrink_center")
	if bits & Control.SIZE_SHRINK_END: names.append("shrink_end")
	if names.is_empty(): return "shrink_begin"
	if names == ["fill", "expand"]: return "expand_fill"
	return "|".join(names)


func _prep_props(props: Dictionary, n: Object = null) -> Dictionary:
	var out := props.duplicate()
	if n:
		var infos := U.prop_infos(n)
		for key in out:
			out[key] = _fix_enum(infos, str(key), out[key])
	for key in ["size_flags_horizontal", "size_flags_vertical"]:
		if out.has(key) and not (out[key] is int or out[key] is float):
			var v = size_flags_value(out[key])
			if U.is_err(v): return v
			out[key] = v
	if out.has("mouse_filter") and out.mouse_filter is String and str(out.mouse_filter).to_lower() in MOUSE_FILTERS:
		out["mouse_filter"] = MOUSE_FILTERS.find(str(out.mouse_filter).to_lower())
	return out


## Lenient enum names: "word_smart" matches "Word (Smart)", "keep-aspect" matches "Keep Aspect"
## (letters and digits only, case-insensitive). Returns the int, or the value unchanged.
func _fix_enum(infos: Dictionary, key: String, val) -> Variant:
	if not (val is String) or not infos.has(key):
		return val
	var pi: Dictionary = infos[key]
	if pi.type != TYPE_INT or pi.hint != PROPERTY_HINT_ENUM:
		return val
	var want := _alnum(val)
	var idx := 0
	for part in str(pi.hint_string).split(","):
		var kv := part.split(":")
		var v := int(kv[1]) if kv.size() > 1 else idx
		if _alnum(kv[0]) == want:
			return v
		idx += 1
	return val


func _alnum(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


func _preset(v):
	if v is int or v is float:
		return int(v)
	var s := str(v).to_lower().strip_edges().replace("preset_", "").replace(" ", "_").replace("-", "_")
	s = PRESET_ALIASES.get(s, s)
	if PRESETS.has(s):
		return PRESETS[s]
	var sug := U.suggest(s, PRESETS.keys())
	if sug == "":
		sug = U.suggest(s, PRESET_ALIASES.keys())
	return U.err("Unknown layout preset '%s'." % str(v), ("Did you mean '%s'? " % sug if sug != "" else "") + "Valid: " + ", ".join(PRESETS.keys()))


func _resize_mode(s: String):
	s = s.to_lower()
	if RESIZE_MODES.has(s):
		return RESIZE_MODES[s]
	return U.err("Unknown resize mode '%s'." % s, "Valid: minsize (default), keep_width, keep_height, keep_size.")


# ---------------------------------------------------------------------------
# Theme overrides and StyleBoxes
# ---------------------------------------------------------------------------

## Converts friendly overrides into {"theme_override_*/name": value}. Accepts flat keys
## (font_size, font_color, separation, panel...) resolved against the control's default
## theme items, or grouped {colors: {...}, constants: {...}, font_sizes, fonts, styles, icons}.
func parse_overrides(c: Control, ov: Dictionary):
	var out := {}
	var infos := U.prop_infos(c)
	for key in ov:
		var val = ov[key]
		var group := str(KIND_ALIASES.get(key, key))
		if OVERRIDE_KINDS.has(group) and val is Dictionary:
			for item in val:
				# Only overrides listed in the property list are real (and saved to the scene);
				# Control.set() silently ignores unknown ones.
				if not infos.has(OVERRIDE_KINDS[group] + str(item)):
					var valid := _items_of_kind(_theme_types(c), group)
					var sug2 := U.suggest(str(item), valid)
					return U.err("'%s' is not a %s theme item of %s." % [item, group.trim_suffix("s"), c.get_class()], ("Did you mean '%s'? " % sug2 if sug2 != "" else "") + ("Valid %s: %s." % [group, ", ".join(valid)] if not valid.is_empty() else "%s has no %s theme items." % [c.get_class(), group]))
				var r = _override_value(group, str(item), val[item])
				if U.is_err(r):
					r["message"] = "%s.%s: %s" % [group, item, r.message]
					return r
				out[OVERRIDE_KINDS[group] + str(item)] = r[0]
			continue
		# Aliases that expand to several items.
		if key == "margin" and c is MarginContainer:
			var m := _four(val)
			for i in 4:
				out["theme_override_constants/margin_" + ["left", "top", "right", "bottom"][i]] = int(m[i])
			continue
		if key == "separation" and c is GridContainer:
			out["theme_override_constants/h_separation"] = int(val)
			out["theme_override_constants/v_separation"] = int(val)
			continue
		var kind := _item_kind(c, str(key), val)
		if kind != "" and not infos.has(OVERRIDE_KINDS[kind] + str(key)):
			kind = ""
		if kind == "":
			var known := _known_items(c)
			var sug := U.suggest(str(key), known)
			return U.err("'%s' is not a theme item of %s." % [key, c.get_class()], ("Did you mean '%s'? " % sug if sug != "" else "") + "Theme items: " + ", ".join(known.slice(0, 40)) + ". Or group explicitly: {\"colors\": {...}, \"constants\": {...}, \"font_sizes\": {...}, \"styles\": {...}}.")
		var r2 = _override_value(kind, str(key), val)
		if U.is_err(r2):
			r2["message"] = "%s: %s" % [key, r2.message]
			return r2
		out[OVERRIDE_KINDS[kind] + str(key)] = r2[0]
	return out


## Returns [value] (wrapped so null = "remove override" is distinguishable) or an error.
func _override_value(kind: String, _name: String, val):
	if val == null:
		return [null]
	match kind:
		"colors":
			var col = parse_color(val)
			if U.is_err(col): return col
			return [col]
		"constants", "font_sizes":
			if val is bool:
				return [1 if val else 0]
			if val is String and (val as String).is_valid_float():
				return [int(val.to_float())]
			if not (val is int or val is float):
				return U.err("Expected a number, got %s." % JSON.stringify(val), "Constants and font sizes are integers, e.g. 16.")
			return [int(val)]
		"fonts":
			var f = font_value(val)
			if U.is_err(f): return f
			return [f]
		"styles":
			var sb = stylebox(val)
			if U.is_err(sb): return sb
			return [sb]
		"icons":
			var t = U.to_object(val, "Texture2D")
			if U.is_err(t): return t
			if not (t is Texture2D):
				return U.err("Icons must be textures (res://icon.png).")
			return [t]
	return U.err("Unknown override kind '%s'." % kind)


func _theme_types(c: Control) -> Array:
	var types := []
	if str(c.theme_type_variation) != "":
		types.append(str(c.theme_type_variation))
	var cls := c.get_class()
	while cls != "" and cls != "CanvasItem":
		types.append(cls)
		cls = ClassDB.get_parent_class(cls)
	return types


func _item_kind(c: Control, key: String, val) -> String:
	var themes: Array = [ThemeDB.get_default_theme()]
	if ThemeDB.get_project_theme():
		themes.push_front(ThemeDB.get_project_theme())
	for t in themes:
		for ty in _theme_types(c):
			# (has_font/has_font_size return true for any name when a default exists.)
			if t.get_color_list(ty).has(key): return "colors"
			if t.get_constant_list(ty).has(key): return "constants"
			if t.get_font_size_list(ty).has(key): return "font_sizes"
			if t.get_font_list(ty).has(key): return "fonts"
			if t.get_stylebox_list(ty).has(key): return "styles"
			if t.get_icon_list(ty).has(key): return "icons"
	# Custom theme types (script-defined): guess from the name / value.
	if key.ends_with("color"): return "colors"
	if key == "font_size" or key.ends_with("_font_size"): return "font_sizes"
	return ""


func _known_items(c: Control) -> Array:
	var t := ThemeDB.get_default_theme()
	var out := []
	for ty in _theme_types(c):
		for kind_list in [t.get_color_list(ty), t.get_constant_list(ty), t.get_font_size_list(ty), t.get_font_list(ty), t.get_stylebox_list(ty), t.get_icon_list(ty)]:
			for item in kind_list:
				if not (item in out):
					out.append(item)
	return out


## Theme items of one kind ("colors", "styles"...) for a list of theme type names, from the
## default theme (what the engine defines for those classes).
func _items_of_kind(types: Array, kind: String) -> Array:
	var t := ThemeDB.get_default_theme()
	var out := []
	for ty in types:
		var lst := PackedStringArray()
		match kind:
			"colors": lst = t.get_color_list(ty)
			"constants": lst = t.get_constant_list(ty)
			"font_sizes": lst = t.get_font_size_list(ty)
			"fonts": lst = t.get_font_list(ty)
			"styles": lst = t.get_stylebox_list(ty)
			"icons": lst = t.get_icon_list(ty)
		for item in lst:
			if not (item in out):
				out.append(item)
	return out


## Class chain used for theme lookups of a type name (follows type variations in `theme`).
## Empty when the type is a custom (script / free-form) theme type.
func _type_chain(theme: Theme, type_name: String) -> Array:
	var ty := type_name
	var guard := 0
	while not ClassDB.class_exists(ty) and guard < 8:
		var base := str(theme.get_type_variation_base(ty)) if theme else ""
		if base == "":
			return []
		ty = base
		guard += 1
	var out := []
	while ty != "" and ty != "CanvasItem" and ty != "Object":
		out.append(ty)
		ty = ClassDB.get_parent_class(ty)
	return out


func parse_color(v):
	if v is String:
		var s: String = v.strip_edges()
		if s.begins_with("Color(") or Color.html_is_valid(s):
			return U.to_color(s)
		var sentinel := Color(0.1234, 0.5678, 0.9012, 0.3456)
		var named := Color.from_string(s, sentinel)
		if named == sentinel:
			return U.err("Invalid color '%s'." % s, "Use '#rrggbb', '#rrggbbaa', a name like 'white'/'dark_slate_gray', or [r, g, b, a].")
		return named
	return U.to_color(v)


## [l, t, r, b] from a number, [h, v], [l, t, r, b] or {left, top, right, bottom}.
func _four(v) -> Array:
	if v is Array:
		if v.size() == 2: return [v[0], v[1], v[0], v[1]]
		if v.size() >= 4: return [v[0], v[1], v[2], v[3]]
		if v.size() == 1: return [v[0], v[0], v[0], v[0]]
	if v is Dictionary:
		return [v.get("left", 0), v.get("top", 0), v.get("right", 0), v.get("bottom", 0)]
	return [v, v, v, v]


## Builds a StyleBox from a friendly spec. Plain dict -> StyleBoxFlat:
## {bg_color, border_color, border_width: n|[l,t,r,b], corner_radius: n|[tl,tr,br,bl],
##  content_margin: n|[h,v]|[l,t,r,b], expand_margin, shadow_color, shadow_size, shadow_offset,
##  anti_aliasing, draw_center, skew, ...any StyleBoxFlat property}.
## "empty" -> StyleBoxEmpty, "res://x.tres" -> loaded, {"type": "StyleBoxTexture", ...} -> that type.
func stylebox(v):
	if v is StyleBox:
		return v
	if v is String:
		var s: String = v
		if s.to_lower() in ["empty", "none", "transparent"]:
			return StyleBoxEmpty.new()
		if s.begins_with("#") or Color.html_is_valid(s):
			v = {"bg_color": s}
		else:
			var o = U.to_object(s, "StyleBox")
			if U.is_err(o): return o
			if not (o is StyleBox):
				return U.err("'%s' is not a StyleBox." % s)
			return o
	if not (v is Dictionary):
		return U.err("A stylebox must be an object like {\"bg_color\": \"#223344\", \"corner_radius\": 8}, \"empty\" or a res:// path.")
	var d: Dictionary = v.duplicate()
	var cls := str(d.get("type", "StyleBoxFlat"))
	d.erase("type")
	if not ClassDB.class_exists(cls) or not ClassDB.is_parent_class(cls, "StyleBox") or not ClassDB.can_instantiate(cls):
		return U.err("'%s' is not a StyleBox type." % cls, "Use StyleBoxFlat (default), StyleBoxEmpty, StyleBoxTexture or StyleBoxLine.")
	var sb: StyleBox = ClassDB.instantiate(cls)
	var infos := U.prop_infos(sb)
	for key in d:
		var val = d[key]
		match key:
			"bg", "color", "background", "bg_color":
				if sb is StyleBoxLine:
					sb.color = U.to_color(val)
				else:
					var c = parse_color(val)
					if U.is_err(c): return c
					sb.set("bg_color", c)
				continue
			"border_width", "border":
				if val is Dictionary:
					if val.has("color"):
						sb.set("border_color", U.to_color(val.color))
					val = val.get("width", 1)
				var w := _four(val)
				for i in 4:
					sb.set("border_width_" + ["left", "top", "right", "bottom"][i], int(w[i]))
				continue
			"corner_radius", "radius", "corners":
				var r := _four(val)
				for i in 4:
					sb.set("corner_radius_" + ["top_left", "top_right", "bottom_right", "bottom_left"][i], int(r[i]))
				continue
			"content_margin", "padding":
				var m := _four(val)
				for i in 4:
					sb.set("content_margin_" + ["left", "top", "right", "bottom"][i], float(m[i]))
				continue
			"expand_margin":
				var e := _four(val)
				for i in 4:
					sb.set("expand_margin_" + ["left", "top", "right", "bottom"][i], float(e[i]))
				continue
			"texture_margin":
				var tm := _four(val)
				for i in 4:
					sb.set("texture_margin_" + ["left", "top", "right", "bottom"][i], float(tm[i]))
				continue
			"shadow":
				if val is Dictionary:
					for sk in val:
						var pr = U.set_prop(sb, "shadow_" + str(sk) if not str(sk).begins_with("shadow_") else str(sk), val[sk], infos)
						if U.is_err(pr): return pr
				continue
		var pr2 = U.set_prop(sb, str(key), val, infos)
		if U.is_err(pr2): return pr2
	return sb


func font_value(v):
	if v is Font:
		return v
	var f = U.to_object(v, "Font")
	if U.is_err(f): return f
	if not (f is Font):
		return U.err("Not a font: %s." % str(v), "Use a res:// .ttf/.otf/.woff2 file or a FontVariation .tres.")
	return f


# ---------------------------------------------------------------------------
# layout / theme_override actions
# ---------------------------------------------------------------------------

const LAYOUT_PROPS := ["layout_mode", "anchors_preset", "anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left", "offset_top", "offset_right", "offset_bottom", "grow_horizontal", "grow_vertical"]


## Applies an anchor preset (and optionally size flags / min size) to one or more Controls.
func a_layout(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var paths: Array = U.p_arr(p, "paths") if p.has("paths") else [U.p_str(p, "path", ".")]
	if not (p.has("preset") or p.has("size_flags") or p.has("min_size")):
		return U.err("Nothing to do.", "Pass preset (e.g. 'full_rect', 'center', 'bottom_wide'), size_flags and/or min_size.")
	var preset = null
	if p.has("preset"):
		preset = _preset(p.preset)
		if U.is_err(preset): return preset
	var rm = _resize_mode(U.p_str(p, "resize", "minsize"))
	if U.is_err(rm): return rm
	var margin := U.p_int(p, "margin", 0)
	var plan := []
	for path in paths:
		var n: Node = ctx.find_node(str(path))
		if n == null:
			return ctx.node_not_found(str(path))
		if not (n is Control):
			return U.err("'%s' is a %s, not a Control." % [path, n.get_class()], "Anchor presets only apply to Control nodes. Put UI under a CanvasLayer > Control.")
		var c: Control = n
		if preset != null and c.get_parent() is Container:
			return U.err("'%s' is inside a %s, which controls its position and size." % [path, c.get_parent().get_class()], "Use size_flags ('expand_fill', 'shrink_center'...) and min_size instead of an anchor preset, or move it out of the container.")
		var old := {}
		for k in LAYOUT_PROPS + ["size_flags_horizontal", "size_flags_vertical", "custom_minimum_size"]:
			old[k] = c.get(k)
		plan.append([c, old])
	var hv = null
	var vv = null
	if p.has("size_flags"):
		var sf = p.size_flags
		var h = sf.get("h", sf.get("horizontal", null)) if sf is Dictionary else (sf[0] if sf is Array and sf.size() == 2 and not _is_flag_list(sf) else sf)
		var v = sf.get("v", sf.get("vertical", null)) if sf is Dictionary else (sf[1] if sf is Array and sf.size() == 2 and not _is_flag_list(sf) else sf)
		if h != null:
			hv = size_flags_value(h)
			if U.is_err(hv): return hv
		if v != null:
			vv = size_flags_value(v)
			if U.is_err(vv): return vv
	# Compute the new values by applying for real, then record them as an undoable action.
	var news := []
	for item in plan:
		var c: Control = item[0]
		if p.has("min_size"):
			c.custom_minimum_size = U.to_vector(p.min_size, TYPE_VECTOR2)
		if hv != null: c.size_flags_horizontal = hv
		if vv != null: c.size_flags_vertical = vv
		if preset != null:
			set_preset(c, preset, rm, margin)
		var nv := {}
		for k in item[1]:
			nv[k] = c.get(k)
		news.append(nv)
	var u = ctx.begin("Set layout")
	for i in plan.size():
		var c: Control = plan[i][0]
		for k in plan[i][1]:
			if plan[i][1][k] != news[i][k]:
				u.add_do_property(c, k, news[i][k])
				u.add_undo_property(c, k, plan[i][1][k])
	ctx.commit()
	var out := []
	for item in plan:
		out.append(_rect_info(item[0]))
	return out[0] if out.size() == 1 else {"nodes": out}


func _rect_info(c: Control) -> Dictionary:
	return {
		"path": ctx.node_path_str(c), "preset": _guess_preset(c),
		"anchors": [snappedf(c.anchor_left, 0.001), snappedf(c.anchor_top, 0.001), snappedf(c.anchor_right, 0.001), snappedf(c.anchor_bottom, 0.001)],
		"offsets": [c.offset_left, c.offset_top, c.offset_right, c.offset_bottom],
		"position": [c.position.x, c.position.y], "size": [c.size.x, c.size.y],
		"size_flags": {"h": size_flags_names(c.size_flags_horizontal), "v": size_flags_names(c.size_flags_vertical)},
	}


## Sets/removes theme overrides on one or more Controls (null value removes an override).
func a_theme_override(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var ov := U.p_dict(p, "overrides")
	if ov.is_empty():
		return U.err("Missing 'overrides'.", "e.g. overrides: {\"font_size\": 32, \"font_color\": \"#ffd166\", \"styles\": {\"panel\": {\"bg_color\": \"#1d2330\", \"corner_radius\": 12}}}.")
	var paths: Array = U.p_arr(p, "paths") if p.has("paths") else [U.p_str(p, "path", ".")]
	var plan := []
	for path in paths:
		var n: Node = ctx.find_node(str(path))
		if n == null:
			return ctx.node_not_found(str(path))
		if not (n is Control):
			return U.err("'%s' is a %s, not a Control." % [path, n.get_class()])
		var props = parse_overrides(n, ov)
		if U.is_err(props): return props
		plan.append([n, props])
	var u = ctx.begin("Theme overrides")
	for item in plan:
		var c: Control = item[0]
		for prop in item[1]:
			u.add_do_property(c, prop, item[1][prop])
			u.add_undo_property(c, prop, c.get(prop))
	ctx.commit()
	var out := {}
	for item in plan:
		out[ctx.node_path_str(item[0])] = _overrides_of(item[0])
	return {"overrides": out}


func _overrides_of(c: Control) -> Dictionary:
	var out := {}
	for pi in c.get_property_list():
		var pname: String = pi.name
		if pname.begins_with("theme_override_") and pname.contains("/"):
			var v = c.get(pname)
			if v != null:
				out[pname.get_slice("/", 1)] = var_to_str(v) if v is Color else U.encode(v)
	return out


# ---------------------------------------------------------------------------
# Theme resources
# ---------------------------------------------------------------------------

## Creates or edits a Theme resource.
## {path, props: {default_font_size, default_font, default_base_scale, colors: {Type: {item: color}},
##  constants, font_sizes, fonts, icons, styles: {Type: {state: stylebox}}, type_variations: {Name: BaseType}},
##  replace?: bool (start empty), assign_to?: node path | "project"}
## Style states in a type inherit the "normal" dict (so hover can just change bg_color).
func a_theme(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if path.get_extension() == "":
		path += ".tres"
	if not (path.get_extension() in ["tres", "res", "theme"]):
		return U.err("Theme path must end in .tres (got '%s')." % path)
	var spec := U.p_dict(p, "props").duplicate()
	var theme_keys := ["default_font_size", "default_font", "default_base_scale", "colors", "constants", "font_sizes", "fonts", "icons", "styles", "styleboxes", "type_variations"]
	for k in p:
		if k in theme_keys:
			if not spec.has(k):
				spec[k] = p[k]
		elif not (k in ["path", "props", "replace", "assign_to", "scene"]):
			var sug := U.suggest(str(k), theme_keys)
			return U.err("Unknown theme key '%s'." % k, ("Did you mean '%s'? " % sug if sug != "" else "") + "Valid: " + ", ".join(theme_keys) + " (at the top level or inside props), plus replace and assign_to.")
	if spec.is_empty() and not p.has("assign_to"):
		return U.err("Nothing to put in the theme.", "Pass e.g. props: {\"default_font_size\": 20, \"styles\": {\"Button\": {\"normal\": {\"bg_color\": \"#2b2d42\", \"corner_radius\": 8}}}}.")
	# Resolve assign_to before writing anything.
	var target := U.p_str(p, "assign_to")
	var target_node: Node = null
	if p.has("assign_to") and target != "project":
		if p.has("scene"):
			var rs = await ensure_scene(U.p_str(p, "scene"))
			if U.is_err(rs): return rs
		target_node = ctx.find_node(target)
		if target_node == null:
			return ctx.node_not_found(target)
		if not (target_node is Control or target_node is Window):
			return U.err("'%s' is a %s; themes go on a Control (its children inherit it) or 'project'." % [target, target_node.get_class()], "Assign it to the Control under it (e.g. '%s/<Control>'), or pass assign_to: 'project'." % target)
	var theme: Theme
	var existed := ResourceLoader.exists(path)
	if existed and not U.p_bool(p, "replace", false):
		var loaded = load(path)
		if not (loaded is Theme):
			return U.err("'%s' exists and is a %s, not a Theme." % [path, loaded.get_class()], "Pick another path.")
		theme = loaded
	else:
		theme = Theme.new()
	# Validate on a copy first so a bad item doesn't leave the cached theme half-edited.
	var probe = _fill_theme(theme.duplicate(), spec)
	if U.is_err(probe): return probe
	_fill_theme(theme, spec)
	ctx.before_write([path])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(theme, path)
	if err != OK:
		return U.err("Failed to save '%s' (error %d)." % [path, err])
	theme.take_over_path(path)
	ctx.fs().update_file(path)
	var out := {"path": path, "created": not existed, "summary": _theme_summary(theme)}
	if p.has("assign_to"):
		if target == "project":
			ctx.before_write(["res://project.godot"])
			ProjectSettings.set_setting("gui/theme/custom", path)
			ProjectSettings.save()
			out["assigned"] = "project (gui/theme/custom) - applies to every Control in the game"
		else:
			var n: Node = target_node
			var u = ctx.begin("Assign theme")
			u.add_do_property(n, "theme", theme)
			u.add_undo_property(n, "theme", n.get("theme"))
			ctx.commit()
			out["assigned"] = ctx.node_path_str(n)
	return out


func _fill_theme(theme: Theme, spec: Dictionary):
	var keys := spec.keys()
	if keys.has("type_variations"):
		keys.erase("type_variations")
		keys.push_front("type_variations")
	for key in keys:
		var val = spec[key]
		match key:
			"default_font_size":
				theme.default_font_size = int(val)
			"default_base_scale":
				theme.default_base_scale = float(val)
			"default_font":
				var f = font_value(val)
				if U.is_err(f): return f
				theme.default_font = f
			"type_variations":
				if not (val is Dictionary):
					return U.err("type_variations must be {\"TitleLabel\": \"Label\"}.")
				for tv in val:
					theme.set_type_variation(str(tv), str(val[tv]))
			"colors", "constants", "font_sizes", "fonts", "icons", "styles", "styleboxes":
				if not (val is Dictionary):
					return U.err("'%s' must be {\"TypeName\": {\"item\": value}}, e.g. {\"Button\": {\"font_color\": \"#ffffff\"}}." % key)
				var kind: String = "styles" if key == "styleboxes" else key
				for type_name in val:
					var items = val[type_name]
					if not (items is Dictionary):
						return U.err("%s.%s must be an object of items." % [key, type_name])
					if not ClassDB.class_exists(str(type_name)) and str(theme.get_type_variation_base(str(type_name))) == "" and not theme.get_type_list().has(str(type_name)):
						var sug := U.suggest(str(type_name), Array(ClassDB.get_inheriters_from_class("Control")))
						return U.err("Unknown theme type '%s'." % type_name, ("Did you mean '%s'? " % sug if sug != "" else "") + "Use a Control class name (Button, Label, Panel...) or declare it in type_variations first.")
					var base_style = items.get("normal", null) if kind == "styles" else null
					if base_style is String and (str(base_style).begins_with("#") or Color.html_is_valid(str(base_style))):
						base_style = {"bg_color": base_style}  # "normal": "#334455" still gives hover a base
					# Engine classes (and variations of them) only read the items they define;
					# catch typos like 'font_colr' instead of storing an item nothing uses.
					var valid := _items_of_kind(_type_chain(theme, str(type_name)), kind)
					for item in items:
						if not valid.is_empty() and not (str(item) in valid):
							var sug_i := U.suggest(str(item), valid)
							return U.err("%s.%s: '%s' is not a %s item of %s." % [key, type_name, item, kind.trim_suffix("s"), type_name], ("Did you mean '%s'? " % sug_i if sug_i != "" else "") + "Valid: " + ", ".join(valid))
						var v = items[item]
						if kind == "styles" and base_style is Dictionary and v is Dictionary and item != "normal" and not v.has("type"):
							var merged: Dictionary = base_style.duplicate()
							merged.merge(v, true)
							v = merged
						var r = _override_value(kind, str(item), v)
						if U.is_err(r):
							r["message"] = "%s.%s.%s: %s" % [key, type_name, item, r.message]
							return r
						var value = r[0]
						match kind:
							"colors": theme.set_color(str(item), str(type_name), value)
							"constants": theme.set_constant(str(item), str(type_name), value)
							"font_sizes": theme.set_font_size(str(item), str(type_name), value)
							"fonts": theme.set_font(str(item), str(type_name), value)
							"icons": theme.set_icon(str(item), str(type_name), value)
							"styles": theme.set_stylebox(str(item), str(type_name), value)
			_:
				return U.err("Unknown theme key '%s'." % key, "Valid: default_font_size, default_font, default_base_scale, colors, constants, font_sizes, fonts, icons, styles, type_variations.")
	return null


func _theme_summary(theme: Theme) -> Dictionary:
	var out := {}
	if theme.default_font_size > 0:
		out["default_font_size"] = theme.default_font_size
	if theme.default_font:
		out["default_font"] = theme.default_font.resource_path if theme.default_font.resource_path != "" else theme.default_font.get_class()
	var types := {}
	for ty in theme.get_type_list():
		var d := {}
		if theme.get_color_list(ty).size(): d["colors"] = Array(theme.get_color_list(ty))
		if theme.get_constant_list(ty).size(): d["constants"] = Array(theme.get_constant_list(ty))
		if theme.get_font_size_list(ty).size(): d["font_sizes"] = Array(theme.get_font_size_list(ty))
		if theme.get_font_list(ty).size(): d["fonts"] = Array(theme.get_font_list(ty))
		if theme.get_stylebox_list(ty).size(): d["styles"] = Array(theme.get_stylebox_list(ty))
		if theme.get_icon_list(ty).size(): d["icons"] = Array(theme.get_icon_list(ty))
		var base := str(theme.get_type_variation_base(ty))
		if base != "": d["variation_of"] = base
		types[ty] = d
	out["types"] = types
	return out


# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------

## Loads a font file (imported as FontFile), optionally wraps it in a FontVariation and/or
## assigns it: {path, size?, variation?: {embolden, spacing_glyph, ...}, save_as?, assign_to?: node | "project" | "res://theme.tres"}.
func a_font(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not ResourceLoader.exists(path):
		if FileAccess.file_exists(path):
			# Copied in from outside the editor (maybe into a brand-new folder): import it now.
			await _import_file(path)
		if not ResourceLoader.exists(path):
			if FileAccess.file_exists(path):
				return U.err("Font '%s' exists but could not be imported." % path, "Run files.rescan, then check editor.logs for import errors.")
			return U.err("Font '%s' not found." % path, "Copy a .ttf/.otf/.woff2 into the project first (files.copy / assets tools), then call ui.font.")
	var font = load(path)
	if not (font is Font):
		return U.err("'%s' is a %s, not a font." % [path, font.get_class()])
	var result: Font = font
	var out := {"path": path, "type": font.get_class()}
	if font is FontFile:
		out["font_name"] = font.get_font_name()
		out["style_name"] = font.get_font_style_name()
	var variation := U.p_dict(p, "variation")
	if not variation.is_empty() or p.has("save_as"):
		var fv := FontVariation.new()
		fv.base_font = font
		for key in variation:
			var k := str(key)
			var pk := k if k.begins_with("variation_") or k.begins_with("spacing_") or k in ["base_font", "fallbacks", "baseline_offset", "opentype_features"] else ("variation_" + k if k in ["embolden", "transform", "face_index", "opentype"] else k)
			if k == "spacing":
				fv.spacing_glyph = int(variation[key])
				continue
			if k == "letter_spacing":
				fv.spacing_glyph = int(variation[key])
				continue
			if k == "slant" or k == "italic":
				fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(float(variation[key]) if k == "slant" else 0.2, 1), Vector2.ZERO)
				continue
			var pr = U.set_prop(fv, pk, variation[key])
			if U.is_err(pr):
				pr["hint"] = "Variation keys: embolden (-2..2), slant (0..1), spacing (glyph px), spacing_space, spacing_top, spacing_bottom, baseline_offset, face_index, opentype ({\"wght\": 700} for variable fonts)."
				return pr
		result = fv
		out["type"] = "FontVariation"
		if p.has("save_as"):
			var sp := U.res_path(U.p_str(p, "save_as"))
			if sp.get_extension() == "":
				sp += ".tres"
			ctx.before_write([sp])
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sp.get_base_dir()))
			if ResourceSaver.save(fv, sp) != OK:
				return U.err("Failed to save '%s'." % sp)
			fv.take_over_path(sp)
			ctx.fs().update_file(sp)
			out["saved"] = sp
	if p.has("assign_to"):
		var target := U.p_str(p, "assign_to")
		var size := U.p_int(p, "size", 0)
		if target == "project":
			var fp: String = result.resource_path if result.resource_path != "" else path
			if result is FontVariation and result.resource_path == "":
				return U.err("Save the variation first (save_as) to use it project-wide.")
			ctx.before_write(["res://project.godot"])
			ProjectSettings.set_setting("gui/theme/custom_font", fp)
			if size > 0:
				ProjectSettings.set_setting("gui/theme/default_font_size", size)
			ProjectSettings.save()
			out["assigned"] = "project (gui/theme/custom_font)"
		elif target.ends_with(".tres") or target.ends_with(".res"):
			var tp := U.res_path(target)
			var th = load(tp) if ResourceLoader.exists(tp) else Theme.new()
			if not (th is Theme):
				return U.err("'%s' is a %s, not a Theme." % [tp, th.get_class() if th else "null"], "Pass a Theme .tres (create one with ui.theme) or a node path.")
			th.default_font = result
			if size > 0:
				th.default_font_size = size
			ctx.before_write([tp])
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tp.get_base_dir()))
			if ResourceSaver.save(th, tp) != OK:
				return U.err("Failed to save theme '%s'." % tp)
			th.take_over_path(tp)
			ctx.fs().update_file(tp)
			out["assigned"] = tp + " (default_font)"
		else:
			var n: Node = ctx.find_node(target)
			if n == null:
				return ctx.node_not_found(target)
			if not (n is Control):
				return U.err("'%s' is not a Control." % target)
			var font_key := "normal_font" if n is RichTextLabel else "font"
			if not U.prop_infos(n).has("theme_override_fonts/" + font_key):
				return U.err("%s '%s' has no font theme item." % [n.get_class(), target], "Assign the font to a text control (Label, Button, LineEdit, RichTextLabel...), to a theme (assign_to: 'res://ui/theme.tres') or to 'project'.")
			var u = ctx.begin("Assign font")
			u.add_do_property(n, "theme_override_fonts/" + font_key, result)
			u.add_undo_property(n, "theme_override_fonts/" + font_key, n.get("theme_override_fonts/" + font_key))
			if size > 0:
				var size_key := "normal_font_size" if n is RichTextLabel else "font_size"
				u.add_do_property(n, "theme_override_font_sizes/" + size_key, size)
				u.add_undo_property(n, "theme_override_font_sizes/" + size_key, n.get("theme_override_font_sizes/" + size_key))
			ctx.commit()
			out["assigned"] = ctx.node_path_str(n)
	elif p.has("size"):
		out["note"] = "size is applied together with assign_to (as a font_size override)."
	return out


## Imports a file that was copied into the project from outside the editor. A file in a folder
## the editor hasn't seen yet needs a full scan (reimport_files fails with "!found" there).
func _import_file(path: String, timeout_ms: int = 20000) -> void:
	var efs := ctx.fs()
	if efs.get_filesystem_path(path.get_base_dir()) == null:
		efs.scan()
	else:
		efs.update_file(path)
		efs.reimport_files(PackedStringArray([path]))
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		await ctx.frame()
		if not efs.is_scanning() and ResourceLoader.exists(path):
			break


# ---------------------------------------------------------------------------
# Focus
# ---------------------------------------------------------------------------

## Keyboard/gamepad focus: {path, neighbors: {left, right, top, bottom, next, previous}, mode?}
## or {chain: [paths], axis?: "vertical"|"horizontal", wrap?: true, mode?} to link a list of
## controls (e.g. menu buttons) in order.
func a_focus(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var sets := []  # [control, prop, value]
	var mode = null
	if p.has("mode"):
		var m := U.p_str(p, "mode").to_lower()
		var modes := ["none", "click", "all"]
		if not (m in modes):
			return U.err("Unknown focus mode '%s'." % m, "Valid: none, click, all.")
		mode = modes.find(m)
	if p.has("chain"):
		var ctrls := []
		for path in U.p_arr(p, "chain"):
			var n: Node = ctx.find_node(str(path))
			if n == null:
				return ctx.node_not_found(str(path))
			if not (n is Control):
				return U.err("'%s' is not a Control." % path)
			ctrls.append(n)
		if ctrls.size() < 2:
			return U.err("chain needs at least 2 controls.")
		var vertical := U.p_str(p, "axis", "vertical").to_lower().begins_with("v")
		var wrap := U.p_bool(p, "wrap", true)
		var prev_side := "focus_neighbor_top" if vertical else "focus_neighbor_left"
		var next_side := "focus_neighbor_bottom" if vertical else "focus_neighbor_right"
		for i in ctrls.size():
			var c: Control = ctrls[i]
			var nxt = ctrls[(i + 1) % ctrls.size()] if (wrap or i < ctrls.size() - 1) else null
			var prv = ctrls[(i - 1 + ctrls.size()) % ctrls.size()] if (wrap or i > 0) else null
			if nxt:
				sets.append([c, next_side, c.get_path_to(nxt)])
				sets.append([c, "focus_next", c.get_path_to(nxt)])
			if prv:
				sets.append([c, prev_side, c.get_path_to(prv)])
				sets.append([c, "focus_previous", c.get_path_to(prv)])
			if mode != null:
				sets.append([c, "focus_mode", mode])
	else:
		var n = await node_arg(p)
		if U.is_err(n): return n
		if not (n is Control):
			return U.err("'%s' is not a Control." % U.p_str(p, "path"))
		var nb := U.p_dict(p, "neighbors")
		if nb.is_empty() and mode == null:
			return U.err("Nothing to do.", "Pass neighbors: {\"bottom\": \"Menu/Options\", \"top\": \"Menu/Quit\"}, mode, or chain: [paths].")
		var sides := {"left": "focus_neighbor_left", "right": "focus_neighbor_right", "top": "focus_neighbor_top", "up": "focus_neighbor_top", "bottom": "focus_neighbor_bottom", "down": "focus_neighbor_bottom", "next": "focus_next", "previous": "focus_previous", "prev": "focus_previous"}
		for side in nb:
			if not sides.has(str(side)):
				return U.err("Unknown focus side '%s'." % side, "Valid: left, right, top, bottom, next, previous.")
			var target_path := str(nb[side])
			var np := NodePath()
			if target_path != "":
				var t: Node = ctx.find_node(target_path)
				if t == null:
					return ctx.node_not_found(target_path)
				np = n.get_path_to(t)
			sets.append([n, sides[side], np])
		if mode != null:
			sets.append([n, "focus_mode", mode])
	var u = ctx.begin("Set focus neighbors")
	for s in sets:
		u.add_do_property(s[0], s[1], s[2])
		u.add_undo_property(s[0], s[1], s[0].get(s[1]))
	ctx.commit()
	var touched := {}
	for s in sets:
		var key := ctx.node_path_str(s[0])
		if not touched.has(key):
			touched[key] = {}
		touched[key][s[1]] = str(s[2]) if s[2] is NodePath else ["none", "click", "all"][int(s[2])]
	var out := {"set": touched}
	if p.has("chain"):
		out["hint"] = "Call grab_focus() on the first control in _ready() so keyboard/gamepad navigation works immediately."
	return out


# ---------------------------------------------------------------------------
# Main menu template
# ---------------------------------------------------------------------------

## Quick main menu: full-screen Control > (background) > CenterContainer > VBox (title, buttons).
## In an empty scene whose root is a plain Control (e.g. from scene.create), the menu is built
## directly into the root instead of nesting another full-screen Control.
func a_menu_template(p: Dictionary):
	var buttons := U.p_arr(p, "buttons")
	if buttons.is_empty():
		buttons = ["Play", "Options", "Quit"]
	var title := U.p_str(p, "title", str(ProjectSettings.get_setting("application/config/name", "My Game")))
	var btn_size = p.get("button_size", [260, 56])
	var font_size := U.p_int(p, "font_size", 24)
	if p.has("scene"):
		var rs = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(rs): return rs
	var root_node: Node = ctx.edited_root()
	# Build the button StyleBoxes once and share them (one sub-resource per state, not per button).
	var shared_styles := {}
	if p.has("button_style"):
		var states := _button_states(p.button_style)
		if states.is_empty():
			return U.err("button_style must be a StyleBox spec like {\"bg_color\": \"#2b2d42\", \"corner_radius\": 8} or {\"normal\": {...}, \"hover\": {...}, \"pressed\": {...}}.")
		for st in states:
			var sb = stylebox(states[st])
			if U.is_err(sb):
				sb["message"] = "button_style.%s: %s" % [st, sb.message]
				return sb
			shared_styles[st] = sb
	var vbox_children := []
	var title_spec := {"type": "Label", "name": "Title", "text": title, "align": "center", "font_size": U.p_int(p, "title_size", 56)}
	if p.has("title_color"):
		title_spec["font_color"] = p.title_color
	vbox_children.append(title_spec)
	if p.has("subtitle"):
		vbox_children.append({"type": "Label", "name": "Subtitle", "text": U.p_str(p, "subtitle"), "align": "center", "font_size": maxi(12, int(font_size * 0.75))})
	vbox_children.append({"type": "Control", "name": "Spacer", "min_size": [0, U.p_int(p, "title_gap", 24)]})
	var btn_names := []
	for b in buttons:
		var bn := _pascal(str(b)) + "Button"
		var k := 2
		while bn in btn_names:  # two buttons with the same label
			bn = _pascal(str(b)) + str(k) + "Button"
			k += 1
		btn_names.append(bn)
	var unique := []
	for i in buttons.size():
		var text := str(buttons[i])
		var bname: String = btn_names[i]
		var bspec := {"type": "Button", "name": bname, "text": text, "min_size": btn_size, "font_size": font_size}
		if not shared_styles.is_empty():
			bspec["theme_overrides"] = {"styles": shared_styles}
		var is_unique: bool = root_node == null or root_node.get_node_or_null("%" + bname) == null
		if is_unique:
			bspec["unique"] = true
		unique.append(is_unique)
		if buttons.size() >= 2:
			# Keyboard/gamepad navigation, wrapping around.
			var prv: String = btn_names[(i - 1 + buttons.size()) % buttons.size()]
			var nxt: String = btn_names[(i + 1) % buttons.size()]
			bspec["props"] = {"focus_neighbor_top": "../" + prv, "focus_previous": "../" + prv, "focus_neighbor_bottom": "../" + nxt, "focus_next": "../" + nxt}
		vbox_children.append(bspec)
	var menu_children := []
	if p.has("background"):
		var bg = p.background
		if bg is String and (bg.begins_with("res://") or bg.begins_with("uid://")):
			menu_children.append({"type": "TextureRect", "name": "Background", "texture": bg, "layout": "full_rect", "props": {"expand_mode": "Ignore Size", "stretch_mode": "Keep Aspect Covered", "mouse_filter": "ignore"}})
		else:
			var bgc = parse_color(bg)
			if U.is_err(bgc):
				bgc["message"] = "background: " + bgc.message
				bgc["hint"] = "Use a color ('#101522') or a res:// image path."
				return bgc
			menu_children.append({"type": "ColorRect", "name": "Background", "color": bg, "layout": "full_rect", "props": {"mouse_filter": "ignore"}})
	menu_children.append({"type": "CenterContainer", "name": "Center", "layout": "full_rect", "children": [
		{"type": "VBoxContainer", "name": "VBox", "separation": U.p_int(p, "spacing", 16), "children": vbox_children}]})
	var parent: Node = ctx.find_node(U.p_str(p, "parent", "."))
	var direct: bool = root_node != null and parent == root_node and root_node.get_class() == "Control" and root_node.get_script() == null \
		and root_node.get_child_count() == 0 and not p.has("name") and not p.has("theme")
	var r
	var base := ""
	if direct:
		r = await build_specs(p, menu_children, "Main menu template")
		if U.is_err(r): return r
		base = "."
	else:
		var spec := {"type": "Control", "name": U.p_str(p, "name", "MainMenu"), "layout": "full_rect", "children": menu_children}
		if p.has("theme"):
			spec["theme"] = p.theme
		r = await build_specs(p, [spec], "Main menu template")
		if U.is_err(r): return r
		base = r.path
	var prefix := "" if base == "." else base + "/"
	var paths := {}
	for i in buttons.size():
		var key := str(buttons[i])
		if paths.has(key):  # duplicate labels: keep every button reachable
			key = "%s (%d)" % [key, i + 1]
		paths[key] = prefix + "Center/VBox/" + btn_names[i]
	var first: String = ("%" + btn_names[0]) if unique[0] else ("$\"" + prefix + "Center/VBox/" + btn_names[0] + "\"")
	var out := {"path": base, "title": prefix + "Center/VBox/Title", "buttons": paths,
		"next": "Connect each button's 'pressed' signal (signal.connect {from: <button path>, signal: 'pressed', to: <script node>, method: '_on_play_pressed'}) and call %s.grab_focus() in _ready()." % first}
	if direct:
		out["note"] = "Built directly into the empty scene root '%s'." % root_node.name
	if r.has("note"):
		out["root_note"] = r.note
	if r.has("warnings"):
		out["warnings"] = r.warnings
	return out


func _pascal(text: String) -> String:
	var out := ""
	for part in text.replace("-", " ").replace("_", " ").split(" ", false):
		var clean := ""
		for ch in part:
			if ch.is_valid_identifier() or ch.is_valid_int():
				clean += ch
		if clean != "":
			out += clean.substr(0, 1).to_upper() + clean.substr(1)
	return out if out != "" else "Menu"


func _button_states(style) -> Dictionary:
	if style is Dictionary and (style.has("normal") or style.has("hover")):
		var base = style.get("normal", {})
		var out := {}
		for k in style:
			var v = style[k]
			if k != "normal" and base is Dictionary and v is Dictionary:
				var m: Dictionary = base.duplicate()
				m.merge(v, true)
				v = m
			out[k] = v
		return out
	# One flat style: derive hover/pressed variants by lightening/darkening bg_color.
	if style is Dictionary:
		var normal: Dictionary = style.duplicate()
		var bg: Color = U.to_color(normal.get("bg_color", "#3a3f4b"))
		var hover := normal.duplicate()
		hover["bg_color"] = bg.lightened(0.15)
		var pressed := normal.duplicate()
		pressed["bg_color"] = bg.darkened(0.2)
		return {"normal": normal, "hover": hover, "pressed": pressed, "focus": {"type": "StyleBoxFlat", "draw_center": false, "border_width": 2, "border_color": "#ffffffaa", "corner_radius": normal.get("corner_radius", 0)}}
	return {}


# ---------------------------------------------------------------------------
# inspect
# ---------------------------------------------------------------------------

## Layout debugging info for a Control and its direct children.
func a_inspect(p: Dictionary):
	var n = await node_arg(p)
	if U.is_err(n): return n
	await ctx.frame()  # let containers sort
	if not (n is Control):
		var kids := []
		for ch in n.get_children():
			if ch is Control:
				kids.append(_child_info(ch))
		return {"path": ctx.node_path_str(n), "type": n.get_class(), "note": "Not a Control; showing its Control children.", "children": kids}
	var c: Control = n
	var par := c.get_parent()
	var out := _rect_info(c)
	out["type"] = c.get_class()
	out["global_rect"] = {"position": [c.global_position.x, c.global_position.y], "size": [c.size.x, c.size.y]}
	out["min_size"] = [c.get_minimum_size().x, c.get_minimum_size().y]
	out["combined_min_size"] = [c.get_combined_minimum_size().x, c.get_combined_minimum_size().y]
	out["custom_minimum_size"] = [c.custom_minimum_size.x, c.custom_minimum_size.y]
	out["grow"] = {"h": ["begin", "end", "both"][c.grow_horizontal], "v": ["begin", "end", "both"][c.grow_vertical]}
	out["stretch_ratio"] = c.size_flags_stretch_ratio
	out["visible"] = c.visible
	out["visible_in_tree"] = c.is_visible_in_tree()
	out["mouse_filter"] = MOUSE_FILTERS[c.mouse_filter]
	out["focus_mode"] = ["none", "click", "all"][c.focus_mode] if c.focus_mode < 3 else c.focus_mode
	out["clip_contents"] = c.clip_contents
	if par:
		out["parent"] = {"path": ctx.node_path_str(par), "type": par.get_class(), "container": par is Container}
		out["positioned_by"] = "container %s (anchors/offsets are ignored)" % par.get_class() if par is Container else "anchors + offsets"
		if par is Control:
			out["parent_size"] = [par.size.x, par.size.y]
		else:
			# In the editor the edited scene is laid out against the project's viewport size.
			var vw := int(ProjectSettings.get_setting("display/window/size/viewport_width", 1152))
			var vh := int(ProjectSettings.get_setting("display/window/size/viewport_height", 648))
			out["parent_size"] = [vw, vh]
			out["parent_size_note"] = "Parent is not a Control; anchors are relative to the viewport (in the editor: the project's window size)."
	if c.theme:
		out["theme"] = c.theme.resource_path if c.theme.resource_path != "" else "embedded"
	var ov := _overrides_of(c)
	if not ov.is_empty():
		out["overrides"] = ov
	if "text" in c:
		out["text"] = str(c.get("text")).substr(0, 120)
	var children := []
	for ch in c.get_children():
		if ch is Control or ch is CanvasItem:
			children.append(_child_info(ch))
	out["children"] = children
	var warns := _layout_warnings(c, false)
	if not warns.is_empty():
		out["warnings"] = warns
	return out


func _child_info(ch: Node) -> Dictionary:
	var d := {"name": str(ch.name), "type": ch.get_class()}
	if ch is Control:
		var c: Control = ch
		d["rect"] = [c.position.x, c.position.y, c.size.x, c.size.y]
		d["min_size"] = [c.get_combined_minimum_size().x, c.get_combined_minimum_size().y]
		d["size_flags"] = {"h": size_flags_names(c.size_flags_horizontal), "v": size_flags_names(c.size_flags_vertical)}
		if not (c.get_parent() is Container):
			d["preset"] = _guess_preset(c)
		if not c.visible:
			d["visible"] = false
		if c.mouse_filter != Control.MOUSE_FILTER_STOP or c is BaseButton:
			d["mouse_filter"] = MOUSE_FILTERS[c.mouse_filter]
	return d


func _guess_preset(c: Control) -> String:
	var a := [c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom]
	var table := {
		"top_left": [0, 0, 0, 0], "top_right": [1, 0, 1, 0], "bottom_left": [0, 1, 0, 1], "bottom_right": [1, 1, 1, 1],
		"center_left": [0, 0.5, 0, 0.5], "center_top": [0.5, 0, 0.5, 0], "center_right": [1, 0.5, 1, 0.5], "center_bottom": [0.5, 1, 0.5, 1],
		"center": [0.5, 0.5, 0.5, 0.5], "left_wide": [0, 0, 0, 1], "top_wide": [0, 0, 1, 0], "right_wide": [1, 0, 1, 1],
		"bottom_wide": [0, 1, 1, 1], "vcenter_wide": [0.5, 0, 0.5, 1], "hcenter_wide": [0, 0.5, 1, 0.5], "full_rect": [0, 0, 1, 1],
	}
	for k in table:
		var t: Array = table[k]
		var ok := true
		for i in 4:
			if absf(float(t[i]) - float(a[i])) > 0.001:
				ok = false
		if ok:
			return k
	return "custom"


## Common layout mistakes in a subtree.
func _layout_warnings(n: Node, recursive: bool = true, depth: int = 0) -> Array:
	var out := []
	if not n.is_inside_tree():
		return out
	if n is Control:
		var c: Control = n
		var label := ctx.node_path_str(c)
		var par := c.get_parent()
		if par is Control and not (par is Container) and (par.size.x <= 0 or par.size.y <= 0) and not (_guess_preset(c) in ["top_left", "custom"]):
			out.append("%s: uses anchor preset '%s' but its parent '%s' has zero size, so it is anchored to a point. Give the parent a size, e.g. ui.layout {path: '%s', preset: 'full_rect'}." % [label, _guess_preset(c), ctx.node_path_str(par), ctx.node_path_str(par)])
		if n is TextureRect and n.texture == null:
			out.append("%s: TextureRect has no texture." % label)
		if n is Label and n.autowrap_mode != TextServer.AUTOWRAP_OFF and par is Container and c.custom_minimum_size.x <= 0 and not (c.size_flags_horizontal & Control.SIZE_EXPAND):
			out.append("%s: wrapped Label in a container needs custom_minimum_size.x or size_flags 'expand_fill', otherwise it collapses to zero width." % label)
		if par is ScrollContainer and par.get_child_count() > 1:
			out.append("%s: ScrollContainer should have exactly one child (put a VBoxContainer inside)." % label)
		if n is ScrollContainer and n.get_child_count() == 1:
			var inner = n.get_child(0)
			if inner is Control and not (inner.size_flags_horizontal & Control.SIZE_EXPAND):
				out.append("%s: the ScrollContainer's child should use size_flags_horizontal 'expand_fill' to fill the width." % label)
		if par is Control and not (par is Container) and c.mouse_filter == Control.MOUSE_FILTER_STOP and not (c is BaseButton) and _guess_preset(c) == "full_rect" and c.get_class() in ["Control", "ColorRect", "Panel", "TextureRect", "CenterContainer", "MarginContainer"]:
			for i in c.get_index():
				var sib = par.get_child(i)
				if sib is Control and sib.visible and _has_button(sib):
					out.append("%s: full-rect %s with mouse_filter 'stop' is drawn above earlier siblings with buttons and will block their clicks; set mouse_filter to 'ignore' or 'pass'." % [label, c.get_class()])
					break
	if recursive and depth < 8:
		for ch in n.get_children():
			out.append_array(_layout_warnings(ch, true, depth + 1))
	return out


func _has_button(n: Node) -> bool:
	if n is BaseButton:
		return true
	for ch in n.get_children():
		if _has_button(ch):
			return true
	return false
