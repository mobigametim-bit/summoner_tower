class_name SummonPool
extends Resource

@export var scenes: Array[PackedScene] = []
@export var weights: Array[int] = []


func is_valid() -> bool:
	if scenes.is_empty() or scenes.size() != weights.size():
		return false
	for index: int in scenes.size():
		if scenes[index] == null or weights[index] <= 0:
			return false
	return true


func roll(rng: RandomNumberGenerator) -> PackedScene:
	if not is_valid():
		return null
	var total: int = 0
	for weight: int in weights:
		total += weight
	var choice: int = rng.randi_range(0, total - 1)
	for index: int in scenes.size():
		choice -= weights[index]
		if choice < 0:
			return scenes[index]
	return null
