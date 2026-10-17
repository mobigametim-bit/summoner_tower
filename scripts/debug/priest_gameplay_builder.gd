@tool
extends RefCounted

var b: RefCounted = preload("res://scripts/debug/graveyard_animation_builder.gd").new()


func build() -> Dictionary:
	var shot: Node2D = Node2D.new()
	shot.name = "LightBolt"
	shot.set_script(load("res://scripts/combat/combat_projectile.gd"))
	shot.set("impact_scene",load("res://scenes/vfx/priest/LightImpact.tscn"))
	shot.set("impact_scale",1.0)
	shot.set("consecration_scene",load("res://scenes/vfx/priest/Consecration.tscn"))
	var visual: Node2D = load("res://scenes/vfx/priest/LightShot.tscn").instantiate()
	visual.name = "Visual"
	shot.add_child(visual)
	b._save(shot,"res://scenes/light_bolt.tscn")
	var priest: Node2D = Node2D.new()
	priest.name = "Priest"
	priest.set_script(load("res://scripts/combat/combat_unit.gd"))
	priest.set("stats",load("res://resources/balance/priest_lv1.tres"))
	priest.set("projectile_scene",load("res://scenes/light_bolt.tscn"))
	priest.set("animated_visual_enabled",true)
	var fallback: Sprite2D = b._node("Sprite2D","Visual",priest) as Sprite2D
	fallback.texture = load("res://art/source/priest/master.svg")
	fallback.scale = Vector2.ONE*(100.0/256.0)
	var muzzle: Marker2D = b._node("Marker2D","Muzzle",priest) as Marker2D
	muzzle.position = Vector2(83,-36)*(100.0/256.0)
	visual = load("res://scenes/visuals/PriestVisual.tscn").instantiate()
	visual.name = "PriestVisual"
	visual.scale = Vector2.ONE*(100.0/256.0)
	priest.add_child(visual)
	b._save(priest,"res://scenes/priest.tscn")
	var addition: SummonPool = SummonPool.new()
	addition.scenes.assign([load("res://scenes/priest.tscn")])
	addition.weights.assign([25])
	assert(ResourceSaver.save(addition,"res://resources/biomes/priest_summon_addition.tres") == OK)
	var biome: BiomeDefinition = load("res://resources/biomes/graveyard.tres") as BiomeDefinition
	biome.summon_additions = load("res://resources/biomes/priest_summon_addition.tres")
	assert(ResourceSaver.save(biome,"res://resources/biomes/graveyard.tres") == OK)
	_review()
	return {"priest":true,"projectile":true,"permanent_unlock":true}


func _review() -> void:
	var root: Node = ResourceLoader.load("res://scenes/debug/GraveyardCombatReview.tscn","PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	root.name = "PriestGameplayReview"
	root.set_script(load("res://scripts/debug/priest_gameplay_review.gd"))
	# Script replacement can reset exported properties; preserve the approved game defaults.
	root.set("config",load("res://resources/balance/first_encounter.tres"))
	root.set("procedural_battlefield_enabled",true)
	root.set("battlefield_seed",106)
	var layer: CanvasLayer = b._node("CanvasLayer","PriestReview",root) as CanvasLayer
	var panel: Panel = b._node("Panel","Panel",layer) as Panel
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -360
	panel.offset_right = 360
	panel.offset_top = -180
	panel.offset_bottom = 0
	b._label(panel,"Title","ЖРЕЦ · БОЕВАЯ ПРОВЕРКА",Rect2(18,6,680,32),24)
	for i: int in 5:
		var button: Button = b._button(panel,"Level%d"%(i+1),"Lv%d"%(i+1),Rect2(18+138*i,44,132,54),true)
		button.pressed.connect(Callable(root,"select_priest_level").bind(i+1),Object.CONNECT_PERSIST)
	for i: int in 4:
		var button: Button = b._button(panel,["Priest","Support","Run","Restart"][i],["+ Жрец","+ Лучник","Забег","Заново"][i],Rect2(18+174*i,112,164,54))
		button.pressed.connect(Callable(root,["add_priest","add_support","start_run","restart"][i]),Object.CONNECT_PERSIST)
	b._save(root,"res://scenes/debug/PriestGameplayReview.tscn")
