class_name EnemyAbilities
extends Node2D

signal started(ability: StringName)
signal retinue_requested

@export var config: EnemyAbilityConfig
@onready var effects: EnemyAbilityVisual = $Effects

var armor_remaining: int = 0
var shield_health: float = 0.0
var raging: bool = false
var rushing: bool = false
var haste_bonus: float = 0.0
var _type: StringName
var _tier: int = 1
var _max_health: int = 0
var _enabled: bool = false
var _half_triggered: bool = false
var _rush_triggered: bool = false
var _queue: Array[StringName] = []
var _waiting: float = 0.0
var _windup: float = 0.0
var _event: StringName
var _dash_clock: float = 0.0
var _dash_remaining: float = 0.0
var _dash_preparing: bool = false


func configure(enemy_type: StringName, tier: int, health: int) -> void:
	stop()
	_type = enemy_type
	_tier = tier
	_max_health = health
	_enabled = (_type == &"boss" and tier >= config.shield_minimum_level) or (_type != &"boss" and tier == 5)
	armor_remaining = config.armor_hits if _enabled and _type == &"golem" else 0
	_dash_clock = config.dash_interval
	effects.configure(_type, armor_remaining)


func health_changed(health: int) -> void:
	if not _enabled or health <= 0:
		return
	var ratio: float = float(health) / float(_max_health)
	if _type == &"orc" and not raging and ratio <= config.rage_health_ratio:
		raging = true
		effects.set_aura(&"rage")
		effects.burst(Color("ff6651"))
		_activate(&"rage")
	elif _type == &"boss":
		if not _half_triggered and ratio <= config.shield_health_trigger:
			_half_triggered = true
			_queue.append(&"shield")
			if _tier >= config.retinue_minimum_level:
				_queue.append(&"summon")
		if not _rush_triggered and _tier >= config.rush_minimum_level and ratio <= config.rush_health_trigger:
			_rush_triggered = true
			_queue.append(&"rush")
		_start_next()


func filter_damage(amount: float, direct: bool) -> float:
	if not _enabled:
		return amount
	if direct and armor_remaining > 0:
		armor_remaining -= 1
		amount *= config.armor_damage_ratio
		effects.break_plate(armor_remaining)
		_activate(&"carapace_hit")
	if shield_health > 0.0:
		var absorbed: float = minf(amount, shield_health)
		shield_health = maxf(shield_health - absorbed, 0.0)
		amount -= absorbed
		effects.set_shield(shield_health / maxf(float(_max_health) * config.shield_health_ratio, 0.001))
	return amount


# Возвращает время движения с учётом ускорения. Границы рывка не зависят от FPS.
func advance(delta: float) -> float:
	if not _enabled:
		return delta
	var remaining: float = delta
	var movement: float = 0.0
	while remaining > 0.000001:
		var slice: float = remaining
		if _type == &"goblin":
			var deadline: float = _windup if _dash_preparing else (_dash_remaining if _dash_remaining > 0.0 else _dash_clock)
			slice = minf(slice, maxf(deadline, 0.000001))
		elif _windup > 0.0:
			slice = minf(slice, _windup)
		elif _waiting > 0.0:
			slice = minf(slice, _waiting)
		movement += slice * speed_multiplier()
		remaining -= slice
		if _type == &"goblin":
			_advance_dash(slice)
		else:
			_advance_boss(slice)
	return movement


func _advance_dash(delta: float) -> void:
	if _dash_preparing:
		_windup = maxf(_windup - delta, 0.0)
		if _windup <= 0.000001:
			_dash_preparing = false
			_dash_remaining = config.dash_duration
			effects.set_aura(&"dash")
			effects.burst(Color("d8f6ff"))
	elif _dash_remaining > 0.0:
		_dash_remaining = maxf(_dash_remaining - delta, 0.0)
		if _dash_remaining <= 0.000001:
			_dash_remaining = 0.0
			effects.set_aura(&"")
	else:
		_dash_clock = maxf(_dash_clock - delta, 0.0)
		if _dash_clock <= 0.000001:
			_dash_clock = maxf(config.dash_interval - config.dash_windup - config.dash_duration, 0.001)
			_dash_preparing = true
			_windup = config.dash_windup
			effects.telegraph(&"dash", config.dash_windup)
			_activate(&"dash")


func _advance_boss(delta: float) -> void:
	if _windup > 0.0:
		_windup = maxf(_windup - delta, 0.0)
		if _windup <= 0.000001:
			_windup = 0.0
			if _event == &"summon":
				effects.burst(Color("ce86ff"))
				# Состояние закрыто до callback: смерть/смена сцены не повторит призыв.
				_event = &""
				retinue_requested.emit()
			elif _event == &"rush":
				rushing = true
				effects.set_aura(&"rush")
				_event = &""
			_waiting = maxf(config.ability_spacing - config.summon_windup, 0.0)
	elif _waiting > 0.0:
		_waiting = maxf(_waiting - delta, 0.0)
	_start_next()


func _start_next() -> void:
	if not _enabled or _queue.is_empty() or _windup > 0.0 or _waiting > 0.000001:
		return
	_event = _queue.pop_front()
	match _event:
		&"shield":
			shield_health = float(_max_health) * config.shield_health_ratio
			effects.set_shield(1.0)
			effects.burst(Color("cbb1ff"))
			_waiting = config.ability_spacing
		&"summon":
			_windup = config.summon_windup
			effects.telegraph(&"summon", _windup)
		&"rush":
			_windup = config.rush_windup
			effects.telegraph(&"rush", _windup)
	_activate(_event)


func _activate(ability: StringName) -> void:
	started.emit(ability)


func speed_multiplier() -> float:
	if not _enabled:
		return 1.0 + haste_bonus
	if _dash_preparing or (_event == &"rush" and _windup > 0.0):
		return 0.0
	if _dash_remaining > 0.0:
		return 1.0 + maxf(config.dash_speed_bonus,haste_bonus)
	if raging:
		return 1.0 + maxf(config.rage_speed_bonus,haste_bonus)
	if rushing:
		return 1.0 + maxf(config.rush_speed_bonus,haste_bonus)
	return 1.0 + haste_bonus


func stop() -> void:
	_enabled = false
	haste_bonus = 0.0
	_queue.clear()
	shield_health = 0.0
	armor_remaining = 0
	raging = false
	rushing = false
	_half_triggered = false
	_rush_triggered = false
	_waiting = 0.0
	_windup = 0.0
	_event = &""
	_dash_remaining = 0.0
	_dash_preparing = false
	if is_instance_valid(effects):
		effects.clear()
