extends "res://tests/support/feature_11_web_probe.gd"


func _ready() -> void:
	SessionProgress.use_test_save("user://feature12-browser.json" if OS.has_feature("web") else "user://feature12-native.json")


func _process(delta: float) -> void:
	super._process(delta)
	if not OS.has_feature("web"):
		return
	# Команды доступны исключительно в отдельном development export.
	var command: String = str(JavaScriptBridge.eval("window.feature12Command || ''"))
	if command.is_empty():
		return
	JavaScriptBridge.eval("window.feature12Command='' ")
	var current: Node = get_tree().current_scene
	if command == "finish_run" and current != null and current.has_node("RunStatistics"):
		current.run_statistics.completed_waves = 100
		current.tower.take_damage(current.tower.current_health)
