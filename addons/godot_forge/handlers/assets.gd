@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Asset helpers that need the editor: procedural placeholder art, import options/presets,
## image info. Downloads and AI generation happen in the MCP server (src/assets).

const IMPORT_PRESETS := {
	"pixel_art": {"compress/mode": 0, "mipmaps/generate": false, "process/fix_alpha_border": true},
	"2d": {"compress/mode": 0, "mipmaps/generate": false},
	"3d_texture": {"compress/mode": 2, "mipmaps/generate": true, "detect_3d/compress_to": 1},
	"normal_map": {"compress/mode": 2, "compress/normal_map": 1, "mipmaps/generate": true},
	"ui": {"compress/mode": 0, "mipmaps/generate": false, "process/size_limit": 0},
}


# ---------------------------------------------------------------------------
# Placeholder art
# ---------------------------------------------------------------------------

## Generates simple, readable placeholder art so prototypes are playable before real art exists.
## kind: sprite (one shape) | spritesheet (frames with a bounce, for animation tests) |
##       tileset (a row of distinct tiles: e.g. grass, dirt, stone, water, ...) | icon
## shape: rect | rounded | circle | triangle | diamond | capsule | star
func a_placeholder(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not path.ends_with(".png"):
		path += ".png"
	var kind := U.p_str(p, "kind", "sprite")
	var size: Vector2i = U.to_vector(p.get("size", [32, 32]), TYPE_VECTOR2I)
	if size.x < 4 or size.y < 4 or size.x > 2048 or size.y > 2048:
		return U.err("size must be between 4 and 2048 px.")
	var color := U.to_color(p.get("color", "#4da6ff"))
	var outline := U.to_color(p.get("outline", "#1a1a2e"))
	var shape := U.p_str(p, "shape", "rounded")
	var face := U.p_bool(p, "face", kind == "sprite" and shape in ["rounded", "circle", "capsule", "rect"])
	var img: Image
	match kind:
		"sprite", "icon":
			img = _shape_image(size, shape, color, outline, face, 0.0)
		"spritesheet":
			var frames := clampi(U.p_int(p, "frames", 4), 1, 32)
			img = Image.create(size.x * frames, size.y, false, Image.FORMAT_RGBA8)
			for i in frames:
				var bounce := sin(float(i) / frames * TAU) * 0.08
				var frame := _shape_image(size, shape, color.lightened(0.08 * sin(float(i) / frames * TAU)), outline, face, bounce)
				img.blit_rect(frame, Rect2i(Vector2i.ZERO, size), Vector2i(i * size.x, 0))
		"tileset":
			var colors: Array = U.p_arr(p, "colors")
			if colors.is_empty():
				colors = ["#5fb350", "#8b5a2b", "#7d7d85", "#3a7bd5", "#e3c16f", "#2e2e38"]
			img = Image.create(size.x * colors.size(), size.y, false, Image.FORMAT_RGBA8)
			for i in colors.size():
				var c := U.to_color(colors[i])
				var tile := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
				tile.fill(c)
				# subtle texture + border so tiles read as a grid
				var rng := RandomNumberGenerator.new()
				rng.seed = i * 7919 + 17
				for n in (size.x * size.y) / 12:
					var px := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
					tile.set_pixelv(px, c.darkened(rng.randf_range(0.05, 0.15)))
				for x in size.x:
					tile.set_pixel(x, 0, c.lightened(0.2))
					tile.set_pixel(x, size.y - 1, c.darkened(0.3))
				for y in size.y:
					tile.set_pixel(0, y, c.lightened(0.1))
					tile.set_pixel(size.x - 1, y, c.darkened(0.25))
				img.blit_rect(tile, Rect2i(Vector2i.ZERO, size), Vector2i(i * size.x, 0))
		_:
			return U.err("Unknown kind '%s'." % kind, "Use sprite, spritesheet, tileset or icon.")
	ctx.before_write([path])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		return U.err("Failed to save %s (error %d)." % [path, err])
	var imported: bool = await ctx.import_file(path)
	var out := {"path": path, "size": var_to_str(img.get_size()), "kind": kind, "imported": imported}
	if kind == "spritesheet":
		out["hframes"] = img.get_width() / size.x
		out["frame_size"] = var_to_str(size)
	if kind == "tileset":
		out["tile_size"] = var_to_str(size)
		out["tiles"] = img.get_width() / size.x
	out["preview"] = U.image_to_b64(img, 256)
	return out


func _shape_image(size: Vector2i, shape: String, color: Color, outline: Color, face: bool, bounce: float) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var w := float(size.x)
	var h := float(size.y)
	var squash := 1.0 + bounce
	var ow := maxf(1.0, minf(w, h) / 16.0)
	for y in size.y:
		for x in size.x:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := ((y + 0.5) / h * 2.0 - 1.0) / squash - bounce
			var d := _sdf(shape, u, v)
			var edge := ow / (minf(w, h) * 0.5)
			if d <= 0.0:
				var shade := color.darkened(clampf((v + 1.0) * 0.12, 0.0, 0.25))
				img.set_pixel(x, y, outline if d > -edge else shade)
	if face:
		var eye := maxi(1, int(minf(w, h) / 10.0))
		var ey := int(h * (0.42 + bounce * 0.5))
		for ex in [int(w * 0.36), int(w * 0.64)]:
			for dy in range(-eye, eye + 1):
				for dx in range(-eye, eye + 1):
					if dx * dx + dy * dy <= eye * eye and ex + dx >= 0 and ex + dx < size.x and ey + dy >= 0 and ey + dy < size.y:
						img.set_pixel(ex + dx, ey + dy, outline)
	return img


func _sdf(shape: String, u: float, v: float) -> float:
	match shape:
		"circle":
			return sqrt(u * u + v * v) - 0.92
		"triangle":
			return maxf(absf(u) * 0.95 + v * 0.5 - 0.45, -v - 0.9)
		"diamond":
			return absf(u) + absf(v) - 0.95
		"capsule":
			var cy := clampf(v, -0.45, 0.45)
			return sqrt(u * u * 1.6 + (v - cy) * (v - cy)) - 0.6
		"star":
			var a := atan2(v, u)
			var r := sqrt(u * u + v * v)
			return r - (0.55 + 0.35 * cos(5.0 * a))
		"rect":
			return maxf(absf(u), absf(v)) - 0.95
		_:  # rounded
			var q := Vector2(absf(u), absf(v)) - Vector2(0.65, 0.65)
			return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 0.3


# ---------------------------------------------------------------------------
# Import options
# ---------------------------------------------------------------------------

## Edits import options of an asset and reimports it. preset: pixel_art | 2d | 3d_texture |
## normal_map | ui (textures). options: raw .import [params] keys, e.g. {"compress/mode": 0}.
func a_import_options(p: Dictionary):
	if not p.has("paths"):
		var e = U.require(p, ["path"])
		if e: return e
	var paths: Array = U.p_arr(p, "paths") if p.has("paths") else [U.p_str(p, "path")]
	var opts := {}
	var preset := U.p_str(p, "preset", "")
	if preset != "":
		if not IMPORT_PRESETS.has(preset):
			return U.err("Unknown preset '%s'." % preset, "Presets: " + ", ".join(IMPORT_PRESETS.keys()))
		opts.merge(IMPORT_PRESETS[preset])
	opts.merge(U.p_dict(p, "options"), true)
	if opts.is_empty():
		return await a_import_info(p)
	var done := []
	var rp_list := PackedStringArray()
	for raw in paths:
		var rp := U.res_path(str(raw))
		var imp := rp + ".import"
		if not FileAccess.file_exists(imp):
			return U.err("'%s' has no .import file (not an imported asset, or not scanned yet)." % rp, "Run files.rescan first.")
		ctx.before_write([imp])
		var cfg := ConfigFile.new()
		cfg.load(imp)
		for k in opts:
			cfg.set_value("params", k, U._auto(opts[k]))
		cfg.save(imp)
		rp_list.append(rp)
		done.append(rp)
	ctx.fs().reimport_files(rp_list)
	await ctx.wait_fs()
	if preset == "pixel_art" and U.p_bool(p, "set_project_filter", true):
		ProjectSettings.set_setting("rendering/textures/canvas_textures/default_texture_filter", 0)
		ProjectSettings.save()
	return {"reimported": done, "options": opts, "note": "pixel_art also sets the project's default canvas texture filter to Nearest." if preset == "pixel_art" else ""}


func a_import_info(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var rp := U.res_path(U.p_str(p, "path"))
	var imp := rp + ".import"
	if not FileAccess.file_exists(imp):
		return U.err("'%s' has no .import file." % rp)
	var cfg := ConfigFile.new()
	cfg.load(imp)
	var params := {}
	if cfg.has_section("params"):
		for k in cfg.get_section_keys("params"):
			params[k] = U.encode(cfg.get_value("params", k))
	var out := {"path": rp, "importer": cfg.get_value("remap", "importer", ""), "type": cfg.get_value("remap", "type", ""), "params": params}
	var res = load(rp) if ResourceLoader.exists(rp) else null
	if res is Texture2D:
		out["size"] = var_to_str(res.get_size())
	return out


## Summary of the project's assets by type with sizes (helps pick what to reuse).
func a_inventory(p: Dictionary):
	var files := []
	ctx.router.handlers["files"]._walk(U.res_path(U.p_str(p, "path", "res://")), true, "", false, files, [], 5000)
	var groups := {"textures": [], "audio": [], "models": [], "fonts": [], "scenes": [], "materials": [], "other": []}
	for f in files:
		var path: String = f.path
		var ext := path.get_extension().to_lower()
		var bucket := "other"
		if ext in ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "hdr", "exr"]:
			bucket = "textures"
		elif ext in ["wav", "ogg", "mp3"]:
			bucket = "audio"
		elif ext in ["glb", "gltf", "fbx", "obj", "blend", "dae"]:
			bucket = "models"
		elif ext in ["ttf", "otf", "woff", "woff2", "fnt"]:
			bucket = "fonts"
		elif ext in ["tscn", "scn"]:
			bucket = "scenes"
		elif ext == "tres" and str(f.get("type", "")).contains("Material"):
			bucket = "materials"
		else:
			continue
		groups[bucket].append(path)
	var counts := {}
	for g in groups:
		counts[g] = groups[g].size()
	return {"counts": counts, "assets": groups}


## Post-processes an image file: trim transparent borders, resize (nearest for pixel art),
## optional palette-free pixelation. {path, resize?: [w, h], nearest?, trim?, save_as?}
func a_process_image(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var rp := U.res_path(U.p_str(p, "path"))
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(rp)) != OK:
		return U.err("Could not load image %s." % rp)
	img.convert(Image.FORMAT_RGBA8)
	if U.p_bool(p, "trim", false):
		var used := img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			img = img.get_region(used)
	if p.has("resize"):
		var target: Vector2i = U.to_vector(p.resize, TYPE_VECTOR2I)
		# Keep aspect ratio inside the target box.
		var s := minf(float(target.x) / img.get_width(), float(target.y) / img.get_height())
		var nw := maxi(1, int(img.get_width() * s))
		var nh := maxi(1, int(img.get_height() * s))
		img.resize(nw, nh, Image.INTERPOLATE_NEAREST if U.p_bool(p, "nearest", false) else Image.INTERPOLATE_LANCZOS)
		if nw != target.x or nh != target.y:
			var canvas := Image.create(target.x, target.y, false, Image.FORMAT_RGBA8)
			canvas.fill(Color(0, 0, 0, 0))
			canvas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((target.x - nw) / 2, (target.y - nh) / 2))
			img = canvas
	var out_path := U.res_path(U.p_str(p, "save_as", rp))
	ctx.before_write([out_path])
	img.save_png(ProjectSettings.globalize_path(out_path))
	ctx.fs().update_file(out_path)
	ctx.fs().reimport_files(PackedStringArray([out_path]))
	await ctx.wait_fs()
	return {"path": out_path, "size": var_to_str(img.get_size()), "preview": U.image_to_b64(img, 256)}
