class_name AdService
extends Node

enum Placement { REVIVE, DOUBLE_REWARD }
enum Outcome { SUCCESS, CANCELED, FAILED }

signal completed(placement: Placement, outcome: Outcome)
signal progress_changed(value: float)

@onready var watch_timer: Timer = $WatchTimer

var busy: bool = false
var _placement: Placement = Placement.REVIVE
# Только для debug-сцен: обычный fake-просмотр завершается успешно.
var next_outcome: Outcome = Outcome.SUCCESS
var _outcome: Outcome = Outcome.SUCCESS


func request(placement: Placement, duration: float) -> bool:
	if busy or duration <= 0.0:
		return false
	busy = true
	_placement = placement
	_outcome = next_outcome
	next_outcome = Outcome.SUCCESS
	watch_timer.start(duration)
	return true


func cancel() -> void:
	_finish(Outcome.CANCELED)


func _process(_delta: float) -> void:
	if busy:
		progress_changed.emit(1.0 - watch_timer.time_left / watch_timer.wait_time)


func abort() -> void:
	# Уход со сцены не должен вызвать выдачу награды из старого забега.
	busy = false
	watch_timer.stop()


func _on_watch_timer_timeout() -> void:
	_finish(_outcome)


func _finish(outcome: Outcome) -> void:
	if not busy:
		return
	busy = false
	watch_timer.stop()
	completed.emit(_placement, outcome)


func _exit_tree() -> void:
	busy = false
