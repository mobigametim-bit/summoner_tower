extends Control

const REVIEW_PATH: String = "user://biome_framework_review.json"
var _snapshot_callback: JavaScriptObject
@onready var menu: Control = $Menu


func _ready() -> void:
	SessionProgress.use_test_save(REVIEW_PATH)
	menu._update_crystals(SessionProgress.crystals)
	menu._update_biome()
	if OS.has_feature("web"):
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getBiomeReview = _snapshot_callback


func _on_test_unlock_pressed() -> void:
	SessionProgress.unlock_biome(&"graveyard")


func _on_test_reset_pressed() -> void:
	var file: FileAccess = FileAccess.open(REVIEW_PATH, FileAccess.WRITE)
	if file == null:
		return
	# Изолированный v2 проходит настоящую миграцию, сохраняя кристаллы и мету.
	file.store_string(JSON.stringify({"version":2,"crystals":321,"upgrade_levels":[1,2,3,4,0,0,0,0,0,0,0]}))
	file.close()
	SessionProgress.use_test_save(REVIEW_PATH)
	menu._update_crystals(SessionProgress.crystals)
	menu._update_biome()


func _publish_snapshot(_args: Array) -> void:
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	window.biomeReviewJSON = JSON.stringify({
		"biome":SessionProgress.selected_biome_id,"unlocked":SessionProgress.unlocked_biomes,
		"crystals":SessionProgress.crystals,"levels":SessionProgress.upgrade_levels,
		"previous_visible":menu.previous_biome.is_visible_in_tree(),"next_visible":menu.next_biome.is_visible_in_tree(),
		"play_disabled":menu.play_button.disabled,"placeholder_visible":menu.biome_placeholder.visible,
		"settings_open":menu.settings_overlay.visible,
		"wallet_position":_center(menu.crystal_wallet), "menu_size":[menu.size.x, menu.size.y],
		"next_position":_center(menu.next_biome),"previous_position":_center(menu.previous_biome),
		"play_position":_center(menu.play_button),"settings_position":_center(menu.settings_button),
		"format_version":SaveManager.FORMAT_VERSION,
	})


func _center(control: Control) -> Array[float]:
	var point: Vector2 = control.get_global_rect().get_center()
	return [point.x, point.y]


func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").getBiomeReview = null
