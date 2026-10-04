@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Live engine API (ClassDB) for the exact Godot version running, plus project script classes.


func a_class(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var name := U.p_str(p, "name")
	var sections: Array = U.p_arr(p, "sections") if p.has("sections") else ["properties", "methods", "signals", "constants"]
	var filter := U.p_str(p, "filter", "").to_lower()
	var inherited := U.p_bool(p, "inherited", false)
	if not ClassDB.class_exists(name):
		for c in ProjectSettings.get_global_class_list():
			if c["class"] == name:
				return _script_class(c, sections, filter)
		var all := Array(ClassDB.get_class_list())
		var s := U.suggest(name, all)
		return U.err("Unknown class '%s'." % name, ("Did you mean '%s'? " % s if s != "" else "") + "Godot 3 names were renamed in Godot 4 (e.g. KinematicBody2D -> CharacterBody2D, Spatial -> Node3D). Use docs.migrate for mappings.")
	var chain := []
	var c2 := name
	while c2 != "":
		chain.append(c2)
		c2 = ClassDB.get_parent_class(c2)
	var out := {"class": name, "inherits": chain.slice(1), "instantiable": ClassDB.can_instantiate(name)}
	var no_inh := not inherited
	if "properties" in sections:
		var props := []
		for pi in ClassDB.class_get_property_list(name, no_inh):
			if pi.usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
				continue
			if filter != "" and not str(pi.name).to_lower().contains(filter):
				continue
			var d := U.describe_property(pi)
			var def = ClassDB.class_get_property_default_value(name, pi.name)
			if def != null:
				d["default"] = U.encode(def)
			props.append(d)
		out["properties"] = props
	if "methods" in sections:
		var methods := []
		for m in ClassDB.class_get_method_list(name, no_inh):
			var mname: String = m.name
			if mname.begins_with("_") and not U.p_bool(p, "include_virtual", true):
				continue
			if filter != "" and not mname.to_lower().contains(filter):
				continue
			methods.append(_sig(m))
		out["methods"] = methods
	if "signals" in sections:
		var sigs := []
		for s2 in ClassDB.class_get_signal_list(name, no_inh):
			if filter != "" and not str(s2.name).to_lower().contains(filter):
				continue
			sigs.append("%s(%s)" % [s2.name, ", ".join(s2.args.map(func(a): return "%s: %s" % [a.name, _tname(a)]))])
		out["signals"] = sigs
	if "constants" in sections:
		var enums := {}
		for en in ClassDB.class_get_enum_list(name, no_inh):
			enums[en] = Array(ClassDB.class_get_enum_constants(name, en, no_inh))
		var loose := []
		var in_enum := {}
		for en in enums:
			for c3 in enums[en]:
				in_enum[c3] = true
		for c4 in ClassDB.class_get_integer_constant_list(name, no_inh):
			if not in_enum.has(c4):
				loose.append(c4)
		if not enums.is_empty():
			out["enums"] = enums
		if not loose.is_empty():
			out["constants"] = loose
	if not inherited:
		out["note"] = "Only members declared on %s. Pass inherited=true to include %s." % [name, ", ".join(chain.slice(1, 4))]
	return out


func _tname(a: Dictionary) -> String:
	if a.type == TYPE_OBJECT:
		return a.class_name if a.class_name != "" else "Object"
	if a.type == TYPE_NIL:
		return "Variant"
	if a.type == TYPE_INT and a.class_name != "":
		return a.class_name
	if a.type == TYPE_ARRAY and a.hint == PROPERTY_HINT_ARRAY_TYPE:
		return "Array[%s]" % a.hint_string
	return type_string(a.type)


func _sig(m: Dictionary) -> String:
	var args := []
	var defaults: Array = m.get("default_args", [])
	var first_default: int = m.args.size() - defaults.size()
	for i in m.args.size():
		var a: Dictionary = m.args[i]
		var s := "%s: %s" % [a.name, _tname(a)]
		if i >= first_default:
			s += " = " + var_to_str(defaults[i - first_default])
		args.append(s)
	var ret := _tname(m.return) if m.has("return") else "void"
	if m.has("return") and m.return.type == TYPE_NIL and not (m.return.usage & PROPERTY_USAGE_NIL_IS_VARIANT):
		ret = "void"
	var q := ""
	if m.flags & METHOD_FLAG_STATIC:
		q = "static "
	if m.flags & METHOD_FLAG_VIRTUAL:
		q = "virtual "
	return "%s%s(%s) -> %s" % [q, m.name, ", ".join(args), ret]


func _script_class(c: Dictionary, sections: Array, filter: String):
	var scr: Script = load(c.path)
	var out := {"class": c["class"], "script": c.path, "extends": c.base}
	if "properties" in sections:
		out["properties"] = scr.get_script_property_list().filter(func(pi): return pi.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and (filter == "" or str(pi.name).contains(filter))).map(func(pi): return U.describe_property(pi))
	if "methods" in sections:
		out["methods"] = scr.get_script_method_list().filter(func(m): return filter == "" or str(m.name).contains(filter)).map(func(m): return _sig(m))
	if "signals" in sections:
		out["signals"] = scr.get_script_signal_list().map(func(s): return "%s(%s)" % [s.name, ", ".join(s.args.map(func(a): return a.name))])
	if "constants" in sections:
		out["constants"] = scr.get_script_constant_map().keys()
	return out


## Searches class names (engine + project script classes).
func a_search(p: Dictionary):
	var q := U.p_str(p, "query").to_lower()
	var base := U.p_str(p, "base", "")
	var out := []
	for c in ClassDB.get_class_list():
		var cn := str(c)
		if cn.begins_with("Editor") and not U.p_bool(p, "include_editor", false):
			continue
		if base != "" and not ClassDB.is_parent_class(cn, base):
			continue
		if q == "" or cn.to_lower().contains(q):
			out.append(cn)
	for c2 in ProjectSettings.get_global_class_list():
		if q == "" or str(c2["class"]).to_lower().contains(q):
			out.append("%s (script: %s)" % [c2["class"], c2.path])
	out.sort()
	return {"classes": out.slice(0, U.p_int(p, "limit", 150)), "total": out.size()}


## Finds which class declares a member (method, property or signal) — handy for "where is X?".
func a_member(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var name := U.p_str(p, "name")
	var base := U.p_str(p, "base", "")
	var out := []
	for c in ClassDB.get_class_list():
		var cn := str(c)
		if base != "" and not ClassDB.is_parent_class(cn, base):
			continue
		if ClassDB.class_has_method(cn, name, true):
			out.append({"class": cn, "kind": "method"})
		elif ClassDB.class_has_signal(cn, name) and ClassDB.class_get_signal(cn, name).size() > 0 and not ClassDB.class_has_signal(ClassDB.get_parent_class(cn), name):
			out.append({"class": cn, "kind": "signal"})
		else:
			for pi in ClassDB.class_get_property_list(cn, true):
				if pi.name == name:
					out.append({"class": cn, "kind": "property", "type": U.describe_property(pi).type})
					break
		if out.size() > 40:
			break
	if out.is_empty():
		return U.err("No engine class declares '%s'." % name, "It may be a Godot 3 name; try docs.migrate.")
	return {"name": name, "declared_in": out}


## Instantiable node types, optionally for a domain ("2d", "3d", "ui") or under a base class.
func a_node_types(p: Dictionary):
	var domain := U.p_str(p, "domain", "")
	var base := U.p_str(p, "base", {"2d": "Node2D", "3d": "Node3D", "ui": "Control"}.get(domain, "Node"))
	var out := []
	for c in ClassDB.get_inheriters_from_class(base):
		if ClassDB.can_instantiate(c) and not str(c).begins_with("Editor") and not str(c).contains("Debugger"):
			out.append(str(c))
	out.sort()
	return {"base": base, "types": out}


## Checks whether a type can be a child of another (warns about common invalid combos).
func a_check_parent(p: Dictionary):
	var child := U.p_str(p, "child")
	var parent := U.p_str(p, "parent")
	var notes := []
	if child.begins_with("CollisionShape2D") or child.begins_with("CollisionPolygon2D"):
		if not ClassDB.is_parent_class(parent, "CollisionObject2D"):
			notes.append("%s only works as a child of a CollisionObject2D (Area2D, StaticBody2D, CharacterBody2D, RigidBody2D)." % child)
	if child.begins_with("CollisionShape3D") or child.begins_with("CollisionPolygon3D"):
		if not ClassDB.is_parent_class(parent, "CollisionObject3D"):
			notes.append("%s only works as a child of a CollisionObject3D." % child)
	if ClassDB.is_parent_class(child, "Node2D") and ClassDB.is_parent_class(parent, "Node3D"):
		notes.append("2D nodes under a 3D node don't render in the 3D scene.")
	if ClassDB.is_parent_class(child, "Node3D") and ClassDB.is_parent_class(parent, "CanvasItem"):
		notes.append("3D nodes under 2D/UI nodes won't be in a 3D world unless inside a SubViewport.")
	if child == "AnimationTree" and parent != "":
		notes.append("AnimationTree needs anim_player pointing at an AnimationPlayer.")
	return {"ok": notes.is_empty(), "notes": notes}
