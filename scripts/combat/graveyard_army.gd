class_name GraveyardArmy
extends Node

@export var config: GraveyardAbilityConfig
@export var skeleton_scene: PackedScene
@export var flesh_scene: PackedScene
@export var corpse_scene: PackedScene
@export var heal_scene: PackedScene
@export var assembly_scene: PackedScene
var manager: WaveManager
var _clock: float = 0.0
var _corpses: Array[Dictionary] = []
var _assemblies: Dictionary = {}


func remains_count() -> int:
	return _corpses.size()


func register(enemy: ApproachingEnemy) -> void:
	if enemy.abilities is GraveyardAbilities:
		(enemy.abilities as GraveyardAbilities).support = self


func _physics_process(delta: float) -> void:
	_clock += delta
	for i: int in range(_corpses.size()-1,-1,-1):
		if _corpses[i].expires <= _clock and _corpses[i].owner == 0:
			_remove_corpse(i)


func record_death(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void:
	if outcome != ApproachingEnemy.Outcome.KILLED or enemy.stats.is_boss or enemy.get_meta("summoned",false):
		return
	if not enemy.stats.enemy_type in [&"skeleton",&"zombie",&"ghoul",&"necromancer"]:
		return
	if _corpses.size() >= config.corpse_limit:
		for i: int in _corpses.size():
			if _corpses[i].owner == 0:
				_remove_corpse(i)
				break
		if _corpses.size() >= config.corpse_limit:
			return
	var mark: Node2D = corpse_scene.instantiate() as Node2D
	add_child(mark)
	mark.global_position = enemy.global_position
	mark.scale = enemy.scale*0.8
	_corpses.append({"point":enemy.global_position,"expires":_clock+config.corpse_lifetime,"owner":0,"mark":mark})


func summon_capacity(caster: ApproachingEnemy, kind: StringName) -> int:
	var limit: int = config.skeleton_limit if kind == &"skeleton" else config.flesh_limit
	for enemy: ApproachingEnemy in manager._active:
		if enemy.is_targetable() and enemy.get_meta("summoner_id",0) == caster.get_instance_id() and enemy.stats.enemy_type == kind:
			limit -= 1
	return maxi(limit,0)


func heal_target(caster: ApproachingEnemy) -> ApproachingEnemy:
	var nearest: ApproachingEnemy
	var distance: float = config.heal_radius*config.heal_radius
	for enemy: ApproachingEnemy in manager._active:
		if enemy == caster or not enemy.is_targetable() or enemy.current_health >= enemy.max_health:
			continue
		var squared: float = caster.global_position.distance_squared_to(enemy.global_position)
		if squared < distance:
			nearest = enemy
			distance = squared
	return nearest


func heal(caster: ApproachingEnemy, target: ApproachingEnemy) -> void:
	if not is_instance_valid(target) or not target.is_targetable() or not _valid(caster):
		return
	if caster.global_position.distance_to(target.global_position) > config.heal_radius:
		return
	target.restore_health(target.max_health*config.heal_ratio)
	var effect: Node2D = heal_scene.instantiate() as Node2D
	add_child(effect)
	effect.call("initialize",caster,target)


func summon_skeletons(caster: ApproachingEnemy, retinue: bool) -> void:
	if not _valid(caster):
		return
	var count: int = config.retinue_count if retinue else mini(config.summon_count,summon_capacity(caster,&"skeleton"))
	var tier: int = caster.difficulty_tier-1 if retinue else caster.difficulty_tier-2
	for i: int in count:
		manager.spawn_summoned(skeleton_scene,caster,tier,config.summon_spacing*(i+1))


func reserve_remains(caster: ApproachingEnemy) -> bool:
	if not _valid(caster) or summon_capacity(caster,&"flesh_golem") <= 0:
		return false
	var chosen: Array[int] = []
	for i: int in _corpses.size():
		var corpse: Dictionary = _corpses[i]
		if corpse.owner == 0 and corpse.expires > _clock and caster.global_position.distance_to(corpse.point) <= config.corpse_radius:
			chosen.append(i)
			if chosen.size() == config.corpse_count:
				break
	if chosen.size() < config.corpse_count:
		return false
	var points: PackedVector2Array = []
	for i: int in chosen:
		_corpses[i].owner = caster.get_instance_id()
		_corpses[i].mark.hide()
		points.append(_corpses[i].point)
	var effect: Node2D = assembly_scene.instantiate() as Node2D
	add_child(effect)
	var goal: Vector2 = caster.global_position
	if caster._route != null:
		goal = caster._route_transform*caster._route.sample_baked(maxf(caster._distance-config.summon_spacing,0.0))
	effect.call("initialize",points,goal,config.assembly_time,caster)
	_assemblies[caster.get_instance_id()] = effect
	return true


func assemble_flesh(caster: ApproachingEnemy) -> void:
	if not _valid(caster):
		return
	var indices: Array[int] = []
	for i: int in _corpses.size():
		if _corpses[i].owner == caster.get_instance_id():
			indices.append(i)
	if indices.size() != config.corpse_count or summon_capacity(caster,&"flesh_golem") <= 0:
		cancel_reservation(caster.get_instance_id())
		return
	# Consume reserved remains before spawning so callbacks cannot reuse them.
	indices.reverse()
	for i: int in indices:
		_remove_corpse(i)
	_assemblies.erase(caster.get_instance_id())
	var flesh: ApproachingEnemy = manager.spawn_summoned(flesh_scene,caster,2 if caster.difficulty_tier == 5 else 1,config.summon_spacing)
	if flesh != null and caster.difficulty_tier == 5:
		flesh.move_speed = config.flesh_fast_speed


func cancel_reservation(id: int) -> void:
	for corpse: Dictionary in _corpses:
		if corpse.owner == id:
			corpse.owner = 0
			if is_instance_valid(corpse.mark):
				corpse.mark.show()
	var effect: Node = _assemblies.get(id) as Node
	if is_instance_valid(effect):
		effect.queue_free()
	_assemblies.erase(id)


func ring_bell(caster: ApproachingEnemy) -> void:
	if not _valid(caster):
		return
	for enemy: ApproachingEnemy in manager._active:
		if enemy != caster and enemy.is_targetable() and enemy.global_position.distance_to(caster.global_position) <= config.bell_radius:
			enemy.apply_haste(config.bell_bonus,config.bell_duration)


func _valid(caster: ApproachingEnemy) -> bool:
	return manager.phase == WaveManager.Phase.FIGHTING and is_instance_valid(caster) and caster.is_targetable() and manager._active.has(caster)


func _remove_corpse(index: int) -> void:
	var mark: Node = _corpses[index].mark as Node
	if is_instance_valid(mark):
		mark.queue_free()
	_corpses.remove_at(index)


func clear() -> void:
	for effect: Node in _assemblies.values():
		if is_instance_valid(effect):
			effect.queue_free()
	_assemblies.clear()
	while not _corpses.is_empty():
		_remove_corpse(_corpses.size()-1)
	for child: Node in get_children():
		child.queue_free()
