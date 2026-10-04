@tool
extends RefCounted
## Base class for request handlers. Actions are methods named a_<action>(p: Dictionary).

const U = preload("res://addons/godot_forge/core/util.gd")
const Ctx = preload("res://addons/godot_forge/core/context.gd")

var ctx: Ctx


func root_or_err():
	var root: Node = ctx.edited_root()
	if root == null:
		return U.err("No scene is open in the editor.", "Open one with scene.open or create one with scene.create.")
	return root


## Finds a node, optionally opening `scene` first. Returns Node or an error dict.
func node_arg(p: Dictionary, key: String = "path"):
	if p.has("scene") and str(p.scene) != "":
		var r = await ensure_scene(str(p.scene))
		if U.is_err(r):
			return r
	var path := U.p_str(p, key, ".")
	var n: Node = ctx.find_node(path)
	if n == null:
		return ctx.node_not_found(path)
	return n


## Makes `scene_path` the edited scene (opens it if needed).
func ensure_scene(scene_path: String):
	var rp := U.res_path(scene_path)
	var root: Node = ctx.edited_root()
	if root and root.scene_file_path == rp:
		return root
	if not ResourceLoader.exists(rp):
		return U.err("Scene '%s' does not exist." % rp, "Create it with scene.create.")
	EditorInterface.open_scene_from_path(rp)
	await ctx.frame()
	root = ctx.edited_root()
	if root == null or root.scene_file_path != rp:
		return U.err("Could not open scene '%s'." % rp)
	return root
