@tool
extends RefCounted

const ART_SPEC: String = "res://art/source/graveyard_animation/rig_spec.json"
const VISUAL_SCRIPT: Script = preload("res://scripts/visuals/undead_enemy_visual.gd")
const EFFECTS_SCRIPT: Script = preload("res://scripts/visuals/undead_ability_effects.gd")
const CLIP_SCRIPT: Script = preload("res://scripts/visuals/undead_effect_clip.gd")
const PARTS: Array[String] = ["back_accessory", "leg_left", "leg_right", "back_arm", "body", "weapon", "front_arm", "head"]
const BONE_NAMES: Dictionary = {"body":"Body", "head":"Head", "back_arm":"BackArm", "front_arm":"FrontArm", "leg_left":"LeftLeg", "leg_right":"RightLeg", "weapon":"Weapon"}

var _spec: Dictionary
var _root: Node2D
var _effect_paths: Dictionary[StringName, PackedScene] = {}


func build_visuals() -> Dictionary:
	_spec = JSON.parse_string(FileAccess.get_file_as_string(ART_SPEC)) as Dictionary
	for key: String in _spec:
		_build_rig(key, _spec[key])
	return {"rigs": _spec.size()}


func build_effects_and_bind() -> Dictionary:
	_spec = JSON.parse_string(FileAccess.get_file_as_string(ART_SPEC)) as Dictionary
	for effect: String in ["bone_shield", "regenerate", "dash", "heal", "summon_skeletons", "assemble_flesh", "retinue", "bone_cover", "grave_bell", "spawn", "impact", "heavy_slam", "hex_impact", "flesh_arrives", "flesh_birth"]:
		_effect_paths[StringName(effect)] = _build_effect(effect)
	for key: String in _spec:
		var packed: PackedScene = ResourceLoader.load(_spec[key].scene,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var visual: Node2D = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		var bank: Dictionary[StringName, PackedScene] = {}
		for ability: String in _spec[key].abilities:
			bank[StringName(ability)] = _effect_paths[StringName(ability)]
		bank[&"spawn"] = _effect_paths[&"flesh_birth" if key == "flesh_golem" else &"spawn"]
		bank[&"impact"] = _effect_paths[&"heavy_slam" if key == "flesh_golem" else (&"hex_impact" if key in ["lich", "necromancer"] else &"impact")]
		if key == "necromancer":
			bank[&"flesh_arrives"] = _effect_paths[&"flesh_arrives"]
		visual.get_node("AbilityEffects").set("effect_scenes", bank)
		_save(visual, _spec[key].scene)
	return {"effects": _effect_paths.size(), "rigs_bound": _spec.size()}


func _label(parent: Node, node_name: String, text: String, rect: Rect2, font_size: int = 22, color: Color = Color("d3dfd9")) -> Label:
	var label: Label = _node("Label", node_name, parent) as Label
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(parent: Node, node_name: String, text: String, rect: Rect2, toggle: bool = false) -> Button:
	var button: Button = _node("Button", node_name, parent) as Button
	button.position = rect.position
	button.size = rect.size
	button.text = text
	button.toggle_mode = toggle
	button.add_theme_font_size_override("font_size", 22)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color("344d43") if state == "pressed" else Color("22333b")
		style.border_color = Color("a2eac1") if state in ["pressed", "focus"] else Color("49645c")
		style.set_border_width_all(2)
		style.set_corner_radius_all(9)
		button.add_theme_stylebox_override(state, style)
	return button


func _actor(parent: Node, node_name: String, key: String, point: Vector2, size_factor: float, level: int) -> Node2D:
	var scene: PackedScene = ResourceLoader.load(_spec[key].scene, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var actor: Node2D = scene.instantiate() as Node2D
	actor.name = node_name
	actor.position = point
	actor.scale = Vector2.ONE * size_factor
	actor.set("level", level)
	parent.add_child(actor)
	return actor


func build_preview() -> Dictionary:
	_spec = JSON.parse_string(FileAccess.get_file_as_string(ART_SPEC)) as Dictionary
	var root: Control = Control.new()
	root.name = "GraveyardAnimationReview"
	root.size = Vector2(720,1280)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.set_script(load("res://scripts/debug/graveyard_animation_review.gd"))
	var theme: Theme = Theme.new()
	theme.default_font = ThemeDB.fallback_font
	theme.default_font_size = 22
	root.theme = theme
	var background: ColorRect = _node("ColorRect","Background",root) as ColorRect
	background.color = Color("101820")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -100
	var center: Control = _node("Control","Center",root) as Control
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.offset_left = -360
	center.offset_right = 360
	center.offset_bottom = 1280
	_label(center,"Title","КЛАДБИЩЕ · АНИМАЦИИ",Rect2(16,16,688,44),30,Color("e6bd68"))
	var all_button: Button = _button(center,"OverviewButton","Все противники",Rect2(16,74,336,52),true)
	all_button.pressed.connect(Callable(root,"show_overview"),Object.CONNECT_PERSIST)
	var focus_button: Button = _button(center,"FocusButton","Крупно + эффекты",Rect2(368,74,336,52),true)
	focus_button.pressed.connect(Callable(root,"show_focus"),Object.CONNECT_PERSIST)
	_label(center,"Hint","Нажми персонажа. Уровни и клипы переключаются внизу.",Rect2(16,144,688,40),20,Color("a8c5b8"))
	var overview: Node2D = _node("Node2D","Overview",center) as Node2D
	overview.position = Vector2(0,200)
	var focus: Node2D = _node("Node2D","Focus",center) as Node2D
	focus.position = Vector2(0,200)
	focus.visible = false
	var index: int = 0
	for key: String in _spec:
		var card: Panel = _node("Panel","Card%d" % index,overview) as Panel
		card.position = Vector2(16 + (index % 2)*352, floori(index / 2.0)*232)
		card.size = Vector2(336,224)
		card.z_index = -30
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color("1c2a2d")
		style.border_color = Color("3c5750")
		style.set_border_width_all(2)
		style.set_corner_radius_all(12)
		card.add_theme_stylebox_override("panel",style)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hit: Button = _button(card,"Choose","",Rect2(0,0,336,224))
		for state: String in ["normal","hover","pressed"]:
			hit.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		hit.pressed.connect(Callable(root,"select_asset").bind(index),Object.CONNECT_PERSIST)
		var title: Label = _label(card,"Title",_spec[key].title,Rect2(10,6,316,34),24,Color("e6bd68"))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var level_label: Label = _label(card,"Level","Lv5",Rect2(10,39,316,28),18,Color("b66dea"))
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_actor(card,"Actor",key,Vector2(168,137),0.65,5)
		index += 1
	var focus_title: Label = _label(focus,"Title","Скелет · 5",Rect2(16,0,688,40),28,Color("e6bd68"))
	focus_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var floor_patch: Polygon2D = _node("Polygon2D","Floor",focus) as Polygon2D
	floor_patch.z_index = -25
	floor_patch.color = Color("263731")
	var polygon: PackedVector2Array = []
	for i: int in 64:
		var angle: float = i * TAU / 64.0
		polygon.append(Vector2(360,425) + Vector2(cos(angle)*330,sin(angle)*53))
	floor_patch.polygon = polygon
	var actors: Node2D = _node("Node2D","Actors",focus) as Node2D
	var samples: Node2D = _node("Node2D","Samples",focus) as Node2D
	for key: String in _spec:
		_actor(actors,key.to_pascal_case(),key,Vector2(275,280),1.15,5)
		_actor(samples,key.to_pascal_case(),key,Vector2(136,598),0.4375,5)
	_label(focus,"RealScale","Игровой размер · 112 px",Rect2(18,665,270,32),18,Color("a7c5b6"))
	var note: Label = _label(focus,"Note","",Rect2(300,480,386,198),21)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var peers: Node2D = _node("Node2D","Peers",focus) as Node2D
	peers.position = Vector2(275,280)
	peers.scale = Vector2.ONE * 1.15
	for peer: String in ["SkeletonA","SkeletonB","SkeletonC"]:
		var actor: Node2D = _actor(peers,peer,"skeleton",Vector2(230,20),0.65,1)
		actor.visible = false
	var flesh: Node2D = _actor(peers,"Flesh","flesh_golem",Vector2(230,20),0.65,4)
	flesh.visible = false
	var controls: Control = _node("Control","Controls",center) as Control
	controls.z_index = 60
	var asset: OptionButton = _node("OptionButton","Asset",controls) as OptionButton
	asset.position = Vector2(16,920)
	asset.size = Vector2(688,48)
	asset.add_theme_font_size_override("font_size",24)
	for key: String in _spec:
		asset.add_item(_spec[key].title)
	asset.item_selected.connect(Callable(root,"_on_asset_selected"),Object.CONNECT_PERSIST)
	var tier_colors: Array[Color] = [Color("88b96b"),Color("ec9b49"),Color("df5654"),Color("5295ef"),Color("b66dea")]
	for i: int in 5:
		var button: Button = _button(controls,"Level%d" % (i+1),"Lv%d" % (i+1),Rect2(16+i*140,980,128,50),true)
		button.add_theme_color_override("font_color",tier_colors[i])
		button.add_theme_color_override("font_pressed_color",tier_colors[i])
		button.pressed.connect(Callable(root,"set_level").bind(i+1),Object.CONNECT_PERSIST)
	var animation: OptionButton = _node("OptionButton","Animation",controls) as OptionButton
	animation.position = Vector2(16,1042)
	animation.size = Vector2(688,48)
	animation.add_theme_font_size_override("font_size",24)
	animation.item_selected.connect(Callable(root,"_on_animation_selected"),Object.CONNECT_PERSIST)
	for i: int in 3:
		var button: Button = _button(controls,["Replay","Pause","Auto"][i],["Повтор","Пауза","Автопоказ"][i],Rect2(16+i*236,1102,216,52),i==2)
		button.pressed.connect(Callable(root,["replay","toggle_pause","toggle_auto"][i]),Object.CONNECT_PERSIST)
	for i: int in 3:
		var button: Button = _button(controls,"Speed%d" % i,["0.5×","1×","2×"][i],Rect2(16+i*236,1166,216,50),true)
		button.button_pressed = i == 1
		button.pressed.connect(Callable(root,"set_speed").bind([0.5,1.0,2.0][i]),Object.CONNECT_PERSIST)
	var repeat: CheckButton = _node("CheckButton","Repeat",controls) as CheckButton
	repeat.text = "Повторять клип"
	repeat.button_pressed = true
	repeat.position = Vector2(16,1230)
	repeat.size = Vector2(320,42)
	_label(controls,"StageNote","Превью · без изменения баланса",Rect2(350,1237,360,32),17,Color("a8bdb1"))
	var timer: Timer = _node("Timer","ReplayTimer",root) as Timer
	timer.one_shot = true
	timer.timeout.connect(Callable(root,"replay"),Object.CONNECT_PERSIST)
	var auto_timer: Timer = _node("Timer","AutoTimer",root) as Timer
	auto_timer.one_shot = true
	auto_timer.timeout.connect(Callable(root,"_auto_step"),Object.CONNECT_PERSIST)
	_save(root,"res://scenes/debug/GraveyardAnimationReview.tscn")
	return {"scene":"res://scenes/debug/GraveyardAnimationReview.tscn","actors":6,"levels":27,"controls":"asset,level,clip,replay,pause,speed,auto"}


func _node(kind: String, node_name: String, parent: Node) -> Node:
	var result: Node = ClassDB.instantiate(kind) as Node
	result.name = node_name
	parent.add_child(result)
	return result


func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		if child.owner == null:
			child.owner = owner
		if child.scene_file_path.is_empty():
			_own(child, owner)


func _save(node: Node, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_own(node, node)
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(node) == OK)
	assert(ResourceSaver.save(packed, path) == OK)
	node.free()


func _track(animation: Animation, path: String, times: Array, values: Array, interpolation: int = Animation.INTERPOLATION_LINEAR) -> void:
	var index: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(index, NodePath(path))
	animation.track_set_interpolation_type(index, interpolation)
	for i: int in times.size():
		animation.track_insert_key(index, float(times[i]), values[i])


func _event(animation: Animation, time: float, effect: StringName) -> void:
	var index: int = animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(index, NodePath("."))
	animation.track_insert_key(index, time, {"method":&"_emit_effect", "args":[effect]})


func _animation(library: AnimationLibrary, clip: String, duration: float, loop: bool = false) -> Animation:
	var result: Animation = Animation.new()
	result.length = duration
	result.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	result.step = 0.01
	library.add_animation(StringName(clip), result)
	return result


func _reset(root: Node, library: AnimationLibrary) -> void:
	var reset: Animation = Animation.new()
	reset.length = 0.001
	var paths: Dictionary = {}
	for clip: StringName in library.get_animation_list():
		var animation: Animation = library.get_animation(clip)
		for index: int in animation.get_track_count():
			if animation.track_get_type(index) != Animation.TYPE_VALUE:
				continue
			var path: String = str(animation.track_get_path(index))
			if paths.has(path):
				continue
			paths[path] = true
			var node_path: String = path.get_slice(":", 0)
			var property: String = path.substr(node_path.length() + 1)
			var node: Node = root if node_path == "." else root.get_node(node_path)
			_track(reset, path, [0.0], [node.get_indexed(NodePath(property))])
	library.add_animation(&"RESET", reset)


func _build_rig(key: String, profile: Dictionary) -> void:
	_root = Node2D.new()
	_root.name = key.to_pascal_case() + "Visual"
	_root.set_script(VISUAL_SCRIPT)
	_root.set("entity_key", StringName(key))
	_root.set("level_ids", PackedInt32Array(profile.levels))
	_root.set("level", int(profile.levels[0]))
	var abilities: Dictionary[StringName, int] = {}
	for name: String in profile.abilities:
		abilities[StringName(name)] = int(profile.abilities[name])
	_root.set("ability_levels", abilities)
	var shadow: Sprite2D = _node("Sprite2D", "Shadow", _root) as Sprite2D
	shadow.texture = load("res://assets/vfx/undead/shadow.svg")
	shadow.position = Vector2(0, 111)
	shadow.z_index = -20
	var skeleton: Skeleton2D = _node("Skeleton2D", "Skeleton2D", _root) as Skeleton2D
	var rig_root: Bone2D = _node("Bone2D", "Root", skeleton) as Bone2D
	rig_root.position = Vector2(-128, -128)
	rig_root.set_autocalculate_length_and_angle(false)
	rig_root.set_length(32)
	rig_root.rest = rig_root.transform
	var bones: Dictionary = {}
	for part: String in ["body", "head", "back_arm", "front_arm", "leg_left", "leg_right", "weapon"]:
		if not profile.has(part):
			continue
		var parent: Node = rig_root if part == "body" else (bones.front_arm if part == "weapon" else bones.body)
		var bone: Bone2D = _node("Bone2D", BONE_NAMES[part], parent) as Bone2D
		var point: Vector2 = Vector2(profile[part][0], profile[part][1])
		var parent_point: Vector2 = Vector2.ZERO
		if part != "body":
			var parent_part: String = "front_arm" if part == "weapon" else "body"
			parent_point = Vector2(profile[parent_part][0], profile[parent_part][1])
		bone.position = point - parent_point
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(30.0 if part in ["body", "head"] else 24.0)
		bone.rest = bone.transform
		bones[part] = bone
	var variants: Dictionary[StringName, Array] = {}
	var paths: Dictionary[StringName, NodePath] = {}
	for part: String in PARTS:
		var images: Array = profile.parts[part]
		if images.all(func(value: Variant) -> bool: return value == null):
			continue
		var parent_part: String = "body" if part == "back_accessory" else part
		var sprite: Sprite2D = _node("Sprite2D", "Accessory" if part == "back_accessory" else "Sprite", bones[parent_part]) as Sprite2D
		sprite.centered = false
		sprite.position = -Vector2(profile[parent_part][0], profile[parent_part][1])
		# SVG imports are 128px; source and pivots retain the common 256px canvas.
		sprite.scale = Vector2.ONE * 2.0
		sprite.z_as_relative = false
		sprite.z_index = PARTS.find(part)
		var textures: Array = []
		for path: Variant in images:
			textures.append(load(str(path)) if path != null else null)
		sprite.texture = textures[0]
		sprite.visible = sprite.texture != null
		variants[StringName(part)] = textures
		paths[StringName(part)] = _root.get_path_to(sprite)
	_root.set("part_variants", variants)
	_root.set("part_paths", paths)
	var effects: Node2D = _node("Node2D", "AbilityEffects", _root) as Node2D
	effects.z_index = 30
	effects.set_script(EFFECTS_SCRIPT)
	var player: AnimationPlayer = _node("AnimationPlayer", "AnimationPlayer", _root) as AnimationPlayer
	player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	var library: AnimationLibrary = AnimationLibrary.new()
	player.add_animation_library(&"", library)
	_rig_clips(key, profile, library)
	_reset(_root, library)
	_save(_root, profile.scene)


func _rig_clips(key: String, profile: Dictionary, library: AnimationLibrary) -> void:
	var body: String = "Skeleton2D/Root/Body"
	var head: String = body + "/Head"
	var back: String = body + "/BackArm"
	var front: String = body + "/FrontArm"
	var left: String = body + "/LeftLeg"
	var right: String = body + "/RightLeg"
	var weapon: String = front + "/Weapon"
	var base: Vector2 = Vector2(profile.body[0], profile.body[1])
	var neck: Vector2 = Vector2(profile.head[0], profile.head[1]) - base
	var duration: float = float(profile.walk)
	var times: Array = [0.0, duration * 0.25, duration * 0.5, duration * 0.75, duration]
	var walk: Animation = _animation(library, "walk_loop", duration, true)
	var stride: float = 0.20 if key not in ["lich", "necromancer"] else 0.08
	var sway: float = 0.14 if key in ["skeleton", "ghoul"] else 0.08
	var bob: float = 6.0 if key == "ghoul" else 3.5
	_track(walk, left + ":rotation", times, [-stride, 0.0, stride, 0.0, -stride], Animation.INTERPOLATION_CUBIC)
	_track(walk, right + ":rotation", times, [stride, 0.0, -stride, 0.0, stride], Animation.INTERPOLATION_CUBIC)
	_track(walk, body + ":position", times, [base, base + Vector2(0, -bob), base, base + Vector2(0, -bob), base], Animation.INTERPOLATION_CUBIC)
	_track(walk, body + ":rotation", times, [-0.035, 0.0, 0.035, 0.0, -0.035], Animation.INTERPOLATION_CUBIC)
	_track(walk, head + ":rotation", times, [-sway, 0.0, sway, 0.0, -sway], Animation.INTERPOLATION_CUBIC)
	_track(walk, head + ":position", times, [neck, neck + Vector2(0, -2), neck, neck + Vector2(0, -2), neck], Animation.INTERPOLATION_CUBIC)
	_track(walk, back + ":rotation", times, [sway, 0.0, -sway, 0.0, sway], Animation.INTERPOLATION_CUBIC)
	_track(walk, front + ":rotation", times, [-sway, 0.0, sway, 0.0, -sway], Animation.INTERPOLATION_CUBIC)
	if profile.has("weapon"):
		_track(walk, weapon + ":rotation", times, [-0.06, 0.0, 0.06, 0.0, -0.06], Animation.INTERPOLATION_CUBIC)
	var attack_length: float = 0.72 if key == "flesh_golem" else 0.55
	var impact: float = 0.38 if key == "flesh_golem" else 0.28
	var attack: Animation = _animation(library, "attack", attack_length)
	var attack_times: Array = [0.0, impact * 0.65, impact, attack_length]
	_track(attack, front + ":rotation", attack_times, [0.0, -0.85, 0.55, 0.0])
	_track(attack, body + ":rotation", attack_times, [0.0, -0.07, 0.10, 0.0])
	_track(attack, head + ":rotation", attack_times, [0.0, -0.08, 0.12, 0.0])
	_track(attack, body + ":position", attack_times, [base, base + Vector2(-4, -5), base + Vector2(5, 4), base])
	if key in ["flesh_golem", "ghoul"]:
		_track(attack, back + ":rotation", attack_times, [0.0, 0.70, -0.5, 0.0])
	if profile.has("weapon"):
		_track(attack, weapon + ":rotation", attack_times, [0.0, -0.25, 0.32, 0.0])
	_event(attack, impact, &"impact")
	var hit: Animation = _animation(library, "hit", 0.22)
	_track(hit, body + ":rotation", [0.0, 0.06, 0.22], [0.0, -0.10, 0.0])
	_track(hit, head + ":rotation", [0.0, 0.06, 0.22], [0.0, 0.13, 0.0])
	_track(hit, "Skeleton2D/Root:modulate", [0.0, 0.045, 0.12, 0.22], [Color.WHITE, Color(1.7, 1.35, 1.25), Color(1.25, 1.1, 1.1), Color.WHITE])
	var death: Animation = _animation(library, "death", 0.68)
	_track(death, body + ":rotation", [0.0, 0.18, 0.50, 0.68], [0.0, -0.12, 0.56, 0.72])
	_track(death, body + ":position", [0.0, 0.18, 0.68], [base, base + Vector2(0, 9), base + Vector2(0, 38)])
	_track(death, head + ":rotation", [0.0, 0.35, 0.68], [0.0, -0.28, -0.42])
	_track(death, front + ":rotation", [0.0, 0.35, 0.68], [0.0, 0.6, 0.8])
	_track(death, "Skeleton2D/Root:modulate", [0.0, 0.28, 0.68], [Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	_track(death, "Shadow:modulate", [0.0, 0.68], [Color.WHITE, Color(1, 1, 1, 0)])
	var intro_length: float = 1.3 if key == "flesh_golem" else 0.76
	var intro: Animation = _animation(library, "spawn_or_intro", intro_length)
	_track(intro, body + ":position", [0.0, intro_length*0.45, intro_length*0.76, intro_length], [base + Vector2(0, 35), base + Vector2(0, -6), base + Vector2(0, 2), base])
	_track(intro, "Skeleton2D/Root:modulate", [0.0, intro_length*0.25, intro_length*0.65, intro_length], [Color(1, 1, 1, 0), Color(1.3, 1.5, 1.4, 0.2), Color(1.1, 1.2, 1.1), Color.WHITE])
	_event(intro, 0.02, &"spawn")
	for ability: String in profile.abilities:
		var length: float = 2.1 if ability == "assemble_flesh" else (0.95 if ability == "dash" else 1.9)
		var clip: Animation = _animation(library, ability, length)
		var power_times: Array = [0.0, 0.26, 0.50, length - 0.25, length]
		_track(clip, body + ":rotation", power_times, [0.0, -0.05, 0.04, 0.02, 0.0])
		_track(clip, head + ":rotation", power_times, [0.0, -0.10, 0.07, 0.03, 0.0])
		_track(clip, front + ":rotation", power_times, [0.0, -0.42, -0.18, -0.15, 0.0])
		_track(clip, back + ":rotation", power_times, [0.0, 0.30, 0.12, 0.10, 0.0])
		if ability == "dash":
			_track(clip, body + ":position", power_times, [base, base + Vector2(-7, 5), base + Vector2(9, 4), base + Vector2(5, 2), base])
		elif ability == "regenerate":
			_track(clip, "Skeleton2D/Root:modulate", power_times, [Color.WHITE, Color(0.75, 1.5, 0.95), Color(0.9, 1.25, 0.9), Color(0.9, 1.15, 0.95), Color.WHITE])
		_event(clip, 0.30, StringName(ability))
		if ability == "assemble_flesh" and key == "necromancer":
			_event(clip, 1.20, &"flesh_arrives")


func _particles(parent: Node, node_name: String, mask: String, amount: int, point: Vector2, color: Color, duration: float = 0.9) -> CPUParticles2D:
	var particles: CPUParticles2D = _node("CPUParticles2D", node_name, parent) as CPUParticles2D
	particles.position = point
	particles.emitting = false
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = duration
	particles.explosiveness = 0.7
	particles.local_coords = true
	particles.texture = load("res://assets/vfx/undead/" + mask + ".svg")
	if mask in ["wisp", "beam", "spark", "slash", "rune"]:
		var glow: CanvasItemMaterial = CanvasItemMaterial.new()
		glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		particles.material = glow
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 42
	particles.direction = Vector2.UP
	particles.spread = 50
	particles.gravity = Vector2(0, -18)
	particles.initial_velocity_min = 35
	particles.initial_velocity_max = 80
	particles.scale_amount_min = 0.38
	particles.scale_amount_max = 0.75
	particles.angular_velocity_min = -60
	particles.angular_velocity_max = 60
	particles.color = color
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.12, 0.6, 1])
	gradient.colors = PackedColorArray([Color(1,1,1,0), Color.WHITE, Color(1,1,1,0.9), Color(1,1,1,0)])
	particles.color_ramp = gradient
	return particles


func _build_effect(key: String) -> PackedScene:
	return load("res://scripts/debug/graveyard_vfx_builder.gd").new().build(self, key)
