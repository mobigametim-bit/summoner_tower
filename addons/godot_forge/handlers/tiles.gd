@tool
extends "res://addons/godot_forge/handlers/base.gd"
## 2D tile maps: TileSet resources built from atlas images (collision, terrains, custom data)
## and TileMapLayer painting (cells, rects, lines, terrains, ASCII layouts). Never uses TileMap.

const NEIGHBORS := {
	"top": TileSet.CELL_NEIGHBOR_TOP_SIDE, "top_right": TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	"right": TileSet.CELL_NEIGHBOR_RIGHT_SIDE, "bottom_right": TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	"bottom": TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, "bottom_left": TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	"left": TileSet.CELL_NEIGHBOR_LEFT_SIDE, "top_left": TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
}
const NEIGHBOR_ALIASES := {"n": "top", "ne": "top_right", "e": "right", "se": "bottom_right", "s": "bottom", "sw": "bottom_left", "w": "left", "nw": "top_left", "up": "top", "down": "bottom"}
## Row-major order of a 3x3 mask string (center skipped).
const MASK_ORDER := ["top_left", "top", "top_right", "left", "", "right", "bottom_left", "bottom", "bottom_right"]
const NEIGHBOR_OFFSETS := {
	"top": Vector2i(0, -1), "top_right": Vector2i(1, -1), "right": Vector2i(1, 0), "bottom_right": Vector2i(1, 1),
	"bottom": Vector2i(0, 1), "bottom_left": Vector2i(-1, 1), "left": Vector2i(-1, 0), "top_left": Vector2i(-1, -1),
}
const TERRAIN_MODES := {
	"match_corners_and_sides": TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES,
	"corners_and_sides": TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES,
	"match_corners": TileSet.TERRAIN_MODE_MATCH_CORNERS, "corners": TileSet.TERRAIN_MODE_MATCH_CORNERS,
	"match_sides": TileSet.TERRAIN_MODE_MATCH_SIDES, "sides": TileSet.TERRAIN_MODE_MATCH_SIDES,
}
const DATA_TYPES := {
	"bool": TYPE_BOOL, "int": TYPE_INT, "float": TYPE_FLOAT, "string": TYPE_STRING, "vector2": TYPE_VECTOR2,
	"vector2i": TYPE_VECTOR2I, "vector3": TYPE_VECTOR3, "color": TYPE_COLOR, "string_name": TYPE_STRING_NAME,
	"array": TYPE_ARRAY, "dictionary": TYPE_DICTIONARY, "object": TYPE_OBJECT, "resource": TYPE_OBJECT,
}
const PALETTE := ["#4caf50", "#8d6e63", "#2196f3", "#ffc107", "#9c27b0", "#f44336", "#00bcd4", "#795548"]
const ASCII_AUTO := "#ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@$%&*+=~^"
const MAX_ASCII := 160
const MAX_CELLS_LISTED := 400


# ---------------------------------------------------------------------------
# TileSet creation / inspection
# ---------------------------------------------------------------------------

## Builds a TileSet .tres from an atlas image: one tile per non-empty cell, optional physics,
## terrains and custom data layers.
func a_create_tileset(p: Dictionary):
	var e = U.require(p, ["path", "texture"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if path.get_extension() == "":
		path += ".tres"
	if not path.get_extension() in ["tres", "res"]:
		return U.err("TileSet path must end in .tres or .res, got '%s'." % path)
	if FileAccess.file_exists(path) and not U.p_bool(p, "overwrite", false):
		return U.err("'%s' already exists." % path, "Pass overwrite=true to replace it, or use tiles.info to inspect it.")
	var tex_path := U.res_path(U.p_str(p, "texture"))
	var tex = await _load_texture(tex_path)
	if U.is_err(tex): return tex
	var tile_size := _v2i(p.get("tile_size", 16), Vector2i(16, 16))
	if tile_size.x <= 0 or tile_size.y <= 0:
		return U.err("tile_size must be positive, got %s." % tile_size)
	var separation := _v2i(p.get("separation", 0), Vector2i.ZERO)
	var margin := _v2i(p.get("margin", p.get("margins", 0)), Vector2i.ZERO)

	var ts := TileSet.new()
	ts.tile_size = tile_size
	if p.has("tile_shape"):
		var shape_names := {"square": TileSet.TILE_SHAPE_SQUARE, "isometric": TileSet.TILE_SHAPE_ISOMETRIC, "half_offset_square": TileSet.TILE_SHAPE_HALF_OFFSET_SQUARE, "hexagon": TileSet.TILE_SHAPE_HEXAGON}
		var sn := U.p_str(p, "tile_shape").to_lower()
		if not shape_names.has(sn):
			return U.err("Unknown tile_shape '%s'." % sn, "Use one of: " + ", ".join(shape_names.keys()))
		ts.tile_shape = shape_names[sn]
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = tile_size
	src.separation = separation
	src.margins = margin
	if p.has("texture_padding"):
		src.use_texture_padding = U.p_bool(p, "texture_padding")
	var source_id := ts.add_source(src, U.p_int(p, "source_id", 0))
	var grid := src.get_atlas_grid_size()
	if grid.x <= 0 or grid.y <= 0:
		return U.err("Texture %s is smaller than one tile (%s with margin %s)." % [tex.get_size(), tile_size, margin], "Check tile_size / margin.")

	# Tiles: every cell that has any visible pixel (or all cells).
	var all_tiles := U.p_bool(p, "all_tiles", false)
	var img: Image = null if all_tiles else _texture_image(tex, tex_path)
	var skipped := 0
	for y in grid.y:
		for x in grid.x:
			var c := Vector2i(x, y)
			if img != null:
				var region := Rect2i(margin + c * (tile_size + separation), tile_size)
				region = region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
				if region.size.x <= 0 or region.size.y <= 0 or img.get_region(region).is_invisible():
					skipped += 1
					continue
			src.create_tile(c)
	if src.get_tiles_count() == 0:
		return U.err("No non-empty tiles found in %s (every %s cell is fully transparent)." % [tex_path, tile_size], "Check tile_size/margin/separation, or pass all_tiles=true.")

	# Physics layers + collision polygons.
	var phys := U.p_arr(p, "physics_layers")
	var coll_tiles := U.p_arr(p, "collision_tiles")
	var full_collision := U.p_bool(p, "full_collision", false)
	if phys.is_empty() and (full_collision or not coll_tiles.is_empty()):
		phys = [{}]
	for i in phys.size():
		var spec = phys[i]
		if not (spec is Dictionary):
			return U.err("physics_layers entries must be objects like {\"collision_layer\": [1], \"collision_mask\": [1, 2]}.")
		ts.add_physics_layer()
		var lb = _bits(spec.get("collision_layer", spec.get("layer", 1)))
		if U.is_err(lb): return lb
		var mb = _bits(spec.get("collision_mask", spec.get("mask", 1)))
		if U.is_err(mb): return mb
		ts.set_physics_layer_collision_layer(i, lb)
		ts.set_physics_layer_collision_mask(i, mb)
		if spec.has("physics_material"):
			var pm = U.to_object(spec.physics_material, "PhysicsMaterial")
			if U.is_err(pm): return pm
			ts.set_physics_layer_physics_material(i, pm)
	var half := Vector2(tile_size) / 2.0
	var square := PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	var collided := 0
	if full_collision:
		for ti in src.get_tiles_count():
			_add_collision(src.get_tile_data(src.get_tile_id(ti), 0), square, false)
			collided += 1
	for item in coll_tiles:
		var coords: Vector2i
		var poly := square
		var one_way := false
		if item is Dictionary:
			coords = _coord_or_bad(item.get("tile", item.get("coords", null)))
			if item.has("points"):
				poly = U.coerce(item.points, TYPE_PACKED_VECTOR2_ARRAY)
			one_way = U.p_bool(item, "one_way", false)
		else:
			coords = _coord_or_bad(item)
		if not src.has_tile(coords):
			return _no_tile_err(src, coords, "collision_tiles")
		_add_collision(src.get_tile_data(coords, 0), poly, one_way)
		collided += 1

	# Custom data layers.
	for cd in U.p_arr(p, "custom_data"):
		if not (cd is Dictionary) or not cd.has("name"):
			return U.err("custom_data entries must be {name, type, values?}.", "Example: {\"name\": \"damage\", \"type\": \"int\", \"values\": {\"3,0\": 10}}")
		var tname := U.p_str(cd, "type", "int").to_lower()
		if not DATA_TYPES.has(tname):
			return U.err("Unknown custom data type '%s'." % tname, "Use one of: " + ", ".join(DATA_TYPES.keys()))
		ts.add_custom_data_layer()
		var li := ts.get_custom_data_layers_count() - 1
		ts.set_custom_data_layer_name(li, U.p_str(cd, "name"))
		ts.set_custom_data_layer_type(li, DATA_TYPES[tname])
		var values = cd.get("values", {})
		if values is Dictionary:
			for key in values:
				var vc := _coords_key(key)
				if not src.has_tile(vc):
					return _no_tile_err(src, vc, "custom_data '%s'" % cd.name)
				src.get_tile_data(vc, 0).set_custom_data_by_layer_id(li, U.coerce(values[key], DATA_TYPES[tname]))

	# Terrains.
	var terr = _build_terrains(ts, src, U.p_arr(p, "terrains"))
	if U.is_err(terr): return terr

	ctx.before_write([path])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	# An overwritten TileSet may be in use by open scenes: remember the old instance so its
	# layers can be pointed at the new one (otherwise they'd keep a path-less copy and embed it).
	var old_ts: Resource = ResourceLoader.get_cached_ref(path) if ResourceLoader.has_cached(path) else null
	var serr := ResourceSaver.save(ts, path)
	if serr != OK:
		return U.err("Failed to save '%s' (error %d)." % [path, serr])
	ts.take_over_path(path)
	ctx.fs().update_file(path)
	var relinked := 0
	if old_ts != null and old_ts != ts:
		for sroot in EditorInterface.get_open_scene_roots():
			var layers: Array = sroot.find_children("*", "TileMapLayer", true, false)
			if sroot is TileMapLayer:
				layers.append(sroot)
			for l in layers:
				if l.tile_set == old_ts:
					l.tile_set = ts
					relinked += 1
		if relinked > 0:
			ctx.mark_dirty()
	var out := {
		"path": path, "source_id": source_id, "tile_size": [tile_size.x, tile_size.y],
		"atlas_grid": [grid.x, grid.y], "tiles_created": src.get_tiles_count(), "empty_cells_skipped": skipped,
		"physics_layers": ts.get_physics_layers_count(), "tiles_with_collision": collided,
		"next": "Add a layer with tiles.create_layer {tileset: '%s'} then paint with tiles.from_ascii or tiles.paint." % path,
	}
	if relinked > 0:
		out["relinked_layers"] = relinked
	if not terr.is_empty():
		out["terrains"] = terr
	if ts.get_custom_data_layers_count() > 0:
		var names := []
		for i in ts.get_custom_data_layers_count():
			names.append(ts.get_custom_data_layer_name(i))
		out["custom_data"] = names
	return out


## Adds a collision polygon (tile-centered coordinates) on physics layer 0.
func _add_collision(td: TileData, poly: PackedVector2Array, one_way: bool) -> void:
	td.add_collision_polygon(0)
	var idx := td.get_collision_polygons_count(0) - 1
	td.set_collision_polygon_points(0, idx, poly)
	if one_way:
		td.set_collision_polygon_one_way(0, idx, true)


func _load_texture(tex_path: String):
	if not ResourceLoader.exists(tex_path):
		if FileAccess.file_exists(tex_path):
			# Freshly written image that hasn't been imported yet: scan and wait for the import.
			ctx.fs().scan()
			var start := Time.get_ticks_msec()
			while not ResourceLoader.exists(tex_path) and Time.get_ticks_msec() - start < 20000:
				await ctx.frame()
			await ctx.wait_fs()
		if not ResourceLoader.exists(tex_path):
			return U.err("Texture '%s' does not exist." % tex_path, "Use files.list pattern='*.png' to find images, or files.rescan after adding one.")
	var tex = load(tex_path)
	if not (tex is Texture2D):
		return U.err("'%s' is not a texture (got %s)." % [tex_path, tex.get_class() if tex else "null"])
	return tex


## Image data of a texture; reads the source file directly when possible (works headless).
func _texture_image(tex: Texture2D, tex_path: String) -> Image:
	var img: Image = null
	if tex_path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "bmp", "tga"] and FileAccess.file_exists(tex_path):
		img = Image.load_from_file(ProjectSettings.globalize_path(tex_path))
	if img == null or img.is_empty():
		img = tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	return img


func _no_tile_err(src: TileSetAtlasSource, coords: Vector2i, where: String) -> Dictionary:
	var g := src.get_atlas_grid_size()
	return U.err("%s: atlas has no tile at %s." % [where, coords], "Atlas grid is %dx%d (coords 0..%d, 0..%d); empty cells have no tile. Use tiles.info to list tiles." % [g.x, g.y, g.x - 1, g.y - 1])


## Creates terrain sets/terrains and assigns peering bits. Returns {name: {terrain_set, terrain}} or error.
func _build_terrains(ts: TileSet, src: TileSetAtlasSource, terrains: Array):
	var out := {}
	var set_for_mode := {}
	var pending := []
	for i in terrains.size():
		var t = terrains[i]
		if not (t is Dictionary) or not t.has("name"):
			return U.err("terrains entries must be {name, color?, mode?, tiles?, block?}.", "Example: {\"name\": \"grass\", \"mode\": \"match_corners_and_sides\", \"block\": [0, 0]}")
		var mode_name := U.p_str(t, "mode", "match_corners_and_sides").to_lower()
		if not TERRAIN_MODES.has(mode_name):
			return U.err("Unknown terrain mode '%s'." % mode_name, "Use match_corners_and_sides, match_sides or match_corners.")
		var mode: int = TERRAIN_MODES[mode_name]
		var set_idx: int
		if t.has("terrain_set"):
			set_idx = U.p_int(t, "terrain_set")
			while ts.get_terrain_sets_count() <= set_idx:
				ts.add_terrain_set()
				ts.set_terrain_set_mode(ts.get_terrain_sets_count() - 1, mode)
		elif set_for_mode.has(mode):
			set_idx = set_for_mode[mode]
		else:
			ts.add_terrain_set()
			set_idx = ts.get_terrain_sets_count() - 1
			ts.set_terrain_set_mode(set_idx, mode)
			set_for_mode[mode] = set_idx
		ts.add_terrain(set_idx)
		var t_idx := ts.get_terrains_count(set_idx) - 1
		ts.set_terrain_name(set_idx, t_idx, U.p_str(t, "name"))
		ts.set_terrain_color(set_idx, t_idx, U.to_color(t.get("color", PALETTE[i % PALETTE.size()])))
		out[U.p_str(t, "name")] = {"terrain_set": set_idx, "terrain": t_idx, "mode": mode_name}
		pending.append([t, set_idx, t_idx])
	# Assign tiles once every terrain exists (tile specs may reference other terrains by name).
	for item in pending:
		var t: Dictionary = item[0]
		var set_idx: int = item[1]
		var t_idx: int = item[2]
		var count := 0
		if t.has("block"):
			var b = t.block
			var origin: Vector2i
			var size := Vector2i(3, 3)
			if b is Dictionary:
				origin = U.to_vector(b.get("origin", [0, 0]), TYPE_VECTOR2I)
				size = _v2i(b.get("size", [3, 3]), size)
			else:
				origin = U.to_vector(b, TYPE_VECTOR2I)
			for by in size.y:
				for bx in size.x:
					var coords := origin + Vector2i(bx, by)
					if not src.has_tile(coords):
						return _no_tile_err(src, coords, "terrain '%s' block" % t.name)
					var bits := []
					for nname in NEIGHBOR_OFFSETS:
						var nb: Vector2i = Vector2i(bx, by) + NEIGHBOR_OFFSETS[nname]
						if nb.x >= 0 and nb.y >= 0 and nb.x < size.x and nb.y < size.y:
							bits.append(nname)
					_apply_bits(src.get_tile_data(coords, 0), set_idx, t_idx, bits)
					count += 1
		var tiles = t.get("tiles", null)
		if tiles is Array:
			for c in tiles:
				var coords := _coord_or_bad(c) as Vector2i
				if not src.has_tile(coords):
					return _no_tile_err(src, coords, "terrain '%s'" % t.name)
				_apply_bits(src.get_tile_data(coords, 0), set_idx, t_idx, NEIGHBORS.keys())
				count += 1
		elif tiles is Dictionary:
			for key in tiles:
				var coords := _coords_key(key)
				if not src.has_tile(coords):
					return _no_tile_err(src, coords, "terrain '%s'" % t.name)
				var td := src.get_tile_data(coords, 0)
				var spec = tiles[key]
				if spec is Dictionary:
					var r = _apply_bit_map(ts, td, set_idx, t_idx, spec)
					if U.is_err(r): return r
				else:
					var bits = _parse_bits(spec)
					if U.is_err(bits): return bits
					_apply_bits(td, set_idx, t_idx, bits)
				count += 1
		elif tiles != null:
			return U.err("terrain '%s': tiles must be a list of [x,y] (fully this terrain) or {\"x,y\": bits}." % t.name)
		out[t.name]["tiles"] = count
	return out


func _apply_bits(td: TileData, set_idx: int, t_idx: int, bits: Array) -> void:
	td.terrain_set = set_idx
	td.terrain = t_idx
	for nname in bits:
		var bit: int = NEIGHBORS[nname]
		if td.is_valid_terrain_peering_bit(bit):
			td.set_terrain_peering_bit(bit, t_idx)


## {"center": "grass", "top": "dirt", ...} per-bit terrain assignment (names or indices, -1/null = empty).
func _apply_bit_map(ts: TileSet, td: TileData, set_idx: int, t_idx: int, spec: Dictionary):
	td.terrain_set = set_idx
	td.terrain = t_idx
	for key in spec:
		var k := _neighbor_name(str(key))
		var tv = _terrain_index(ts, set_idx, spec[key])
		if U.is_err(tv): return tv
		if str(key) == "center" or str(key) == "terrain":
			td.terrain = tv
			continue
		if k == "":
			return U.err("Unknown neighbor '%s'." % key, "Use center, top, top_right, right, bottom_right, bottom, bottom_left, left, top_left.")
		var bit: int = NEIGHBORS[k]
		if td.is_valid_terrain_peering_bit(bit):
			td.set_terrain_peering_bit(bit, tv)
	return null


func _terrain_index(ts: TileSet, set_idx: int, v):
	if v == null:
		return -1
	if v is float or v is int:
		return int(v)
	var s := str(v)
	if s.is_valid_int():
		return s.to_int()
	var names := []
	for i in ts.get_terrains_count(set_idx):
		names.append(ts.get_terrain_name(set_idx, i))
		if ts.get_terrain_name(set_idx, i) == s:
			return i
	var sg := U.suggest(s, names)
	return U.err("Terrain '%s' not found in terrain set %d." % [s, set_idx], ("Did you mean '%s'? " % sg if sg != "" else "") + "Terrains: " + ", ".join(names))


func _neighbor_name(s: String) -> String:
	s = s.to_lower().replace("-", "_").replace(" ", "_")
	if NEIGHBOR_ALIASES.has(s):
		s = NEIGHBOR_ALIASES[s]
	return s if NEIGHBORS.has(s) else ""


## "all" | ["top", "right", ...] | "111/1.1/000" 3x3 mask -> neighbor names.
func _parse_bits(spec):
	if spec == null or (spec is bool and spec) or (spec is String and spec.to_lower() in ["all", "full", "center"]):
		return NEIGHBORS.keys() if not (spec is String and spec.to_lower() == "center") else []
	if spec is Array:
		var out := []
		for s in spec:
			var n := _neighbor_name(str(s))
			if n == "":
				return U.err("Unknown neighbor '%s'." % s, "Use top, top_right, right, bottom_right, bottom, bottom_left, left, top_left.")
			out.append(n)
		return out
	if spec is String:
		var m: String = spec.replace("/", "").replace("\n", "").replace(" ", "").replace("|", "")
		if m.length() == 9:
			var out2 := []
			for i in 9:
				if MASK_ORDER[i] != "" and m[i] in ["1", "#", "x", "X", "*"]:
					out2.append(MASK_ORDER[i])
			return out2
	return U.err("Bad terrain bits %s." % JSON.stringify(spec), "Use \"all\", a list like [\"right\", \"bottom\", \"bottom_right\"], or a 3x3 mask \"000/011/011\" (row-major, 1 = same terrain).")


func a_info(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.p_str(p, "path")
	var ts: TileSet = null
	var out := {}
	if path.begins_with("res://") or path.begins_with("uid://") or path.ends_with(".tres") or path.ends_with(".res"):
		var rp := U.res_path(path)
		if not ResourceLoader.exists(rp):
			return U.err("TileSet '%s' does not exist." % rp, "Create one with tiles.create_tileset.")
		var r = load(rp)
		if not (r is TileSet):
			return U.err("'%s' is a %s, not a TileSet." % [rp, r.get_class()])
		ts = r
		out["path"] = rp
	else:
		var layer = await _layer(p)
		if U.is_err(layer): return layer
		ts = layer.tile_set
		var used: Rect2i = layer.get_used_rect()
		out["layer"] = {"path": ctx.node_path_str(layer), "used_cells": layer.get_used_cells().size(), "used_rect": [used.position.x, used.position.y, used.size.x, used.size.y], "enabled": layer.enabled, "collision_enabled": layer.collision_enabled}
		if ts == null:
			out["tileset"] = null
			out["hint"] = "This layer has no tile_set; create one with tiles.create_tileset and assign it via node.set {props: {tile_set: 'res://...'}}."
			return out
		out["tileset_path"] = ts.resource_path
	out.merge(_tileset_info(ts, U.p_bool(p, "tiles", true)))
	return out


func _tileset_info(ts: TileSet, list_tiles: bool) -> Dictionary:
	var out := {"tile_size": [ts.tile_size.x, ts.tile_size.y], "tile_shape": ["square", "isometric", "half_offset_square", "hexagon"][ts.tile_shape]}
	var sources := []
	for i in ts.get_source_count():
		var sid := ts.get_source_id(i)
		var s := ts.get_source(sid)
		var sd := {"id": sid, "type": s.get_class(), "tile_count": s.get_tiles_count()}
		if s is TileSetAtlasSource:
			var a: TileSetAtlasSource = s
			var g := a.get_atlas_grid_size()
			sd["texture"] = a.texture.resource_path if a.texture else null
			sd["atlas_grid"] = [g.x, g.y]
			sd["region_size"] = [a.texture_region_size.x, a.texture_region_size.y]
			if a.separation != Vector2i.ZERO:
				sd["separation"] = [a.separation.x, a.separation.y]
			if a.margins != Vector2i.ZERO:
				sd["margins"] = [a.margins.x, a.margins.y]
			if list_tiles:
				var tiles := []
				var details := {}
				for ti in mini(a.get_tiles_count(), 512):
					var c := a.get_tile_id(ti)
					tiles.append([c.x, c.y])
					var td := a.get_tile_data(c, 0)
					var extra := {}
					if ts.get_physics_layers_count() > 0 and td.get_collision_polygons_count(0) > 0:
						extra["collision"] = true
					if td.terrain_set >= 0 and td.terrain >= 0:
						extra["terrain"] = ts.get_terrain_name(td.terrain_set, td.terrain)
					for ci in ts.get_custom_data_layers_count():
						var v = td.get_custom_data_by_layer_id(ci)
						if v != null and v != type_convert(null, ts.get_custom_data_layer_type(ci)):
							extra[ts.get_custom_data_layer_name(ci)] = U.encode(v)
					if a.get_alternative_tiles_count(c) > 1:
						extra["alternatives"] = a.get_alternative_tiles_count(c)
					if a.get_tile_size_in_atlas(c) != Vector2i.ONE:
						extra["size_in_atlas"] = [a.get_tile_size_in_atlas(c).x, a.get_tile_size_in_atlas(c).y]
					if not extra.is_empty():
						details["%d,%d" % [c.x, c.y]] = extra
				sd["tiles"] = tiles
				if not details.is_empty():
					sd["tile_details"] = details
		elif s is TileSetScenesCollectionSource:
			var sc: TileSetScenesCollectionSource = s
			var scenes := []
			for ti in sc.get_scene_tiles_count():
				var tid := sc.get_scene_tile_id(ti)
				var ps = sc.get_scene_tile_scene(tid)
				scenes.append({"id": tid, "scene": ps.resource_path if ps else null})
			sd["scenes"] = scenes
		sources.append(sd)
	out["sources"] = sources
	var phys := []
	for i in ts.get_physics_layers_count():
		phys.append({"collision_layer": ts.get_physics_layer_collision_layer(i), "collision_mask": ts.get_physics_layer_collision_mask(i)})
	out["physics_layers"] = phys
	var tsets := []
	for si in ts.get_terrain_sets_count():
		var names := []
		for ti in ts.get_terrains_count(si):
			names.append({"terrain": ti, "name": ts.get_terrain_name(si, ti), "color": "#" + ts.get_terrain_color(si, ti).to_html(false)})
		tsets.append({"terrain_set": si, "mode": ["match_corners_and_sides", "match_corners", "match_sides"][ts.get_terrain_set_mode(si)], "terrains": names})
	out["terrain_sets"] = tsets
	var cds := []
	for i in ts.get_custom_data_layers_count():
		cds.append({"name": ts.get_custom_data_layer_name(i), "type": type_string(ts.get_custom_data_layer_type(i))})
	out["custom_data"] = cds
	out["navigation_layers"] = ts.get_navigation_layers_count()
	out["occlusion_layers"] = ts.get_occlusion_layers_count()
	return out


# ---------------------------------------------------------------------------
# Layers
# ---------------------------------------------------------------------------

func a_create_layer(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var parent: Node = ctx.find_node(U.p_str(p, "parent", "."))
	if parent == null:
		return ctx.node_not_found(U.p_str(p, "parent"))
	var layer := TileMapLayer.new()
	layer.name = U.p_str(p, "name", "TileMapLayer")
	var tsp := U.p_str(p, "tileset", U.p_str(p, "tile_set", ""))
	if tsp != "":
		var rp := U.res_path(tsp)
		var ts = load(rp) if ResourceLoader.exists(rp) else null
		if not (ts is TileSet):
			layer.free()
			return U.err("TileSet '%s' not found." % rp, "Create one with tiles.create_tileset, or list them with files.list pattern='*.tres'.")
		layer.tile_set = ts
	if p.has("props"):
		var pr = U.apply_props(layer, U.p_dict(p, "props"))
		if U.is_err(pr):
			layer.free()
			return pr
	if p.has("position"):
		layer.position = U.to_vector(p.position, TYPE_VECTOR2)
	var u = ctx.begin("Add TileMapLayer")
	u.add_do_method(parent, "add_child", layer, true)
	if p.has("index"):
		u.add_do_method(parent, "move_child", layer, U.p_int(p, "index"))
	u.add_do_method(ctx.router.handlers["node"], "set_owner_rec", layer, root)
	u.add_do_reference(layer)
	u.add_undo_method(parent, "remove_child", layer)
	ctx.commit()
	var out := {"path": ctx.node_path_str(layer), "tileset": layer.tile_set.resource_path if layer.tile_set else null}
	if layer.tile_set == null:
		out["warning"] = "No tileset assigned; pass tileset or set tile_set before painting."
	return out


# ---------------------------------------------------------------------------
# Painting
# ---------------------------------------------------------------------------

func _layer(p: Dictionary, need_tileset: bool = false):
	var n = await node_arg(p)
	if U.is_err(n): return n
	if n.get_class() == "TileMap":
		return U.err("'%s' is a deprecated TileMap node." % ctx.node_path_str(n), "Use TileMapLayer nodes instead (tiles.create_layer); in the editor, the TileMap bottom panel can extract its layers.")
	if not (n is TileMapLayer):
		var hint := "Pass the path of a TileMapLayer node."
		var found := []
		for c in n.find_children("*", "TileMapLayer", true, false):
			found.append(ctx.node_path_str(c))
		if not found.is_empty():
			hint += " TileMapLayers under it: " + ", ".join(found.slice(0, 10))
		return U.err("'%s' is a %s, not a TileMapLayer." % [ctx.node_path_str(n), n.get_class()], hint)
	if need_tileset and n.tile_set == null:
		return U.err("TileMapLayer '%s' has no tile_set." % ctx.node_path_str(n), "Assign one: node.set {path: '%s', props: {tile_set: 'res://tileset.tres'}} or create it with tiles.create_tileset." % ctx.node_path_str(n))
	return n


## Cells from {cell | cells | rect | line}. Returns Array[Vector2i] or error.
func _cells(p: Dictionary, required: bool = true):
	var out: Array[Vector2i] = []
	if p.has("cell"):
		var c1 = _coord(p.cell)
		if c1 == null:
			return U.err("cell must be [x, y], got %s." % JSON.stringify(p.cell))
		out.append(c1)
	var raw_cells = p.get("cells", [])
	if raw_cells is Array and raw_cells.size() == 2 and (raw_cells[0] is float or raw_cells[0] is int):
		raw_cells = [raw_cells]  # a single [x, y] pair passed as cells
	for c in (raw_cells if raw_cells is Array else [raw_cells]):
		var cv = _coord(c)
		if cv == null:
			return U.err("cells must be a list of [x, y] pairs, got %s." % JSON.stringify(c), "Example: cells: [[0, 0], [1, 0]]. For areas use rect: [x, y, w, h].")
		out.append(cv)
	if p.has("rect"):
		var r = _rect(p.rect)
		if U.is_err(r): return r
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				out.append(Vector2i(x, y))
	if p.has("line"):
		var pts := U.p_arr(p, "line")
		if pts.size() < 2:
			return U.err("line needs at least two points: [[x1, y1], [x2, y2]].")
		for pt in pts:
			if _coord(pt) == null:
				return U.err("line points must be [x, y], got %s." % JSON.stringify(pt), "Example: line: [[0, 5], [10, 5]].")
		for i in range(pts.size() - 1):
			var seg := _bresenham(_coord(pts[i]), _coord(pts[i + 1]))
			if i > 0:
				seg.remove_at(0)
			out.append_array(seg)
	if out.is_empty() and required:
		return U.err("No cells given.", "Pass cells: [[x, y], ...], rect: [x, y, w, h] or line: [[x1, y1], [x2, y2]]. Coordinates are map cells, not pixels.")
	return out


func _rect(v):
	if v is Array and v.size() == 4:
		var r := Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3]))
		if r.size.x <= 0 or r.size.y <= 0:
			return U.err("rect width/height must be positive: [x, y, w, h].")
		if r.size.x * r.size.y > 1000000:
			return U.err("rect covers %d cells; limit is 1,000,000." % (r.size.x * r.size.y))
		return r
	return U.err("rect must be [x, y, width, height] in cells, got %s." % JSON.stringify(v))


func _bresenham(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var c := a
	while true:
		out.append(c)
		if c == b or out.size() > 100000:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			c.x += sx
		if e2 <= dx:
			err += dx
			c.y += sy
	return out


## Resolves {tile, source?, alternative?} against the tileset. Returns [source_id, Array[Vector2i] tiles, alt] or error.
func _tile_arg(layer: TileMapLayer, p: Dictionary, key: String = "tile"):
	var ts: TileSet = layer.tile_set
	if ts.get_source_count() == 0:
		return U.err("The layer's TileSet has no sources.", "Build it with tiles.create_tileset.")
	var sid := U.p_int(p, "source", ts.get_source_id(0))
	if not ts.has_source(sid):
		var ids := []
		for i in ts.get_source_count():
			ids.append(ts.get_source_id(i))
		return U.err("TileSet has no source %d." % sid, "Sources: %s" % str(ids))
	if not p.has(key):
		return U.err("Missing '%s': atlas coords [x, y] of the tile to paint." % key, "Use tiles.info on the layer to list available tile coords.")
	var raw = p[key]
	var list: Array[Vector2i] = []
	for t in (raw if raw is Array and not raw.is_empty() and not (raw[0] is float or raw[0] is int) else [raw]):
		var tc = _coord(t)
		if tc == null:
			var hint := "Use atlas coords like [3, 0] (see tiles.info)."
			if t is String and ts.get_terrain_sets_count() > 0:
				hint += " For autotiled terrain use tiles.terrain {terrain: '%s'} (or a {terrain: name} legend entry in from_ascii)." % t
			return U.err("%s must be atlas coords [x, y], got %s." % [key, JSON.stringify(t)], hint)
		list.append(tc)
	var src := ts.get_source(sid)
	var alt := U.p_int(p, "alternative", 0)
	for c in list:
		if not src.has_tile(c):
			if src is TileSetAtlasSource:
				return _no_tile_err(src, c, key)
			return U.err("Source %d has no tile %s." % [sid, c])
		if not src.has_alternative_tile(c, alt):
			return U.err("Tile %s has no alternative %d." % [c, alt], "Alternatives: 0..%d" % (src.get_alternative_tiles_count(c) - 1))
	return [sid, list, alt]


func _commit_paint(layer: TileMapLayer, before: PackedByteArray, action: String) -> void:
	var after: PackedByteArray = layer.tile_map_data
	var u = ctx.begin(action)
	u.add_do_property(layer, "tile_map_data", after)
	u.add_undo_property(layer, "tile_map_data", before)
	ctx.commit()


func _set_cells(layer: TileMapLayer, cells: Array, t: Array) -> void:
	var tiles: Array = t[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cells.size())
	for c in cells:
		var tile: Vector2i = tiles[0] if tiles.size() == 1 else tiles[rng.randi() % tiles.size()]
		layer.set_cell(c, t[0], tile, t[2])


func a_paint(p: Dictionary):
	var layer = await _layer(p, true)
	if U.is_err(layer): return layer
	var cells = _cells(p)
	if U.is_err(cells): return cells
	var t = _tile_arg(layer, p)
	if U.is_err(t): return t
	var before: PackedByteArray = layer.tile_map_data
	_set_cells(layer, cells, t)
	_commit_paint(layer, before, "Paint %d tiles" % cells.size())
	return {"path": ctx.node_path_str(layer), "painted": cells.size(), "used_cells": layer.get_used_cells().size()}


## Fills a rect, optionally with a different border tile or hollow (walls only).
func a_fill_rect(p: Dictionary):
	var layer = await _layer(p, true)
	if U.is_err(layer): return layer
	if not p.has("rect"):
		return U.err("Missing 'rect': [x, y, width, height] in cells.")
	var r = _rect(p.rect)
	if U.is_err(r): return r
	var t = _tile_arg(layer, p)
	if U.is_err(t): return t
	var border = null
	if p.has("border"):
		border = _tile_arg(layer, p, "border")
		if U.is_err(border): return border
	var hollow := U.p_bool(p, "hollow", false)
	var before: PackedByteArray = layer.tile_map_data
	var inner: Array[Vector2i] = []
	var edge: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var on_edge: bool = x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			if on_edge:
				edge.append(Vector2i(x, y))
			else:
				inner.append(Vector2i(x, y))
	if hollow:
		_set_cells(layer, edge, border if border != null else t)
		for c in inner:
			layer.erase_cell(c)
	else:
		_set_cells(layer, inner, t)
		_set_cells(layer, edge, border if border != null else t)
	_commit_paint(layer, before, "Fill rect")
	return {"path": ctx.node_path_str(layer), "painted": edge.size() + (0 if hollow else inner.size()), "rect": [r.position.x, r.position.y, r.size.x, r.size.y]}


func a_erase(p: Dictionary):
	var layer = await _layer(p)
	if U.is_err(layer): return layer
	var cells = _cells(p)
	if U.is_err(cells): return cells
	var before: PackedByteArray = layer.tile_map_data
	var erased := 0
	for c in cells:
		if layer.get_cell_source_id(c) != -1:
			erased += 1
		layer.erase_cell(c)
	_commit_paint(layer, before, "Erase %d tiles" % erased)
	return {"path": ctx.node_path_str(layer), "erased": erased, "used_cells": layer.get_used_cells().size()}


func a_clear(p: Dictionary):
	var layer = await _layer(p)
	if U.is_err(layer): return layer
	var n: int = layer.get_used_cells().size()
	var before: PackedByteArray = layer.tile_map_data
	layer.clear()
	_commit_paint(layer, before, "Clear tiles")
	return {"path": ctx.node_path_str(layer), "cleared": n}


## Paints with terrain autotiling (set_cells_terrain_connect / _path).
func a_terrain(p: Dictionary):
	var layer = await _layer(p, true)
	if U.is_err(layer): return layer
	var ts: TileSet = layer.tile_set
	if ts.get_terrain_sets_count() == 0:
		return U.err("The TileSet has no terrains.", "Recreate it with tiles.create_tileset {terrains: [{name, block: [x, y]}]} or set terrains up in the TileSet editor.")
	var cells = _cells(p)
	if U.is_err(cells): return cells
	var resolved = _resolve_terrain(ts, p.get("terrain", 0), p.get("terrain_set", null))
	if U.is_err(resolved): return resolved
	var before: PackedByteArray = layer.tile_map_data
	var mode := U.p_str(p, "mode", "connect")
	var cells_typed: Array[Vector2i] = cells
	if mode == "path":
		layer.set_cells_terrain_path(cells_typed, resolved[0], resolved[1], U.p_bool(p, "ignore_empty_terrains", true))
	else:
		layer.set_cells_terrain_connect(cells_typed, resolved[0], resolved[1], U.p_bool(p, "ignore_empty_terrains", true))
	_commit_paint(layer, before, "Paint terrain")
	var missing := 0
	for c in cells_typed:
		if layer.get_cell_source_id(c) == -1:
			missing += 1
	var out := {"path": ctx.node_path_str(layer), "terrain_set": resolved[0], "terrain": resolved[1]}
	if resolved[1] < 0:
		out["erased"] = missing
	else:
		out["painted"] = cells_typed.size() - missing
	if missing > 0 and resolved[1] >= 0:
		out["warning"] = "%d cells got no tile: the terrain has no tile matching those neighbor combinations. Add more terrain tiles (e.g. a 3x3 block) or paint larger areas." % missing
	return out


## terrain: index or name; terrain_set optional (searched when a name is given). Returns [set, terrain].
func _resolve_terrain(ts: TileSet, terrain, terrain_set):
	if terrain == null or (terrain is float or terrain is int) or (terrain is String and terrain.is_valid_int()):
		var si := int(terrain_set) if terrain_set != null else 0
		var ti := int(terrain) if terrain != null else -1
		if si < 0 or si >= ts.get_terrain_sets_count():
			return U.err("Terrain set %d does not exist (TileSet has %d)." % [si, ts.get_terrain_sets_count()])
		if ti >= ts.get_terrains_count(si):
			return U.err("Terrain %d does not exist in set %d (has %d)." % [ti, si, ts.get_terrains_count(si)], "Use tiles.info to list terrains, or pass the terrain name.")
		return [si, ti]
	var name := str(terrain)
	var all := []
	for si2 in ts.get_terrain_sets_count():
		if terrain_set != null and int(terrain_set) != si2:
			continue
		for ti2 in ts.get_terrains_count(si2):
			all.append(ts.get_terrain_name(si2, ti2))
			if ts.get_terrain_name(si2, ti2) == name:
				return [si2, ti2]
	var s := U.suggest(name, all)
	return U.err("Terrain '%s' not found." % name, ("Did you mean '%s'? " % s if s != "" else "") + "Terrains: " + ", ".join(all))


## Paints from an ASCII layout: rows + legend {char: [ax, ay] | null | {tile, source, alternative} | {terrain}}.
func a_from_ascii(p: Dictionary):
	var layer = await _layer(p, true)
	if U.is_err(layer): return layer
	var rows = p.get("rows", null)
	if rows is String:
		rows = rows.split("\n")
	if not (rows is Array or rows is PackedStringArray) or rows.is_empty():
		return U.err("Missing 'rows': list of strings, one per map row, e.g. [\"#####\", \"#...#\", \"#####\"].")
	var legend := U.p_dict(p, "legend")
	if legend.is_empty():
		return U.err("Missing 'legend': {char: [atlas_x, atlas_y]}.", "Example: {\"#\": [0, 0], \".\": null} (null = erase). Use {\"terrain\": \"grass\"} for autotiled cells.")
	var ts: TileSet = layer.tile_set
	var origin: Vector2i = U.to_vector(p.get("origin", [0, 0]), TYPE_VECTOR2I)
	# Resolve legend entries.
	var resolved := {}
	for ch in legend:
		var v = legend[ch]
		var key := str(ch)
		if key.length() != 1:
			return U.err("Legend keys must be single characters, got '%s'." % key)
		if v == null or (v is String and v in ["", "erase", "empty"]):
			resolved[key] = {"erase": true}
		elif v is Dictionary and v.has("terrain"):
			var rt = _resolve_terrain(ts, v.terrain, v.get("terrain_set", null))
			if U.is_err(rt):
				return _prefix(rt, "legend '%s': " % key)
			resolved[key] = {"terrain": rt}
		elif v is String and v != "" and not v.contains(",") and ts.get_terrain_sets_count() > 0:
			var rt2 = _resolve_terrain(ts, v, null)
			if U.is_err(rt2):
				return _prefix(rt2, "legend '%s': " % key)
			resolved[key] = {"terrain": rt2}
		else:
			var spec: Dictionary = v if v is Dictionary else {"tile": v}
			var t = _tile_arg(layer, spec)
			if U.is_err(t):
				return _prefix(t, "legend '%s': " % key)
			resolved[key] = {"tile": t}
	var before: PackedByteArray = layer.tile_map_data
	if U.p_bool(p, "clear", false):
		layer.clear()
	var painted := 0
	var erased := 0
	var terrain_cells := {}
	var unknown := {}
	for y in rows.size():
		var row := str(rows[y])
		for x in row.length():
			var ch := row[x]
			var c := origin + Vector2i(x, y)
			if not resolved.has(ch):
				if ch != " ":
					unknown[ch] = true
				continue
			var r: Dictionary = resolved[ch]
			if r.has("erase"):
				layer.erase_cell(c)
				erased += 1
			elif r.has("terrain"):
				var tkey := "%d:%d" % [r.terrain[0], r.terrain[1]]
				if not terrain_cells.has(tkey):
					terrain_cells[tkey] = [r.terrain, [] as Array[Vector2i]]
				terrain_cells[tkey][1].append(c)
			else:
				_set_cells(layer, [c], r.tile)
				painted += 1
	if not unknown.is_empty():
		layer.tile_map_data = before
		return U.err("Characters not in legend: %s." % " ".join(unknown.keys()), "Add them to legend (null = erase) or use a space to leave a cell untouched.")
	var no_match := 0
	for tkey in terrain_cells:
		var item: Array = terrain_cells[tkey]
		var cells_t: Array[Vector2i] = item[1]
		layer.set_cells_terrain_connect(cells_t, item[0][0], item[0][1], true)
		for tc in cells_t:
			if layer.get_cell_source_id(tc) == -1:
				no_match += 1
			else:
				painted += 1
	_commit_paint(layer, before, "Paint ASCII layout")
	var width := 0
	for row in rows:
		width = maxi(width, str(row).length())
	var out := {"path": ctx.node_path_str(layer), "painted": painted, "erased": erased, "size": [width, rows.size()], "origin": [origin.x, origin.y], "used_cells": layer.get_used_cells().size()}
	if no_match > 0:
		out["warning"] = "%d terrain cells got no tile: the terrain has no tile for those neighbor combinations (e.g. 1-cell-wide strips with a 3x3 block terrain). Make terrain areas at least 2x2, or add tiles for thin/inner-corner cases." % no_match
	return out


## Reads used cells (+ an ASCII picture). legend {char: [ax, ay]} maps tiles back to characters.
func a_read(p: Dictionary):
	var layer = await _layer(p)
	if U.is_err(layer): return layer
	var used: Rect2i = layer.get_used_rect()
	var r: Rect2i = used
	if p.has("rect"):
		var rr = _rect(p.rect)
		if U.is_err(rr): return rr
		r = rr
	var out := {"path": ctx.node_path_str(layer), "used_rect": [used.position.x, used.position.y, used.size.x, used.size.y], "used_cells": layer.get_used_cells().size()}
	if r.size.x <= 0 or r.size.y <= 0:
		out["ascii"] = []
		return out
	# Reverse legend: "source:x,y:alt" -> char.
	# Accepts the same legend as from_ascii, so a layout can be read back with its own legend.
	var rev := {}
	var legend := U.p_dict(p, "legend")
	var tset: TileSet = layer.tile_set
	var empty_ch := "."
	for ch in legend:
		var v = legend[ch]
		if v == null or (v is String and v in ["", "erase", "empty"]):
			empty_ch = str(ch)
			continue
		if tset == null:
			continue
		var spec: Dictionary = v if v is Dictionary else {"tile": v}
		if spec.has("tile") and _coord(spec.tile) == null and spec.tile is String:
			spec = {"terrain": spec.tile}  # bare terrain name, e.g. "g": "grass"
		if spec.has("terrain"):
			var rt = _resolve_terrain(tset, spec.terrain, spec.get("terrain_set", null))
			if U.is_err(rt):
				return _prefix(rt, "legend '%s': " % ch)
			rev["t:%d:%d" % [rt[0], rt[1]]] = str(ch)
		elif spec.has("tile"):
			var c: Vector2i = _coord(spec.tile)
			var def_sid: int = tset.get_source_id(0) if tset.get_source_count() > 0 else 0
			rev["%d:%d,%d:%d" % [int(spec.get("source", def_sid)), c.x, c.y, int(spec.get("alternative", 0))]] = str(ch)
	var auto := {}
	var auto_i := 0
	var cells := []
	var rows := []
	var draw := r.size.x <= MAX_ASCII and r.size.y <= MAX_ASCII
	for y in range(r.position.y, r.end.y):
		var line := ""
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var sid: int = layer.get_cell_source_id(c)
			if sid == -1:
				line += empty_ch
				continue
			var ac: Vector2i = layer.get_cell_atlas_coords(c)
			var alt: int = layer.get_cell_alternative_tile(c)
			var key := "%d:%d,%d:%d" % [sid, ac.x, ac.y, alt]
			var ch = rev.get(key, null)
			if ch == null:
				var td: TileData = layer.get_cell_tile_data(c)
				if td and td.terrain_set >= 0 and td.terrain >= 0:
					ch = rev.get("t:%d:%d" % [td.terrain_set, td.terrain], null)
			if ch == null:
				if not auto.has(key):
					# Skip characters the caller's legend (or the empty char) already uses.
					while auto_i < ASCII_AUTO.length() - 1 and (legend.has(ASCII_AUTO[auto_i]) or ASCII_AUTO[auto_i] == empty_ch):
						auto_i += 1
					auto[key] = ASCII_AUTO[auto_i % ASCII_AUTO.length()]
					auto_i += 1
				ch = auto[key]
			line += ch
			if cells.size() < MAX_CELLS_LISTED:
				var cd := {"cell": [x, y], "tile": [ac.x, ac.y]}
				if sid != 0:
					cd["source"] = sid
				if alt != 0:
					cd["alternative"] = alt
				cells.append(cd)
		if draw:
			rows.append(line)
	out["rect"] = [r.position.x, r.position.y, r.size.x, r.size.y]
	if draw:
		out["ascii"] = rows
		out["empty_char"] = empty_ch
	else:
		out["ascii_skipped"] = "Area is larger than %dx%d; pass rect to read a window." % [MAX_ASCII, MAX_ASCII]
	if not auto.is_empty():
		var al := {}
		for k in auto:
			var parts: PackedStringArray = k.split(":")
			var xy: PackedStringArray = parts[1].split(",")
			var entry := {"tile": [int(xy[0]), int(xy[1])]}
			if parts[0] != "0":
				entry["source"] = int(parts[0])
			if parts[2] != "0":
				entry["alternative"] = int(parts[2])
			al[auto[k]] = entry if entry.size() > 1 else entry.tile
		out["auto_legend"] = al
	if U.p_bool(p, "cells", false) or r.size.x * r.size.y <= 64:
		out["cells"] = cells
	return out


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Strict [x, y] / "x,y" / {x, y} / Vector2i parser: returns Vector2i, or null when `v` isn't a
## coordinate pair (U.to_vector would silently turn e.g. "stone" into (0, 0)).
func _coord(v):
	if v is Vector2i or v is Vector2:
		return Vector2i(v)
	if v is Array and v.size() == 2 and (v[0] is float or v[0] is int) and (v[1] is float or v[1] is int):
		return Vector2i(int(v[0]), int(v[1]))
	if v is Dictionary and v.has("x") and v.has("y"):
		return Vector2i(int(v.x), int(v.y))
	if v is String:
		var parts: PackedStringArray = str(v).replace("(", "").replace(")", "").replace("[", "").replace("]", "").replace("Vector2i", "").replace("Vector2", "").replace(" ", "").split(",")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			return Vector2i(parts[0].to_int(), parts[1].to_int())
	return null


## _coord, but unparseable input becomes (-1, -1) so has_tile() checks report it as a bad tile.
func _coord_or_bad(v) -> Vector2i:
	var c = _coord(v)
	return c if c != null else Vector2i(-1, -1)


func _v2i(v, default: Vector2i) -> Vector2i:
	if v == null:
		return default
	if v is float or v is int:
		return Vector2i(int(v), int(v))
	return U.to_vector(v, TYPE_VECTOR2I)


func _coords_key(key) -> Vector2i:
	if key is Array:
		return U.to_vector(key, TYPE_VECTOR2I)
	var s := str(key).replace("(", "").replace(")", "").replace("[", "").replace("]", "").replace(" ", "")
	var parts := s.split(",")
	if parts.size() == 2:
		return Vector2i(parts[0].to_int(), parts[1].to_int())
	return Vector2i(-1, -1)


## Layer names/numbers -> bitmask. Delegates to the physics handler (named 2D layers) when present.
func _bits(v):
	if ctx.router.handlers.has("physics") and ctx.router.handlers["physics"].has_method("layer_bits"):
		return ctx.router.handlers["physics"].layer_bits(v, "2d_physics")
	var bits := 0
	for item in (v if v is Array else [v]):
		var n := int(item)
		if n < 1 or n > 32:
			return U.err("Layer numbers must be 1..32, got %s." % str(item))
		bits |= 1 << (n - 1)
	return bits


func _prefix(e: Dictionary, prefix: String) -> Dictionary:
	e["message"] = prefix + str(e.get("message", ""))
	return e
