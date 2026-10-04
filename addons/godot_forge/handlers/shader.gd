@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Shaders (.gdshader): create from templates, compile-check, read/edit, list uniforms,
## ShaderMaterial files and shader parameters on nodes.

const TYPES := ["canvas_item", "spatial", "particles", "sky", "fog"]

const NOISE_FN := """
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}
"""

const TEMPLATES := {
	"canvas_item": {
		"blank": """shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0);

void vertex() {
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * tint;
}
""",
		"dissolve": """shader_type canvas_item;
// Dissolve: animate 'progress' 0 -> 1 to burn the sprite away.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale = 12.0;
uniform float edge_width : hint_range(0.0, 0.3) = 0.06;
uniform vec4 edge_color : source_color = vec4(1.0, 0.55, 0.1, 1.0);
{NOISE}
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float n = value_noise(UV * noise_scale);
	float keep = step(progress, n);
	float edge = step(progress, n + edge_width) - keep;
	COLOR = mix(base, edge_color, edge);
	COLOR.a = base.a * max(keep, edge) * (progress >= 1.0 ? 0.0 : 1.0);
}
""",
		"outline": """shader_type canvas_item;
// Sprite outline. Leave transparent padding around the sprite so the outline fits.

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float width : hint_range(0.0, 16.0) = 1.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * width;
	float a = 0.0;
	a = max(a, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	a = max(a, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	a = max(a, texture(TEXTURE, UV + px).a);
	a = max(a, texture(TEXTURE, UV - px).a);
	a = max(a, texture(TEXTURE, UV + vec2(px.x, -px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(-px.x, px.y)).a);
	vec4 outline = vec4(outline_color.rgb, a * outline_color.a);
	COLOR = mix(outline, col, col.a);
}
""",
		"flash": """shader_type canvas_item;
// Hit flash: tween 'flash_amount' 1 -> 0 when the object takes damage.

uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	COLOR = vec4(mix(col.rgb, flash_color.rgb, flash_amount), col.a);
}
""",
		"water": """shader_type canvas_item;
// 2D water: distorts what is behind it and tints it. Put on a ColorRect/Sprite2D over the scene.

uniform vec4 water_color : source_color = vec4(0.15, 0.45, 0.75, 0.45);
uniform float wave_strength = 0.008;
uniform float wave_frequency = 30.0;
uniform float wave_speed = 2.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 offset = vec2(sin(UV.y * wave_frequency + TIME * wave_speed), cos(UV.x * wave_frequency + TIME * wave_speed * 0.8)) * wave_strength;
	vec3 behind = texture(screen_texture, SCREEN_UV + offset).rgb;
	float shine = pow(max(sin((UV.x + UV.y) * wave_frequency * 0.5 + TIME * wave_speed), 0.0), 16.0) * 0.15;
	COLOR = vec4(mix(behind, water_color.rgb, water_color.a) + shine, 1.0);
}
""",
		"toon": """shader_type canvas_item;
// Posterize: reduces colors to a few bands for a flat/toon look.

uniform int bands : hint_range(2, 16) = 4;
uniform float saturation : hint_range(0.0, 2.0) = 1.1;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float gray = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	vec3 c = mix(vec3(gray), col.rgb, saturation);
	c = floor(c * float(bands) + 0.5) / float(bands);
	COLOR = vec4(c, col.a);
}
""",
		"hologram": """shader_type canvas_item;

uniform vec4 holo_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform float line_density = 120.0;
uniform float scroll_speed = 1.5;
uniform float flicker : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float lines = 0.6 + 0.4 * sin((UV.y + TIME * scroll_speed * 0.1) * line_density);
	float f = 1.0 - flicker * step(0.97, fract(sin(floor(TIME * 20.0) * 12.9898) * 43758.5453));
	float lum = dot(col.rgb, vec3(0.333));
	COLOR = vec4(holo_color.rgb * (0.4 + lum), col.a * lines * f * holo_color.a);
}
""",
		"pixelate": """shader_type canvas_item;

uniform float pixel_size : hint_range(1.0, 64.0) = 4.0;

void fragment() {
	vec2 cell = TEXTURE_PIXEL_SIZE * pixel_size;
	vec2 uv = floor(UV / cell) * cell + cell * 0.5;
	COLOR = texture(TEXTURE, uv);
}
""",
		"wave": """shader_type canvas_item;
// Sways the top of the sprite (grass, flags, plants). Bottom stays anchored.

uniform float amplitude = 6.0;
uniform float frequency = 2.0;
uniform float speed = 2.0;

void vertex() {
	float weight = 1.0 - UV.y;
	VERTEX.x += sin(TIME * speed + VERTEX.y * 0.05 * frequency) * amplitude * weight;
}

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
""",
		"scroll": """shader_type canvas_item;
// Scrolling texture (parallax clouds, conveyor belts, water surfaces).

uniform vec2 scroll_speed = vec2(0.1, 0.0);

void fragment() {
	COLOR = texture(TEXTURE, fract(UV + TIME * scroll_speed));
}
""",
		"vignette": """shader_type canvas_item;
// Full-screen vignette: put on a ColorRect covering the screen (in a CanvasLayer).

uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float radius : hint_range(0.0, 1.0) = 0.55;
uniform float softness : hint_range(0.01, 1.0) = 0.45;

void fragment() {
	float d = distance(UV, vec2(0.5)) * 1.41421;
	float v = smoothstep(radius, radius + softness, d) * intensity;
	COLOR = vec4(vignette_color.rgb, clamp(v, 0.0, 1.0) * vignette_color.a);
}
""",
	},
	"spatial": {
		"blank": """shader_type spatial;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

void vertex() {
}

void fragment() {
	ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
""",
		"dissolve": """shader_type spatial;
// Dissolve: animate 'progress' 0 -> 1. Glowing edge via emission.

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale = 8.0;
uniform float edge_width : hint_range(0.0, 0.3) = 0.05;
uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform float edge_energy = 4.0;
{NOISE}
void fragment() {
	float n = value_noise(UV * noise_scale);
	if (n < progress) {
		discard;
	}
	float edge = 1.0 - step(progress + edge_width, n);
	ALBEDO = mix(albedo.rgb, edge_color.rgb, edge);
	EMISSION = edge_color.rgb * edge * edge_energy;
}
""",
		"outline": """shader_type spatial;
// Inverted-hull outline. Goes in the object's material_overlay (or a material's next_pass); shader.create does this with assign_to.
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width = 0.03;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
""",
		"flash": """shader_type spatial;
// Hit flash: tween 'flash_amount' 1 -> 0 when hit.

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 base = albedo.rgb * texture(albedo_texture, UV).rgb;
	ALBEDO = mix(base, flash_color.rgb, flash_amount);
	EMISSION = flash_color.rgb * flash_amount;
}
""",
		"water": """shader_type spatial;
// Stylized water for a subdivided PlaneMesh (set subdivide_width/depth ~ 32+).
render_mode cull_disabled;

uniform vec4 shallow_color : source_color = vec4(0.2, 0.65, 0.75, 0.75);
uniform vec4 deep_color : source_color = vec4(0.02, 0.15, 0.35, 1.0);
uniform float wave_height = 0.15;
uniform float wave_scale = 0.35;
uniform float wave_speed = 1.2;
uniform float roughness : hint_range(0.0, 1.0) = 0.05;

float wave(vec2 p) {
	return sin(p.x * wave_scale * 6.2831 + TIME * wave_speed) * cos(p.y * wave_scale * 5.1 + TIME * wave_speed * 0.8);
}

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	VERTEX.y += wave(p) * wave_height;
	float e = 0.1;
	float dx = (wave(p + vec2(e, 0.0)) - wave(p - vec2(e, 0.0))) * wave_height / (2.0 * e);
	float dz = (wave(p + vec2(0.0, e)) - wave(p - vec2(0.0, e))) * wave_height / (2.0 * e);
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, fresnel);
	ALPHA = mix(shallow_color.a, 1.0, fresnel);
	ROUGHNESS = roughness;
	SPECULAR = 0.6;
}
""",
		"toon": """shader_type spatial;
// Cel shading with hard light bands and a rim light.

uniform vec4 albedo : source_color = vec4(0.85, 0.45, 0.35, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform int bands : hint_range(1, 8) = 3;
uniform vec4 shadow_color : source_color = vec4(0.35, 0.3, 0.45, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	ALBEDO = albedo.rgb * texture(albedo_texture, UV).rgb;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float stepped = ceil(ndl * float(bands)) / float(bands);
	vec3 band = mix(shadow_color.rgb, vec3(1.0), stepped);
	DIFFUSE_LIGHT += band * LIGHT_COLOR / PI;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	SPECULAR_LIGHT += step(0.5, rim * stepped) * rim_amount * LIGHT_COLOR / PI;
}
""",
		"hologram": """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 holo_color : source_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform float line_density = 60.0;
uniform float scroll_speed = 0.6;
uniform float fresnel_power = 2.5;
uniform float flicker : hint_range(0.0, 1.0) = 0.1;

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float lines = 0.5 + 0.5 * sin((world_pos.y + TIME * scroll_speed) * line_density);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float f = 1.0 - flicker * step(0.96, fract(sin(floor(TIME * 24.0) * 12.9898) * 43758.5453));
	ALBEDO = holo_color.rgb * (lines * 0.6 + fresnel) * f;
	ALPHA = holo_color.a;
}
""",
		"wave": """shader_type spatial;
// Vertex sway for foliage/flags: vertices higher up (object space) move more.
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(0.35, 0.65, 0.25, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float amplitude = 0.15;
uniform float frequency = 1.5;
uniform float speed = 2.0;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float weight = max(VERTEX.y, 0.0);
	VERTEX.x += sin(TIME * speed + world.x * frequency + world.z * 0.7) * amplitude * weight;
	VERTEX.z += cos(TIME * speed * 0.8 + world.z * frequency) * amplitude * 0.5 * weight;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = albedo.rgb * tex.rgb;
}
""",
		"scroll": """shader_type spatial;
// Scrolling texture (conveyor belts, lava, waterfalls, screens).

uniform sampler2D albedo_texture : source_color, hint_default_white, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec2 scroll_speed = vec2(0.0, 0.25);
uniform float emission_strength = 0.0;

void fragment() {
	vec3 col = texture(albedo_texture, UV + TIME * scroll_speed).rgb * albedo.rgb;
	ALBEDO = col;
	EMISSION = col * emission_strength;
}
""",
	},
	"particles": {
		"blank": """shader_type particles;
// Process shader for GPUParticles3D/2D: fountain with gravity.

uniform vec3 direction = vec3(0.0, 1.0, 0.0);
uniform float spread : hint_range(0.0, 1.0) = 0.3;
uniform float speed = 4.0;
uniform vec3 gravity = vec3(0.0, -9.8, 0.0);
uniform vec4 color : source_color = vec4(1.0);

float rand_from_seed(inout uint seed) {
	seed = seed * 1103515245u + 12345u;
	return float((seed >> 16u) & 32767u) / 32767.0;
}

void start() {
	uint seed = NUMBER * 928371u + RANDOM_SEED;
	vec3 rnd = vec3(rand_from_seed(seed), rand_from_seed(seed), rand_from_seed(seed)) * 2.0 - 1.0;
	TRANSFORM = EMISSION_TRANSFORM;
	VELOCITY = normalize(direction + rnd * spread) * speed;
	COLOR = color;
}

void process() {
	VELOCITY += gravity * DELTA;
}
""",
	},
	"sky": {
		"blank": """shader_type sky;
// Gradient sky with a sun disc that follows the first DirectionalLight3D.

uniform vec3 top_color : source_color = vec3(0.22, 0.42, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.82, 0.92);
uniform vec3 ground_color : source_color = vec3(0.25, 0.22, 0.2);
uniform float sun_size : hint_range(0.001, 0.2) = 0.03;
uniform float energy = 1.0;

void sky() {
	float h = EYEDIR.y;
	vec3 col = h > 0.0 ? mix(horizon_color, top_color, sqrt(h)) : mix(horizon_color, ground_color, sqrt(-h));
	if (LIGHT0_ENABLED) {
		float d = distance(EYEDIR, LIGHT0_DIRECTION);
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (1.0 - smoothstep(sun_size * 0.6, sun_size, d));
	}
	COLOR = col * energy;
}
""",
	},
	"fog": {
		"blank": """shader_type fog;
// FogVolume material: fog that fades out towards the volume's edges.

uniform float density : hint_range(0.0, 8.0) = 1.0;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float edge_fade : hint_range(0.001, 1.0) = 0.2;

void fog() {
	DENSITY = density * clamp(-SDF / edge_fade, 0.0, 1.0);
	ALBEDO = albedo.rgb;
	EMISSION = emission.rgb;
}
""",
	},
}

## Godot 3 -> 4 mistakes: [regex, message].
const LINT := [
	["\\bhint_color\\b", "'hint_color' was renamed to 'source_color' in Godot 4."],
	["\\bhint_albedo\\b", "'hint_albedo' was renamed to 'source_color' in Godot 4."],
	["\\bhint_black_albedo\\b", "'hint_black_albedo' is now 'source_color, hint_default_black'."],
	["\\bhint_black\\b", "'hint_black' was renamed to 'hint_default_black'."],
	["\\bhint_white\\b", "'hint_white' was renamed to 'hint_default_white'."],
	["\\bhint_aniso\\b", "'hint_aniso' was renamed to 'hint_anisotropy'."],
	["\\bSCREEN_TEXTURE\\b", "SCREEN_TEXTURE was removed: declare 'uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;' and sample that."],
	["\\bDEPTH_TEXTURE\\b", "DEPTH_TEXTURE was removed: declare 'uniform sampler2D depth_texture : hint_depth_texture;'."],
	["\\bNORMAL_ROUGHNESS_TEXTURE\\b", "NORMAL_ROUGHNESS_TEXTURE was removed: declare 'uniform sampler2D nr_texture : hint_normal_roughness_texture;'."],
	["\\bWORLD_MATRIX\\b", "WORLD_MATRIX was renamed to MODEL_MATRIX."],
	["\\bWORLD_NORMAL_MATRIX\\b", "WORLD_NORMAL_MATRIX was renamed to MODEL_NORMAL_MATRIX."],
	["\\bINV_CAMERA_MATRIX\\b", "INV_CAMERA_MATRIX was renamed to VIEW_MATRIX."],
	["\\bCAMERA_MATRIX\\b", "CAMERA_MATRIX was renamed to INV_VIEW_MATRIX."],
	["\\bNORMALMAP_DEPTH\\b", "NORMALMAP_DEPTH was renamed to NORMAL_MAP_DEPTH."],
	["\\bNORMALMAP\\b", "NORMALMAP was renamed to NORMAL_MAP."],
	["\\bTRANSMISSION\\b", "TRANSMISSION was renamed to BACKLIGHT."],
	["\\bALPHA_SCISSOR\\b(?!_)", "ALPHA_SCISSOR was renamed to ALPHA_SCISSOR_THRESHOLD."],
	["\\basync_visible\\b|\\basync_hidden\\b", "async_visible/async_hidden render modes were removed."],
	["\\bWORLD_VERTEX_COORDS\\b|\\bworld_vertex_coords\\b", "Use MODEL_MATRIX to transform VERTEX; world_vertex_coords is only valid for canvas_item in Godot 3."],
]


# =============================================================================
# Helpers
# =============================================================================

func _shader_path(p: Dictionary, key: String = "path"):
	var raw := U.p_str(p, key)
	if raw == "":
		return U.err("Missing required parameter '%s'." % key)
	var path := U.res_path(raw)
	if path.get_extension() == "":
		path += ".gdshader"
	if not U.is_safe_path(path):
		return U.err("Path '%s' is outside the project." % raw)
	return path


func _type_of(code: String) -> String:
	var m := RegEx.create_from_string("(?m)^\\s*shader_type\\s+(\\w+)\\s*;").search(_strip_comments(code))
	return m.get_string(1) if m else ""


## Removes // and /* */ comments, keeping line breaks so line numbers stay valid.
func _strip_comments(code: String) -> String:
	var out := ""
	var i := 0
	var n := code.length()
	while i < n:
		var c := code[i]
		if c == "/" and i + 1 < n and code[i + 1] == "/":
			while i < n and code[i] != "\n":
				i += 1
			continue
		if c == "/" and i + 1 < n and code[i + 1] == "*":
			i += 2
			while i < n and not (code[i] == "*" and i + 1 < n and code[i + 1] == "/"):
				if code[i] == "\n":
					out += "\n"
				i += 1
			i += 2
			continue
		out += c
		i += 1
	return out


## Compiles shader code with the engine's shader compiler (errors are captured from the log).
## Returns {ok, errors: [{line, message}], uniforms: [...engine uniform infos]}.
func compile_check(code: String) -> Dictionary:
	ctx.flush_logs()
	var before: int = ctx.log_seq()
	ctx.quiet += 1
	var s := Shader.new()
	s.code = code
	var ulist := s.get_shader_uniform_list()
	ctx.flush_logs()
	ctx.quiet -= 1
	var errors := []
	for entry in ctx.get_logs(before, "", "warning", 50):
		if str(entry.get("kind", "")) != "shader":
			continue
		var msg := str(entry.get("message", ""))
		if msg.begins_with("Parse Error: "):
			msg = msg.substr(13)
		errors.append({"line": int(entry.get("line", 0)), "message": msg, "severity": "warning" if entry.get("level") == "warning" else "error"})
	# These diagnostics belong to this check only; keep them out of the editor error log so later
	# editor.logs / errors calls don't report a broken shader that doesn't exist on disk.
	# (The compiler also prints a numbered source listing: "--Main Shader--", "    1 | ...", "E   2-> ...".)
	var listing := RegEx.create_from_string("^(--\\w[\\w ]*--|E?\\s*\\d+\\s*(\\||->))")
	ctx.logs = ctx.logs.filter(func(x): return not (int(x.get("seq", 0)) > before and (str(x.get("kind", "")) == "shader" or listing.search(str(x.get("message", ""))) != null)))
	var ok := errors.filter(func(x): return x.severity == "error").is_empty()
	return {"ok": ok, "errors": errors, "uniforms": ulist, "shader": s}


## Structural checks + Godot 3 migration lint. Returns [{line, message, severity}].
func lint(code: String, type: String = "") -> Array:
	var out := []
	var clean := _strip_comments(code)
	var lines := clean.split("\n")
	var st := _type_of(code)
	if st == "":
		out.append({"line": 1, "severity": "error", "message": "Missing 'shader_type <type>;' at the top (one of %s)." % ", ".join(TYPES)})
	elif not st in TYPES:
		out.append({"line": 1, "severity": "error", "message": "Unknown shader_type '%s'. Use one of %s." % [st, ", ".join(TYPES)]})
	elif type != "" and st != type:
		out.append({"line": 1, "severity": "warning", "message": "shader_type is '%s' but '%s' was expected." % [st, type]})
	var depth := 0
	var paren := 0
	for i in lines.size():
		var line: String = lines[i]
		for ch in line:
			if ch == "{": depth += 1
			elif ch == "}": depth -= 1
			elif ch == "(": paren += 1
			elif ch == ")": paren -= 1
		if depth < 0:
			out.append({"line": i + 1, "severity": "error", "message": "Unmatched '}'."})
			depth = 0
	if depth > 0:
		out.append({"line": lines.size(), "severity": "error", "message": "%d unclosed '{' (missing '}')." % depth})
	if paren != 0:
		out.append({"line": lines.size(), "severity": "error", "message": "Unbalanced parentheses (%+d)." % paren})
	for rule in LINT:
		var re := RegEx.create_from_string(rule[0])
		for i in lines.size():
			if re.search(lines[i]):
				out.append({"line": i + 1, "severity": "error", "message": rule[1]})
				break
	if st == "particles" and RegEx.create_from_string("void\\s+vertex\\s*\\(").search(clean):
		out.append({"line": 1, "severity": "error", "message": "Godot 4 particle shaders use start() and process(), not vertex()."})
	if st == "spatial" and RegEx.create_from_string("\\bCOLOR\\s*=").search(clean) and not RegEx.create_from_string("void\\s+vertex").search(clean):
		out.append({"line": 1, "severity": "warning", "message": "Spatial fragment() writes ALBEDO, not COLOR (COLOR is the vertex color input)."})
	return out


## Parses uniform declarations from source: name, type, hint, default, group, scope.
func parse_uniforms(code: String) -> Array:
	var out := []
	var clean := _strip_comments(code)
	var re := RegEx.create_from_string("(?m)(?:^|;|\\})\\s*(?:(global|instance)\\s+)?uniform\\s+(?:(?:lowp|mediump|highp)\\s+)?(\\w+)\\s+(\\w+)\\s*(\\[\\s*\\d*\\s*\\])?\\s*(?::\\s*([^=;]+?))?\\s*(?:=\\s*([^;]+?))?\\s*;")
	var group_re := RegEx.create_from_string("group_uniforms\\s+([\\w.]*)\\s*;")
	var groups := []
	for g in group_re.search_all(clean):
		groups.append([g.get_start(), g.get_string(1)])
	for m in re.search_all(clean):
		var u := {"name": m.get_string(3), "type": m.get_string(2) + m.get_string(4).replace(" ", "")}
		if m.get_string(5) != "":
			u["hint"] = m.get_string(5).strip_edges()
		if m.get_string(6) != "":
			u["default"] = m.get_string(6).strip_edges()
		if m.get_string(1) != "":
			u["scope"] = m.get_string(1)
		var grp := ""
		for g in groups:
			if g[0] < m.get_start():
				grp = g[1]
		if grp != "":
			u["group"] = grp
		u["line"] = clean.substr(0, m.get_start(3)).count("\n") + 1
		out.append(u)
	return out


func _uniform_info(shader: Shader, name: String):
	for u in shader.get_shader_uniform_list():
		if u.name == name:
			return u
	return null


## Coerces a JSON value to a shader uniform's type ("#hex" colors, [x,y,z], "res://tex.png",
## {"type": "NoiseTexture2D", "noise": {"type": "FastNoiseLite"}}).
func coerce_param(shader: Shader, name: String, value):
	var info = _uniform_info(shader, name)
	if info == null:
		var names := shader.get_shader_uniform_list().map(func(u): return u.name)
		var s := U.suggest(name, names)
		return U.err("Shader '%s' has no uniform '%s'." % [shader.resource_path.get_file() if shader.resource_path != "" else "(inline)", name], ("Did you mean '%s'? " % s if s != "" else "") + "Uniforms: " + (", ".join(names) if not names.is_empty() else "(none)"))
	if value is String and str(value).begins_with("res://") and info.type == TYPE_OBJECT:
		var rp := U.res_path(str(value))
		if not ResourceLoader.exists(rp):
			return U.err("Texture '%s' does not exist." % rp)
		return load(rp)
	var v = U.coerce(value, info.type, info.hint, info.hint_string)
	if U.is_err(v):
		v["message"] = "Uniform '%s' (%s): %s" % [name, type_string(info.type) if info.type != TYPE_OBJECT else str(info.hint_string), v.message]
	return v


## Configures a ShaderMaterial from {shader: path|Shader, params: {...}, <uniform>: value, render_priority, next_pass}.
func configure_material(m: ShaderMaterial, props: Dictionary) -> Variant:
	if props.has("shader"):
		var sv = props.shader
		if sv is Shader:
			m.shader = sv
		elif str(sv) != "":
			var sp := U.res_path(str(sv))
			if sp.get_extension() == "":
				sp += ".gdshader"
			if not ResourceLoader.exists(sp):
				return U.err("Shader '%s' does not exist." % sp, "Create it first with shader.create {path, type, template}.")
			var sh = load(sp)
			if not (sh is Shader):
				return U.err("'%s' is not a Shader." % sp)
			m.shader = sh
	var params := U.p_dict(props, "params").duplicate()
	var infos := U.prop_infos(m)
	for k in props:
		if k in ["shader", "params", "type", "path"]:
			continue
		if infos.has(k) and not k.begins_with("shader_parameter/"):
			var r = U.set_prop(m, k, props[k], infos)
			if U.is_err(r): return r
		else:
			params[k] = props[k]
	if not params.is_empty() and m.shader == null:
		return U.err("Set 'shader' before shader params.", "Pass shader='res://x.gdshader' along with params.")
	for k in params:
		var name := str(k).trim_prefix("shader_parameter/")
		var v = coerce_param(m.shader, name, params[k])
		if U.is_err(v): return v
		m.set_shader_parameter(name, v)
	return null


## Finds ShaderMaterials on a node: [[object, property/label, material]].
func _node_shader_materials(n: Node) -> Array:
	var out := []
	var props := ["material_override", "material", "process_material", "material_overlay"]
	for pr in props:
		if pr in n:
			var m = n.get(pr)
			if m is ShaderMaterial:
				out.append([n, pr, m])
			if m is Material and m.next_pass is ShaderMaterial:
				out.append([m, "next_pass", m.next_pass])
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for i in mi.get_surface_override_material_count():
			var sm = mi.get_surface_override_material(i)
			if sm is ShaderMaterial:
				out.append([n, "surface_material_override/%d" % i, sm])
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mm = mi.mesh.surface_get_material(i)
				if mm is ShaderMaterial:
					out.append([mi.mesh, "mesh surface %d" % i, mm])
	if n is WorldEnvironment and n.environment and n.environment.sky and n.environment.sky.sky_material is ShaderMaterial:
		out.append([n.environment.sky, "sky_material", n.environment.sky.sky_material])
	return out


## Where to put a new ShaderMaterial of the given shader type on a node.
func _assign_slot(n: Node, type: String, surface: int):
	match type:
		"canvas_item":
			if n is CanvasItem:
				return [n, "material"]
			return U.err("canvas_item shaders go on 2D/UI nodes (CanvasItem); '%s' is a %s." % [n.name, n.get_class()], "Use type='spatial' for 3D meshes.")
		"spatial":
			if surface >= 0:
				if n is MeshInstance3D and surface < n.get_surface_override_material_count():
					return [n, "surface_material_override/%d" % surface]
				return U.err("Surface %d not found on '%s'." % [surface, n.name])
			if n.is_class("CSGPrimitive3D"):
				return [n, "material"]
			if n is GeometryInstance3D:
				return [n, "material_override"]
			return U.err("spatial shaders go on 3D geometry (MeshInstance3D, CSG, Sprite3D...); '%s' is a %s." % [n.name, n.get_class()], "Use type='canvas_item' for 2D nodes.")
		"particles":
			if n is GPUParticles3D or n is GPUParticles2D:
				return [n, "process_material"]
			return U.err("particles shaders are process materials for GPUParticles2D/3D; '%s' is a %s." % [n.name, n.get_class()])
		"sky":
			if n is WorldEnvironment:
				return [n, "sky"]
			return U.err("sky shaders go on a WorldEnvironment; '%s' is a %s." % [n.name, n.get_class()], "Create one with world3d.environment, then assign_to it.")
		"fog":
			if n is FogVolume:
				return [n, "material"]
			return U.err("fog shaders go on a FogVolume; '%s' is a %s." % [n.name, n.get_class()])
	return U.err("Unknown shader type '%s'." % type)


## Assigns mat to node (undoable). Returns the slot label or an error.
## as_next_pass chains it after the current material; as_overlay uses GeometryInstance3D.material_overlay.
func assign_material(n: Node, type: String, mat: ShaderMaterial, surface: int = -1, as_next_pass: bool = false, as_overlay: bool = false):
	var slot = _assign_slot(n, type, surface)
	if U.is_err(slot): return slot
	var obj: Object = slot[0]
	var prop: String = slot[1]
	if (as_overlay or as_next_pass) and not (n is GeometryInstance3D):
		return U.err("overlay/next_pass need a 3D GeometryInstance3D (MeshInstance3D, CSG...); '%s' is a %s." % [n.name, n.get_class()])
	if as_next_pass and not (obj.get(prop) is Material):
		as_overlay = true  # nothing to chain after: an overlay keeps the mesh's own surface materials
	if as_overlay:
		var u0 = ctx.begin("Assign overlay shader to " + str(n.name))
		u0.add_do_property(n, "material_overlay", mat)
		u0.add_undo_property(n, "material_overlay", n.get("material_overlay"))
		ctx.commit()
		return "material_overlay"
	var u = ctx.begin("Assign shader to " + str(n.name))
	if prop == "sky":
		var we: WorldEnvironment = n
		var env: Environment = we.environment.duplicate() if we.environment else Environment.new()
		var sky: Sky = env.sky.duplicate() if env.sky else Sky.new()
		sky.sky_material = mat
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		u.add_do_property(we, "environment", env)
		u.add_undo_property(we, "environment", we.environment)
		ctx.commit()
		return "environment.sky.sky_material"
	var cur = obj.get(prop)
	if as_next_pass:
		var base: Material = cur.duplicate()
		var last: Material = base
		while last.next_pass != null:
			last.next_pass = last.next_pass.duplicate()
			last = last.next_pass
		last.next_pass = mat
		u.add_do_property(obj, prop, base)
		u.add_undo_property(obj, prop, cur)
		ctx.commit()
		if cur is Material and cur.resource_path != "" and not cur.resource_path.contains("::"):
			return prop + ".next_pass (on an embedded copy of %s, so other users of that file are unaffected)" % cur.resource_path
		return prop + ".next_pass"
	u.add_do_property(obj, prop, mat)
	u.add_undo_property(obj, prop, cur)
	ctx.commit()
	return prop


func _diag_result(path: String, code: String, type: String) -> Dictionary:
	var c := compile_check(code)
	var diags: Array = c.errors.duplicate()
	var lint_issues := lint(code, type)
	for li in lint_issues:
		var dup := false
		for d in diags:
			if d.line == li.line:
				dup = true
		if not dup or li.severity == "error":
			li["source"] = "lint"
			diags.append(li)
	var ok: bool = c.ok and lint_issues.filter(func(x): return x.severity == "error").is_empty()
	return {"ok": ok, "diagnostics": diags, "uniforms": c.uniforms.map(func(u): return u.name)}


# =============================================================================
# Actions
# =============================================================================

func a_templates(_p: Dictionary):
	var out := {}
	for t in TEMPLATES:
		out[t] = TEMPLATES[t].keys()
	return {"templates": out}


func _template_code(type: String, template: String):
	if not TEMPLATES.has(type):
		return U.err("Unknown shader type '%s'." % type, "Types: " + ", ".join(TYPES))
	var set_: Dictionary = TEMPLATES[type]
	if not set_.has(template):
		var others := []
		for t in TEMPLATES:
			if TEMPLATES[t].has(template):
				others.append(t)
		var s := U.suggest(template, set_.keys())
		return U.err("No '%s' template for %s shaders." % [template, type], ("Did you mean '%s'? " % s if s != "" else "") + "Templates for %s: %s." % [type, ", ".join(set_.keys())] + (" '%s' exists for: %s." % [template, ", ".join(others)] if not others.is_empty() else ""))
	return str(set_[template]).replace("{NOISE}", NOISE_FN)


func _infer_type(p: Dictionary, n: Node, template: String) -> String:
	if p.has("type"):
		return U.p_str(p, "type")
	if n != null:
		if n is CanvasItem: return "canvas_item"
		if n is GPUParticles3D or n is GPUParticles2D: return "particles"
		if n is WorldEnvironment: return "sky"
		if n is FogVolume: return "fog"
		return "spatial"
	if p.has("code"):
		var t := _type_of(U.p_str(p, "code"))
		if t != "": return t
	var having := []
	for t2 in TEMPLATES:
		if TEMPLATES[t2].has(template):
			having.append(t2)
	if having.size() == 1:
		return having[0]
	var root: Node = ctx.edited_root()
	return "spatial" if root is Node3D else "canvas_item"


## Creates a .gdshader from a template (or code), compile-checks it and optionally assigns it.
func a_create(p: Dictionary):
	var path = _shader_path(p)
	if U.is_err(path): return path
	if FileAccess.file_exists(path) and not U.p_bool(p, "overwrite", false):
		return U.err("'%s' already exists." % path, "Use shader.edit to change it, or pass overwrite=true.")
	var target: Node = null
	if p.has("assign_to"):
		var n = await node_arg({"path": U.p_str(p, "assign_to"), "scene": p.get("scene", "")})
		if U.is_err(n): return n
		target = n
	var template := U.p_str(p, "template", "blank")
	var type := _infer_type(p, target, template)
	if not type in TYPES:
		var s := U.suggest(type, TYPES)
		return U.err("Unknown shader type '%s'." % type, ("Did you mean '%s'? " % s if s != "" else "") + "Types: " + ", ".join(TYPES))
	var code: String
	if p.has("code"):
		code = U.p_str(p, "code")
		var st := _type_of(code)
		if st == "":
			code = "shader_type %s;\n\n" % type + code
		elif st != type:
			if p.has("type"):
				return U.err("The code declares 'shader_type %s;' but type='%s'." % [st, type], "Drop 'type' (the code's shader_type is used) or fix the shader_type line.")
			type = st
	else:
		var tc = _template_code(type, template)
		if U.is_err(tc): return tc
		code = tc
	if target:
		var slot_check = _assign_slot(target, type, U.p_int(p, "surface", -1))
		if U.is_err(slot_check): return slot_check
	var wr = await ctx.router.handlers["files"].write_text(path, code)
	if U.is_err(wr): return wr
	await ctx.wait_fs()
	var diag := _diag_result(path, code, type)
	var out := {"path": path, "type": type, "template": template if not p.has("code") else "custom", "ok": diag.ok, "uniforms": diag.uniforms, "validation": "engine shader compiler + lint"}
	if not diag.diagnostics.is_empty():
		out["diagnostics"] = diag.diagnostics
	if target or p.has("material_path"):
		var shader = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if not (shader is Shader):
			return U.err("Created '%s' but could not load it as a Shader." % path)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		if p.has("params"):
			var cr = configure_material(mat, {"params": U.p_dict(p, "params")})
			if U.is_err(cr):
				cr["message"] = "Shader created, but params failed: " + str(cr.message)
				return cr
		if p.has("material_path"):
			var mp := U.res_path(U.p_str(p, "material_path"))
			if mp.get_extension() == "":
				mp += ".tres"
			ctx.before_write([mp])
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(mp.get_base_dir()))
			if ResourceSaver.save(mat, mp) != OK:
				return U.err("Could not save material '%s'." % mp)
			mat.take_over_path(mp)
			ctx.fs().update_file(mp)
			out["material"] = mp
		if target:
			# Inverted-hull outlines render as an extra pass: material_overlay (whole mesh, keeps
			# the object's own materials untouched) unless next_pass=true is asked for.
			var outline := type == "spatial" and template == "outline" and not p.has("code")
			var as_next := U.p_bool(p, "next_pass", false)
			var as_overlay := U.p_bool(p, "overlay", outline and not as_next)
			var slot = assign_material(target, type, mat, U.p_int(p, "surface", -1), as_next, as_overlay)
			if U.is_err(slot): return slot
			out["assigned_to"] = "%s.%s" % [ctx.node_path_str(target), slot]
	return out


## Compile-checks a shader file or code. Uses the engine's shader compiler (reports the first
## compile error with its line) plus a lint for structure and Godot 3 leftovers.
func a_validate(p: Dictionary):
	var code := ""
	var path := ""
	var offset := 0
	if p.has("code"):
		code = U.p_str(p, "code")
		var t := U.p_str(p, "type", "")
		if _type_of(code) == "":
			if t == "":
				return U.err("The code has no 'shader_type' line.", "Add 'shader_type spatial;' (or canvas_item/particles/sky/fog) or pass type.")
			code = "shader_type %s;\n" % t + code
			offset = 1
	else:
		var sp = _shader_path(p)
		if U.is_err(sp): return sp
		path = sp
		if not FileAccess.file_exists(path):
			return U.err("Shader '%s' does not exist." % path, "Pass code to validate a snippet, or create the file with shader.create.")
		code = FileAccess.get_file_as_string(path)
	var diag := _diag_result(path, code, U.p_str(p, "type", ""))
	if offset > 0:
		for d in diag.diagnostics:
			d.line = maxi(1, int(d.line) - offset)
	var out := {"ok": diag.ok, "type": _type_of(code), "diagnostics": diag.diagnostics, "uniforms": diag.uniforms,
		"validation": "engine: the shader was compiled by Godot's shader compiler (reports the first error only); plus a lint for structure and Godot 3 syntax"}
	if path != "":
		out["path"] = path
	return out


## Reads a shader: {path: res://x.gdshader | res://material.tres | node path}.
func a_read(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var raw := U.p_str(p, "path")
	var shader: Shader = null
	var path := ""
	if raw.begins_with("res://") or raw.get_extension() in ["gdshader", "tres", "res", "material"]:
		path = U.res_path(raw)
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			return U.err("'%s' does not exist." % path, "Use files.list pattern='*.gdshader' to find shaders.")
		if path.get_extension() == "gdshader":
			var code := FileAccess.get_file_as_string(path)
			return {"path": path, "type": _type_of(code), "code": code, "uniforms": parse_uniforms(code)}
		var r = load(path)
		if r is ShaderMaterial:
			shader = r.shader
		elif r is Shader:
			shader = r
		else:
			return U.err("'%s' is a %s, not a shader or ShaderMaterial." % [path, r.get_class()])
	else:
		var n = await node_arg(p)
		if U.is_err(n): return n
		var mats := _node_shader_materials(n)
		if mats.is_empty():
			return U.err("'%s' has no ShaderMaterial." % raw, "Create one with shader.create {path, assign_to: '%s'}." % raw)
		shader = mats[0][2].shader
	if shader == null:
		return U.err("The material has no shader assigned.")
	var out := {"path": shader.resource_path, "type": _type_of(shader.code), "code": shader.code, "uniforms": parse_uniforms(shader.code)}
	if shader.resource_path == "" or shader.resource_path.contains("::"):
		out["embedded"] = true
	return out


## Edits a .gdshader with exact replacements (or replaces all code) and re-validates it.
func a_edit(p: Dictionary):
	var path = _shader_path(p)
	if U.is_err(path): return path
	if not FileAccess.file_exists(path):
		return U.err("Shader '%s' does not exist." % path, "Create it with shader.create.")
	var r
	if p.has("code"):
		r = await ctx.router.handlers["files"].write_text(path, U.p_str(p, "code"))
	else:
		var edits := U.p_arr(p, "edits")
		if edits.is_empty() and not p.has("old"):
			return U.err("Provide 'edits': [{old, new}] or 'code' (full replacement).")
		r = await ctx.router.handlers["files"].a_edit({"path": path, "edits": edits, "old": p.get("old"), "new": p.get("new", "")} if p.has("old") else {"path": path, "edits": edits})
	if U.is_err(r): return r
	var code := FileAccess.get_file_as_string(path)
	var diag := _diag_result(path, code, "")
	var out := {"path": path, "ok": diag.ok, "uniforms": diag.uniforms}
	if r.has("edits_applied"):
		out["edits_applied"] = r.edits_applied
	if not diag.diagnostics.is_empty():
		out["diagnostics"] = diag.diagnostics
	return out


## Lists uniforms (type, hint, default, group) of a shader, material file or node material,
## with current values when a material is given.
func a_uniforms(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var raw := U.p_str(p, "path")
	var shader: Shader = null
	var mat: ShaderMaterial = null
	if raw.begins_with("res://") or raw.get_extension() in ["gdshader", "tres", "res", "material"]:
		var path := U.res_path(raw)
		if not ResourceLoader.exists(path):
			return U.err("'%s' does not exist." % path)
		var r = load(path)
		if r is Shader: shader = r
		elif r is ShaderMaterial:
			mat = r
			shader = r.shader
		else:
			return U.err("'%s' is a %s, not a shader or ShaderMaterial." % [path, r.get_class()])
	else:
		var n = await node_arg(p)
		if U.is_err(n): return n
		var mats := _node_shader_materials(n)
		if mats.is_empty():
			return U.err("'%s' has no ShaderMaterial." % raw, "Assign one with shader.create {assign_to} or world3d.material {type: 'shader'}.")
		mat = mats[0][2]
		shader = mat.shader
	if shader == null:
		return U.err("No shader assigned to the material.")
	var parsed := parse_uniforms(shader.code)
	var engine := {}
	for u in shader.get_shader_uniform_list():
		engine[u.name] = u
	for u in parsed:
		if engine.has(u.name):
			var info: Dictionary = engine[u.name]
			u["value_type"] = type_string(info.type) if info.type != TYPE_OBJECT else str(info.hint_string)
			if info.hint == PROPERTY_HINT_RANGE:
				u["range"] = info.hint_string
		if mat:
			var v = mat.get_shader_parameter(u.name)
			if v != null:
				u["value"] = U.encode(v)
	var out := {"shader": shader.resource_path, "type": _type_of(shader.code), "uniforms": parsed}
	if mat and mat.resource_path != "" and not mat.resource_path.contains("::"):
		out["material"] = mat.resource_path
	if parsed.is_empty() and not engine.is_empty():
		out["uniforms"] = engine.values().map(func(x): return {"name": x.name, "value_type": type_string(x.type)})
	return out


## Sets shader parameters on a node's ShaderMaterial (undoable) or on a material file.
func a_set_param(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var params := U.p_dict(p, "params").duplicate()
	if p.has("param"):
		params[U.p_str(p, "param")] = p.get("value")
	if params.is_empty():
		return U.err("Provide param + value, or params: {name: value}.")
	var raw := U.p_str(p, "path")
	if raw.begins_with("res://") or raw.get_extension() in ["tres", "res", "material"]:
		var path := U.res_path(raw)
		if not ResourceLoader.exists(path):
			return U.err("'%s' does not exist." % path)
		var m = load(path)
		if not (m is ShaderMaterial):
			return U.err("'%s' is a %s, not a ShaderMaterial." % [path, m.get_class()], "Pass a node path or a ShaderMaterial .tres.")
		var cr = configure_material(m, {"params": params})
		if U.is_err(cr): return cr
		ctx.before_write([path])
		if ResourceSaver.save(m, path) != OK:
			return U.err("Could not save '%s'." % path)
		ctx.fs().update_file(path)
		return {"path": path, "set": _values(m, params)}
	var n = await node_arg(p)
	if U.is_err(n): return n
	var mats := _node_shader_materials(n)
	if mats.is_empty():
		return U.err("'%s' (%s) has no ShaderMaterial." % [raw, n.get_class()], "Create one with shader.create {path, template, assign_to: '%s'}." % raw)
	var idx := U.p_int(p, "material_index", 0)
	var entry: Array = mats[clampi(idx, 0, mats.size() - 1)]
	if not p.has("material_index") and mats.size() > 1:
		# Prefer the material that actually has the params.
		for m2 in mats:
			var sh2: Shader = m2[2].shader
			if sh2 and params.keys().all(func(k): return _uniform_info(sh2, str(k)) != null):
				entry = m2
				break
	var mat: ShaderMaterial = entry[2]
	if mat.shader == null:
		return U.err("The ShaderMaterial on '%s' has no shader." % raw)
	var plan := {}
	for k in params:
		var v = coerce_param(mat.shader, str(k), params[k])
		if U.is_err(v): return v
		plan[str(k)] = v
	if mat.resource_path != "" and not mat.resource_path.contains("::"):
		# Shared material file: edit the file (affects every user of it).
		for k in plan:
			mat.set_shader_parameter(k, plan[k])
		ctx.before_write([mat.resource_path])
		ResourceSaver.save(mat, mat.resource_path)
		ctx.fs().update_file(mat.resource_path)
		return {"path": ctx.node_path_str(n), "material": mat.resource_path, "set": _values(mat, params), "note": "The material is a shared file; saved it."}
	var u = ctx.begin("Set shader params on " + str(n.name))
	for k in plan:
		u.add_do_method(mat, "set_shader_parameter", k, plan[k])
		u.add_undo_method(mat, "set_shader_parameter", k, mat.get_shader_parameter(k))
	ctx.commit()
	return {"path": ctx.node_path_str(n), "slot": str(entry[1]), "set": _values(mat, params)}


func _values(mat: ShaderMaterial, params: Dictionary) -> Dictionary:
	var out := {}
	for k in params:
		out[str(k)] = U.encode(mat.get_shader_parameter(str(k)))
	return out


## Creates a ShaderMaterial .tres from a shader with parameters (optionally assigns it).
func a_material(p: Dictionary):
	var e = U.require(p, ["path", "shader"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if path.get_extension() == "":
		path += ".tres"
	if path.get_extension() == "gdshader":
		return U.err("'path' is where the ShaderMaterial is saved (.tres); the .gdshader goes in 'shader'.")
	var existing: ShaderMaterial = null
	if FileAccess.file_exists(path) and not U.p_bool(p, "overwrite", false):
		var cur = load(path)
		if not (cur is ShaderMaterial):
			return U.err("'%s' already exists (%s)." % [path, cur.get_class() if cur else "unreadable"], "Pass overwrite=true or another path.")
		existing = cur
	var props := {"shader": p.shader, "params": U.p_dict(p, "params")}
	for k in U.p_dict(p, "props"):
		props[k] = p.props[k]
	# Validate on a scratch copy; an existing material is updated in place (keeps its other params
	# and every node that uses it), a new one is created.
	var trial: ShaderMaterial = existing.duplicate() if existing else ShaderMaterial.new()
	var cr = configure_material(trial, props)
	if U.is_err(cr): return cr
	var mat: ShaderMaterial = trial
	if existing:
		mat = existing
		configure_material(mat, props)
	ctx.before_write([path])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if ResourceSaver.save(mat, path) != OK:
		return U.err("Could not save '%s'." % path)
	if not existing:
		mat.take_over_path(path)
	ctx.fs().update_file(path)
	var out := {"path": path, "created": existing == null, "shader": mat.shader.resource_path, "params": _values(mat, props.params)}
	if p.has("assign_to"):
		var n = await node_arg({"path": U.p_str(p, "assign_to"), "scene": p.get("scene", "")})
		if U.is_err(n): return n
		var slot = assign_material(n, _type_of(mat.shader.code), mat, U.p_int(p, "surface", -1))
		if U.is_err(slot): return slot
		out["assigned_to"] = "%s.%s" % [ctx.node_path_str(n), slot]
	return out
