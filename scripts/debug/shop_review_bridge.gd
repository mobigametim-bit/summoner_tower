extends RefCounted

var tree: SceneTree
var callback: JavaScriptObject


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree
	callback = JavaScriptBridge.create_callback(_snapshot)
	JavaScriptBridge.get_interface("window").shopReview = callback


func _snapshot(_arguments: Array) -> void:
	var scene: Node = tree.current_scene
	var result: Dictionary = {"scene":scene.scene_file_path, "loading":not scene.is_node_ready()}
	if scene.is_node_ready():
		result.merge({"crystals":SessionProgress.crystals, "no_ads":ShopService.has_no_ads(),
			"test":ShopService.test_mode, "save_path":SessionProgress.save_manager.path,
			"viewport":[scene.get_viewport_rect().size.x, scene.get_viewport_rect().size.y]})
		if scene.has_node("Products"):
			var cards: Array = []
			for card: ShopProductCard in scene.get_node("Products").get_children():
				cards.append({"id":String(card.product.product_id), "amount":card.product.crystals, "price":card.product.price_rub, "button":_rect(card.price_button)})
			result.merge({"cards":cards,"details":scene.get_node("Details").visible,
				"panel":_rect(scene.panel), "info_visible":scene.get_node("Details/Panel/Info").visible,
				"detail_title":_rect(scene.get_node("Details/Panel/Title")),
				"back":_rect(scene.back_button),"buy":_rect(scene.get_node("Details/Panel/Buy")),
				"success":_rect(scene.get_node("Details/Panel/Outcomes/Success")),
				"cancel":_rect(scene.get_node("Details/Panel/Outcomes/Cancel")),
				"failure":_rect(scene.get_node("Details/Panel/Outcomes/Failure")),
				"close":_rect(scene.get_node("Details/Panel/Close"))})
		elif scene.has_method("_on_shop_button_pressed"):
			result.merge({"shop":_rect(scene.shop_button),"play":_rect(scene.play_button),
				"wallet":_rect(scene.crystal_wallet),"title":_rect(scene.biome_title),
				"wallet_font":scene.crystal_balance.get_theme_font_size("font_size"),
				"wallet_icon":_rect(scene.crystal_wallet.get_node("Icon"))})
	JavaScriptBridge.get_interface("window").shopSnapshot = JSON.stringify(result)


static func _rect(control: Control) -> Array:
	var rect: Rect2 = control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
	return [rect.get_center().x, rect.get_center().y, rect.size.x, rect.size.y]
