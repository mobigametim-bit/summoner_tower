class_name RunStatistics
extends Node

@export var config: RunRewardConfig

var reached_wave: int = 1
var completed_waves: int = 0
var killed_enemies: int = 0
var killed_bosses: int = 0
var merges: int = 0
var earned_crystals: int = 0
var total_crystals: int = 0
var finished: bool = false
var victory: bool = false
var result_saved: bool = false
var newly_unlocked_biome: StringName
var reward_doubled: bool = false
var _last_completed_wave: int = 0
var _unlock_biome_id: StringName
var _saving_result: bool = false


func reset() -> void:
	reached_wave = 1
	completed_waves = 0
	killed_enemies = 0
	killed_bosses = 0
	merges = 0
	earned_crystals = 0
	total_crystals = 0
	finished = false
	victory = false
	result_saved = false
	newly_unlocked_biome = &""
	_unlock_biome_id = &""
	_saving_result = false
	reward_doubled = false
	_last_completed_wave = 0


func record_enemy(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome) -> void:
	if finished or outcome != ApproachingEnemy.Outcome.KILLED:
		return
	killed_enemies += 1
	if enemy.stats.is_boss:
		killed_bosses += 1


func record_wave_state(wave: int, phase: WaveManager.Phase, _seconds: int, _alive: int, _pending: int) -> void:
	if not finished and phase == WaveManager.Phase.FIGHTING:
		reached_wave = maxi(reached_wave, wave)


func record_completed_wave(wave: int) -> void:
	if finished or wave <= _last_completed_wave:
		return
	_last_completed_wave = wave
	completed_waves += 1


func record_merge() -> void:
	if not finished:
		merges += 1


func finish(won: bool = false, unlock_biome_id: StringName = &"") -> bool:
	if finished:
		return false
	# Фиксируем результат до сигнала кошелька: повторный callback не выдаст награду.
	finished = true
	victory = won
	_unlock_biome_id = unlock_biome_id if won else &""
	earned_crystals = config.reward_for(completed_waves, killed_bosses)
	save_result()
	return true


func save_result() -> bool:
	if not finished or _saving_result:
		return false
	if result_saved:
		return true
	_saving_result = true
	var was_locked: bool = not _unlock_biome_id.is_empty() and not SessionProgress.is_biome_unlocked(_unlock_biome_id)
	result_saved = (earned_crystals == 0 and _unlock_biome_id.is_empty()) or SessionProgress.try_add_reward(earned_crystals, _unlock_biome_id)
	if result_saved and was_locked:
		newly_unlocked_biome = _unlock_biome_id
	total_crystals = SessionProgress.crystals
	_saving_result = false
	return result_saved


func can_double_reward() -> bool:
	return finished and result_saved and not reward_doubled and earned_crystals > 0


func double_reward() -> bool:
	if not can_double_reward():
		return false
	# Защита от повторного вызова из сигналов кошелька.
	reward_doubled = true
	if not SessionProgress.try_add_reward(earned_crystals):
		reward_doubled = false
		return false
	earned_crystals *= 2
	total_crystals = SessionProgress.crystals
	return true
