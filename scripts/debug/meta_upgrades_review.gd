extends "res://scripts/ui/meta_upgrades.gd"

var _snapshot_callback: JavaScriptObject


func _ready() -> void:
	super._ready()
	if OS.has_feature("web"):
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getMetaUpgradesReview = _snapshot_callback


func _publish_snapshot(_arguments: Array) -> void:
	var cards: Array = []
	for card: MetaUpgradeCard in get_node("Center/Stack/Scroll/Cards").get_children():
		var point: Vector2 = card.get_global_rect().get_center()
		cards.append({"kind":card.kind,"position":[point.x,point.y],"level":SessionProgress.upgrade_level(card.kind),"disabled":card.disabled,"tooltip":card.tooltip_text,"price":SessionProgress.UPGRADE_CONFIG.price_for(0,card.kind),"title":tr(SessionProgress.UPGRADE_CONFIG.titles[card.kind])})
	JavaScriptBridge.get_interface("window").metaUpgradesSnapshotJSON = JSON.stringify({"cards":cards,"crystals":SessionProgress.crystals,"scroll":get_node("Center/Stack/Scroll").scroll_vertical})


func _exit_tree() -> void:
	if _snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getMetaUpgradesReview = null
