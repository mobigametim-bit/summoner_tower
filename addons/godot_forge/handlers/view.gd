@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Seeing things: editor viewport screenshots, offscreen renders of scenes from any angle,
## and screenshots of the running game.

const ANGLES := {
	"front": Vector3(0, 0.25, 1), "back": Vector3(0, 0.25, -1), "left": Vector3(-1, 0.25, 0), "right": Vector3(1, 0.25, 0),
	"top": Vector3(0, 1, 0.001), "iso": Vector3(1, 0.8, 1), "iso_back": Vector3(-1, 0.8, -1), "low": Vector3(0.6, 0.1, 1),
}


func _no_display():
	if DisplayServer.get_name() == "headless":
		return U.err("The editor is running headless; nothing is rendered.", "Open the project in the normal Godot editor (not --headless) to get screenshots.")
	return null


## Screenshot of an editor viewport: which = "2d" | "3d" | "editor" (whole window).
func a_editor(p: Dictionary):
	var nd = _no_display()
	if nd: return nd
	var which := U.p_str(p, "which", "auto")
	if which == "auto":
		var root: Node = ctx.edited_root()
		which = "3d" if root is Node3D else "2d"
	var img: Image
	match which:
		"2d":
			EditorInterface.set_main_screen_editor("2D")
			await RenderingServer.frame_post_draw
			img = EditorInterface.get_editor_viewport_2d().get_texture().get_image()
		"3d":
			EditorInterface.set_main_screen_editor("3D")
			await RenderingServer.frame_post_draw
			img = EditorInterface.get_editor_viewport_3d(U.p_int(p, "index", 0)).get_texture().get_image()
		_:
			await RenderingServer.frame_post_draw
			img = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	var shot := U.image_to_b64(img, U.p_int(p, "max_size", ctx.settings.screenshot_max_size))
	shot["which"] = which
	return shot


## Renders a scene offscreen with an automatically framed camera. Great for checking layout
## and art from several angles without touching the editor camera.
## p: scene (defaults to edited), focus (node path), angles (3D: front/top/iso/...), size [w,h],
##    zoom (2D multiplier), preview_light (bool, add light+sky if the scene has none).
func a_render(p: Dictionary):
	var nd = _no_display()
	if nd: return nd
	var inst: Node
	var sp := U.p_str(p, "scene", "")
	if sp != "":
		sp = U.res_path(sp)
		if not ResourceLoader.exists(sp):
			return U.err("Scene '%s' does not exist." % sp)
		inst = (load(sp) as PackedScene).instantiate()
	else:
		var root = root_or_err()
		if U.is_err(root): return root
		inst = root.duplicate()
	var size: Vector2i = U.to_vector(p.get("size", [960, 540]), TYPE_VECTOR2I)
	var sv := SubViewport.new()
	sv.size = size
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.own_world_3d = true
	sv.transparent_bg = false
	sv.msaa_2d = Viewport.MSAA_4X
	sv.msaa_3d = Viewport.MSAA_4X
	EditorInterface.get_base_control().add_child(sv)
	sv.add_child(inst)
	var focus: Node = inst
	if p.has("focus"):
		var fp := U.p_str(p, "focus")
		focus = inst.get_node_or_null(fp) if fp not in ["", "."] else inst
		if focus == null:
			sv.queue_free()
			return U.err("Focus node '%s' not found." % fp)
	var shots := []
	var is3d := inst is Node3D or (not (inst is CanvasItem) and _has_3d(inst))
	if is3d:
		await ctx.frame()  # let the instance enter the tree so global transforms are valid
		# Cutaway: hide geometry above a height (ceilings/roofs) to look inside buildings.
		var hidden := 0
		if p.has("cutaway"):
			hidden = _cutaway(inst, U.p_float(p, "cutaway"))
		var aabb := _aabb(focus)
		if aabb.size == Vector3.ZERO:
			aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
		var light_mode = p.get("preview_light", true)
		var force_light: bool = str(light_mode) == "force"
		if force_light or (bool(light_mode) and not _has_type(inst, "DirectionalLight3D") and not _has_type(inst, "WorldEnvironment")):
			if force_light:
				_disable_envs(inst)
			_add_preview_lighting(sv)
		var cam := Camera3D.new()
		cam.fov = U.p_float(p, "fov", 50.0)
		sv.add_child(cam)
		cam.current = true
		# Explicit viewpoint: a node in the scene (Camera3D/Marker3D), or position + look_at.
		if p.has("from_node") or p.has("camera"):
			var xf := Transform3D.IDENTITY
			var label := ""
			if p.has("from_node"):
				var src: Node = inst.get_node_or_null(U.p_str(p, "from_node"))
				if not (src is Node3D):
					sv.queue_free()
					return U.err("from_node '%s' is not a Node3D in the scene." % U.p_str(p, "from_node"), "Use a Camera3D or Marker3D path relative to the scene root.")
				xf = (src as Node3D).global_transform
				if src is Camera3D:
					cam.fov = (src as Camera3D).fov
				label = U.p_str(p, "from_node")
			else:
				var cspec: Dictionary = U.p_dict(p, "camera")
				var pos: Vector3 = U.to_vector(cspec.get("position", [0, 2, 5]), TYPE_VECTOR3)
				var target: Vector3 = U.to_vector(cspec.get("look_at", [0, 0, 0]), TYPE_VECTOR3)
				xf = Transform3D.IDENTITY.translated(pos).looking_at(target, Vector3.UP) if not pos.is_equal_approx(target) else Transform3D.IDENTITY.translated(pos)
				if cspec.has("fov"):
					cam.fov = float(cspec.fov)
				label = "camera"
			cam.global_transform = xf
			cam.near = 0.05
			cam.far = 4000.0
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var vshot := U.image_to_b64(sv.get_texture().get_image(), U.p_int(p, "max_size", ctx.settings.screenshot_max_size))
			vshot["view"] = label
			if hidden > 0:
				vshot["cutaway_hidden"] = hidden
			sv.queue_free()
			return vshot
		var angles: Array = U.p_arr(p, "angles") if p.has("angles") else ["iso"]
		for angle in angles:
			var dir: Vector3 = ANGLES.get(str(angle), ANGLES.iso).normalized()
			if angle is Array:
				dir = U.to_vector(angle, TYPE_VECTOR3).normalized()
			var radius := aabb.size.length() * 0.5
			var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * U.p_float(p, "distance_scale", 1.0)
			var center := aabb.get_center()
			cam.near = maxf(0.01, dist * 0.01)
			cam.far = dist * 10.0 + radius * 4.0
			cam.look_at_from_position(center + dir * dist, center, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var shot := U.image_to_b64(sv.get_texture().get_image(), U.p_int(p, "max_size", ctx.settings.screenshot_max_size))
			shot["angle"] = str(angle)
			if hidden > 0:
				shot["cutaway_hidden"] = hidden
			shots.append(shot)
	else:
		var rect := _rect2d(focus)
		if rect.size == Vector2.ZERO:
			rect = Rect2(Vector2.ZERO, Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 1152), ProjectSettings.get_setting("display/window/size/viewport_height", 648)))
		rect = rect.grow(maxf(rect.size.x, rect.size.y) * 0.06)
		_disable_cameras(inst)
		var cam2 := Camera2D.new()
		cam2.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
		cam2.position = rect.get_center()
		var z := minf(size.x / maxf(1.0, rect.size.x), size.y / maxf(1.0, rect.size.y)) * U.p_float(p, "zoom", 1.0)
		cam2.zoom = Vector2(z, z)
		sv.add_child(cam2)
		cam2.enabled = true
		cam2.make_current()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot2 := U.image_to_b64(sv.get_texture().get_image(), U.p_int(p, "max_size", ctx.settings.screenshot_max_size))
		shot2["world_rect"] = var_to_str(rect)
		shots.append(shot2)
	sv.queue_free()
	return shots[0] if shots.size() == 1 else {"__raw": true, "images": shots}


## Hides visual geometry whose bottom is above `height` (world Y). Returns how many were hidden.
func _cutaway(n: Node, height: float) -> int:
	var count := 0
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is VisualInstance3D and (c as VisualInstance3D).visible:
			var a: AABB = (c as VisualInstance3D).global_transform * (c as VisualInstance3D).get_aabb()
			if a.position.y >= height - 0.01 or (a.size.y < 0.6 and a.get_center().y > height):
				(c as VisualInstance3D).visible = false
				count += 1
				continue
		for ch in c.get_children():
			stack.append(ch)
	return count


func _disable_envs(n: Node) -> void:
	for c in n.find_children("*", "WorldEnvironment", true, false):
		c.queue_free()


func _has_3d(n: Node) -> bool:
	if n is Node3D:
		return true
	for c in n.get_children():
		if _has_3d(c):
			return true
	return false


func _has_type(n: Node, type: String) -> bool:
	if n.is_class(type):
		return true
	for c in n.get_children():
		if _has_type(c, type):
			return true
	return false


func _aabb(n: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is VisualInstance3D and (c as VisualInstance3D).visible:
			var a: AABB = (c as VisualInstance3D).global_transform * (c as VisualInstance3D).get_aabb()
			if a.size.length() < 100000.0:
				result = a if first else result.merge(a)
				first = false
		for ch in c.get_children():
			stack.append(ch)
	return result


func _rect2d(n: Node) -> Rect2:
	var result := Rect2()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var r := Rect2()
		var has := false
		if c is Control and (c as Control).visible:
			r = (c as Control).get_global_rect()
			has = true
		elif c is Sprite2D or c is AnimatedSprite2D:
			if c is Sprite2D and c.texture:
				r = c.global_transform * (c as Sprite2D).get_rect()
				has = true
			elif c is AnimatedSprite2D and c.sprite_frames and c.sprite_frames.has_animation(c.animation) and c.sprite_frames.get_frame_count(c.animation) > 0:
				var tex: Texture2D = c.sprite_frames.get_frame_texture(c.animation, 0)
				if tex:
					var sz := tex.get_size()
					r = c.global_transform * Rect2(-sz / 2 if c.centered else Vector2.ZERO, sz)
					has = true
		elif c.is_class("TileMapLayer") and c.get("tile_set") != null:
			var used: Rect2i = c.get_used_rect()
			if used.size != Vector2i.ZERO:
				var ts: Vector2 = c.tile_set.tile_size
				r = c.global_transform * Rect2(Vector2(used.position) * ts, Vector2(used.size) * ts)
				has = true
		elif c is Polygon2D and (c as Polygon2D).polygon.size() > 0:
			var poly: PackedVector2Array = c.global_transform * (c as Polygon2D).polygon
			r = Rect2(poly[0], Vector2.ZERO)
			for pt in poly:
				r = r.expand(pt)
			has = true
		elif c is CollisionShape2D and c.shape:
			r = c.global_transform * c.shape.get_rect()
			has = true
		elif c is Node2D and c.get_child_count() == 0:
			r = Rect2(c.global_position - Vector2(8, 8), Vector2(16, 16))
			has = true
		if has:
			result = r if first else result.merge(r)
			first = false
		for ch in c.get_children():
			stack.append(ch)
	return result


func _disable_cameras(n: Node) -> void:
	if n is Camera2D:
		(n as Camera2D).enabled = false
	for c in n.get_children():
		_disable_cameras(c)


func _add_preview_lighting(sv: SubViewport) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.shadow_enabled = true
	sv.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# Neutral studio-like ground so renders read clearly from high angles.
	sky_mat.ground_bottom_color = Color(0.32, 0.34, 0.38)
	sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.72)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	sv.add_child(env)


## Screenshot of the running game (optionally annotated with node markers).
func a_game(p: Dictionary):
	return await ctx.runtime.request("screenshot", p, 15000)


## Generates thumbnail previews of resources (textures, meshes, scenes, materials).
func a_preview(p: Dictionary):
	var nd = _no_display()
	if nd: return nd
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not ResourceLoader.exists(path):
		return U.err("'%s' does not exist." % path)
	var res = load(path)
	if res is Texture2D:
		return U.image_to_b64(res.get_image(), U.p_int(p, "max_size", 512))
	if res is PackedScene:
		return await a_render({"scene": path, "angles": U.p_arr(p, "angles") if p.has("angles") else ["iso"], "size": [640, 480]})
	# Meshes and materials are rendered in a tiny temporary scene.
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		var holder_scene := Node3D.new()
		holder_scene.add_child(mi)
		mi.owner = holder_scene
		var ps := PackedScene.new()
		ps.pack(holder_scene)
		holder_scene.free()
		var tmp := "res://.godot/forge/_preview.tscn"
		ResourceSaver.save(ps, tmp)
		return await a_render({"scene": tmp, "angles": U.p_arr(p, "angles") if p.has("angles") else ["iso"], "size": [640, 480]})
	if res is Material:
		var mi2 := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.material = res
		mi2.mesh = sphere
		var hs := Node3D.new()
		hs.add_child(mi2)
		mi2.owner = hs
		var ps2 := PackedScene.new()
		ps2.pack(hs)
		hs.free()
		var tmp2 := "res://.godot/forge/_preview.tscn"
		ResourceSaver.save(ps2, tmp2)
		return await a_render({"scene": tmp2, "angles": ["front"], "size": [512, 512]})
	return U.err("No preview available for %s." % res.get_class())
