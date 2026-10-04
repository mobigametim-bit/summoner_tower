@tool
extends "res://addons/godot_forge/handlers/base.gd"
## Export presets (export_presets.cfg) and export template status. The actual export build
## runs server side (a separate headless Godot process), see src/tools/content/export.ts.

const PRESETS_FILE := "res://export_presets.cfg"
const PLATFORMS := {
	"windows": "Windows Desktop", "win": "Windows Desktop", "windows desktop": "Windows Desktop",
	"linux": "Linux", "linux/x11": "Linux", "x11": "Linux",
	"macos": "macOS", "mac": "macOS", "osx": "macOS",
	"web": "Web", "html5": "Web", "html": "Web", "browser": "Web",
	"android": "Android", "ios": "iOS",
}
## Template files that must exist (any one of each group) for release exports.
const TEMPLATE_FILES := {
	"Windows Desktop": [["windows_release_x86_64.exe"], ["windows_debug_x86_64.exe"]],
	"Linux": [["linux_release.x86_64"], ["linux_debug.x86_64"]],
	"macOS": [["macos.zip"], ["macos.zip"]],
	"Web": [["web_nothreads_release.zip", "web_release.zip"], ["web_nothreads_debug.zip", "web_debug.zip"]],
	"Android": [["android_release.apk", "android_source.zip"], ["android_debug.apk", "android_source.zip"]],
	"iOS": [["ios.zip"], ["ios.zip"]],
}


func _platform_name(s: String) -> String:
	var k := s.strip_edges().to_lower()
	if PLATFORMS.has(k):
		return PLATFORMS[k]
	for v in PLATFORMS.values():
		if str(v).to_lower() == k:
			return v
	return ""


func _load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(PRESETS_FILE):
		cfg.load(PRESETS_FILE)
	return cfg


func _preset_count(cfg: ConfigFile) -> int:
	var i := 0
	while cfg.has_section("preset.%d" % i):
		i += 1
	return i


func _preset_info(cfg: ConfigFile, i: int, with_options: bool) -> Dictionary:
	var sec := "preset.%d" % i
	var d := {"index": i, "name": cfg.get_value(sec, "name", ""), "platform": cfg.get_value(sec, "platform", ""),
		"runnable": cfg.get_value(sec, "runnable", false), "export_path": cfg.get_value(sec, "export_path", ""),
		"export_filter": cfg.get_value(sec, "export_filter", "all_resources")}
	var feats := str(cfg.get_value(sec, "custom_features", ""))
	if feats != "":
		d["custom_features"] = feats
	if str(cfg.get_value(sec, "exclude_filter", "")) != "":
		d["exclude_filter"] = cfg.get_value(sec, "exclude_filter")
	if str(cfg.get_value(sec, "include_filter", "")) != "":
		d["include_filter"] = cfg.get_value(sec, "include_filter")
	var osec := sec + ".options"
	if cfg.has_section(osec):
		d["option_count"] = cfg.get_section_keys(osec).size()
		if with_options:
			var opts := {}
			for k in cfg.get_section_keys(osec):
				opts[k] = U.encode(cfg.get_value(osec, k))
			d["options"] = opts
	return d


## Lists presets in export_presets.cfg (and template status for their platforms).
func a_presets(p: Dictionary):
	var cfg := _load_cfg()
	var out := []
	for i in _preset_count(cfg):
		out.append(_preset_info(cfg, i, U.p_bool(p, "options", false)))
	var res := {"presets": out, "file": PRESETS_FILE, "exists": FileAccess.file_exists(PRESETS_FILE)}
	if out.is_empty():
		res["hint"] = "No export presets yet. Add one with export.add_preset {platform: 'windows'|'linux'|'macos'|'web'|'android'}."
	var tpl = a_templates({})
	res["templates_installed"] = tpl.installed
	if not tpl.installed:
		res["templates_hint"] = tpl.hint
	return res


func _project_slug() -> String:
	var name := str(ProjectSettings.get_setting("application/config/name", "game"))
	var slug := ""
	for ch in name:
		if ch.is_valid_identifier() or ch.is_valid_int() or ch == "-":
			slug += ch
		elif ch == " " and not slug.ends_with("_"):
			slug += "_"
	slug = slug.strip_edges().trim_suffix("_")
	return slug if slug != "" else "game"


func _default_export_path(platform: String) -> String:
	var slug := _project_slug()
	match platform:
		"Windows Desktop": return "build/windows/%s.exe" % slug
		"Linux": return "build/linux/%s.x86_64" % slug
		"macOS": return "build/macos/%s.zip" % slug
		"Web": return "build/web/index.html"
		"Android": return "build/android/%s.apk" % slug
		"iOS": return "build/ios/%s.ipa" % slug
	return "build/%s" % slug


func _bundle_id() -> String:
	var s := _project_slug().to_lower().replace("_", "").replace("-", "")
	if s == "" or not s.substr(0, 1).is_valid_identifier():
		s = "game" + s
	return "com.example." + s


## Sensible option defaults per platform (the editor fills in every other option with its
## defaults when it loads the file).
func _default_options(platform: String) -> Dictionary:
	match platform:
		"Windows Desktop":
			return {"binary_format/architecture": "x86_64", "binary_format/embed_pck": false, "texture_format/s3tc_bptc": true, "texture_format/etc2_astc": false, "debug/export_console_wrapper": 1}
		"Linux":
			return {"binary_format/architecture": "x86_64", "binary_format/embed_pck": false, "texture_format/s3tc_bptc": true, "texture_format/etc2_astc": false}
		"macOS":
			return {"binary_format/architecture": "universal", "application/bundle_identifier": _bundle_id(), "texture_format/s3tc_bptc": true, "texture_format/etc2_astc": true}
		"Web":
			return {"variant/extensions_support": false, "variant/thread_support": false, "vram_texture_compression/for_desktop": true, "vram_texture_compression/for_mobile": false, "html/export_icon": true, "html/canvas_resize_policy": 2, "progressive_web_app/enabled": false}
		"Android":
			return {"gradle_build/use_gradle_build": false, "package/unique_name": _bundle_id(), "package/name": str(ProjectSettings.get_setting("application/config/name", "")), "architectures/arm64-v8a": true, "architectures/armeabi-v7a": false, "architectures/x86_64": false}
		"iOS":
			return {"application/bundle_identifier": _bundle_id(), "application/app_store_team_id": ""}
	return {}


## Adds (or updates, if a preset with the same name exists) an export preset.
## {platform, name?, export_path?, options?: {key: value}, runnable?=true, custom_features?,
##  export_filter?: all_resources|scenes|resources|exclude, include_filter?, exclude_filter?}
func a_add_preset(p: Dictionary):
	var e = U.require(p, ["platform"])
	if e: return e
	var platform := _platform_name(U.p_str(p, "platform"))
	if platform == "":
		var s := U.suggest(U.p_str(p, "platform"), ["windows", "linux", "macos", "web", "android", "ios"])
		return U.err("Unknown platform '%s'." % U.p_str(p, "platform"), ("Did you mean '%s'? " % s if s != "" else "") + "Use windows, linux, macos, web, android or ios.")
	var name := U.p_str(p, "name", platform)
	var filter := U.p_str(p, "export_filter", "all_resources")
	if not (filter in ["all_resources", "scenes", "resources", "exclude", "customized"]):
		return U.err("Unknown export_filter '%s'." % filter, "Use all_resources (default), scenes, resources or exclude.")
	var cfg := _load_cfg()
	var count := _preset_count(cfg)
	var idx := -1
	for i in count:
		if str(cfg.get_value("preset.%d" % i, "name", "")) == name:
			idx = i
	var created := idx < 0
	if created:
		idx = count
	var sec := "preset.%d" % idx
	if not created and str(cfg.get_value(sec, "platform", "")) != platform:
		return U.err("Preset '%s' already exists for platform %s." % [name, cfg.get_value(sec, "platform")], "Pick another name for the %s preset." % platform)
	var export_path := U.p_str(p, "export_path", str(cfg.get_value(sec, "export_path", "")) if not created else _default_export_path(platform))
	if export_path.begins_with("res://"):
		export_path = export_path.substr(6)
	if platform == "Web" and not export_path.ends_with(".html"):
		return U.err("Web exports must end in .html (got '%s')." % export_path, "e.g. build/web/index.html")
	if platform == "Windows Desktop" and not export_path.ends_with(".exe"):
		return U.err("Windows exports must end in .exe (got '%s')." % export_path, "e.g. build/windows/%s.exe" % _project_slug())
	if platform == "Android" and not (export_path.ends_with(".apk") or export_path.ends_with(".aab")):
		return U.err("Android exports must end in .apk or .aab (got '%s')." % export_path)
	var base := {
		"name": name, "platform": platform, "runnable": U.p_bool(p, "runnable", true), "advanced_options": false,
		"dedicated_server": U.p_bool(p, "dedicated_server", false), "custom_features": U.p_str(p, "custom_features", ""),
		"export_filter": filter, "include_filter": U.p_str(p, "include_filter", ""), "exclude_filter": U.p_str(p, "exclude_filter", ""),
		"export_path": export_path, "patches": PackedStringArray(), "encryption_include_filters": "", "encryption_exclude_filters": "",
		"seed": 0, "encrypt_pck": false, "encrypt_directory": false, "script_export_mode": 2,
	}
	if created:
		for k in base:
			cfg.set_value(sec, k, base[k])
	else:
		cfg.set_value(sec, "export_path", export_path)
		for k in ["runnable", "custom_features", "export_filter", "include_filter", "exclude_filter", "dedicated_server"]:
			if p.has(k):
				cfg.set_value(sec, k, base[k])
	var osec := sec + ".options"
	if created:
		var defaults := _default_options(platform)
		for k in defaults:
			cfg.set_value(osec, k, defaults[k])
	var opts := U.p_dict(p, "options")
	for k in opts:
		var v = opts[k]
		if v is float and v == floor(v):
			v = int(v)
		cfg.set_value(osec, str(k), v)
	# Only one runnable preset per platform: the editor's one-click deploy uses it.
	if cfg.get_value(sec, "runnable", false):
		for i in _preset_count(cfg):
			if i != idx and str(cfg.get_value("preset.%d" % i, "platform", "")) == platform:
				cfg.set_value("preset.%d" % i, "runnable", false)
	ctx.before_write([PRESETS_FILE])
	var err := cfg.save(PRESETS_FILE)
	if err != OK:
		return U.err("Could not write %s (error %d)." % [PRESETS_FILE, err])
	ctx.fs().update_file(PRESETS_FILE)
	var out := {"created": created, "preset": _preset_info(cfg, idx, true), "file": PRESETS_FILE,
		"next": "Build it with export.build {preset: '%s'}." % name}
	var tpl = a_templates({})
	var missing := _missing_templates(tpl, platform)
	if str(cfg.get_value(osec, "custom_template/release", "")) != "":
		missing = []
	if not missing.is_empty():
		out["warning"] = "Export templates for %s (%s) are not installed, so export.build will fail until they are (or set options custom_template/release to a template file). Download: %s — details via export.templates." % [platform, tpl.version, tpl.download_url]
	if platform == "Android":
		out["note"] = "Android also needs the Android SDK path and a keystore configured in Editor Settings (export/android/*); debug builds use the debug keystore."
	elif platform == "macOS" or platform == "iOS":
		out["note"] = "Code signing/notarization options are left at defaults; unsigned macOS builds run after right-click > Open."
	out["editor_note"] = "The open editor keeps its own copy of the presets; if you edit presets in Project > Export and save there, re-run this action afterwards."
	return out


## Removes a preset by name, re-indexing the rest (the editor requires contiguous indices).
func a_remove_preset(p: Dictionary):
	var e = U.require(p, ["name"])
	if e: return e
	var name := U.p_str(p, "name")
	var cfg := _load_cfg()
	var count := _preset_count(cfg)
	var idx := -1
	var names := []
	for i in count:
		var n := str(cfg.get_value("preset.%d" % i, "name", ""))
		names.append(n)
		if n == name:
			idx = i
	if idx < 0:
		var s := U.suggest(name, names)
		return U.err("No export preset named '%s'." % name, ("Did you mean '%s'? " % s if s != "" else "") + "Presets: " + ", ".join(names))
	var fresh := ConfigFile.new()
	var j := 0
	for i in count:
		if i == idx:
			continue
		for suffix in ["", ".options"]:
			var src := "preset.%d%s" % [i, suffix]
			if cfg.has_section(src):
				for k in cfg.get_section_keys(src):
					fresh.set_value("preset.%d%s" % [j, suffix], k, cfg.get_value(src, k))
		j += 1
	for sec in cfg.get_sections():
		if not sec.begins_with("preset."):
			for k in cfg.get_section_keys(sec):
				fresh.set_value(sec, k, cfg.get_value(sec, k))
	ctx.before_write([PRESETS_FILE])
	if fresh.save(PRESETS_FILE) != OK:
		return U.err("Could not write %s." % PRESETS_FILE)
	ctx.fs().update_file(PRESETS_FILE)
	names.erase(name)
	return {"removed": name, "presets": names}


func _version_dir_name() -> String:
	var v := Engine.get_version_info()
	var s := "%d.%d" % [v.major, v.minor]
	if int(v.patch) > 0:
		s += ".%d" % v.patch
	s += "." + str(v.status)
	if ClassDB.class_exists("CSharpScript"):
		s += ".mono"
	return s


## Reports whether export templates for the running Godot version are installed.
func a_templates(_p: Dictionary):
	var ver := _version_dir_name()
	var root := EditorInterface.get_editor_paths().get_data_dir().path_join("export_templates")
	var dir := root.path_join(ver)
	var installed := DirAccess.dir_exists_absolute(dir)
	var files := []
	if installed:
		files = Array(DirAccess.get_files_at(dir))
	var platforms := {}
	for plat in TEMPLATE_FILES:
		var rel_ok := false
		var dbg_ok := false
		for f in TEMPLATE_FILES[plat][0]:
			rel_ok = rel_ok or f in files
		for f in TEMPLATE_FILES[plat][1]:
			dbg_ok = dbg_ok or f in files
		platforms[plat] = {"release": rel_ok, "debug": dbg_ok}
	var others := []
	if DirAccess.dir_exists_absolute(root):
		for d in DirAccess.get_directories_at(root):
			if d != ver:
				others.append(d)
	var v := Engine.get_version_info()
	var tag := "%d.%d%s-%s" % [v.major, v.minor, (".%d" % v.patch) if int(v.patch) > 0 else "", v.status]
	var mono := "_mono" if ClassDB.class_exists("CSharpScript") else ""
	var url := "https://github.com/godotengine/godot/releases/download/%s/Godot_v%s%s_export_templates.tpz" % [tag, tag, mono]
	var out := {"version": ver, "installed": installed and not files.is_empty(), "dir": dir, "platforms": platforms, "file_count": files.size()}
	if not others.is_empty():
		out["other_versions_installed"] = others
	out["download_url"] = url
	if not out.installed:
		var hint := "Install templates for %s: in the editor use Editor > Manage Export Templates > Download and Install, or download %s and use Manage Export Templates > Install from File (a .tpz is a zip; its 'templates' folder contents go into %s)." % [ver, url, dir]
		if not others.is_empty():
			hint += " Note: templates for %s are installed but they only work with that exact Godot build." % ", ".join(others)
		out["hint"] = hint
	else:
		out["hint"] = "Templates are installed."
	return out


func _missing_templates(tpl: Dictionary, platform: String) -> Array:
	var st: Dictionary = tpl.platforms.get(platform, {})
	var missing := []
	if not st.get("release", false): missing.append("release")
	if not st.get("debug", false): missing.append("debug")
	return missing
