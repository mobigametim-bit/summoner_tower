@tool
extends RefCounted
## Editor-only authoring. Saves real particle nodes and animation tracks through MCP.

const MASKS: String = "res://assets/vfx/kenney_particles/"
const VIOLET: Color = Color("b35cff")
const MINT: Color = Color("72ffbc")
const ICE: Color = Color("e7d5ff")

var _b: RefCounted
var _root: Node2D
var _clip: Animation
var _duration: float
var _serial: int = 0


func build(builder: RefCounted, key: String) -> PackedScene:
	_b = builder
	_root = Node2D.new()
	_root.name = key.to_pascal_case()
	_root.set_script(load("res://scripts/visuals/undead_effect_clip.gd"))
	var player: AnimationPlayer = _b._node("AnimationPlayer", "AnimationPlayer", _root)
	var library: AnimationLibrary = AnimationLibrary.new()
	player.add_animation_library(&"", library)
	_duration = 1.55 if key not in ["impact", "heavy_slam", "hex_impact", "dash"] else 0.8
	_clip = _b._animation(library, "effect", _duration)
	match key:
		"summon_skeletons", "retinue":
			var places: Array = [Vector2(180,100),Vector2(260,95)] if key == "summon_skeletons" else [Vector2(-170,100),Vector2(165,100),Vector2(260,95)]
			for point: Vector2 in places:
				_summon(point, 0.72)
		"spawn", "flesh_arrives":
			_summon(Vector2(230,80) if key == "flesh_arrives" else Vector2(0,90), 1.0)
		"assemble_flesh", "flesh_birth":
			var goal: Vector2 = Vector2(0,85) if key == "flesh_birth" else Vector2(230,85)
			for i: int in 3:
				var start: Vector2 = [Vector2(-50,92),Vector2(60,112),Vector2(155,82)][i]
				var pile: Sprite2D = _b._node("Sprite2D", "Remains%d" % i, _root)
				pile.texture = load("res://assets/vfx/undead/bone.svg")
				pile.position = start
				pile.scale = Vector2(1.1,0.65)
				pile.rotation = i * 0.7
				_b._track(_clip, str(pile.name)+":position", [0.0,0.18,0.92], [start,start,goal])
				_b._track(_clip, str(pile.name)+":modulate", [0.0,0.7,1.0], [Color.WHITE,Color.WHITE,Color(1,1,1,0)])
				var soul: Sprite2D = _sprite("Soul", "light_01", start, Vector2(50,50), VIOLET)
				_b._track(_clip, str(soul.name)+":position", [0.0,0.18,0.92], [start,start,goal])
				_fade(soul, 0.0, 0.15, 0.8, 1.1)
				var stream: CPUParticles2D = _burst("magic_05", 18, start, VIOLET, 0.65, 7, 140, 230, 8, 18)
				stream.direction = (goal-start).normalized()
				stream.spread = 8
				stream.explosiveness = 0.25
			_floor(goal, 130, VIOLET)
			if key == "flesh_birth":
				_summon(goal, 1.0, 0.45)
		"bone_shield", "bone_cover":
			var boss: bool = key == "bone_cover"
			var color: Color = VIOLET if boss else MINT
			var radius: float = 132.0 if boss else 108.0
			var center: Vector2 = Vector2(0,-12)
			var aura: Sprite2D = _sprite("WardAura", "light_02", center, Vector2.ONE*radius*2.35, Color(color,0.8), -40)
			_fade(aura,0,0.15,1.1,_duration)
			_rotate(aura, -0.35, 0.5)
			var arcs: Sprite2D = _sprite("WardLightning", "spark_02", center, Vector2.ONE*radius*2.3, Color(color,0.85))
			_fade(arcs,0,0.08,0.8,_duration)
			_rotate(arcs,0,1.1)
			var sparks: CPUParticles2D = _burst("magic_05",42,center,color,1.15,radius,0,10,11,20)
			_orbit(sparks,radius,0.24)
			var bones: CPUParticles2D = _b._particles(_root,"OrbitBones","bone",12,center,Color("fff0dd"),1.3)
			_orbit(bones,radius,0.18)
			bones.scale_amount_min = 0.45
			bones.scale_amount_max = 0.6
			_floor(Vector2(0,107),radius*1.5,color)
		"regenerate":
			_floor(Vector2(0,107),180,MINT)
			var glow: Sprite2D = _sprite("VitalGlow","light_01",Vector2(0,42),Vector2(165,210),Color(MINT,0.5),-40)
			_fade(glow,0,0.2,1,_duration)
			var rising: CPUParticles2D = _burst("magic_05",38,Vector2(0,90),MINT,1.2,50,100,180,14,26)
			rising.explosiveness = 0.12
			rising.spread = 16
			_smoke(Vector2(0,90),MINT,10,0.6)
			var crosses: CPUParticles2D = _b._particles(_root,"HealingCrosses","plus",6,Vector2(0,36),Color("baffd5"),1.1)
			crosses.explosiveness = 0.1
			crosses.scale_amount_min = 0.35
			crosses.scale_amount_max = 0.5
		"heal":
			var start: Vector2 = Vector2(84,-50)
			var end: Vector2 = Vector2(230,12)
			# Particle stream follows a curved lane above the silhouettes.
			for lane: int in 2:
				var flow: CPUParticles2D = _burst("magic_05",24,start,MINT,0.8,4,0,0,16,28)
				flow.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
				var points: PackedVector2Array = []
				for j: int in 24:
					var t: float = float(j)/23.0
					points.append(start.lerp(end,t)-start+Vector2(0,-sin(t*PI)*45+lane*5))
				flow.emission_points = points
				flow.direction = Vector2(0.9,0.3)
				flow.initial_velocity_min = 25
				flow.initial_velocity_max = 45
				flow.spread = 10
				flow.explosiveness = 0.05
			_glint(start,60,MINT,0)
			_glint(end,75,MINT,0.08)
			_floor(Vector2(230,100),110,MINT)
			var sparks: CPUParticles2D = _burst("magic_05",20,end,MINT,1.0,20,35,90,14,25)
			sparks.spread = 140
		"dash":
			var wake: CPUParticles2D = _burst("twirl_01",18,Vector2(-38,30),VIOLET,0.5,40,200,360,32,65)
			wake.direction = Vector2.LEFT
			wake.spread = 10
			wake.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			wake.emission_rect_extents = Vector2(12,45)
			wake.angle_min = 90
			wake.angle_max = 110
			var sparks: CPUParticles2D = _burst("magic_05",30,Vector2(-25,40),ICE,0.55,35,170,320,6,14)
			sparks.direction = Vector2.LEFT
			sparks.spread = 22
			_smoke(Vector2(-24,98),VIOLET,12,0.65)
		"grave_bell":
			var bell: Sprite2D = _b._node("Sprite2D","Bell",_root)
			bell.texture = load("res://assets/vfx/undead/bell.svg")
			bell.position = Vector2(0,-148)
			bell.modulate = ICE
			bell.scale = Vector2.ONE*1.8
			_b._track(_clip,"Bell:rotation",[0,0.15,0.4,0.65,0.9,1.2,_duration],[-0.15,0.28,-0.26,0.22,-0.18,0.1,0])
			_fade(bell,0,0.12,1.1,_duration)
			_glint(Vector2(0,-148),130,VIOLET,0)
			for i: int in 3:
				var wave: Sprite2D = _sprite("Toll","light_02",Vector2(0,-36),Vector2.ONE*90,Color(VIOLET,0.8))
				var delay: float = i*0.18
				_b._track(_clip,str(wave.name)+":scale",[0,delay+0.01,1.25+delay],[Vector2.ONE*0.3,Vector2.ONE*0.3,Vector2.ONE*3.6])
				_fade(wave,delay,delay+0.12,delay+0.55,_duration)
			var souls: CPUParticles2D = _burst("twirl_01",24,Vector2(0,-38),VIOLET,1.15,90,40,90,25,45)
			_orbit(souls,90,0.2)
			_burst("magic_05",36,Vector2(0,-55),ICE,1.2,85,50,110,7,15)
		"impact", "heavy_slam", "hex_impact":
			var heavy: bool = key == "heavy_slam"
			var point: Vector2 = Vector2(50,95) if heavy else Vector2(85,20)
			var color: Color = Color("e1d3af") if heavy else VIOLET
			_glint(point,130 if heavy else 85,color,0)
			var burst: CPUParticles2D = _burst("magic_05",24 if heavy else 16,point,color,0.5,10,100,230,7,18)
			burst.spread = 180
			if heavy:
				_smoke(point,color,14,0.6)
				var stones: CPUParticles2D = _b._particles(_root,"Debris","stone",12,point,color,0.6)
				stones.spread = 100
				stones.initial_velocity_min = 100
				stones.initial_velocity_max = 200
				stones.gravity = Vector2(0,300)
	_b._reset(_root,library)
	var path: String = "res://scenes/vfx/undead/" + key.to_pascal_case() + ".tscn"
	_b._save(_root,path)
	return ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene


func _name(prefix: String) -> String:
	_serial += 1
	return prefix+str(_serial)


func _sprite(prefix: String, mask: String, point: Vector2, size: Vector2, color: Color, layer: int = 0) -> Sprite2D:
	var sprite: Sprite2D = _b._node("Sprite2D",_name(prefix),_root)
	sprite.texture = load(MASKS+mask+".png")
	sprite.position = point
	sprite.scale = size / 128.0
	sprite.self_modulate = color
	sprite.z_index = layer
	var material: CanvasItemMaterial = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = material
	return sprite


func _fade(item: CanvasItem, start: float, peak: float, hold: float, end: float) -> void:
	_b._track(_clip,str(item.name)+":modulate",[start,peak,hold,end],[Color(1,1,1,0),Color.WHITE,Color(1,1,1,0.7),Color(1,1,1,0)])


func _rotate(item: Node2D, from: float, to: float) -> void:
	_b._track(_clip,str(item.name)+":rotation",[0,_duration],[from,to])


func _glint(point: Vector2, size: float, color: Color, delay: float) -> void:
	var flash: Sprite2D = _sprite("Flash","light_01",point,Vector2.ONE*size,Color(color,0.85))
	_fade(flash,delay,delay+0.06,delay+0.13,delay+0.42)
	var star: Sprite2D = _sprite("WhiteCore","magic_05",point,Vector2.ONE*size*0.6,ICE)
	_fade(star,delay,delay+0.05,delay+0.1,delay+0.3)


func _floor(point: Vector2, width: float, color: Color) -> void:
	var floor_glow: Sprite2D = _sprite("FloorGlow","light_01",point,Vector2(width,width*0.4),Color(color,0.8),-40)
	_fade(floor_glow,0,0.12,_duration*0.5,_duration)
	var swirl: Sprite2D = _sprite("SealSwirl","twirl_01",point,Vector2(width,width*0.4),color,-35)
	_fade(swirl,0,0.1,_duration*0.45,_duration)
	_rotate(swirl,0,0.5)


func _burst(mask: String, count: int, point: Vector2, color: Color, life: float, radius: float, speed_min: float, speed_max: float, size_min: float, size_max: float) -> CPUParticles2D:
	var particles: CPUParticles2D = _b._particles(_root,_name("Particles"),"spark",count,point,color,life)
	particles.texture = load(MASKS+mask+".png")
	particles.emission_sphere_radius = radius
	particles.initial_velocity_min = speed_min
	particles.initial_velocity_max = speed_max
	particles.gravity = Vector2.ZERO
	particles.spread = 35
	particles.explosiveness = 0.65
	particles.scale_amount_min = size_min/128.0
	particles.scale_amount_max = size_max/128.0
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0,0.4))
	curve.add_point(Vector2(0.15,1))
	curve.add_point(Vector2(0.7,0.7))
	curve.add_point(Vector2(1,0))
	particles.scale_amount_curve = curve
	return particles


func _orbit(particles: CPUParticles2D, radius: float, velocity: float) -> void:
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	particles.emission_ring_inner_radius = radius-6
	particles.emission_ring_radius = radius+6
	particles.initial_velocity_min = 0
	particles.initial_velocity_max = 6
	particles.gravity = Vector2.ZERO
	particles.orbit_velocity_min = velocity
	particles.orbit_velocity_max = velocity*1.3
	particles.explosiveness = 0.15


func _smoke(point: Vector2, color: Color, count: int, life: float) -> void:
	var smoke: CPUParticles2D = _burst("smoke_04",count,point,Color(color,0.45),life,25,35,85,40,75)
	smoke.spread = 100
	smoke.angular_velocity_min = -35
	smoke.angular_velocity_max = 35


func _summon(point: Vector2, strength: float, delay: float = 0.0) -> void:
	_floor(point,150*strength,VIOLET)
	_glint(point+Vector2(0,-40)*strength,135*strength,VIOLET,delay)
	# Instance the real gameplay summon rays, preserving their texture, ramp and motion.
	var rays: CPUParticles2D = load("res://scenes/vfx/SummonRays.tscn").instantiate() as CPUParticles2D
	rays.name = _name("SummonRays")
	_root.add_child(rays)
	rays.position = point
	rays.scale = Vector2.ONE*strength*1.5
	rays.modulate = VIOLET
	rays.z_index = 0
	rays.amount = 28
	rays.lifetime = 0.85
	rays.initial_velocity_min = 120
	rays.initial_velocity_max = 210
	rays.set_meta("start_delay",delay)
	# A smaller white core gives contrast without washing out the new creature.
	var sparks: CPUParticles2D = _burst("magic_05",28,point,VIOLET,1.1,38*strength,85,175,10*strength,22*strength)
	sparks.spread = 22
	sparks.explosiveness = 0.25
	sparks.set_meta("start_delay",delay)
	_smoke(point,VIOLET,12,1.0)
