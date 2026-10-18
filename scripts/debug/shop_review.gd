extends Node


func _ready() -> void:
	# Все покупки этого запуска живут только в памяти, отдельно от настоящего игрока.
	SessionProgress.use_test_save()
	SessionProgress.crystals = 248
	SessionProgress.unlocked_biomes.assign(["forest", "graveyard"])
	var tutorial: Node = get_node_or_null("/root/Tutorial")
	if tutorial != null:
		tutorial.set("enabled", false)
	ShopService.enable_test_mode()
	if OS.has_feature("web"):
		ShopService.set_meta("review_bridge", load("res://scripts/debug/shop_review_bridge.gd").new(get_tree()))
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
