@tool
extends RefCounted

var b: RefCounted = preload("res://scripts/debug/graveyard_animation_builder.gd").new()
const ENTITIES: Array[String] = ["zombie","ghoul","necromancer","flesh_golem","lich"]


func build() -> Dictionary:
	_effects()
	for kind: String in ENTITIES:
		_enemy(kind)
	var skeleton: Node = _load_scene("res://scenes/skeleton.tscn")
	skeleton.get_node("UndeadVisual").set("haste_scene",load("res://scenes/vfx/undead/HasteAura.tscn"))
	b._save(skeleton,"res://scenes/skeleton.tscn")
	_army()
	_waves()
	return {"enemies":6,"army":true,"waves":true}


func _load_scene(path: String) -> Node:
	return ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)


func _flatten(branch: Node, root: Node) -> void:
	branch.scene_file_path = ""
	branch.owner = root
	for child: Node in branch.find_children("*","",true,false):
		child.scene_file_path = ""
		child.owner = root


func _effects() -> void:
	var root: Node2D = Node2D.new()
	root.name = "HasteAura"
	var aura: CPUParticles2D = b._particles(root,"Sparks","spark",16,Vector2(0,72),Color("b58bff"),0.65)
	aura.texture = load("res://assets/vfx/kenney_particles/magic_05.png")
	aura.one_shot = false
	aura.emitting = true
	aura.explosiveness = 0.0
	aura.emission_sphere_radius = 65
	aura.initial_velocity_min = 75
	aura.initial_velocity_max = 120
	aura.scale_amount_min = 0.16
	aura.scale_amount_max = 0.28
	aura.z_index = 30
	b._save(root,"res://scenes/vfx/undead/HasteAura.tscn")
	root = Node2D.new()
	root.name = "CorpseMark"
	root.z_index = 1
	root.z_as_relative = false
	var sprite: Sprite2D = b._node("Sprite2D","Bones",root)
	sprite.texture = load("res://assets/vfx/undead/corpse_pile.svg")
	sprite.scale = Vector2.ONE*2.0
	b._save(root,"res://scenes/vfx/undead/CorpseMark.tscn")
	root = Node2D.new()
	root.name = "HealLink"
	root.z_index = 25
	root.set_script(load("res://scripts/vfx/undead_heal_link.gd"))
	var line: Line2D = b._node("Line2D","Link",root)
	line.width = 2
	line.default_color = Color(0.5,1,0.75,0.4)
	line.antialiased = true
	for key: String in ["Source","Target"]:
		var glow: Sprite2D = b._node("Sprite2D",key,root)
		glow.texture = load("res://assets/vfx/kenney_particles/light_01.png")
		glow.scale = Vector2.ONE*0.45
		glow.modulate = Color("78ffc4")
		var material: CanvasItemMaterial = CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = material
	var flow: CPUParticles2D = b._particles(root,"Flow","spark",30,Vector2.ZERO,Color("8affc7"),0.65)
	flow.texture = load("res://assets/vfx/kenney_particles/magic_05.png")
	flow.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	flow.emission_points = PackedVector2Array([Vector2.ZERO])
	flow.scale_amount_min = 0.10
	flow.scale_amount_max = 0.18
	flow.local_coords = false
	flow.initial_velocity_min = 6
	flow.initial_velocity_max = 18
	flow.explosiveness = 0.0
	var receiver: CPUParticles2D = b._particles(root,"Receiver","spark",12,Vector2.ZERO,Color("c2ffe1"),0.65)
	receiver.scale_amount_min = 0.18
	receiver.scale_amount_max = 0.3
	receiver.emission_sphere_radius = 14
	receiver.initial_velocity_min = 20
	receiver.initial_velocity_max = 35
	b._save(root,"res://scenes/vfx/undead/HealLink.tscn")
	root = Node2D.new()
	root.name = "Assembly"
	root.z_index = 22
	root.set_script(load("res://scripts/vfx/undead_assembly.gd"))
	for i: int in 3:
		var bone: Sprite2D = b._node("Sprite2D","Bone%d"%i,root)
		bone.texture = load("res://assets/vfx/undead/bone.svg")
		bone.modulate = Color("e0bbff")
		var glow: CPUParticles2D = b._particles(bone,"Souls","spark",12,Vector2.ZERO,Color("b673ff"),0.6)
		glow.emitting = true
		glow.one_shot = false
		glow.explosiveness = 0.0
		glow.local_coords = false
		glow.emission_sphere_radius = 8
		glow.initial_velocity_min = 8
		glow.initial_velocity_max = 20
	b._save(root,"res://scenes/vfx/undead/Assembly.tscn")


func _enemy(kind: String) -> void:
	var root: Node2D = _load_scene("res://scenes/skeleton.tscn")
	root.name = kind.to_pascal_case()
	root.set("stats",load("res://resources/balance/%s_stats.tres"%kind))
	for key: String in ["UndeadVisual","EnemyAbilities"]:
		var old: Node = root.get_node(key)
		root.remove_child(old)
		old.free()
	var visual: Node2D = _load_scene("res://scenes/visuals/%sVisual.tscn"%kind.to_pascal_case())
	var fields: Dictionary = {}
	for field: String in ["entity_key","level_ids","level","part_variants","part_paths","ability_levels"]:
		fields[field] = visual.get(field)
	visual.set_script(null)
	visual.set_script(load("res://scripts/visuals/graveyard_gameplay_visual.gd"))
	for field: String in fields:
		visual.set(field,fields[field])
	visual.name = "UndeadVisual"
	var sizes: Dictionary = {"zombie":116.0,"ghoul":112.0,"necromancer":112.0,"flesh_golem":140.0,"lich":156.0}
	var size: float = sizes[kind]
	visual.set("gameplay_canvas_size",size)
	visual.set("attack_impact_time",0.38 if kind == "flesh_golem" else 0.28)
	visual.scale = Vector2.ONE*(size/256.0)
	visual.set("shield_scene",load("res://scenes/vfx/undead/BoneCover.tscn"))
	visual.set("shield_config",load("res://resources/balance/skeleton_shield.tres"))
	visual.set("haste_scene",load("res://scenes/vfx/undead/HasteAura.tscn"))
	visual.set("regeneration_scene",load("res://scenes/vfx/undead/Regenerate.tscn"))
	if kind == "flesh_golem":
		var bank: Dictionary = visual.get_node("AbilityEffects").get("effect_scenes").duplicate()
		bank[&"spawn"] = load("res://scenes/vfx/undead/Spawn.tscn")
		visual.get_node("AbilityEffects").set("effect_scenes",bank)
	root.add_child(visual)
	_flatten(visual,root)
	var fallback: Sprite2D = root.get_node("Visual")
	fallback.texture = load("res://art/source/%s/master.svg"%kind)
	fallback.scale = visual.scale
	var bar: ProgressBar = root.get_node("HealthBar")
	bar.offset_left = -size*0.36
	bar.offset_right = size*0.36
	bar.offset_top = -size*0.48-10
	bar.offset_bottom = bar.offset_top+8
	var abilities: Node2D = _load_scene("res://scenes/combat/EnemyAbilities.tscn")
	abilities.set_script(null)
	abilities.set_script(load("res://scripts/combat/graveyard_abilities.gd"))
	abilities.set("config",load("res://resources/balance/enemy_abilities.tres"))
	abilities.set("undead_config",load("res://resources/balance/graveyard_abilities.tres"))
	root.add_child(abilities)
	_flatten(abilities,root)
	abilities.connect(&"shield_changed",Callable(visual,"set_shield_active"),Object.CONNECT_PERSIST)
	b._save(root,"res://scenes/%s.tscn"%kind)


func _army() -> void:
	var army: Node = Node.new()
	army.name = "GraveyardArmy"
	army.set_script(load("res://scripts/combat/graveyard_army.gd"))
	army.set("config",load("res://resources/balance/graveyard_abilities.tres"))
	army.set("skeleton_scene",load("res://scenes/skeleton.tscn"))
	army.set("flesh_scene",load("res://scenes/flesh_golem.tscn"))
	army.set("corpse_scene",load("res://scenes/vfx/undead/CorpseMark.tscn"))
	army.set("heal_scene",load("res://scenes/vfx/undead/HealLink.tscn"))
	army.set("assembly_scene",load("res://scenes/vfx/undead/Assembly.tscn"))
	b._save(army,"res://scenes/combat/GraveyardArmy.tscn")
	var game: Node = _load_scene("res://scenes/game.tscn")
	if game.has_node("WaveManager/GraveyardArmy"):
		game.get_node("WaveManager/GraveyardArmy").free()
	game.get_node("WaveManager").add_child(_load_scene("res://scenes/combat/GraveyardArmy.tscn"))
	b._save(game,"res://scenes/game.tscn")


func _waves() -> void:
	var balance: PowerBalanceConfig = load("res://resources/balance/power_balance.tres").duplicate()
	var stats: Array[EnemyStats] = []
	for key: String in ["skeleton","zombie","ghoul","necromancer","lich"]:
		stats.append(load("res://resources/balance/%s_stats.tres"%key))
	balance.enemy_stats = stats
	ResourceSaver.save(balance,"res://resources/balance/graveyard_power.tres")
	var waves: WaveConfig = load("res://resources/balance/wave_config.tres").duplicate()
	waves.power_balance = ResourceLoader.load("res://resources/balance/graveyard_power.tres","Resource",ResourceLoader.CACHE_MODE_IGNORE)
	waves.enemy_health_growth = 0
	var scenes: Array[PackedScene] = []
	for key: String in ["skeleton","zombie","ghoul","necromancer"]:
		scenes.append(load("res://scenes/%s.tscn"%key))
	waves.regular_scenes = scenes
	waves.regular_first_waves = [1,2,3,4]
	waves.regular_weights = [0.45,0.25,0.20,0.10]
	waves.goblin_scene = waves.regular_scenes[0]
	waves.orc_scene = waves.regular_scenes[1]
	waves.golem_scene = waves.regular_scenes[2]
	waves.boss_scene = load("res://scenes/lich.tscn")
	ResourceSaver.save(waves,"res://resources/balance/graveyard_waves.tres")
	var biome: BiomeDefinition = load("res://resources/biomes/graveyard.tres")
	biome.wave_config = ResourceLoader.load("res://resources/balance/graveyard_waves.tres","Resource",ResourceLoader.CACHE_MODE_IGNORE)
	ResourceSaver.save(biome,"res://resources/biomes/graveyard.tres")
