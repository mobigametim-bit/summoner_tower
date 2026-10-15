class_name CombatHit
extends RefCounted


static func targets_in_area(enemies: Node2D, center: Vector2, radius: float) -> Array[ApproachingEnemy]:
	var result: Array[ApproachingEnemy] = []
	if not is_instance_valid(enemies):
		return result
	for child: Node in enemies.get_children():
		var enemy: ApproachingEnemy = child as ApproachingEnemy
		if is_instance_valid(enemy) and enemy.is_targetable() and enemy.global_position.distance_squared_to(center) <= radius * radius:
			result.append(enemy)
	return result


static func apply(enemy: ApproachingEnemy, damage: float, slow: float, slow_duration: float, burn_ratio: float, burn_duration: float, freeze_duration: float = 0.0) -> void:
	if not is_instance_valid(enemy) or not enemy.is_targetable():
		return
	enemy.take_damage(damage)
	if not is_instance_valid(enemy) or not enemy.is_targetable():
		return
	enemy.apply_slow(slow, slow_duration)
	enemy.apply_burn(damage * burn_ratio, burn_duration)
	enemy.apply_freeze(freeze_duration)
