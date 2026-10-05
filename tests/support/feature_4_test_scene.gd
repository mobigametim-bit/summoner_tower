extends Node


func run_checks() -> void:
	set_meta("feature4_checks", load("res://tests/support/feature_4_checks.gd").new().run($Game))
