extends CanvasLayer

const CORE: Array[String] = ["field", "health", "summon_first", "unit", "move", "summon_second", "merge", "levels", "combat"]

@export var map_config: TutorialMapConfig = preload("res://resources/tutorial/map_config.tres")

@onready var overlay: Control = $Overlay
var progress: TutorialProgress
var enabled: bool = true
var active_id: String = ""
var core_active: bool = false
var core_index: int = 0
var _host: Node
var _mode: String = ""
var _pending: Array[String] = []
var _series: Array[String] = []
var _owns_pause: bool = false
var _first: CombatUnit
var _destination: SummonSlot
var _hint_after: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Отладочные сцены не читают/не портят обычное обучение и не получают лишних окон.
	enabled = not SessionProgress._test_session
	progress = TutorialProgress.new(TutorialProgress.SAVE_PATH if enabled else "")
	SessionProgress.upgrades_changed.connect(_on_meta_bought)
	LocaleService.language_changed.connect(_refresh_text)


func use_test_session(path: String = "") -> void:
	_detach()
	enabled = true
	progress = TutorialProgress.new(path)


func needs_core() -> bool:
	return enabled and progress.started and not progress.completed and not progress.skipped


func enter_menu(menu: Control) -> void:
	_attach(menu, "menu")
	if not enabled or progress.skipped:
		return
	if not progress.completed:
		_show("play" if progress.started else "welcome")
	elif SessionProgress.crystals > 0 and progress.seen.has("results"):
		_enqueue("meta_entry")
	if SessionProgress.unlocked_biomes.size() > 1:
		_enqueue("biomes")
	_hint_after = 0.0


func enter_meta(screen: Control) -> void:
	_attach(screen, "meta")
	if progress.completed:
		_enqueue("meta")
	_hint_after = 0.0


func prepare_game(game: Node) -> bool:
	_attach(game, "game")
	if not enabled or progress.skipped:
		return false
	game.summon_manager.unit_summoned.connect(_on_unit_summoned)
	game.summon_manager.transfer_completed.connect(_on_transfer)
	game.summon_manager.state_changed.connect(_on_summon_state)
	game.drag_controller.drag_started.connect(_on_drag_started)
	game.wave_manager.state_changed.connect(_on_wave)
	game.wave_manager.enemy_resolved.connect(_on_enemy_resolved)
	game.enemies.child_entered_tree.connect(_on_enemy_created)
	if not needs_core():
		return false
	core_active = true
	core_index = 0
	game.summon_manager.tutorial_archers_remaining = 2
	game.state = game.State.TUTORIAL_SETUP
	game.hud.set_settings_available(false)
	game.hud.update_wave(1, WaveManager.Phase.STOPPED, 0, 0, 5)
	_show_core.call_deferred()
	return true


func present_context(game: Node, context: String) -> void:
	if not enabled or progress.skipped or core_active or game != _host:
		return
	_close()
	_series.clear()
	match context:
		"upgrade":
			_series.assign(["cards", "card_colors", "reroll"])
			var boss_number: int = maxi(game._upgrade_wave / game.wave_manager.config.boss_interval, 1)
			_series.append("map_80" if boss_number == 1 else ("map_60" if boss_number == 2 else "map_40"))
		"revive": _series.append("revive")
		"results":
			if game.run_statistics.victory:
				_series.append("victory")
			_series.append("results")
		"settings": _series.append("settings")
	_next_series()


func replay_from_menu() -> void:
	if not enabled or _mode != "menu" or not is_instance_valid(_host):
		return
	progress.replay()
	_pending.clear()
	_show("welcome")


func _attach(host: Node, mode: String) -> void:
	_detach()
	_host = host
	_mode = mode
	host.tree_exiting.connect(_detach, CONNECT_ONE_SHOT)


func _detach() -> void:
	_close()
	if is_instance_valid(_host) and _host.tree_exiting.is_connected(_detach):
		_host.tree_exiting.disconnect(_detach)
	_host = null
	_first = null
	_destination = null
	core_active = false
	_pending.clear()
	_series.clear()
	_mode = ""


func _process(delta: float) -> void:
	if not enabled or progress == null or progress.skipped or not is_instance_valid(_host):
		return
	_clock += delta
	if _clock < 0.1:
		return
	_clock = 0.0
	if not active_id.is_empty():
		_arrange()
		return
	if core_active or Time.get_ticks_msec() < _hint_after:
		return
	if _mode == "game":
		if _host.state != _host.State.RUNNING or _host.drag_controller.has_pointer():
			return
		var army: Node = _host.wave_manager.graveyard_army
		if army != null and army.has_method("remains_count") and army.remains_count() > 0:
			_enqueue("remains")
	elif _mode == "menu" and _host.settings_overlay.visible:
		return
	if not _pending.is_empty():
		var id: String = _pending.pop_front()
		if not progress.seen.has(id) and _still_relevant(id):
			_show(id)


func _still_relevant(id: String) -> bool:
	if _mode != "game":
		return true
	if id == "full":
		return _host.summon_manager.occupied_count() == _host.summon_manager._slots.size()
	if id == "boss_leftovers":
		return _host.wave_manager.config.is_boss_wave(_host.wave_manager.wave_number) and _host.wave_manager.active_count() > 0
	if id == "boss":
		return _host.wave_manager.config.is_boss_wave(_host.wave_manager.wave_number)
	return true


func _enqueue(id: String) -> void:
	if enabled and not progress.skipped and not progress.seen.has(id) and active_id != id and not _pending.has(id):
		_pending.append(id)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(overlay) or not overlay.visible or not (event is InputEventKey or event is InputEventJoypadButton):
		return
	# Затемнение блокирует указатель, а клавиатуру держим внутри модального окна.
	# Иначе Escape может закрыть лежащую под советом паузу, а Tab — выбрать башню.
	if event.is_action_pressed(&"ui_cancel") and _mode == "game" and is_instance_valid(_host):
		_host.drag_controller.cancel_drag()
	elif event.is_action_pressed(&"ui_accept"):
		if overlay.next_button.visible:
			overlay._on_next_pressed()
	elif event.is_action_pressed(&"ui_focus_next") or event.is_action_pressed(&"ui_focus_prev"):
		if overlay.next_button.visible:
			overlay.next_button.grab_focus()
	get_viewport().set_input_as_handled()


func _next_series() -> void:
	while not _series.is_empty():
		var id: String = _series.pop_front()
		if not progress.seen.has(id):
			_show(id)
			return


func _show_core() -> void:
	if not core_active or not is_instance_valid(_host):
		return
	var id: String = CORE[core_index]
	# При новом забеге действия нужно повторить, но уже прочитанные объяснения пропускаются.
	if id in ["field", "health", "unit", "levels"] and progress.seen.has(id):
		_advance_core()
		return
	if id == "move" and is_instance_valid(_first):
		var best: float = INF
		var cell_center: Vector2 = _host.battlefield.layout.cell_center(map_config.move_cell)
		for slot: SummonSlot in _host.summon_manager._slots:
			var distance: float = slot.global_position.distance_squared_to(cell_center)
			if slot.is_empty() and distance < best:
				_destination = slot
				best = distance
		_host.drag_controller.tutorial_source = _first.get_parent().get_parent() as SummonSlot
		_host.drag_controller.tutorial_destination = _destination
	elif id == "merge":
		_host.drag_controller.tutorial_source = _first.get_parent().get_parent() as SummonSlot
		for slot: SummonSlot in _host.summon_manager._slots:
			if not slot.is_empty() and slot.unit != _first:
				_destination = slot
		_host.drag_controller.tutorial_destination = _destination
	_show(id)


func _show(id: String) -> void:
	if not is_instance_valid(_host):
		return
	active_id = id
	var action: bool = id in ["play", "summon_first", "move", "summon_second", "merge"]
	if _mode == "game" and not core_active and not _owns_pause:
		_owns_pause = _host.begin_tutorial_pause()
	_refresh_text()
	_arrange.call_deferred()


func _refresh_text() -> void:
	if active_id.is_empty() or not is_instance_valid(_host):
		return
	var value: Variant = null
	if active_id == "range_sale":
		value = _host.run_bonuses.manual_refund_percent(_host.summon_manager.config.refund_percent)
	elif active_id.begins_with("map_"):
		var boss_number: int = maxi(_host._upgrade_wave / _host.wave_manager.config.boss_interval, 1)
		value = _host.summon_manager.config.map_refund_percent_for(boss_number)
	elif active_id == "revive":
		value = _host.run_statistics.config.revive_health
	var action: bool = active_id in ["play", "summon_first", "move", "summon_second", "merge"]
	overlay.present(TutorialLessons.line(active_id, value), action, active_id == "welcome",
		progress.last_error != OK, _mode == "game")


func _arrange() -> void:
	var rect: Rect2
	var start: Vector2
	var finish: Vector2
	match active_id:
		"play": rect = _host.play_button.get_global_rect().grow(10.0)
		"meta_entry": rect = _host.upgrades_button.get_global_rect().grow(10.0)
		"biomes": rect = (_host.next_biome if _host.next_biome.visible else _host.previous_biome).get_global_rect().grow(10.0)
		"field": rect = _host.hud.field_rect.grow(-6)
		"health": rect = _host.hud.health_label.get_parent().get_global_rect().grow(8.0)
		"summon_first", "summon_second": rect = _host.tower.summon_button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _host.tower.summon_button.size)
		"unit":
			if is_instance_valid(_first):
				rect = _first.get_global_transform_with_canvas()*Rect2(Vector2(-65,-70),Vector2(130,140))
		"move", "merge":
			if is_instance_valid(_first) and is_instance_valid(_destination):
				start = _first.get_global_transform_with_canvas().origin
				finish = _destination.get_global_transform_with_canvas().origin
				rect = Rect2(start - Vector2(70, 80), Vector2(140, 160)).merge(Rect2(finish - Vector2(70, 80), Vector2(140, 160)))
	var action: bool = active_id in ["play", "summon_first", "move", "summon_second", "merge"]
	var top: bool = rect.has_area() and rect.get_center().y > overlay.size.y*0.5
	if active_id in ["welcome", "cards", "card_colors", "reroll"] or active_id.begins_with("map_"):
		top = false
	overlay.arrange(rect, action, top, start, finish)


func _on_continued() -> void:
	if active_id.is_empty():
		return
	var id: String = active_id
	progress.mark(id)
	_close()
	if id == "welcome":
		progress.started = true
		progress.save()
		# Только явное начало обучения выбирает лес; открытия/мета не меняются.
		SessionProgress.select_biome(&"forest")
		_show("play")
	elif core_active:
		_advance_core()
	else:
		_next_series()


func _close() -> void:
	if is_instance_valid(overlay):
		overlay.hide()
	active_id = ""
	if _owns_pause and is_instance_valid(_host):
		_host.end_tutorial_pause()
	_owns_pause = false
	_hint_after = Time.get_ticks_msec() + 8000.0


func _advance_core() -> void:
	if not core_active:
		return
	_close()
	_host.summon_manager.set_interaction_enabled(true)
	_host.drag_controller.tutorial_source = null
	_host.drag_controller.tutorial_destination = null
	core_index += 1
	if core_index >= CORE.size():
		progress.completed = true
		progress.save()
		_finish_core()
	else:
		_show_core()


func _finish_core() -> void:
	core_active = false
	_host.summon_manager.tutorial_archers_remaining = 0
	_host.drag_controller.tutorial_source = null
	_host.drag_controller.tutorial_destination = null
	_host.finish_tutorial_setup()


func _on_unit_summoned(unit: CombatUnit, gift: bool) -> void:
	if core_active:
		if active_id == "summon_first":
			_first = unit
			_complete_action()
		elif active_id == "summon_second":
			_complete_action()
		return
	_enqueue("gift" if gift else "random")
	if unit.stats.unit_type in [&"mage", &"frost_mage", &"priest"]:
		_enqueue(String(unit.stats.unit_type))
	if unit.stats.level == 5:
		_enqueue("lv5")


func _on_transfer(unit: CombatUnit, destination: SummonSlot, merged: bool, swapped: bool) -> void:
	if core_active:
		if destination == _destination and ((active_id == "move" and unit == _first) or (active_id == "merge" and merged)):
			_complete_action()
		return
	if swapped:
		_enqueue("max" if unit.stats.level == 5 else "swap")
	if merged:
		if destination.unit.stats.level >= 3:
			_enqueue("lv3")
		if destination.unit.stats.level == 5:
			_enqueue("lv5")


func _on_summon_state(_mana: int, _cost: int, occupied: int, capacity: int, _available: bool) -> void:
	if not core_active and occupied == capacity:
		_enqueue("full")
		_enqueue("range_sale")


func _complete_action() -> void:
	# Закрываем вход до deferred-перехода: второй тап не покупает лишнего бойца.
	progress.mark(active_id)
	active_id = ""
	overlay.shade.allows_action = false
	_host.summon_manager.set_interaction_enabled(false)
	_advance_core.call_deferred()


func _on_drag_started(_unit: CombatUnit) -> void:
	if not core_active:
		_enqueue("range_sale")


func _on_wave(wave: int, phase: WaveManager.Phase, _seconds: int, _alive: int, _pending_count: int) -> void:
	if phase == WaveManager.Phase.FIGHTING and _host.wave_manager.config.is_boss_wave(wave) and not _pending.has("boss") and active_id != "boss" and not progress.seen.has("boss"):
		_enqueue("boss")
		_hint_after = maxf(_hint_after, Time.get_ticks_msec() + 2500.0)


func _on_enemy_resolved(enemy: ApproachingEnemy, outcome: ApproachingEnemy.Outcome, _mana: int) -> void:
	_enqueue("mana")
	if outcome == ApproachingEnemy.Outcome.KILLED and enemy.stats.is_boss and _host.wave_manager.active_count() > 0:
		_enqueue("boss_leftovers")


func _on_enemy_created(node: Node) -> void:
	_inspect_enemy.call_deferred(weakref(node))


func _inspect_enemy(reference: WeakRef) -> void:
	var node: Node = reference.get_ref() as Node
	if not is_instance_valid(node) or not node is ApproachingEnemy or _mode != "game" or not is_instance_valid(_host) or not _host.enemies.is_ancestor_of(node):
		return
	if node.difficulty_tier > 1:
		_enqueue("enemy_level")
	node.abilities.started.connect(_on_enemy_ability)
	if node.abilities is GraveyardAbilities:
		node.abilities.shield_changed.connect(_on_undead_shield)


func _on_undead_shield(active: bool) -> void:
	if active:
		_on_enemy_ability(&"shield")


func _on_enemy_ability(ability: StringName) -> void:
	var id: String = "ability_" + String(ability)
	if TutorialLessons.LINES.has(id):
		_enqueue(id)
		if _pending.has(id):
			_pending.erase(id)
			_pending.push_front(id)
			_hint_after = 0.0


func _on_meta_bought() -> void:
	if _mode == "meta":
		_enqueue("meta_bought")
		_hint_after = 0.0
