extends Node


func _ready() -> void:
	# Только отдельная браузерная тестовая сборка; tests/* исключены из обычного Web export.
	if OS.has_feature("web"):
		var manager: SummonManager = $Game/SummonManager
		manager.mana = 1000
		manager._emit_state()


func run_checks() -> void:
	set_meta("feature5_checks", load("res://tests/support/feature_5_checks.gd").new().run($Game))
