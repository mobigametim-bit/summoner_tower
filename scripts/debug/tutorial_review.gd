extends Node


func _ready() -> void:
	SessionProgress.use_test_save("user://tutorial_review_progress.json")
	Tutorial.use_test_session("user://tutorial_review.json")
	if OS.has_feature("web"):
		if JavaScriptBridge.eval("new URLSearchParams(location.search).get('restart') === '1'",true):
			Tutorial.progress.replay()
		# Broker живёт в autoload и переживает смену меню на бой.
		Tutorial.set_meta("review_bridge",load("res://scripts/debug/tutorial_review_bridge.gd").new(get_tree()))
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
