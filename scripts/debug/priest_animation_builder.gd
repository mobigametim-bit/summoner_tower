@tool
extends RefCounted

var b: RefCounted = preload("res://scripts/debug/graveyard_animation_builder.gd").new()
const BODY: String = "Skeleton2D/Root/Body"
const STAFF: String = BODY+"/FrontArm/Staff"
const BASE: String = "res://scenes/vfx/priest/"


func build() -> Dictionary:
	_visual()
	_effects()
	_preview()
	return {"visual":"res://scenes/visuals/PriestVisual.tscn","preview":"res://scenes/debug/PriestAnimationReview.tscn","bones":8,"effects":4}


func _bone(node_name: String, parent: Node2D, position: Vector2) -> Bone2D:
	var bone: Bone2D = b._node("Bone2D",node_name,parent) as Bone2D
	bone.position = position
	bone.set_autocalculate_length_and_angle(false)
	bone.set_length(24.0)
	bone.rest = bone.transform
	return bone


func _visual() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/source/priest/rig_manifest.json"))
	var root: Node2D = Node2D.new()
	root.name = "PriestVisual"
	root.set_script(load("res://scripts/visuals/priest_visual.gd"))
	var shadow: Sprite2D = b._node("Sprite2D","Shadow",root) as Sprite2D
	shadow.texture = load("res://assets/vfx/undead/shadow.svg")
	shadow.position = Vector2(0,111)
	shadow.scale = Vector2(0.9,0.7)
	shadow.z_index = -10
	var skeleton: Skeleton2D = b._node("Skeleton2D","Skeleton2D",root) as Skeleton2D
	var rig_root: Bone2D = _bone("Root",skeleton,Vector2(-128,-128))
	var bones: Dictionary = {"Root":rig_root}
	var pivots: Dictionary = {"Root":Vector2.ZERO}
	for node_name: String in ["Body","Head","BackArm","FrontArm","Staff","LeftLeg","RightLeg"]:
		for part: Dictionary in spec.parts:
			if part.bone == node_name:
				var pivot: Vector2 = Vector2(part.pivot[0],part.pivot[1])
				bones[node_name] = _bone(node_name,bones[part.parent_bone],pivot-pivots[part.parent_bone])
				pivots[node_name] = pivot
	var variants: Dictionary[StringName,Array] = {}
	var paths: Dictionary[StringName,NodePath] = {}
	for part: Dictionary in spec.parts:
		var bone_name: String = part.bone if part.bone != null else part.parent_bone
		var sprite: Sprite2D = b._node("Sprite2D","Halo" if part.name == "halo" else "Sprite",bones[bone_name]) as Sprite2D
		sprite.centered = false
		sprite.position = Vector2(part.sprite_offset[0],part.sprite_offset[1])
		sprite.z_index = int(part.z_index)
		sprite.z_as_relative = false
		var textures: Array = []
		for level: int in range(1,6):
			var path: Variant = spec.levels[str(level)].parts[part.name]
			textures.append(load("res://art/source/priest/"+str(path)) if path != null else null)
		sprite.texture = textures[0]
		sprite.visible = sprite.texture != null
		variants[StringName(part.name)] = textures
		paths[StringName(part.name)] = root.get_path_to(sprite)
	root.set("part_variants",variants)
	root.set("part_paths",paths)
	var point: Marker2D = b._node("Marker2D","ReleasePoint",bones.Staff) as Marker2D
	point.position = Vector2(9,-85)
	var energy: Sprite2D = b._node("Sprite2D","Energy",point) as Sprite2D
	energy.texture = load("res://assets/vfx/priest/light_orb.svg")
	energy.modulate = Color(1,0.88,0.55,0)
	energy.z_index = 20
	var sparks: CPUParticles2D = _particles(point,"StaffParticles",7,0.8)
	sparks.one_shot = false
	sparks.explosiveness = 0.0
	sparks.emission_sphere_radius = 12
	sparks.initial_velocity_min = 5
	sparks.initial_velocity_max = 15
	sparks.scale_amount_min = 0.3
	sparks.scale_amount_max = 0.5
	sparks.emitting = true
	var rays: Node = load("res://scenes/vfx/SummonRays.tscn").instantiate()
	rays.name = "SummonRays"
	root.add_child(rays)
	(rays as Node2D).position = Vector2(0,110)
	var player: AnimationPlayer = b._node("AnimationPlayer","AnimationPlayer",root) as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	player.animation_finished.connect(Callable(root,"_on_animation_finished"),Object.CONNECT_PERSIST)
	var library: AnimationLibrary = AnimationLibrary.new()
	player.add_animation_library(&"",library)
	var idle: Animation = b._animation(library,"idle_loop",1.2,true)
	b._track(idle,BODY+":position",[0,.3,.6,.9,1.2],[Vector2(128,175),Vector2(128,172),Vector2(128,170),Vector2(128,172),Vector2(128,175)],Animation.INTERPOLATION_CUBIC)
	b._track(idle,BODY+"/Head:rotation",[0,.3,.6,.9,1.2],[-0.025,0.0,0.025,0.0,-0.025],Animation.INTERPOLATION_CUBIC)
	b._track(idle,BODY+"/BackArm:rotation",[0,.6,1.2],[0.025,-0.035,0.025],Animation.INTERPOLATION_CUBIC)
	b._track(idle,BODY+"/FrontArm:rotation",[0,.6,1.2],[-0.02,0.025,-0.02],Animation.INTERPOLATION_CUBIC)
	var cast: Animation = b._animation(library,"cast",0.5)
	var times: Array = [0.0,0.12,0.18,0.26,0.5]
	b._track(cast,BODY+"/BackArm:rotation",times,[0.0,0.18,0.12,0.08,0.0])
	b._track(cast,BODY+"/FrontArm:rotation",times,[0.0,-0.20,-0.12,0.07,0.0])
	b._track(cast,STAFF+":rotation",times,[0.0,-0.07,0.03,0.08,0.0])
	b._track(cast,BODY+"/Head:rotation",times,[0.0,-0.045,0.035,0.02,0.0])
	b._track(cast,BODY+":position",times,[Vector2(128,175),Vector2(126,171),Vector2(130,173),Vector2(129,175),Vector2(128,175)])
	b._track(cast,STAFF+"/ReleasePoint/Energy:modulate",times,[Color(1,0.88,0.55,0),Color(1,0.88,0.55,0.7),Color(1,1,0.8,1),Color(1,0.88,0.55,0.2),Color(1,0.88,0.55,0)])
	b._track(cast,STAFF+"/ReleasePoint/Energy:scale",times,[Vector2.ONE*0.4,Vector2.ONE,Vector2.ONE*1.5,Vector2.ONE*0.8,Vector2.ONE*0.4])
	var event: int = cast.add_track(Animation.TYPE_METHOD)
	cast.track_set_path(event,NodePath("."))
	cast.track_insert_key(event,0.18,{"method":&"_emit_release","args":[]})
	var spawn: Animation = b._animation(library,"spawn",0.45)
	b._track(spawn,"Skeleton2D/Root:position",[0.0,0.2,0.32,0.45],[Vector2(-128,-98),Vector2(-128,-136),Vector2(-128,-125),Vector2(-128,-128)])
	b._track(spawn,"Skeleton2D/Root:scale",[0.0,0.2,0.45],[Vector2.ONE*0.75,Vector2(1.05,1.02),Vector2.ONE])
	b._track(spawn,"Skeleton2D/Root:modulate",[0.0,0.12,0.45],[Color(1,1,1,0),Color(1.2,1.15,1,0.8),Color.WHITE])
	b._reset(root,library)
	var spawn_player: AnimationPlayer = b._node("AnimationPlayer","SpawnPlayer",root) as AnimationPlayer
	var spawn_library: AnimationLibrary = AnimationLibrary.new()
	spawn_library.add_animation(&"spawn",spawn)
	spawn_player.add_animation_library(&"",spawn_library)
	b._save(root,"res://scenes/visuals/PriestVisual.tscn")


func _particles(parent: Node, node_name: String, amount: int, lifetime: float) -> CPUParticles2D:
	var p: CPUParticles2D = b._node("CPUParticles2D",node_name,parent) as CPUParticles2D
	p.texture = load("res://assets/vfx/priest/light_orb.svg")
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.gravity = Vector2.ZERO
	p.direction = Vector2.UP
	p.spread = 180
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 5
	p.initial_velocity_min = 35
	p.initial_velocity_max = 95
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.5
	p.color = Color("ffdc84")
	p.z_index = 20
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0,0.15,0.65,1])
	gradient.colors = PackedColorArray([Color(1,1,1,0),Color.WHITE,Color(1,1,1,0.9),Color(1,1,1,0)])
	p.color_ramp = gradient
	return p


func _effect_root(node_name: String) -> Node2D:
	var root: Node2D = Node2D.new()
	root.name = node_name
	root.z_index = 12
	root.set_script(load("res://scripts/visuals/undead_effect_clip.gd"))
	return root


func _sprite(parent: Node, node_name: String, path: String) -> Sprite2D:
	var result: Sprite2D = b._node("Sprite2D",node_name,parent) as Sprite2D
	result.texture = load(path)
	return result


func _effect_player(root: Node2D, duration: float) -> Animation:
	var player: AnimationPlayer = b._node("AnimationPlayer","AnimationPlayer",root) as AnimationPlayer
	var library: AnimationLibrary = AnimationLibrary.new()
	player.add_animation_library(&"",library)
	return b._animation(library,"effect",duration)


func _effects() -> void:
	var root: Node2D = Node2D.new()
	root.name = "LightShot"
	root.z_index = 15
	var core: Sprite2D = _sprite(root,"Core","res://assets/vfx/priest/light_orb.svg")
	core.scale = Vector2(2,2)
	var glow: Sprite2D = _sprite(root,"Glow","res://assets/vfx/priest/light_orb.svg")
	glow.scale = Vector2(3.2,3.2)
	glow.modulate = Color(1,0.78,0.3,0.25)
	glow.show_behind_parent = true
	var trail: CPUParticles2D = _particles(root,"Trail",14,0.32)
	trail.one_shot = false
	trail.explosiveness = 0.0
	trail.local_coords = false
	trail.initial_velocity_min = 0
	trail.initial_velocity_max = 12
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 0.9
	trail.emitting = true
	b._save(root,BASE+"LightShot.tscn")
	root = _effect_root("LightImpact")
	_particles(root,"Sparks",12,0.45)
	var flash: Sprite2D = _sprite(root,"Flash","res://assets/vfx/priest/light_orb.svg")
	var clip: Animation = _effect_player(root,0.6)
	b._track(clip,"Flash:scale",[0,.06,.22],[Vector2.ONE*0.4,Vector2.ONE*2.0,Vector2.ONE*2.7])
	b._track(clip,"Flash:modulate",[0,.06,.22],[Color(1,1,1,0.9),Color.WHITE,Color(1,1,1,0)])
	b._save(root,BASE+"LightImpact.tscn")
	root = _effect_root("LightMark")
	var sun: Sprite2D = _sprite(root,"Sun","res://assets/vfx/priest/sun_mark.svg")
	sun.scale = Vector2.ONE*1.6
	var orbit: Sprite2D = _sprite(root,"Orbit","res://assets/vfx/priest/solar_ring.svg")
	orbit.scale = Vector2.ONE*0.5
	orbit.modulate = Color(1,0.83,0.4,0.6)
	var descent: CPUParticles2D = _particles(root,"Descent",8,0.5)
	descent.texture = load("res://assets/vfx/summon_portal/white_ray.svg")
	descent.position = Vector2(0,-30)
	descent.direction = Vector2.DOWN
	descent.spread = 10
	descent.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	descent.emission_rect_extents = Vector2(24,3)
	descent.initial_velocity_min = 35
	descent.initial_velocity_max = 65
	descent.scale_amount_min = 0.5
	descent.scale_amount_max = 0.8
	var sparks: CPUParticles2D = _particles(root,"Sparks",6,0.7)
	sparks.one_shot = false
	sparks.explosiveness = 0.0
	sparks.emission_sphere_radius = 40
	sparks.initial_velocity_min = 5
	sparks.initial_velocity_max = 12
	sparks.scale_amount_min = 0.3
	sparks.scale_amount_max = 0.5
	clip = _effect_player(root,3.0)
	b._track(clip,"Sun:scale",[0,.15,.6,1.1,1.6,2.1,2.6,3],[Vector2.ONE*0.6,Vector2.ONE*1.8,Vector2.ONE*1.6,Vector2.ONE*1.8,Vector2.ONE*1.6,Vector2.ONE*1.8,Vector2.ONE*1.6,Vector2.ONE*1.6])
	b._track(clip,"Sun:modulate",[0,.12,2.7,3],[Color(1,1,1,0),Color.WHITE,Color.WHITE,Color(1,1,1,0)])
	b._track(clip,"Orbit:scale",[0,.18,.6,2.7,3],[Vector2.ONE*0.1,Vector2.ONE*0.6,Vector2.ONE*0.5,Vector2.ONE*0.55,Vector2.ONE*0.6])
	b._track(clip,"Orbit:rotation",[0,3],[0.0,0.7])
	b._track(clip,"Orbit:modulate",[0,.12,2.6,3],[Color(1,0.83,0.4,0),Color(1,0.83,0.4,0.65),Color(1,0.83,0.4,0.5),Color(1,0.83,0.4,0)])
	b._save(root,BASE+"LightMark.tscn")
	root = _effect_root("Consecration")
	var ring: Sprite2D = _sprite(root,"Ring","res://assets/vfx/priest/solar_ring.svg")
	ring.modulate = Color("ffe19a")
	_sprite(root,"Flash","res://assets/vfx/priest/light_orb.svg")
	var rays: CPUParticles2D = _particles(root,"Rays",18,0.65)
	rays.texture = load("res://assets/vfx/summon_portal/white_ray.svg")
	rays.emission_sphere_radius = 45
	rays.direction = Vector2.UP
	rays.spread = 35
	rays.initial_velocity_min = 70
	rays.initial_velocity_max = 130
	rays.scale_amount_min = 0.65
	rays.scale_amount_max = 1.1
	rays.color = Color("fff0b9")
	var motes: CPUParticles2D = _particles(root,"Motes",26,0.8)
	motes.emission_sphere_radius = 55
	motes.initial_velocity_min = 40
	motes.initial_velocity_max = 110
	clip = _effect_player(root,1.0)
	b._track(clip,"Ring:scale",[0,.15,.55,1.0],[Vector2.ONE*0.15,Vector2.ONE*0.72,Vector2.ONE*0.9,Vector2.ONE])
	b._track(clip,"Ring:modulate",[0,.1,.6,1.0],[Color(1,0.9,0.6,0),Color(1,0.9,0.6,1),Color(1,0.9,0.6,0.8),Color(1,0.9,0.6,0)])
	b._track(clip,"Flash:scale",[0,.1,.3],[Vector2.ONE,Vector2.ONE*5.0,Vector2.ONE*6.0])
	b._track(clip,"Flash:modulate",[0,.08,.3],[Color(1,1,1,0.3),Color(1,1,0.8,0.85),Color(1,1,1,0)])
	b._save(root,BASE+"Consecration.tscn")


func _actor(parent: Node, node_name: String, point: Vector2, size_factor: float, level: int) -> Node2D:
	var actor: Node2D = ResourceLoader.load("res://scenes/visuals/PriestVisual.tscn","PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	actor.name = node_name
	actor.position = point
	actor.scale = Vector2.ONE*size_factor
	actor.set("level",level)
	parent.add_child(actor)
	return actor


func _target(parent: Node, node_name: String, point: Vector2, size_factor: float) -> Node2D:
	var root: Node2D = b._node("Node2D",node_name,parent) as Node2D
	root.position = point
	var enemy: Node2D = load("res://scenes/visuals/SkeletonVisual.tscn").instantiate()
	enemy.name = "Actor"
	enemy.scale = Vector2.ONE*size_factor
	root.add_child(enemy)
	var health: ProgressBar = b._node("ProgressBar","Health",root) as ProgressBar
	health.position = Vector2(-45,-85 if size_factor > 0.5 else -45)
	health.size = Vector2(90,10)
	health.show_percentage = false
	health.value = 75
	health.z_index = 10
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color("db7564")
	health.add_theme_stylebox_override("fill",fill)
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color("33434c")
	health.add_theme_stylebox_override("background",background)
	return root


func _preview() -> void:
	var root: Control = Control.new()
	root.name = "PriestAnimationReview"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.set_script(load("res://scripts/debug/priest_animation_review.gd"))
	root.set("shot_scene",load(BASE+"LightShot.tscn"))
	root.set("impact_scene",load(BASE+"LightImpact.tscn"))
	root.set("mark_scene",load(BASE+"LightMark.tscn"))
	root.set("consecration_scene",load(BASE+"Consecration.tscn"))
	var theme: Theme = Theme.new()
	theme.default_font = ThemeDB.fallback_font
	theme.default_font_size = 22
	root.theme = theme
	var background: ColorRect = b._node("ColorRect","Background",root) as ColorRect
	background.color = Color("101820")
	background.z_index = -100
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center: Control = b._node("Control","Center",root) as Control
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.offset_left = -360
	center.offset_right = 360
	center.offset_bottom = 1280
	b._label(center,"Title","ЖРЕЦ СВЕТА · АНИМАЦИИ",Rect2(18,14,684,42),32,Color("ffe0a0"))
	var description: Label = b._label(center,"Description","",Rect2(20,68,680,86),26)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var stage: Node2D = b._node("Node2D","Stage",center) as Node2D
	for row: Array in [[Vector2(170,407),1.5],[Vector2(145,832),0.7],[Vector2(76,602),0.7],[Vector2(218,602),0.7],[Vector2(360,602),0.7],[Vector2(502,602),0.7],[Vector2(644,602),0.7]]:
		var pedestal: Sprite2D = _sprite(stage,"Pedestal%d"%stage.get_child_count(),"res://assets/environment/graveyard/pedestal.svg")
		pedestal.position = row[0]
		pedestal.scale = Vector2.ONE*float(row[1])
		pedestal.z_index = -5
	_actor(stage,"Hero",Vector2(170,310),1.1,5)
	var target: Node2D = _target(stage,"Target",Vector2(535,330),0.8)
	for i: int in 2:
		var peer: Node2D = load("res://scenes/visuals/SkeletonVisual.tscn").instantiate()
		peer.name = "PeerA" if i == 0 else "PeerB"
		peer.position = Vector2(-92 if i == 0 else 92,40)
		peer.scale = Vector2.ONE*0.45
		target.add_child(peer)
	var levels: Node2D = b._node("Node2D","Levels",stage) as Node2D
	for i: int in 5:
		_actor(levels,"Level%d"%(i+1),Vector2(76+i*142,570),100.0/256.0,i+1)
		b._label(center,"Caption%d"%i,"Lv%d"%(i+1),Rect2(46+i*142,632,100,35),22,Color(["88b96b","ec9b49","df5654","5295ef","b66dea"][i]))
	b._label(center,"LevelHint","Пять уровней · игровой размер",Rect2(20,485,680,35),22)
	_actor(stage,"Sample",Vector2(145,800),100.0/256.0,5)
	_target(stage,"RealTarget",Vector2(540,800),100.0/256.0)
	b._label(center,"ScaleHint","Снаряд и эффект в игровом размере",Rect2(20,695,680,35),22)
	var effects: Node2D = b._node("Node2D","Effects",stage) as Node2D
	effects.z_index = 12
	b._label(center,"Readout","",Rect2(20,925,680,32),22,Color("aac2b8"))
	var mode: OptionButton = b._node("OptionButton","Mode",center) as OptionButton
	mode.position = Vector2(18,970)
	mode.size = Vector2(684,58)
	mode.add_theme_font_size_override("font_size",26)
	for title: String in ["Покой","Выстрел","Появление","Снаряд света","Метка света","Освящение"]:
		mode.add_item(title)
	mode.item_selected.connect(Callable(root,"set_mode"),Object.CONNECT_PERSIST)
	for i: int in 5:
		var button: Button = b._button(center,"Level%d"%(i+1),"Lv%d"%(i+1),Rect2(18+i*138,1042,132,58),true)
		button.pressed.connect(Callable(root,"set_level").bind(i+1),Object.CONNECT_PERSIST)
	for i: int in 3:
		var button: Button = b._button(center,["Replay","Pause","Mirror"][i],"",Rect2(18+i*232,1114,220,58),i == 2)
		button.icon = load("res://assets/debug/priest/"+["replay","pause","mirror"][i]+".svg")
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.pressed.connect(Callable(root,["replay","toggle_pause","toggle_mirror"][i]),Object.CONNECT_PERSIST)
	for i: int in 3:
		var button: Button = b._button(center,"Speed%d"%i,["0.5×","1×","2×"][i],Rect2(18+i*232,1186,220,58),true)
		button.button_pressed = i == 1
		button.pressed.connect(Callable(root,"set_speed").bind([0.5,1.0,2.0][i]),Object.CONNECT_PERSIST)
	var timer: Timer = b._node("Timer","ReplayTimer",root) as Timer
	timer.one_shot = true
	timer.timeout.connect(Callable(root,"replay"),Object.CONNECT_PERSIST)
	b._save(root,"res://scenes/debug/PriestAnimationReview.tscn")
