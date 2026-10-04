@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Audio: the project's bus layout (buses, volumes, effects; persisted to default_bus_layout.tres),
## AudioStreamPlayer nodes, stream info, import loop settings, and procedurally generated
## placeholder sound effects (sfxr-style) saved as .wav files.

const EFFECTS := {
	"reverb": "AudioEffectReverb", "delay": "AudioEffectDelay", "echo": "AudioEffectDelay",
	"compressor": "AudioEffectCompressor", "limiter": "AudioEffectHardLimiter", "hard_limiter": "AudioEffectHardLimiter",
	"eq": "AudioEffectEQ10", "eq6": "AudioEffectEQ6", "eq10": "AudioEffectEQ10", "eq21": "AudioEffectEQ21",
	"chorus": "AudioEffectChorus", "distortion": "AudioEffectDistortion", "phaser": "AudioEffectPhaser",
	"lowpass": "AudioEffectLowPassFilter", "low_pass": "AudioEffectLowPassFilter", "highpass": "AudioEffectHighPassFilter",
	"high_pass": "AudioEffectHighPassFilter", "bandpass": "AudioEffectBandPassFilter", "band_pass": "AudioEffectBandPassFilter",
	"notch": "AudioEffectNotchFilter", "lowshelf": "AudioEffectLowShelfFilter", "highshelf": "AudioEffectHighShelfFilter",
	"bandlimit": "AudioEffectBandLimitFilter", "amplify": "AudioEffectAmplify", "gain": "AudioEffectAmplify",
	"panner": "AudioEffectPanner", "pan": "AudioEffectPanner", "pitch_shift": "AudioEffectPitchShift", "pitch": "AudioEffectPitchShift",
	"stereo_enhance": "AudioEffectStereoEnhance", "record": "AudioEffectRecord", "spectrum": "AudioEffectSpectrumAnalyzer",
	"spectrum_analyzer": "AudioEffectSpectrumAnalyzer", "capture": "AudioEffectCapture",
}
const WAV_LOOP_MODES := {"detect": 0, "disabled": 1, "off": 1, "forward": 2, "pingpong": 3, "ping_pong": 3, "backward": 4}
const AUDIO_EXT := ["wav", "ogg", "mp3"]


# ---------------------------------------------------------------------------
# Buses
# ---------------------------------------------------------------------------

func _layout_path() -> String:
	# The editor may store this setting as a uid:// reference.
	var path := U.res_path(str(ProjectSettings.get_setting("audio/buses/default_bus_layout", "res://default_bus_layout.tres")))
	if path == "" or path.begins_with("uid://"):
		path = "res://default_bus_layout.tres"
	return path


func a_buses(_p: Dictionary):
	var out := []
	for i in AudioServer.bus_count:
		out.append(_bus_info(i))
	var path := _layout_path()
	return {"buses": out, "layout_file": path, "saved": FileAccess.file_exists(path), "effect_types": _effect_names()}


func _effect_names() -> Array:
	return ["reverb", "delay", "compressor", "limiter", "eq", "eq6", "eq21", "chorus", "distortion", "phaser", "lowpass", "highpass", "bandpass", "notch", "lowshelf", "highshelf", "amplify", "panner", "pitch_shift", "stereo_enhance", "spectrum_analyzer", "record", "capture"]


func _bus_info(i: int) -> Dictionary:
	var d := {"index": i, "name": AudioServer.get_bus_name(i), "volume_db": snappedf(AudioServer.get_bus_volume_db(i), 0.01)}
	if i > 0:
		d["send"] = str(AudioServer.get_bus_send(i))
	if AudioServer.is_bus_mute(i): d["mute"] = true
	if AudioServer.is_bus_solo(i): d["solo"] = true
	if AudioServer.is_bus_bypassing_effects(i): d["bypass_effects"] = true
	var fx := []
	for j in AudioServer.get_bus_effect_count(i):
		var eff := AudioServer.get_bus_effect(i, j)
		var e := {"index": j, "type": _effect_short(eff.get_class()), "class": eff.get_class(), "enabled": AudioServer.is_bus_effect_enabled(i, j)}
		var props := U.changed_props(eff)
		props.erase("resource_name")
		props.erase("resource_path")
		if not props.is_empty():
			e["props"] = props
		fx.append(e)
	if not fx.is_empty():
		d["effects"] = fx
	return d


func _effect_short(cls: String) -> String:
	for k in EFFECTS:
		if EFFECTS[k] == cls:
			return k
	return cls


## Builds an AudioEffect from "reverb" | {type: "reverb", props: {...}} | {type: "reverb", room_size: 0.8}.
func _make_effect(spec):
	var type := ""
	var props := {}
	var enabled := true
	if spec is String:
		type = spec
	elif spec is Dictionary:
		type = U.p_str(spec, "type")
		props = U.p_dict(spec, "props").duplicate()
		for k in spec:
			if not (k in ["type", "props", "enabled"]):
				props[k] = spec[k]
		enabled = U.p_bool(spec, "enabled", true)
	else:
		return U.err("Effect must be a name like \"reverb\" or {\"type\": \"reverb\", \"props\": {\"room_size\": 0.8}}.")
	var cls: String = EFFECTS.get(type.to_lower(), type)
	if not ClassDB.class_exists(cls) or not ClassDB.is_parent_class(cls, "AudioEffect") or not ClassDB.can_instantiate(cls):
		var s := U.suggest(type, EFFECTS.keys())
		return U.err("Unknown audio effect '%s'." % type, ("Did you mean '%s'? " % s if s != "" else "") + "Types: " + ", ".join(_effect_names()))
	var eff: AudioEffect = ClassDB.instantiate(cls)
	var r = _apply_effect_props(eff, props)
	if U.is_err(r): return r
	return [eff, enabled]


## Sets effect properties, accepting friendly aliases (cutoff -> cutoff_hz, mix -> wet on reverb,
## gain -> volume_db on amplify).
func _apply_effect_props(eff: AudioEffect, props: Dictionary):
	var infos := U.prop_infos(eff)
	var aliases := {"cutoff": "cutoff_hz", "frequency": "cutoff_hz", "gain": "volume_db" if eff is AudioEffectAmplify else "gain", "mix": "wet" if eff is AudioEffectReverb else "mix", "volume": "volume_db"}
	var fixed := {}
	for k in props:
		var key := str(k)
		if not infos.has(key) and aliases.has(key) and infos.has(aliases[key]):
			key = aliases[key]
		fixed[key] = props[k]
	var r = U.apply_props(eff, fixed)
	if U.is_err(r):
		r["message"] = "%s: %s" % [eff.get_class(), r.message]
		return r
	return null


func _bus_idx(name: String) -> int:
	return AudioServer.get_bus_index(name)


func _bus_not_found(name: String) -> Dictionary:
	var names := []
	for i in AudioServer.bus_count:
		names.append(AudioServer.get_bus_name(i))
	var s := U.suggest(name, names)
	return U.err("Audio bus '%s' not found." % name, ("Did you mean '%s'? " % s if s != "" else "") + "Buses: " + ", ".join(names) + ". Create one with audio.add_bus.")


## Deep copy of the live bus layout. generate_bus_layout() shares the effect objects with the
## server, so a snapshot taken before an edit would otherwise change along with it.
func _snapshot() -> AudioBusLayout:
	return AudioServer.generate_bus_layout().duplicate(true) as AudioBusLayout


## Applies a whole bus layout to the AudioServer and saves it to the project's layout file.
## Used as the do/undo method so every bus edit is undoable and persisted.
func apply_layout(layout: AudioBusLayout) -> void:
	# Apply a copy so later in-place edits never alter the layouts stored in the undo history.
	AudioServer.set_bus_layout(layout.duplicate(true) as AudioBusLayout)
	var path := _layout_path()
	var fresh := AudioServer.generate_bus_layout()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(fresh, path)
	if err == OK:
		fresh.take_over_path(path)
		ctx.fs().update_file(path)
	else:
		push_warning("Godot Forge: could not save bus layout to %s (error %d)" % [path, err])


## Runs `mutate` against the live AudioServer, then records old/new layouts as one undoable action.
func _commit_layout(action_name: String, before: AudioBusLayout) -> void:
	var after := _snapshot()
	ctx.before_write([_layout_path()])
	# Recorded in the edited scene's history (like every other Forge action) so editor.undo and
	# batch rollback see it; with no scene open it lands in the global history.
	var u = ctx.begin(action_name)
	u.add_do_method(self, "apply_layout", after)
	u.add_undo_method(self, "apply_layout", before)
	ctx.commit()


## {name, send?='Master', volume_db?, mute?, solo?, bypass_effects?, effects?: [...], index?}
func a_add_bus(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var name := U.p_str(p, "name")
	if _bus_idx(name) >= 0:
		return U.err("Audio bus '%s' already exists." % name, "Use audio.set_bus to change it.")
	var send := U.p_str(p, "send", "Master")
	if _bus_idx(send) < 0:
		return _bus_not_found(send)
	var effects := []
	for spec in U.p_arr(p, "effects"):
		var fx = _make_effect(spec)
		if U.is_err(fx): return fx
		effects.append(fx)
	var before := _snapshot()
	var idx := AudioServer.bus_count
	if p.has("index"):
		idx = clampi(U.p_int(p, "index"), 1, AudioServer.bus_count)
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, send)
	_apply_bus_props(idx, p)
	for fx in effects:
		AudioServer.add_bus_effect(idx, fx[0])
		AudioServer.set_bus_effect_enabled(idx, AudioServer.get_bus_effect_count(idx) - 1, fx[1])
	_commit_layout("Add audio bus " + name, before)
	return {"bus": _bus_info(_bus_idx(name)), "saved_to": _layout_path(), "hint": "Route sounds with the player's bus property (audio.player {bus: '%s'}), or set volume in-game with AudioServer.set_bus_volume_db(AudioServer.get_bus_index(\"%s\"), db)." % [name, name]}


func _apply_bus_props(idx: int, p: Dictionary) -> void:
	if p.has("volume_db"):
		AudioServer.set_bus_volume_db(idx, U.p_float(p, "volume_db"))
	elif p.has("volume"):
		AudioServer.set_bus_volume_linear(idx, U.p_float(p, "volume"))
	if p.has("mute"):
		AudioServer.set_bus_mute(idx, U.p_bool(p, "mute"))
	if p.has("solo"):
		AudioServer.set_bus_solo(idx, U.p_bool(p, "solo"))
	if p.has("bypass_effects"):
		AudioServer.set_bus_bypass_effects(idx, U.p_bool(p, "bypass_effects"))


## {name, rename?, send?, volume_db?|volume?, mute?, solo?, bypass_effects?,
##  effects? (replace all), add_effects?, remove_effects?: [index|type], effect_props?: {index|type: {props}}}
func a_set_bus(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var name := U.p_str(p, "name")
	var idx := _bus_idx(name)
	if idx < 0:
		return _bus_not_found(name)
	if p.has("send"):
		if idx == 0:
			return U.err("The Master bus cannot send to another bus.")
		var send := U.p_str(p, "send")
		if _bus_idx(send) < 0:
			return _bus_not_found(send)
		if send == name:
			return U.err("A bus cannot send to itself.")
	if p.has("rename"):
		var nn := U.p_str(p, "rename")
		if nn == "" or (_bus_idx(nn) >= 0 and nn != name):
			return U.err("Cannot rename to '%s' (empty or already used)." % nn)
	var new_fx := []
	for spec in U.p_arr(p, "effects") + U.p_arr(p, "add_effects"):
		var fx = _make_effect(spec)
		if U.is_err(fx): return fx
		new_fx.append(fx)
	# Resolve removals / prop edits before touching the server.
	var remove := []
	for r in U.p_arr(p, "remove_effects"):
		var j := _find_effect(idx, r)
		if j < 0:
			return U.err("Bus '%s' has no effect '%s'." % [name, _key_str(r)], _effects_hint(idx))
		remove.append(j)
	var edits := {}
	var ep := U.p_dict(p, "effect_props")
	for key in ep:
		var j2 := _find_effect(idx, key)
		if j2 < 0:
			return U.err("Bus '%s' has no effect '%s'." % [name, _key_str(key)], _effects_hint(idx))
		if not (ep[key] is Dictionary):
			return U.err("effect_props.%s must be an object of properties, e.g. {\"room_size\": 0.8}." % key)
		# Edit a copy and swap it in (below): the original instance may be shared with undo history.
		var copy: AudioEffect = AudioServer.get_bus_effect(idx, j2).duplicate()
		var pr = _apply_effect_props(copy, ep[key])
		if U.is_err(pr): return pr
		edits[j2] = copy
	var before := _snapshot()
	if p.has("send"):
		AudioServer.set_bus_send(idx, U.p_str(p, "send"))
	_apply_bus_props(idx, p)
	for j3 in edits:
		var was_enabled := AudioServer.is_bus_effect_enabled(idx, j3)
		AudioServer.remove_bus_effect(idx, j3)
		AudioServer.add_bus_effect(idx, edits[j3], j3)
		AudioServer.set_bus_effect_enabled(idx, j3, was_enabled)
	remove.sort()
	remove.reverse()
	for j4 in remove:
		AudioServer.remove_bus_effect(idx, j4)
	if p.has("effects"):
		while AudioServer.get_bus_effect_count(idx) > 0:
			AudioServer.remove_bus_effect(idx, 0)
	for fx in new_fx:
		AudioServer.add_bus_effect(idx, fx[0])
		AudioServer.set_bus_effect_enabled(idx, AudioServer.get_bus_effect_count(idx) - 1, fx[1])
	if p.has("rename"):
		AudioServer.set_bus_name(idx, U.p_str(p, "rename"))
	_commit_layout("Edit audio bus " + name, before)
	var out := {"bus": _bus_info(idx), "saved_to": _layout_path()}
	if p.has("rename"):
		out["note"] = "Players whose bus is '%s' must be updated to '%s' (they fall back to Master)." % [name, U.p_str(p, "rename")]
	return out


func _key_str(key) -> String:
	return str(int(key)) if key is float and key == floor(key) else str(key)


func _effects_hint(idx: int) -> String:
	var fx: Array = _bus_info(idx).get("effects", [])
	if fx.is_empty():
		return "The bus has no effects; add some with add_effects."
	return "Refer to an effect by index or type. Effects: " + ", ".join(fx.map(func(x): return "%d:%s" % [x.index, x.type]))


func _find_effect(bus: int, key) -> int:
	var n := AudioServer.get_bus_effect_count(bus)
	if key is int or key is float or (key is String and key.is_valid_int()):
		var j := int(key)
		return j if j >= 0 and j < n else -1
	var cls: String = EFFECTS.get(str(key).to_lower(), str(key))
	for j in n:
		if AudioServer.get_bus_effect(bus, j).get_class() == cls:
			return j
	return -1


func a_remove_bus(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var name := U.p_str(p, "name")
	var idx := _bus_idx(name)
	if idx < 0:
		return _bus_not_found(name)
	if idx == 0:
		return U.err("The Master bus cannot be removed.")
	var before := _snapshot()
	# Buses that sent to it now go to Master.
	var rerouted := []
	for i in AudioServer.bus_count:
		if i != idx and str(AudioServer.get_bus_send(i)) == name:
			AudioServer.set_bus_send(i, "Master")
			rerouted.append(AudioServer.get_bus_name(i))
	AudioServer.remove_bus(idx)
	_commit_layout("Remove audio bus " + name, before)
	var out := {"removed": name, "buses": range(AudioServer.bus_count).map(func(i): return AudioServer.get_bus_name(i)), "saved_to": _layout_path()}
	if not rerouted.is_empty():
		out["rerouted_to_master"] = rerouted
	return out


# ---------------------------------------------------------------------------
# Players
# ---------------------------------------------------------------------------

## Adds an AudioStreamPlayer / 2D / 3D with a stream.
## {parent?='.', name?, type?: 1d|2d|3d (default from parent), stream, bus?, autoplay?, volume_db?,
##  pitch_scale?, loop?, max_distance?, props?}
func a_player(p: Dictionary):
	if p.has("scene"):
		var r = await ensure_scene(U.p_str(p, "scene"))
		if U.is_err(r): return r
	var root = root_or_err()
	if U.is_err(root): return root
	var parent: Node = ctx.find_node(U.p_str(p, "parent", "."))
	if parent == null:
		return ctx.node_not_found(U.p_str(p, "parent"))
	var type := U.p_str(p, "type", "").to_lower()
	if type == "":
		# Positional only when attached to an entity (not the scene root) and not music.
		var nm := U.p_str(p, "name", "").to_lower()
		var is_music := nm.contains("music") or nm.contains("ambien") or nm.contains("bgm") or U.p_str(p, "bus", "").to_lower() in ["music", "ambience", "ui"]
		if parent != root and not is_music:
			type = "2d" if parent is Node2D else ("3d" if parent is Node3D else "1d")
		else:
			type = "1d"
	var cls: String = {"1d": "AudioStreamPlayer", "global": "AudioStreamPlayer", "ui": "AudioStreamPlayer", "music": "AudioStreamPlayer", "2d": "AudioStreamPlayer2D", "3d": "AudioStreamPlayer3D"}.get(type, "")
	if cls == "":
		if type in ["audiostreamplayer", "audiostreamplayer2d", "audiostreamplayer3d"]:
			cls = {"audiostreamplayer": "AudioStreamPlayer", "audiostreamplayer2d": "AudioStreamPlayer2D", "audiostreamplayer3d": "AudioStreamPlayer3D"}[type]
		else:
			return U.err("Unknown player type '%s'." % type, "Use '1d' (non-positional: music, UI), '2d' (positional in 2D) or '3d'.")
	# Validate everything cheap before touching the stream's import settings (loop).
	var bus := U.p_str(p, "bus", "Master")
	if _bus_idx(bus) < 0:
		return _bus_not_found(bus)
	if p.has("props") and not (p.props is Dictionary):
		return U.err("'props' must be an object of player properties, e.g. {\"max_polyphony\": 4}.")
	var stream = null
	var notes := []
	if p.has("stream"):
		var sp = p.stream
		if sp is String:
			var rp := U.res_path(sp)
			if not ResourceLoader.exists(rp):
				return _stream_not_found(rp)
			if not (load(rp) is AudioStream):
				return U.err("'%s' is not an AudioStream." % rp, "Use a .wav/.ogg/.mp3 file or an AudioStream resource.")
			if p.has("loop"):
				var lr = await _set_loop(rp, U.p_bool(p, "loop"), p)
				if U.is_err(lr): return lr
				notes.append(lr.get("note", "loop=%s" % U.p_bool(p, "loop")))
			stream = load(rp)
		else:
			stream = U.to_object(sp, "AudioStream")
			if U.is_err(stream): return stream
		if not (stream is AudioStream):
			return U.err("'%s' is not an AudioStream." % str(p.stream), "Use a .wav/.ogg/.mp3 file or an AudioStream resource.")
	var n: Node = ClassDB.instantiate(cls)
	n.name = U.p_str(p, "name", "Music" if (type == "music") else (stream.resource_path.get_file().get_basename().to_pascal_case() + "Player" if stream and stream.resource_path != "" else cls))
	if stream:
		n.stream = stream
	n.bus = bus
	if p.has("autoplay"): n.autoplay = U.p_bool(p, "autoplay")
	if p.has("volume_db"): n.volume_db = U.p_float(p, "volume_db")
	if p.has("pitch_scale"): n.pitch_scale = U.p_float(p, "pitch_scale")
	if p.has("max_distance") and cls != "AudioStreamPlayer": n.max_distance = U.p_float(p, "max_distance")
	if p.has("props"):
		var pr = U.apply_props(n, U.p_dict(p, "props"))
		if U.is_err(pr):
			n.free()
			return pr
	var u = ctx.begin("Add " + cls)
	u.add_do_method(parent, "add_child", n, true)
	u.add_do_method(n, "set_owner", root)
	u.add_do_reference(n)
	u.add_undo_method(parent, "remove_child", n)
	ctx.commit()
	var out := {"path": ctx.node_path_str(n), "type": cls, "bus": bus}
	if stream:
		out["stream"] = _stream_summary(stream)
	if not notes.is_empty():
		out["notes"] = notes
	if (cls == "AudioStreamPlayer2D" and not (parent is Node2D)) or (cls == "AudioStreamPlayer3D" and not (parent is Node3D)):
		out["warning"] = "%s is positional but its parent is a %s, not a %s; it will play from the origin. Use type '1d' for non-positional sound or add it under the emitting entity." % [cls, parent.get_class(), "Node2D" if cls.ends_with("2D") else "Node3D"]
	out["hint"] = "Play it with $%s.play() from a script on the scene root%s." % [ctx.node_path_str(n), "" if parent == root else " ($%s.play() from a script on %s)" % [str(n.name), parent.name]]
	return out


func _stream_not_found(rp: String) -> Dictionary:
	var names := []
	ctx.router.handlers["files"]._walk("res://", true, "*", false, names, [], 3000)
	var audio := []
	for f in names:
		var fp: String = f.path if f is Dictionary else str(f)
		if fp.get_extension().to_lower() in AUDIO_EXT:
			audio.append(fp)
	var s := U.suggest(rp, audio)
	return U.err("Audio file '%s' not found." % rp, ("Did you mean '%s'? " % s if s != "" else "") + ("Audio files: %s" % ", ".join(audio.slice(0, 15)) if not audio.is_empty() else "No audio in the project yet; make placeholders with audio.generate_tone."))


func _stream_summary(s: AudioStream) -> Dictionary:
	var d := {"type": s.get_class(), "length_s": snappedf(s.get_length(), 0.001)}
	if s.resource_path != "":
		d["path"] = s.resource_path
	if s is AudioStreamWAV:
		d["loop"] = s.loop_mode != AudioStreamWAV.LOOP_DISABLED
	elif "loop" in s:
		d["loop"] = s.get("loop")
	return d


# ---------------------------------------------------------------------------
# Stream info / import loop
# ---------------------------------------------------------------------------

func a_stream_info(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not ResourceLoader.exists(path):
		return _stream_not_found(path)
	var s = load(path)
	if not (s is AudioStream):
		return U.err("'%s' is a %s, not an AudioStream." % [path, s.get_class()])
	var out := {"path": path, "type": s.get_class(), "length_s": snappedf(s.get_length(), 0.001)}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			out["file_bytes"] = f.get_length()
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = s
		out["format"] = ["8_bit", "16_bit", "ima_adpcm", "qoa"][w.format] if w.format < 4 else w.format
		out["mix_rate"] = w.mix_rate
		out["stereo"] = w.stereo
		out["loop_mode"] = ["disabled", "forward", "pingpong", "backward"][w.loop_mode]
		out["loop_begin"] = w.loop_begin
		out["loop_end"] = w.loop_end
	else:
		for k in ["loop", "loop_offset", "bpm", "beat_count", "bar_beats"]:
			if k in s:
				out[k] = s.get(k)
	var imp := path + ".import"
	if FileAccess.file_exists(imp):
		var cfg := ConfigFile.new()
		if cfg.load(imp) == OK:
			out["importer"] = cfg.get_value("remap", "importer", "")
			var params := {}
			if cfg.has_section("params"):
				for k in cfg.get_section_keys("params"):
					params[k] = U.encode(cfg.get_value("params", k))
			out["import_params"] = params
	return out


## Sets looping in the .import file of a wav/ogg/mp3 and reimports.
## {path, loop, loop_offset? (ogg/mp3 seconds), loop_begin?/loop_end? (wav frames), mode?: forward|pingpong|backward (wav)}
func a_import_loop(p: Dictionary):
	var e = U.require(p, ["path", "loop"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if not FileAccess.file_exists(path):
		return _stream_not_found(path)
	var r = await _set_loop(path, U.p_bool(p, "loop"), p)
	if U.is_err(r): return r
	var info = a_stream_info({"path": path})
	r["info"] = info
	return r


func _set_loop(path: String, loop: bool, p: Dictionary):
	var ext := path.get_extension().to_lower()
	if ext in ["tres", "res"]:
		var s = load(path)
		if s is AudioStreamWAV:
			var w: AudioStreamWAV = s
			w.loop_mode = _wav_mode(p) if loop else AudioStreamWAV.LOOP_DISABLED
			if loop:
				w.loop_begin = U.p_int(p, "loop_begin", 0)
				w.loop_end = U.p_int(p, "loop_end", _wav_frames(w))
		elif s is AudioStream and "loop" in s:
			s.set("loop", loop)
			if p.has("loop_offset") and "loop_offset" in s:
				s.set("loop_offset", U.p_float(p, "loop_offset"))
		else:
			return U.err("'%s' has no loop setting." % path)
		ctx.before_write([path])
		ResourceSaver.save(s, path)
		ctx.fs().update_file(path)
		return {"path": path, "loop": loop, "note": "loop saved in the resource"}
	var imp := path + ".import"
	if not FileAccess.file_exists(imp):
		ctx.fs().update_file(path)
		await ctx.wait_fs()
		if not FileAccess.file_exists(imp):
			return U.err("'%s' has not been imported yet." % path, "Run files.rescan and try again.")
	var cfg := ConfigFile.new()
	if cfg.load(imp) != OK:
		return U.err("Cannot read '%s'." % imp)
	var importer := str(cfg.get_value("remap", "importer", ""))
	match importer:
		"wav":
			cfg.set_value("params", "edit/loop_mode", _wav_mode(p) + 1 if loop else 1)  # import enum: 0 detect, 1 disabled, 2 forward...
			if loop:
				cfg.set_value("params", "edit/loop_begin", U.p_int(p, "loop_begin", 0))
				cfg.set_value("params", "edit/loop_end", U.p_int(p, "loop_end", -1))
		"oggvorbisstr", "mp3":
			cfg.set_value("params", "loop", loop)
			if p.has("loop_offset"):
				cfg.set_value("params", "loop_offset", U.p_float(p, "loop_offset"))
		_:
			return U.err("Looping is not supported for importer '%s' (%s)." % [importer, path], "Supported: .wav, .ogg, .mp3.")
	ctx.before_write([path, imp])
	if cfg.save(imp) != OK:
		return U.err("Cannot write '%s'." % imp)
	ctx.fs().reimport_files(PackedStringArray([path]))
	await ctx.wait_fs()
	if ResourceLoader.has_cached(path):
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	return {"path": path, "loop": loop, "importer": importer, "note": "import setting changed and file reimported"}


func _wav_mode(p: Dictionary) -> int:
	var m := U.p_str(p, "mode", "forward").to_lower()
	match m:
		"pingpong", "ping_pong", "ping-pong": return AudioStreamWAV.LOOP_PINGPONG
		"backward", "reverse": return AudioStreamWAV.LOOP_BACKWARD
	return AudioStreamWAV.LOOP_FORWARD


func _wav_frames(w: AudioStreamWAV) -> int:
	var bytes_per := 1 if w.format == AudioStreamWAV.FORMAT_8_BITS else 2
	if w.stereo:
		bytes_per *= 2
	if w.format in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]:
		return w.data.size() / bytes_per
	return int(w.get_length() * w.mix_rate)


# ---------------------------------------------------------------------------
# Procedural placeholder sound effects
# ---------------------------------------------------------------------------

const TONE_PRESETS := {
	"beep": {"wave": "square", "freq": 880.0, "duration": 0.15, "attack": 0.005, "decay": 0.03, "duty": 0.5},
	"blip": {"wave": "square", "freq": 1200.0, "duration": 0.06, "attack": 0.002, "decay": 0.03, "duty": 0.5, "volume": 0.4},
	"click": {"wave": "square", "freq": 1800.0, "freq_end": 900.0, "duration": 0.025, "attack": 0.0, "decay": 0.02, "volume": 0.4},
	"select": {"wave": "triangle", "freq": 660.0, "duration": 0.1, "arp_mult": 1.5, "arp_time": 0.05, "decay": 0.04, "volume": 0.5},
	"jump": {"wave": "square", "freq": 280.0, "freq_end": 720.0, "duration": 0.22, "attack": 0.005, "decay": 0.12, "duty": 0.5},
	"coin": {"wave": "square", "freq": 988.0, "duration": 0.32, "arp_mult": 1.335, "arp_time": 0.07, "attack": 0.0, "decay": 0.22, "duty": 0.5},
	"pickup": {"wave": "sine", "freq": 700.0, "freq_end": 1400.0, "duration": 0.15, "decay": 0.08},
	"powerup": {"wave": "square", "freq": 300.0, "freq_end": 1100.0, "duration": 0.55, "vibrato_rate": 14.0, "vibrato_depth": 0.06, "decay": 0.2, "duty": 0.35},
	"laser": {"wave": "saw", "freq": 1400.0, "freq_end": 180.0, "duration": 0.2, "attack": 0.0, "decay": 0.12},
	"shoot": {"wave": "square", "freq": 900.0, "freq_end": 250.0, "duration": 0.14, "decay": 0.1, "duty": 0.3, "noise_mix": 0.25},
	"hit": {"wave": "noise", "freq": 900.0, "freq_end": 250.0, "duration": 0.14, "attack": 0.0, "decay": 0.1, "noise_mix": 1.0},
	"hurt": {"wave": "square", "freq": 420.0, "freq_end": 110.0, "duration": 0.25, "decay": 0.15, "duty": 0.4, "noise_mix": 0.3},
	"explosion": {"wave": "noise", "freq": 380.0, "freq_end": 40.0, "duration": 0.9, "attack": 0.0, "decay": 0.75, "lowpass": 2400.0, "lowpass_end": 300.0, "noise_mix": 1.0},
	"death": {"wave": "triangle", "freq": 500.0, "freq_end": 60.0, "duration": 0.8, "decay": 0.5, "vibrato_rate": 9.0, "vibrato_depth": 0.08},
	"step": {"wave": "noise", "freq": 1600.0, "freq_end": 600.0, "duration": 0.07, "decay": 0.06, "lowpass": 3000.0, "volume": 0.5},
	"error": {"wave": "square", "freq": 180.0, "duration": 0.3, "decay": 0.05, "arp_mult": 0.8, "arp_time": 0.15, "duty": 0.5},
}
const TONE_KEYS := ["wave", "freq", "freq_end", "duration", "attack", "decay", "duty", "volume", "vibrato_rate", "vibrato_depth", "arp_mult", "arp_time", "noise_mix", "lowpass", "lowpass_end", "mix_rate", "seed", "variation"]


## Synthesises a short sound effect and saves it as an imported .wav.
## {path, preset?: beep|blip|click|select|jump|coin|pickup|powerup|laser|shoot|hit|hurt|explosion|death|step|error,
##  wave?: square|sine|saw|triangle|noise, freq?, freq_end?, duration?, attack?, decay?, duty?, volume?=0.6,
##  vibrato_rate?, vibrato_depth?, arp_mult?, arp_time?, noise_mix?, lowpass?, lowpass_end?, seed?, variation?: 0..1,
##  loop?, overwrite?=true}
func a_generate_tone(p: Dictionary):
	var e = U.require(p, ["path"])
	if e: return e
	var path := U.res_path(U.p_str(p, "path"))
	if path.get_extension() == "":
		path += ".wav"
	if path.get_extension().to_lower() != "wav":
		return U.err("generate_tone writes .wav files (got '%s')." % path, "Use a path like res://sfx/jump.wav.")
	if not U.is_safe_path(path):
		return U.err("Path must stay inside the project.")
	if FileAccess.file_exists(path) and not U.p_bool(p, "overwrite", true):
		return U.err("'%s' already exists." % path, "Pass overwrite=true.")
	var preset := U.p_str(p, "preset", "")
	var cfg := {"wave": "square", "freq": 440.0, "duration": 0.2, "attack": 0.005, "decay": 0.1, "duty": 0.5, "volume": 0.6}
	if preset != "":
		if not TONE_PRESETS.has(preset.to_lower()):
			var s := U.suggest(preset, TONE_PRESETS.keys())
			return U.err("Unknown preset '%s'." % preset, ("Did you mean '%s'? " % s if s != "" else "") + "Presets: " + ", ".join(TONE_PRESETS.keys()))
		cfg.merge(TONE_PRESETS[preset.to_lower()], true)
	for k in p:
		if k in TONE_KEYS:
			cfg[k] = p[k]
	for k in cfg:
		if k == "wave":
			continue
		var v = cfg[k]
		if v is String and (v as String).is_valid_float():
			cfg[k] = v.to_float()
		elif not (v is int or v is float):
			return U.err("'%s' must be a number (got %s)." % [k, JSON.stringify(v)], "e.g. duration: 0.3 (seconds), freq: 440 (Hz), volume: 0.6 (0..1).")
	cfg.wave = {"sawtooth": "saw", "tri": "triangle", "pulse": "square", "sin": "sine", "white_noise": "noise"}.get(str(cfg.wave).to_lower(), str(cfg.wave).to_lower())
	if not (str(cfg.wave) in ["square", "sine", "saw", "triangle", "noise"]):
		var sw := U.suggest(str(cfg.wave), ["square", "sine", "saw", "triangle", "noise"])
		return U.err("Unknown wave '%s'." % cfg.wave, ("Did you mean '%s'? " % sw if sw != "" else "") + "Use square, sine, saw, triangle or noise.")
	var dur := clampf(float(cfg.duration), 0.01, 10.0)
	var rate := int(cfg.get("mix_rate", 44100))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", hash(path)))
	var variation := clampf(float(cfg.get("variation", 0.0)), 0.0, 1.0)
	if variation > 0.0:
		cfg.freq = float(cfg.freq) * (1.0 + rng.randf_range(-0.25, 0.25) * variation)
		if cfg.has("freq_end"):
			cfg.freq_end = float(cfg.freq_end) * (1.0 + rng.randf_range(-0.25, 0.25) * variation)
		dur *= 1.0 + rng.randf_range(-0.2, 0.2) * variation
	var samples := _synth(cfg, dur, rate, rng)
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	var loop := U.p_bool(p, "loop", false)
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	ctx.before_write([path])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := wav.save_to_wav(path)
	if err != OK:
		return U.err("Failed to write '%s' (error %d)." % [path, err])
	await import_new_file(path)
	var out := {"path": path, "duration_s": snappedf(dur, 0.001), "mix_rate": rate, "wave": cfg.wave, "imported": ResourceLoader.exists(path)}
	if preset != "":
		out["preset"] = preset
	if loop:
		var lr = await _set_loop(path, true, {})
		if not U.is_err(lr):
			out["loop"] = true
	out["hint"] = "Play it with audio.player {stream: '%s'} or assign it to an existing AudioStreamPlayer's stream." % path
	return out


func _synth(cfg: Dictionary, dur: float, rate: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var wave := str(cfg.wave)
	var f0 := maxf(1.0, float(cfg.freq))
	var f1 := maxf(1.0, float(cfg.get("freq_end", f0)))
	var attack := maxf(0.0, float(cfg.get("attack", 0.005)))
	var decay := clampf(float(cfg.get("decay", 0.1)), 0.0, dur)
	var duty := clampf(float(cfg.get("duty", 0.5)), 0.05, 0.95)
	var vol := clampf(float(cfg.get("volume", 0.6)), 0.0, 1.0)
	var vib_rate := float(cfg.get("vibrato_rate", 0.0))
	var vib_depth := float(cfg.get("vibrato_depth", 0.0))
	var arp_mult := float(cfg.get("arp_mult", 1.0))
	var arp_time := float(cfg.get("arp_time", 0.0))
	var noise_mix := clampf(float(cfg.get("noise_mix", 1.0 if wave == "noise" else 0.0)), 0.0, 1.0)
	var lp0 := float(cfg.get("lowpass", 0.0))
	var lp1 := float(cfg.get("lowpass_end", lp0))
	var phase := 0.0
	var noise_val := 0.0
	var noise_phase := 0.0
	var lp_state := 0.0
	var sustain_end := dur - decay
	for i in n:
		var t := float(i) / rate
		var k := t / dur
		var freq := f0 * pow(f1 / f0, k)  # exponential slide
		if arp_time > 0.0 and t >= arp_time:
			freq *= arp_mult
		if vib_rate > 0.0:
			freq *= 1.0 + sin(TAU * vib_rate * t) * vib_depth
		phase = fmod(phase + freq / rate, 1.0)
		var tone := 0.0
		match wave:
			"square", "noise":
				tone = 1.0 if phase < duty else -1.0
			"sine":
				tone = sin(TAU * phase)
			"saw":
				tone = 2.0 * phase - 1.0
			"triangle":
				tone = 4.0 * absf(phase - 0.5) - 1.0
		# sfxr-style noise: a new random value every half period, so pitch still matters.
		noise_phase += freq * 2.0 / rate
		if noise_phase >= 1.0:
			noise_phase = fmod(noise_phase, 1.0)
			noise_val = rng.randf_range(-1.0, 1.0)
		var s := lerpf(tone, noise_val, noise_mix)
		if lp0 > 0.0:
			var cutoff := lerpf(lp0, lp1, k)
			var a := clampf(TAU * cutoff / rate, 0.0, 1.0)
			lp_state += (s - lp_state) * a
			s = lp_state
		var env := 1.0
		if attack > 0.0 and t < attack:
			env = t / attack
		elif t > sustain_end and decay > 0.0:
			env = clampf(1.0 - (t - sustain_end) / decay, 0.0, 1.0)
		env *= env if t > sustain_end else 1.0  # exponential-ish tail
		out[i] = s * env * vol
	# Tiny fade in/out to avoid clicks.
	var fade := mini(64, n / 4)
	for i in fade:
		out[i] *= float(i) / fade
		out[n - 1 - i] *= float(i) / fade
	return out


## Makes the editor import a file that was just written (new folders need a scan first).
func import_new_file(path: String, timeout_ms: int = 15000) -> void:
	var efs := ctx.fs()
	if efs.get_filesystem_path(path.get_base_dir()) == null:
		efs.scan()
	else:
		efs.update_file(path)
		efs.reimport_files(PackedStringArray([path]))
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		await ctx.frame()
		if not efs.is_scanning() and ResourceLoader.exists(path) and FileAccess.file_exists(path + ".import"):
			break
	if ResourceLoader.has_cached(path):
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
