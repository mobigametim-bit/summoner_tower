class_name GraveyardAbilities
extends EnemyAbilities

signal shield_changed(active: bool)

@export var undead_config: GraveyardAbilityConfig
var support: Node
var shield_remaining: float = 0.0
var _enemy: ApproachingEnemy
var _regen_used: bool = false
var _regen_remaining: float = 0.0
var _retinue_used: bool = false
var _bell_used: bool = false
var _heal_clock: float = 0.0
var _summon_clock: float = 0.0
var _flesh_clock: float = 0.0
var _cast_remaining: float = 0.0
var _cast: StringName
var _casts: Array[StringName] = []
var _heal_target: WeakRef


func configure(enemy_type: StringName, tier: int, health: int) -> void:
	stop()
	_enemy = get_parent() as ApproachingEnemy
	_type = enemy_type
	_tier = tier
	_max_health = health
	_enabled = true
	_heal_clock = undead_config.heal_interval
	_summon_clock = undead_config.summon_interval
	_flesh_clock = undead_config.flesh_interval
	_dash_clock = undead_config.dash_interval
	effects.hide()
	set_physics_process(true)


func health_changed(health: int) -> void:
	if not _enabled or health <= 0:
		return
	var ratio: float = float(health)/_max_health
	if _type == &"zombie" and _tier == 5 and not _regen_used and ratio <= undead_config.regen_trigger:
		_regen_used = true
		_regen_remaining = undead_config.regen_duration
		if _enemy.undead_visual != null:
			_enemy.undead_visual.call("show_regeneration",undead_config.regen_duration)
		started.emit(&"regenerate")
	if _type != &"lich":
		return
	if _tier >= 3 and not _retinue_used and ratio <= undead_config.retinue_trigger:
		_retinue_used = true
		_casts.append(&"retinue")
	if _tier >= 4 and not _half_triggered and ratio <= undead_config.shield_trigger:
		_half_triggered = true
		shield_health = _max_health*undead_config.shield_ratio
		shield_remaining = undead_config.shield_duration
		shield_changed.emit(true)
	if _tier >= 5 and not _bell_used and ratio <= undead_config.bell_trigger:
		_bell_used = true
		_casts.append(&"grave_bell")
	_start_next()


func filter_damage(amount: float, _direct: bool) -> float:
	var absorbed: float = minf(amount,shield_health)
	shield_health -= absorbed
	if absorbed > 0.0 and shield_health <= 0.0:
		_clear_shield()
	return amount-absorbed


func _physics_process(delta: float) -> void:
	if not _enabled or not is_instance_valid(_enemy) or not _enemy.is_targetable():
		return
	if shield_remaining > 0.0:
		shield_remaining = maxf(shield_remaining-delta,0.0)
		if shield_remaining <= 0.0:
			_clear_shield()
	if _regen_remaining > 0.0:
		var slice: float = minf(delta,_regen_remaining)
		_regen_remaining = maxf(_regen_remaining-delta,0.0)
		_enemy.restore_health(float(_max_health)*undead_config.regen_ratio/undead_config.regen_duration*slice)
	# Frozen casters hold their cast pose and pending summons; passive lifetimes keep running.
	if _enemy._freeze_remaining > 0.0:
		return
	if _cast_remaining > 0.0:
		_cast_remaining = maxf(_cast_remaining-delta,0.0)
		if _cast_remaining <= 0.0:
			_finish_cast()
	if _type == &"necromancer" and is_instance_valid(support):
		_heal_clock -= delta
		_summon_clock -= delta
		_flesh_clock -= delta
		if _cast_remaining <= 0.0:
			_plan_necromancer()
	_start_next()


func _plan_necromancer() -> void:
	if _tier >= 4 and _flesh_clock <= 0.0:
		_flesh_clock = undead_config.query_interval
		if support.reserve_remains(_enemy):
			_flesh_clock = undead_config.flesh_interval
			_begin_cast(&"assemble_flesh",undead_config.assembly_time)
			return
	if _tier >= 3 and _summon_clock <= 0.0:
		_summon_clock = undead_config.query_interval
		if support.summon_capacity(_enemy,&"skeleton") > 0:
			_summon_clock = undead_config.summon_interval
			_begin_cast(&"summon_skeletons",undead_config.cast_time)
			return
	if _heal_clock <= 0.0:
		_heal_clock = undead_config.query_interval
		var target: ApproachingEnemy = support.heal_target(_enemy)
		if target != null:
			_heal_target = weakref(target)
			_heal_clock = undead_config.heal_interval
			_begin_cast(&"heal",undead_config.cast_time)


func _start_next() -> void:
	if _cast_remaining <= 0.0 and not _casts.is_empty():
		_begin_cast(_casts.pop_front(),undead_config.cast_time)


func _begin_cast(kind: StringName, duration: float) -> void:
	_cast = kind
	_cast_remaining = duration
	started.emit(kind)


func _finish_cast() -> void:
	var kind: StringName = _cast
	_cast = &""
	if not is_instance_valid(support) or not _enemy.is_targetable():
		return
	match kind:
		&"heal":
			var target: ApproachingEnemy = _heal_target.get_ref() as ApproachingEnemy if _heal_target != null else null
			support.heal(_enemy,target)
		&"summon_skeletons": support.summon_skeletons(_enemy,false)
		&"assemble_flesh": support.assemble_flesh(_enemy)
		&"retinue": support.summon_skeletons(_enemy,true)
		&"grave_bell": support.ring_bell(_enemy)


func advance(delta: float) -> float:
	if _type != &"ghoul" or _tier < 5:
		return delta*speed_multiplier()
	var remaining: float = delta
	var motion: float = 0.0
	while remaining > 0.000001:
		var deadline: float = _windup if _dash_preparing else (_dash_remaining if _dash_remaining > 0.0 else _dash_clock)
		var slice: float = minf(remaining,maxf(deadline,0.000001))
		motion += slice*speed_multiplier()
		remaining -= slice
		if _dash_preparing:
			_windup = maxf(_windup-slice,0.0)
			if _windup <= 0.000001:
				_dash_preparing = false
				_dash_remaining = undead_config.dash_duration
		elif _dash_remaining > 0.0:
			_dash_remaining = maxf(_dash_remaining-slice,0.0)
		else:
			_dash_clock = maxf(_dash_clock-slice,0.0)
			if _dash_clock <= 0.000001:
				_dash_clock = undead_config.dash_interval-undead_config.dash_windup-undead_config.dash_duration
				_dash_preparing = true
				_windup = undead_config.dash_windup
				started.emit(&"dash")
	return motion


func speed_multiplier() -> float:
	if _dash_preparing:
		return 0.0
	return 1.0+maxf(haste_bonus,undead_config.dash_bonus if _dash_remaining > 0.0 else 0.0)


func _clear_shield() -> void:
	shield_health = 0.0
	shield_remaining = 0.0
	shield_changed.emit(false)


func stop() -> void:
	if is_instance_valid(support) and is_instance_valid(_enemy):
		support.cancel_reservation(_enemy.get_instance_id())
	super.stop()
	set_physics_process(false)
	_regen_used = false
	_regen_remaining = 0.0
	_retinue_used = false
	_bell_used = false
	_cast_remaining = 0.0
	_cast = &""
	_casts.clear()
	_heal_target = null
	_clear_shield()
