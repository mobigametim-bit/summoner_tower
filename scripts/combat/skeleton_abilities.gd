class_name SkeletonAbilities
extends EnemyAbilities

signal shield_changed(active: bool)

@export var shield_config: SkeletonShieldConfig
var shield_remaining: float = 0.0


func configure(enemy_type: StringName, tier: int, health: int) -> void:
	stop()
	_type = enemy_type
	_tier = tier
	_max_health = health
	_enabled = enemy_type == &"skeleton" and tier >= shield_config.minimum_tier
	effects.hide()
	set_physics_process(_enabled)


func health_changed(health: int) -> void:
	if not _enabled or _half_triggered or health <= 0:
		return
	if float(health) > float(_max_health)*shield_config.health_trigger:
		return
	# Commit the one-time trigger before callbacks can deliver another hit.
	_half_triggered = true
	shield_health = float(_max_health)*shield_config.health_ratio
	shield_remaining = shield_config.duration
	shield_changed.emit(true)
	started.emit(&"bone_shield")


func filter_damage(amount: float, _direct: bool) -> float:
	var absorbed: float = minf(amount,shield_health)
	shield_health = maxf(shield_health-absorbed,0.0)
	if absorbed > 0.0 and shield_health <= 0.0:
		_clear_shield()
	return amount-absorbed


func _physics_process(delta: float) -> void:
	if shield_remaining > 0.0:
		shield_remaining = maxf(shield_remaining-delta,0.0)
		if shield_remaining <= 0.0:
			_clear_shield()


func advance(delta: float) -> float:
	# Shield time advances in physics even while movement is frozen.
	return delta*speed_multiplier()


func _clear_shield() -> void:
	shield_health = 0.0
	shield_remaining = 0.0
	shield_changed.emit(false)


func stop() -> void:
	super.stop()
	set_physics_process(false)
	_clear_shield()
