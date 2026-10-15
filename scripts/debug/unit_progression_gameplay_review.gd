extends "res://scripts/game/game_manager.gd"

var _snapshot_callback: JavaScriptObject
var review_checks: Dictionary = {}
var review_unit: CombatUnit
var _ready_for_review: bool = false


func _ready() -> void:
	super._ready()
	wave_manager.stop()
	for enemy: Node in enemies.get_children():
		enemy.queue_free()
	await get_tree().process_frame
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("new URL(location.href).searchParams.get('checks') === '1'",true)):
		review_checks = await load("res://scripts/debug/unit_progression_checks.gd").new().run(self)
	var kind: String = "archer"
	var level: int = 5
	if OS.has_feature("web"):
		var requested: String = str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('unit') || 'archer'",true))
		if requested in ["archer","mage","frost_mage"]:
			kind = requested
		level = clampi(int(JavaScriptBridge.eval("Number(new URL(location.href).searchParams.get('level')) || 5",true)),1,5)
	var slot: SummonSlot = summon_manager._slots[0]
	for candidate: SummonSlot in summon_manager._slots:
		if candidate.global_position.x < 450.0 and candidate.global_position.y > 200.0 and candidate.global_position.y < 800.0:
			slot = candidate
			break
	review_unit = load("res://scenes/%s.tscn" % kind).instantiate()
	review_unit.stats = load("res://resources/balance/%s_lv%d.tres" % [kind,level])
	slot.place_unit(review_unit)
	review_unit.configure(enemies,projectiles,run_bonuses)
	review_unit.paid_mana = 20
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("new URL(location.href).searchParams.get('pair') === '1'",true)):
		var added: int = 0
		for candidate: SummonSlot in summon_manager._slots:
			if not candidate.is_empty():
				continue
			var paired: CombatUnit = load("res://scenes/%s.tscn" % (kind if added == 0 else "mage" if kind == "archer" else "archer")).instantiate()
			paired.stats = review_unit.stats if added == 0 else paired.stats
			candidate.place_unit(paired)
			paired.configure(enemies,projectiles,run_bonuses)
			added += 1
			if added == 2:
				break
	var count: int = 4
	if OS.has_feature("web"):
		count = clampi(int(JavaScriptBridge.eval("Number(new URL(location.href).searchParams.get('count')) || 4",true)),4,80)
	for index: int in count:
		var enemy: ApproachingEnemy = load("res://scenes/boss.tscn" if index == 3 else "res://scenes/enemy.tscn").instantiate()
		enemies.add_child(enemy)
		# В нагрузочном fixture целочисленное деление задаёт номер строки.
		@warning_ignore("integer_division")
		var offset: Vector2 = Vector2(75.0+index*12.0,(index-1)*25.0) if count == 4 else Vector2(40.0+(index%10)*9.0,(index/10-4)*12.0)
		enemy.configure(review_unit.global_position+offset,10000.0,100000)
		if count > 4:
			enemy.apply_burn(10000.0,6.0)
		enemy.move_speed = 0.0
		if index == 3:
			enemy.scale = Vector2.ONE * 0.65
	_ready_for_review = true
	if OS.has_feature("web"):
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getUnitProgressionGame = _snapshot_callback


func _publish_snapshot(_arguments: Array) -> void:
	var targets: Array[Dictionary] = []
	for child: Node in enemies.get_children():
		var enemy: ApproachingEnemy = child as ApproachingEnemy
		if enemy == null:
			continue
		targets.append({"boss":enemy.stats.is_boss,"health":enemy.current_health,"burn":enemy._burn_remaining,"freeze":enemy._freeze_remaining,"slow":enemy._slow_ratio,"position":[enemy.global_position.x,enemy.global_position.y]})
	var data: Dictionary = {"ready":_ready_for_review,"checks":review_checks,"paused":get_tree().paused,"state":state,"targets":targets,"fps":Engine.get_frames_per_second(),"nodes":get_tree().get_node_count(),"power":_player_power(),"skill_cooldown":review_unit._skill_cooldown if is_instance_valid(review_unit) else -1.0,"shots":projectiles.get_child_count(),"range":review_unit.stats.attack_range if is_instance_valid(review_unit) else 0.0,"unit_position":[review_unit.global_position.x,review_unit.global_position.y] if is_instance_valid(review_unit) else [0,0]}
	data["controls"] = {"settings":_center(hud.settings_button),"resume":_center(hud.resume_button),"menu":_center(hud.get_node("SettingsOverlay/Center/Panel/Stack/SettingsMenuButton")),"tower":[tower.global_position.x,tower.global_position.y]}
	data["draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	data["drag_range"] = drag_controller.attack_range_preview.visible
	var range_preview: AttackRangePreview = drag_controller.attack_range_preview
	data["range_preview"] = {"radius":range_preview.radius,"color":range_preview.level_color.to_html(),"position":[range_preview.global_position.x,range_preview.global_position.y]}
	var merge_preview: AttackRangePreview = drag_controller.merge_range_preview
	data["merge_range_preview"] = {"visible":merge_preview.visible,"radius":merge_preview.radius,"color":merge_preview.level_color.to_html(),"position":[merge_preview.global_position.x,merge_preview.global_position.y]}
	var slots: Array[Dictionary] = []
	for slot: SummonSlot in summon_manager._slots:
		var item: Dictionary = {"position":[slot.global_position.x,slot.global_position.y],"occupied":not slot.is_empty()}
		if not slot.is_empty():
			item["unit_position"] = [slot.unit.global_position.x,slot.unit.global_position.y]
			item["type"] = slot.unit.stats.unit_type
			item["level"] = slot.unit.stats.level
		slots.append(item)
	data["slots"] = slots
	JavaScriptBridge.eval("window.unitProgressionGame = %s;" % JSON.stringify(data),true)


func _center(control: Control) -> Array[float]:
	var point: Vector2 = control.get_global_rect().get_center()
	return [point.x,point.y]


func _exit_tree() -> void:
	if _snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getUnitProgressionGame = null
	super._exit_tree()
