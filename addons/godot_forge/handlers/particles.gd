@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Particles: GPU/CPU 2D/3D emitters from ready-made presets (fire, smoke, sparks...) and edits of
## the process material with friendly values (gradients as color lists, curves as point lists, [min, max] ranges).

const TYPES := {"gpu_2d": "GPUParticles2D", "cpu_2d": "CPUParticles2D", "gpu_3d": "GPUParticles3D", "cpu_3d": "CPUParticles3D"}
const PARTICLE_CLASSES := ["GPUParticles2D", "CPUParticles2D", "GPUParticles3D", "CPUParticles3D"]
## Generated textures are this many pixels wide; in 2D a scale of 1.0 draws a 64px particle.
const TEX_SIZE := 64.0
## Presets are written in 2D units (pixels, y down); 3D versions are scaled by this and flipped.
const TO_3D := 0.01
const NODE_KEYS := ["amount", "lifetime", "one_shot", "explosiveness", "preprocess", "randomness", "local_coords", "speed_scale", "fixed_fps", "emitting", "draw_order", "interpolate", "fract_delta", "amount_ratio"]

const PRESETS := {
	"fire": {
		"desc": "Looping flame: additive particles rising and shrinking, white-yellow core fading through orange to dark red.",
		"size": 28, "tex": "soft", "additive": true,
		"node": {"amount": 48, "lifetime": 0.9},
		"process": {"emission": {"shape": "sphere", "radius": 10}, "direction": [0, -1], "spread": 12, "initial_velocity": [50, 90], "gravity": [0, -60], "damping": [5, 15], "scale": [0.6, 1.1], "scale_curve": [[0, 0.5], [0.25, 1], [1, 0.1]], "color_ramp": [[0, "#fff3b0"], [0.25, "#ffb13b"], [0.6, "#e8431acc"], [1, "#40101000"]], "hue_variation": [-0.02, 0.02], "lifetime_randomness": 0.3},
	},
	"smoke": {
		"desc": "Soft grey puffs that rise, grow and fade out slowly.",
		"size": 48, "tex": "soft",
		"node": {"amount": 24, "lifetime": 2.5},
		"process": {"emission": {"shape": "sphere", "radius": 8}, "direction": [0, -1], "spread": 15, "initial_velocity": [25, 45], "gravity": [0, -15], "damping": [4, 8], "angular_velocity": [-30, 30], "angle": [0, 360], "scale": [0.5, 0.9], "scale_curve": [[0, 0.4], [1, 1.6]], "color_ramp": [[0, "#6e6e6e00"], [0.15, "#6e6e6e99"], [0.7, "#50505055"], [1, "#40404000"]], "turbulence_enabled": true, "turbulence_noise_strength": 2.0, "turbulence_influence": [0.05, 0.12], "lifetime_randomness": 0.2},
	},
	"sparks": {
		"desc": "Fast additive sparks thrown upward that fall with gravity and burn out (continuous; set one_shot for a burst).",
		"size": 6, "tex": "spark", "additive": true,
		"node": {"amount": 40, "lifetime": 0.7, "explosiveness": 0.1},
		"process": {"direction": [0, -1], "spread": 60, "initial_velocity": [150, 300], "gravity": [0, 500], "scale": [0.6, 1.0], "scale_curve": [[0, 1], [1, 0]], "color_ramp": [[0, "#ffffff"], [0.2, "#ffe070"], [0.6, "#ff8a20"], [1, "#ff300000"]], "lifetime_randomness": 0.4},
	},
	"explosion": {
		"desc": "One-shot fireball burst: bright flash expanding outward, cooling to smoke.",
		"size": 32, "tex": "soft", "additive": true,
		"node": {"amount": 64, "lifetime": 0.8, "one_shot": true, "explosiveness": 0.95},
		"process": {"emission": {"shape": "sphere", "radius": 6}, "spread": 180, "initial_velocity": [80, 260], "damping": [200, 300], "gravity": [0, -30], "scale": [0.6, 1.4], "scale_curve": [[0, 0.3], [0.2, 1], [1, 0]], "color_ramp": [[0, "#ffffff"], [0.15, "#ffd060"], [0.4, "#ff6a1a"], [0.7, "#5a2a1a88"], [1, "#20202000"]], "angle": [0, 360], "lifetime_randomness": 0.3},
	},
	"dust": {
		"desc": "Small tan puffs kicked up from the ground (footsteps, landing). Short and subtle.",
		"size": 14, "tex": "soft",
		"node": {"amount": 16, "lifetime": 1.2, "explosiveness": 0.3},
		"process": {"emission": {"shape": "box", "extents": [16, 2]}, "direction": [0, -1], "spread": 70, "initial_velocity": [15, 40], "gravity": [0, -5], "damping": [20, 30], "scale": [0.5, 1.0], "scale_curve": [[0, 0.3], [0.3, 1], [1, 0.6]], "color_ramp": [[0, "#c8b49600"], [0.2, "#c8b496aa"], [1, "#c8b49600"]]},
	},
	"rain": {
		"desc": "Screen-wide rain streaks falling fast, aligned to velocity. Place it above the view; widen emission extents to fit.",
		"size": 16, "tex": "streak",
		"node": {"amount": 200, "lifetime": 1.0, "preprocess": 1.0},
		"process": {"emission": {"shape": "box", "extents": [600, 10]}, "direction": [0.1, 1], "spread": 2, "initial_velocity": [600, 700], "gravity": [0, 300], "scale": [0.6, 1.0], "color_ramp": [[0, "#a0c4ff00"], [0.1, "#a0c4ffb0"], [1, "#a0c4ffb0"]], "particle_flag_align_y": true},
	},
	"snow": {
		"desc": "Gently falling, drifting snowflakes across a wide area.",
		"size": 8, "tex": "soft",
		"node": {"amount": 150, "lifetime": 6.0, "preprocess": 6.0},
		"process": {"emission": {"shape": "box", "extents": [600, 10]}, "direction": [0, 1], "spread": 20, "initial_velocity": [20, 40], "gravity": [0, 10], "scale": [0.4, 1.0], "color_ramp": [[0, "#ffffff00"], [0.1, "#ffffffff"], [0.9, "#ffffffee"], [1, "#ffffff00"]], "turbulence_enabled": true, "turbulence_noise_strength": 3.0, "turbulence_influence": [0.1, 0.2]},
	},
	"magic": {
		"desc": "Swirling additive purple-blue motes (spells, pickups, portals). Tint it with 'color'.",
		"size": 12, "tex": "soft", "additive": true,
		"node": {"amount": 40, "lifetime": 1.4},
		"process": {"emission": {"shape": "sphere_surface", "radius": 20}, "direction": [0, -1], "spread": 180, "initial_velocity": [10, 30], "gravity": [0, -20], "orbit_velocity": [0.2, 0.5], "scale": [0.4, 1.0], "scale_curve": [[0, 0], [0.2, 1], [1, 0]], "color_ramp": [[0, "#e0c8ff00"], [0.2, "#c080ffff"], [0.6, "#6f7dff"], [1, "#40a0ff00"]], "hue_variation": [-0.05, 0.05], "turbulence_enabled": true, "turbulence_noise_strength": 1.5, "turbulence_influence": [0.05, 0.1]},
	},
	"hit": {
		"desc": "Tiny one-shot impact burst (bullet hit, sword clash). Fast, bright, gone in a third of a second.",
		"size": 8, "tex": "spark", "additive": true,
		"node": {"amount": 14, "lifetime": 0.35, "one_shot": true, "explosiveness": 1.0},
		"process": {"spread": 180, "initial_velocity": [120, 220], "damping": [300, 400], "gravity": [0, 0], "scale": [0.6, 1.2], "scale_curve": [[0, 1], [1, 0]], "color_ramp": [[0, "#ffffff"], [0.4, "#fff0a0"], [1, "#ffa04000"]]},
	},
	"trail": {
		"desc": "Fading trail left behind a moving node (projectile, dash). Attach as a child; uses world coordinates.",
		"size": 12, "tex": "soft",
		"node": {"amount": 60, "lifetime": 0.5, "local_coords": false},
		"process": {"emission": {"shape": "sphere", "radius": 2}, "spread": 180, "initial_velocity": [0, 5], "gravity": [0, 0], "scale": [0.8, 1.0], "scale_curve": [[0, 1], [1, 0]], "color_ramp": [[0, "#ffffffcc"], [1, "#80c0ff00"]]},
	},
	"confetti": {
		"desc": "One-shot burst of multicolored spinning confetti that falls and fades (victory, celebration).",
		"size": 8, "tex": "square",
		"node": {"amount": 80, "lifetime": 3.0, "one_shot": true, "explosiveness": 0.9},
		"process": {"direction": [0, -1], "spread": 45, "initial_velocity": [250, 450], "gravity": [0, 300], "damping": [60, 100], "angular_velocity": [-720, 720], "angle": [0, 360], "scale": [0.6, 1.0], "color_initial_ramp": ["#ff4d4d", "#ffd84d", "#4dff88", "#4dc3ff", "#b84dff", "#ff4dd2"], "color_ramp": [[0, "#ffffffff"], [0.8, "#ffffffff"], [1, "#ffffff00"]], "lifetime_randomness": 0.3},
	},
	"bubbles": {
		"desc": "Hollow bubbles rising and wobbling (underwater, potions).",
		"size": 16, "tex": "ring",
		"node": {"amount": 20, "lifetime": 3.0},
		"process": {"emission": {"shape": "box", "extents": [40, 4]}, "direction": [0, -1], "spread": 10, "initial_velocity": [30, 60], "gravity": [0, -20], "scale": [0.4, 1.0], "scale_curve": [[0, 0.5], [1, 1]], "color_ramp": [[0, "#bfe8ff00"], [0.1, "#bfe8ffcc"], [0.9, "#bfe8ffaa"], [1, "#bfe8ff00"]], "turbulence_enabled": true, "turbulence_noise_strength": 2.0, "turbulence_influence": [0.05, 0.15]},
	},
}
## Used when no preset is given: a plain emitter that is at least visible.
const BASIC := {
	"desc": "Plain emitter.", "size": 16, "tex": "soft",
	"node": {"amount": 16, "lifetime": 1.0},
	"process": {"direction": [0, -1], "spread": 30, "initial_velocity": [40, 60], "gravity": [0, 98], "scale_curve": [[0, 1], [1, 0]]},
}
## ParticleProcessMaterial names that CPUParticles spell differently.
const CPU_RENAMES := {"scale_min": "scale_amount_min", "scale_max": "scale_amount_max", "scale_curve": "scale_amount_curve"}


# ---------------------------------------------------------------------------
# Friendly values
# ---------------------------------------------------------------------------

## Gradient from ["#fff", "#f00"], [[0, "#fff"], [1, "#f000"]] or {colors, offsets}.
func _gradient(v):
	if v is Gradient:
		return v
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	if v is Dictionary and v.has("colors"):
		var cs: Array = v.colors
		var os: Array = v.get("offsets", [])
		for i in cs.size():
			colors.append(U.to_color(cs[i]))
			offsets.append(float(os[i]) if i < os.size() else (float(i) / maxf(1.0, cs.size() - 1)))
	elif v is Array and not v.is_empty():
		for i in v.size():
			var item = v[i]
			if item is Array and item.size() == 2 and (item[0] is float or item[0] is int):
				offsets.append(float(item[0]))
				colors.append(U.to_color(item[1]))
			else:
				offsets.append(float(i) / maxf(1.0, v.size() - 1))
				colors.append(U.to_color(item))
	else:
		return U.err("Cannot build a gradient from %s." % JSON.stringify(v), "Use a list of colors ['#fff', '#f000'], [[offset, color], ...] or {colors, offsets}.")
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	return g


## Curve from [1, 0.5, 0] (evenly spaced), [[x, y], ...] or {points, min?, max?}.
func _curve(v):
	if v is Curve:
		return v
	var pts := []
	var src = v.get("points", []) if v is Dictionary else v
	if not (src is Array) or src.is_empty():
		return U.err("Cannot build a curve from %s." % JSON.stringify(v), "Use [y0, y1, ...] (evenly spaced over the lifetime) or [[t, y], ...] with t in 0..1.")
	for i in src.size():
		var item = src[i]
		if item is Array and item.size() >= 2:
			pts.append(Vector2(float(item[0]), float(item[1])))
		else:
			pts.append(Vector2(float(i) / maxf(1.0, src.size() - 1), float(item)))
	var c := Curve.new()
	var lo := 0.0
	var hi := 1.0
	for pt in pts:
		lo = minf(lo, pt.y)
		hi = maxf(hi, pt.y)
	c.min_value = float(v.get("min", lo)) if v is Dictionary else lo
	c.max_value = float(v.get("max", hi)) if v is Dictionary else hi
	for pt in pts:
		c.add_point(pt, 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return c


## Coerces a value for a particle property: color lists become gradients (wrapped in GradientTexture1D for
## the process material), point lists become curves (wrapped in CurveTexture), everything else via U.coerce.
func _friendly(obj: Object, key: String, value, infos: Dictionary):
	var pi: Dictionary = infos[key]
	var plain: bool = value is Array or (value is Dictionary and not value.has("type") and not value.has("path"))
	if pi.type == TYPE_OBJECT and value is String and not (value.begins_with("res://") or value.begins_with("uid://") or ClassDB.class_exists(value) or value == ""):
		var hs0: String = pi.hint_string
		if hs0.contains("Gradient") or (hs0.contains("Texture") and key.contains("color")):
			return U.err("expects a gradient, got %s." % JSON.stringify(value), "Use a list of colors ['#ffffff', '#ff000000'] or [[offset, color], ...]. For one flat color set 'color' instead.")
		if hs0.contains("Curve") or hs0.contains("Texture"):
			return U.err("expects a curve, got %s." % JSON.stringify(value), "Use [start, ..., end] values spread over the lifetime (e.g. [1, 0] to shrink) or [[t, value], ...] with t in 0..1.")
	if pi.type == TYPE_OBJECT and plain:
		var hs: String = pi.hint_string
		if hs == "Gradient":
			return _gradient(value)
		if hs == "Curve":
			return _curve(value)
		if hs.contains("Texture"):
			if key.contains("color") or hs.contains("Gradient"):
				var g = _gradient(value)
				if U.is_err(g): return g
				var gt := GradientTexture1D.new()
				gt.gradient = g
				return gt
			var c = _curve(value)
			if U.is_err(c): return c
			var ct := CurveTexture.new()
			ct.curve = c
			return ct
	return U.coerce(value, pi.type, pi.hint, pi.hint_string)


func _set_one(obj: Object, key: String, value, infos: Dictionary, touched: Array):
	var v = _friendly(obj, key, value, infos)
	if U.is_err(v):
		v["message"] = "%s: %s" % [key, v.message]
		return v
	obj.set(key, v)
	touched.append(key)
	return null


## Expands {"shape": "sphere", "radius": 10} into emission_* properties.
func _emission(obj: Object, spec, infos: Dictionary, touched: Array):
	if spec is String:
		spec = {"shape": spec}
	if not (spec is Dictionary):
		return U.err("'emission' must be {shape: point|sphere|sphere_surface|box|ring, radius?, extents?, inner_radius?, height?, axis?}.")
	var shape := U.p_str(spec, "shape", "point").to_lower()
	var is_cpu2d := obj is CPUParticles2D
	var shapes := {"point": 0, "sphere": 1, "circle": 1, "sphere_surface": 2, "circle_edge": 2, "box": 3, "rect": 3, "rectangle": 3, "points": 4, "directed_points": 5, "ring": 6}
	if not shapes.has(shape):
		return U.err("Unknown emission shape '%s'." % shape, "Valid: point, sphere, sphere_surface, box, ring (points/directed_points need emission textures).")
	obj.set("emission_shape", shapes[shape])
	touched.append("emission_shape")
	var map := {"radius": "emission_sphere_radius", "extents": "emission_rect_extents" if is_cpu2d else "emission_box_extents", "size": "emission_rect_extents" if is_cpu2d else "emission_box_extents", "offset": "emission_shape_offset", "scale": "emission_shape_scale", "inner_radius": "emission_ring_inner_radius", "height": "emission_ring_height", "axis": "emission_ring_axis", "cone_angle": "emission_ring_cone_angle"}
	if shape == "ring":
		map["radius"] = "emission_ring_radius"
		# In 3D a ring lies flat on the ground (axis Y) unless an axis is given; in 2D it faces the screen (axis Z).
		var is_3d: bool = obj is CPUParticles3D or (obj is ParticleProcessMaterial and not obj.particle_flag_disable_z)
		if not spec.has("axis") and infos.has("emission_ring_axis"):
			obj.set("emission_ring_axis", Vector3(0, 1, 0) if is_3d else Vector3(0, 0, 1))
			touched.append("emission_ring_axis")
	for k in spec:
		if k == "shape":
			continue
		if not map.has(k):
			return U.err("Unknown emission option '%s'." % k, "Options: %s" % ", ".join(map.keys()))
		var prop: String = map[k]
		if not infos.has(prop):
			continue  # e.g. ring height on 2D CPU particles
		var r = _set_one(obj, prop, spec[k], infos, touched)
		if r: return r
	return null


## Applies process-material style properties with friendly values to a ParticleProcessMaterial or
## a CPUParticles node. Supports "initial_velocity": [min, max] ranges and "emission": {...}.
## Returns the list of touched property names or an error.
func _apply_process(obj: Object, process: Dictionary) -> Variant:
	var infos := U.prop_infos(obj)
	var touched := []
	var is_cpu := obj is CPUParticles2D or obj is CPUParticles3D
	for key in process:
		var k := str(key)
		var val = process[key]
		if k == "emission":
			var er = _emission(obj, val, infos, touched)
			if er: return er
			continue
		if is_cpu:
			if CPU_RENAMES.has(k):
				k = CPU_RENAMES[k]
			elif k == "scale" and not infos.has("scale_min"):
				k = "scale_amount"
			elif k == "emission_box_extents" and obj is CPUParticles2D:
				k = "emission_rect_extents"
			elif k.begins_with("turbulence") or k in ["collision_mode", "sub_emitter_mode", "attractor_interaction_enabled"]:
				continue  # GPU-only features; CPU particles ignore them
		if infos.has(k) and not (infos.has(k + "_min") and (val is Array)):
			var r = _set_one(obj, k, val, infos, touched)
			if r: return r
		elif infos.has(k + "_min") and infos.has(k + "_max"):
			var lo = val
			var hi = val
			if val is Array:
				if val.size() != 2:
					return U.err("%s: a range is [min, max], got %s." % [k, JSON.stringify(val)])
				lo = val[0]
				hi = val[1]
			var r1 = _set_one(obj, k + "_min", lo, infos, touched)
			if r1: return r1
			var r2 = _set_one(obj, k + "_max", hi, infos, touched)
			if r2: return r2
		else:
			var names := []
			for n in infos.keys():
				if infos[n].usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
					continue
				names.append(str(n).trim_suffix("_min").trim_suffix("_max"))
			var s := U.suggest(k, names)
			return U.err("%s has no property '%s'." % [obj.get_class(), k], ("Did you mean '%s'? " % s if s != "" else "") + "Ranges can be given as '<name>': [min, max] (e.g. initial_velocity, scale, angle). Use introspect.class %s for the full list." % obj.get_class())
	return touched


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

func _texture(kind: String) -> Texture2D:
	var g := Gradient.new()
	var t := GradientTexture2D.new()
	t.width = int(TEX_SIZE)
	t.height = int(TEX_SIZE)
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	var w := Color(1, 1, 1, 1)
	match kind:
		"spark":
			g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
			g.colors = PackedColorArray([w, Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
		"square":
			t.width = 16
			t.height = 16
			t.fill = GradientTexture2D.FILL_LINEAR
			g.offsets = PackedFloat32Array([0.0, 1.0])
			g.colors = PackedColorArray([w, w])
		"streak":
			t.width = 8
			t.fill = GradientTexture2D.FILL_LINEAR
			t.fill_from = Vector2(0.5, 0.0)
			t.fill_to = Vector2(0.5, 1.0)
			g.offsets = PackedFloat32Array([0.0, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 0), w])
		"ring":
			g.offsets = PackedFloat32Array([0.0, 0.6, 0.82, 0.92, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.15), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
		_:
			g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
			g.colors = PackedColorArray([w, Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	t.gradient = g
	return t


func _scale_num(v, f: float):
	if v is Array:
		return v.map(func(x): return float(x) * f)
	return float(v) * f


## Converts a 2D preset (pixels, y down) to 3D (meters, y up).
func _to_3d(process: Dictionary) -> Dictionary:
	var out := process.duplicate(true)
	for k in ["direction", "gravity"]:
		if out.has(k):
			var v: Array = out[k]
			var f := TO_3D if k == "gravity" else 1.0
			out[k] = [float(v[0]) * f, -float(v[1]) * f, 0.0]
	for k in ["initial_velocity", "linear_accel", "radial_accel", "tangential_accel", "damping"]:
		if out.has(k):
			out[k] = _scale_num(out[k], TO_3D)
	if out.has("emission"):
		var em: Dictionary = out.emission
		for k in ["radius", "inner_radius", "height"]:
			if em.has(k):
				em[k] = float(em[k]) * TO_3D
		if em.has("extents"):
			var ex: Array = em.extents
			em["extents"] = [float(ex[0]) * TO_3D, float(ex[1]) * TO_3D, float(ex[0]) * TO_3D]
		if em.get("shape", "") == "ring":
			em["axis"] = [0, 1, 0]
	out.erase("orbit_velocity")
	return out


## Recolors a gradient toward `tint`: every stop takes the tint's hue, keeps its relative saturation
## (a white-hot core stays pale) and its brightness and alpha (dark smoky ends stay dark).
func _tint_gradient(g: Gradient, tint: Color) -> Gradient:
	var ng: Gradient = g.duplicate()
	var cols := ng.colors
	var max_s := 0.0
	for c: Color in cols:
		max_s = maxf(max_s, c.s)
	for i in cols.size():
		var c: Color = cols[i]
		var rel := c.s / max_s if max_s > 0.05 else 1.0
		var nc := Color.from_hsv(tint.h, tint.s * rel, c.v * tint.v)
		nc.a = c.a * tint.a
		cols[i] = nc
	ng.colors = cols
	return ng


func _parse_type(p: Dictionary, parent: Node):
	var t := U.p_str(p, "type", "").to_lower().replace("particles", "").replace("-", "_")
	var is3d := _is_3d(parent)
	match t:
		"":
			return "gpu_3d" if is3d else "gpu_2d"
		"gpu", "cpu":
			return t + ("_3d" if is3d else "_2d")
		"2d", "3d":
			return "gpu_" + t
		"gpu2d", "cpu2d", "gpu3d", "cpu3d":
			return t.substr(0, 3) + "_" + t.substr(3)
	if TYPES.has(t):
		return t
	return U.err("Unknown particles type '%s'." % U.p_str(p, "type"), "Use gpu_2d, cpu_2d, gpu_3d or cpu_3d (default: gpu, 2D/3D from the parent).")


func _is_3d(n: Node) -> bool:
	while n:
		if n is Node3D:
			return true
		if n is CanvasItem:
			return false
		n = n.get_parent()
	return false


## Builds a detached particles node. Returns the node or an error.
func _build(type: String, preset_name: String, p: Dictionary, warnings: Array):
	var is_2d := type.ends_with("2d")
	var is_cpu := type.begins_with("cpu")
	var pr: Dictionary = PRESETS.get(preset_name, BASIC)
	var size := float(pr.size)
	var process: Dictionary = (pr.process as Dictionary).duplicate(true)
	# Texture / mesh.
	var tex: Texture2D = null
	var tex_arg := U.p_str(p, "texture", "")
	if tex_arg != "" and tex_arg in ["soft", "spark", "square", "streak", "ring"]:
		tex = _texture(tex_arg)
	elif tex_arg != "":
		var rp := U.res_path(tex_arg)
		if not ResourceLoader.exists(rp):
			return U.err("Texture '%s' not found." % rp, "Pass a res:// image, or one of: soft, spark, square, streak, ring.")
		var loaded = load(rp)
		if not (loaded is Texture2D):
			return U.err("'%s' is not a texture." % rp)
		tex = loaded
	else:
		tex = _texture(str(pr.tex))
	# In 2D, preset sizes are pixels: scale relative to the texture actually used.
	var tex_px := maxf(1.0, maxf(tex.get_width(), tex.get_height()))
	if is_2d:
		if p.has("size"):
			size = U.p_float(p, "size")
		if process.has("scale"):
			process["scale"] = _scale_num(process.scale, size / tex_px)
		else:
			process["scale"] = size / tex_px
	else:
		process = _to_3d(process)
		size = U.p_float(p, "size", size * TO_3D)
	var mat := ParticleProcessMaterial.new()
	if is_2d:
		mat.particle_flag_disable_z = true
	var r = _apply_process(mat, process)
	if U.is_err(r):
		r["message"] = "Preset '%s': %s" % [preset_name, r.message]
		return r
	r = _apply_process(mat, U.p_dict(p, "process"))
	if U.is_err(r): return r
	if p.has("color"):
		var tint := U.to_color(p.color)
		if mat.color_ramp is GradientTexture1D and mat.color_ramp.gradient:
			var gt := GradientTexture1D.new()
			gt.gradient = _tint_gradient(mat.color_ramp.gradient, tint)
			mat.color_ramp = gt
		else:
			mat.color = tint
	var additive: bool = U.p_bool(p, "additive", pr.get("additive", false))
	var gpu: Node = GPUParticles2D.new() if is_2d else GPUParticles3D.new()
	gpu.process_material = mat
	for k in pr.node:
		gpu.set(k, pr.node[k])
	if is_2d:
		gpu.texture = tex
		if additive:
			var cim := CanvasItemMaterial.new()
			cim.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			gpu.material = cim
	else:
		var quad := QuadMesh.new()
		var streak := str(pr.tex) == "streak" and tex_arg == ""
		quad.size = Vector2(size * 0.25, size) if streak else Vector2(size, size)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.vertex_color_use_as_albedo = true
		sm.albedo_texture = tex
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if streak else BaseMaterial3D.BILLBOARD_PARTICLES
		if additive:
			sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		quad.material = sm
		gpu.draw_pass_1 = quad
	# Shortcuts.
	for k in ["amount", "lifetime", "one_shot", "explosiveness", "preprocess", "local_coords", "emitting", "speed_scale"]:
		if p.has(k):
			var cr = U.set_prop(gpu, k, p[k])
			if U.is_err(cr): return cr
	_fit_bounds(gpu, is_2d)
	var n: Node = gpu
	if is_cpu:
		n = CPUParticles2D.new() if is_2d else CPUParticles3D.new()
		n.convert_from_particles(gpu)
		_copy_ring(mat, n)
		n.set("fixed_fps", 0)  # GPU default is 30 with interpolation; CPU particles would stutter
		n.set("emitting", gpu.emitting)
		if is_2d:
			n.texture = tex
			n.material = gpu.material
		else:
			n.mesh = gpu.draw_pass_1
		if mat.turbulence_enabled:
			warnings.append("CPU particles don't support turbulence; the preset's drifting motion is simplified.")
		gpu.free()
	var props := U.p_dict(p, "props")
	if not props.is_empty():
		var infos := U.prop_infos(n)
		for k in props:
			if not infos.has(str(k)):
				var s := U.suggest(str(k), infos.keys())
				var cls := n.get_class()
				n.free()
				return U.err("%s has no property '%s'." % [cls, k], ("Did you mean '%s'? " % s if s != "" else "") + "Process material settings go in 'process'.")
			var pr2 = _set_one(n, str(k), props[k], infos, [])
			if pr2:
				n.free()
				return pr2
	return n


## Sets visibility_rect / visibility_aabb from how far particles can travel, so they aren't culled.
func _fit_bounds(gpu: Node, is_2d: bool) -> void:
	var b = _bounds_for(gpu, is_2d)
	if b != null:
		gpu.set("visibility_rect" if is_2d else "visibility_aabb", b)


## [property, value] for visibility bounds that fit the particles' reach, or null.
func _bounds_for(gpu: Node, is_2d: bool) -> Variant:
	var mat = gpu.process_material
	if not (mat is ParticleProcessMaterial):
		return null
	var life: float = gpu.lifetime
	var reach: float = mat.initial_velocity_max * life + 0.5 * mat.gravity.length() * life * life
	var ext := maxf(mat.emission_sphere_radius, maxf(mat.emission_ring_radius, maxf(mat.emission_box_extents.x, mat.emission_box_extents.y)))
	var r: float = reach + ext + (mat.scale_max * TEX_SIZE if is_2d else mat.scale_max)
	if is_2d:
		r = maxf(r, 100.0)
		return Rect2(-r, -r, r * 2, r * 2)
	r = maxf(r, 4.0)
	return AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2)


## convert_from_particles() doesn't carry the ring emission settings over; copy them.
func _copy_ring(src: Object, dst: Object) -> void:
	if src == null or dst == null:
		return
	var dst_infos := U.prop_infos(dst)
	for k in ["emission_ring_axis", "emission_ring_height", "emission_ring_radius", "emission_ring_inner_radius", "emission_ring_cone_angle"]:
		if k in src and dst_infos.has(k):
			dst.set(k, src.get(k))


func _summary(n: Node) -> Dictionary:
	var d := {"path": ctx.node_path_str(n), "type": n.get_class(), "amount": n.amount, "lifetime": snappedf(n.lifetime, 0.0001), "one_shot": n.one_shot, "emitting": n.emitting, "explosiveness": snappedf(n.explosiveness, 0.0001)}
	if n is GPUParticles2D or n is GPUParticles3D:
		var m = n.process_material
		d["process"] = _friendly_props(m) if m else null
		if n is GPUParticles2D:
			d["visibility_rect"] = var_to_str(n.visibility_rect)
	else:
		var skip := ["amount", "lifetime", "one_shot", "emitting", "explosiveness"]
		var own := {}
		var cp := _friendly_props(n)
		for pi in ClassDB.class_get_property_list(n.get_class(), true):
			if cp.has(pi.name) and not (pi.name in skip):
				own[pi.name] = cp[pi.name]
		d["process"] = own
	return d


## Changed properties, with gradients/curves shown as readable point lists.
func _friendly_props(obj: Object) -> Dictionary:
	var out := U.changed_props(obj)
	for k in out.keys():
		if out[k] is float:
			out[k] = snappedf(out[k], 0.0001)
	out.erase("resource_path")
	out.erase("resource_name")
	for k in out.keys():
		for suf in ["_min", "_max"]:
			if str(k).ends_with(suf) and out.has(str(k).trim_suffix(suf)) and typeof(obj.get(str(k).trim_suffix(suf))) == TYPE_VECTOR2:
				out.erase(k)
	for k in out.keys():
		var v = obj.get(k)
		var g: Gradient = null
		var c: Curve = null
		if v is GradientTexture1D: g = v.gradient
		elif v is Gradient: g = v
		elif v is CurveTexture: c = v.curve
		elif v is Curve: c = v
		if g:
			var pts := []
			for i in g.get_point_count():
				pts.append([snappedf(g.get_offset(i), 0.001), "#" + g.get_color(i).to_html(g.get_color(i).a < 1.0)])
			out[k] = {"gradient": pts}
		elif c:
			var cps := []
			for i in c.point_count:
				var pp := c.get_point_position(i)
				cps.append([snappedf(pp.x, 0.001), snappedf(pp.y, 0.001)])
			out[k] = {"curve": cps}
	return out


func _particles_arg(p: Dictionary):
	var n = await node_arg(p)
	if U.is_err(n): return n
	if not (n.get_class() in PARTICLE_CLASSES):
		var kids := []
		for c in n.get_children():
			if c.get_class() in PARTICLE_CLASSES:
				kids.append(c)
		if kids.size() == 1:
			return kids[0]
		return U.err("'%s' is a %s, not a particles node." % [U.p_str(p, "path"), n.get_class()], "Pass the path of a GPUParticles2D/3D or CPUParticles2D/3D node, or create one with particles.create.")
	return n


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func a_presets(_p: Dictionary):
	var out := {}
	for k in PRESETS:
		var pr: Dictionary = PRESETS[k]
		out[k] = {"desc": pr.desc, "amount": pr.node.get("amount"), "lifetime": pr.node.get("lifetime"), "one_shot": pr.node.get("one_shot", false), "additive": pr.get("additive", false)}
	return {"presets": out, "note": "Presets are tuned for 2D in pixels (sizes ~8-48px); in 3D they are converted to meters (1px = 0.01m). Override anything with 'process', 'props', 'color', 'size', 'amount', 'lifetime'."}


## Adds a particles node built from a preset (or a plain emitter) plus overrides.
func a_create(p: Dictionary):
	if p.has("scene") and str(p.scene) != "":
		var r = await ensure_scene(str(p.scene))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var parent: Node = ctx.find_node(U.p_str(p, "parent", "."))
	if parent == null:
		return ctx.node_not_found(U.p_str(p, "parent"))
	var type = _parse_type(p, parent)
	if U.is_err(type): return type
	var preset := U.p_str(p, "preset", "").to_lower()
	if preset != "" and not PRESETS.has(preset):
		var s := U.suggest(preset, PRESETS.keys())
		return U.err("Unknown particles preset '%s'." % preset, ("Did you mean '%s'? " % s if s != "" else "") + "Presets: %s" % ", ".join(PRESETS.keys()))
	var warnings := []
	var n = _build(type, preset, p, warnings)
	if U.is_err(n): return n
	n.name = U.p_str(p, "name", (preset.to_pascal_case() + "Particles") if preset != "" else TYPES[type])
	if p.has("position"):
		var pv = p.position
		var ok: bool = typeof(pv) in [TYPE_VECTOR2, TYPE_VECTOR3] or (pv is Array and pv.size() >= 2 and pv.all(func(x): return x is float or x is int)) or (pv is Dictionary and pv.has("x")) or (pv is String and pv.begins_with("Vector"))
		if not ok:
			n.free()
			return U.err("Cannot read position %s." % JSON.stringify(pv), "Use [x, y] in 2D or [x, y, z] in 3D.")
		n.set("position", U.to_vector(pv, TYPE_VECTOR2 if type.ends_with("2d") else TYPE_VECTOR3))
	var u = ctx.begin("Add %s particles" % (preset if preset != "" else type))
	u.add_do_method(parent, "add_child", n, true)
	u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", n, root)
	u.add_do_reference(n)
	u.add_undo_method(parent, "remove_child", n)
	ctx.commit()
	var out := _summary(n)
	if preset != "":
		out["preset"] = preset
	if n.one_shot and n.emitting:
		out["note"] = "One-shot: it fires once when the scene starts. In game code call restart() to fire it again (set emitting=false to only fire from code)."
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


## Edits a particles node: process material values, node props, re-applying a preset, tint.
func a_set(p: Dictionary):
	var n = await _particles_arg(p)
	if U.is_err(n): return n
	var is_gpu := n is GPUParticles2D or n is GPUParticles3D
	var plan := []  # [object, property, new value]
	var warnings := []
	if p.has("preset"):
		var preset := U.p_str(p, "preset").to_lower()
		if not PRESETS.has(preset):
			var s := U.suggest(preset, PRESETS.keys())
			return U.err("Unknown particles preset '%s'." % preset, ("Did you mean '%s'? " % s if s != "" else "") + "Presets: %s" % ", ".join(PRESETS.keys()))
		var type: String = TYPES.find_key(n.get_class())
		var q := p.duplicate()
		q.erase("props")
		var fresh = _build(type, preset, q, warnings)
		if U.is_err(fresh): return fresh
		var props_list := ClassDB.class_get_property_list(n.get_class(), true)
		for pi in props_list:
			if pi.usage & PROPERTY_USAGE_STORAGE and not (pi.name in ["emitting", "sub_emitter"]):
				plan.append([n, pi.name, fresh.get(pi.name)])
		if n is CanvasItem:
			plan.append([n, "material", fresh.material])
		fresh.free()
	else:
		var process := U.p_dict(p, "process")
		if is_gpu and (not process.is_empty() or p.has("color")):
			var old = n.process_material
			var mat: ParticleProcessMaterial = old.duplicate(true) if old is ParticleProcessMaterial else ParticleProcessMaterial.new()
			if not (old is ParticleProcessMaterial) and n is GPUParticles2D:
				mat.particle_flag_disable_z = true
			var r = _apply_process(mat, process)
			if U.is_err(r): return r
			if p.has("color"):
				_tint_into(mat, U.to_color(p.color))
			plan.append([n, "process_material", mat])
		elif not is_gpu and (not process.is_empty() or p.has("color")):
			var tmp: Node = n.duplicate(0)
			var r2 = _apply_process(tmp, process)
			if U.is_err(r2):
				tmp.free()
				return r2
			if p.has("color"):
				_tint_into(tmp, U.to_color(p.color))
				r2.append("color_ramp")
				r2.append("color")
			for k in r2:
				plan.append([n, k, tmp.get(k)])
			tmp.free()
	var props := U.p_dict(p, "props")
	for k in ["amount", "lifetime", "one_shot", "explosiveness", "preprocess", "local_coords", "emitting", "speed_scale"]:
		if p.has(k):
			props[k] = p[k]
	if not props.is_empty():
		var tmp2: Node = n.duplicate(0)
		var infos := U.prop_infos(tmp2)
		for k in props:
			if not infos.has(str(k)):
				var s2 := U.suggest(str(k), infos.keys())
				tmp2.free()
				return U.err("%s has no property '%s'." % [n.get_class(), k], ("Did you mean '%s'? " % s2 if s2 != "" else "") + "Process material settings go in 'process'.")
			var e = _set_one(tmp2, str(k), props[k], infos, [])
			if e:
				tmp2.free()
				return e
			plan.append([n, str(k), tmp2.get(str(k))])
		tmp2.free()
	if plan.is_empty():
		return U.err("Nothing to change.", "Pass 'process' (material values), 'props' (node values), 'preset', 'color', or shortcuts like amount/lifetime/one_shot.")
	# Grow the visibility bounds (part of the same undo step) when the new settings reach further.
	if is_gpu and not p.has("preset"):
		var bprop := "visibility_rect" if n is GPUParticles2D else "visibility_aabb"
		var touched_bounds := plan.any(func(it): return it[1] == bprop)
		if not touched_bounds:
			var probe: Node = n.duplicate(0)
			for item in plan:
				probe.set(item[1], item[2])
			var b = _bounds_for(probe, n is GPUParticles2D)
			probe.free()
			var cur = n.get(bprop)
			if b != null and not cur.encloses(b):
				plan.append([n, bprop, cur.merge(b)])
	var u = ctx.begin("Edit particles")
	for item in plan:
		u.add_do_property(item[0], item[1], item[2])
		u.add_undo_property(item[0], item[1], item[0].get(item[1]))
	ctx.commit()
	var out := _summary(n)
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


func _tint_into(obj: Object, tint: Color) -> void:
	var ramp = obj.get("color_ramp")
	if ramp is GradientTexture1D and ramp.gradient:
		var gt := GradientTexture1D.new()
		gt.gradient = _tint_gradient(ramp.gradient, tint)
		obj.set("color_ramp", gt)
	elif ramp is Gradient:
		obj.set("color_ramp", _tint_gradient(ramp, tint))
	else:
		obj.set("color", tint)


## Reads a particles node with its process settings in friendly form.
func a_get(p: Dictionary):
	var n = await _particles_arg(p)
	if U.is_err(n): return n
	return _summary(n)


## Restarts emission (previews one-shot effects in the editor).
func a_restart(p: Dictionary):
	var n = await _particles_arg(p)
	if U.is_err(n): return n
	n.restart()
	if not n.emitting:
		n.emitting = true
	return {"path": ctx.node_path_str(n), "emitting": n.emitting, "one_shot": n.one_shot}


## Converts GPU particles to CPU particles or back (keeps name, transform and settings).
func a_convert(p: Dictionary):
	var e = U.require(p, ["to"])
	if e: return e
	var n = await _particles_arg(p)
	if U.is_err(n): return n
	var to := U.p_str(p, "to").to_lower()
	if not (to in ["cpu", "gpu"]):
		return U.err("'to' must be 'cpu' or 'gpu'.", "GPU particles are faster and support turbulence/collisions; CPU particles work on every renderer and are easier to debug.")
	var is_2d: bool = n is GPUParticles2D or n is CPUParticles2D
	var is_gpu: bool = n is GPUParticles2D or n is GPUParticles3D
	if (to == "gpu") == is_gpu:
		return U.err("'%s' is already %s particles." % [ctx.node_path_str(n), to.to_upper()], "Use particles.set to change its settings.")
	var nn: Node
	if to == "cpu":
		nn = CPUParticles2D.new() if is_2d else CPUParticles3D.new()
	else:
		nn = GPUParticles2D.new() if is_2d else GPUParticles3D.new()
	nn.convert_from_particles(n)
	if to == "cpu":
		_copy_ring(n.process_material, nn)
		nn.set("fixed_fps", 0)
	else:
		_copy_ring(n, nn.process_material)
	if is_2d:
		nn.texture = n.texture
	elif to == "cpu":
		nn.mesh = n.draw_pass_1
	else:
		nn.draw_pass_1 = n.mesh
	for base in (["CanvasItem", "Node2D"] if is_2d else ["Node3D", "GeometryInstance3D"]):
		for pi in ClassDB.class_get_property_list(base, true):
			if pi.usage & PROPERTY_USAGE_STORAGE and pi.name in U.prop_infos(nn):
				nn.set(pi.name, n.get(pi.name))
	nn.set("emitting", n.emitting)
	nn.name = n.name
	if to == "gpu" and nn.process_material is ParticleProcessMaterial and is_2d:
		nn.process_material.particle_flag_disable_z = true
	if to == "gpu":
		_fit_bounds(nn, is_2d)
	var root: Node = ctx.edited_root()
	var u = ctx.begin("Convert particles to " + to.to_upper())
	u.add_do_method(n, "replace_by", nn, true)
	u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", nn, root)
	u.add_undo_method(nn, "replace_by", n, true)
	u.add_undo_method(ctx.router.handlers["node"], "set_owner_rec", n, root)
	u.add_do_reference(nn)
	u.add_undo_reference(n)
	ctx.commit()
	var out := _summary(nn)
	if to == "cpu" and n.process_material is ParticleProcessMaterial and n.process_material.turbulence_enabled:
		out["warnings"] = ["Turbulence isn't supported by CPU particles and was dropped."]
	return out
