extends Control

const KEYS: Array[StringName] = [&"skeleton", &"zombie", &"ghoul", &"necromancer", &"flesh_golem", &"lich"]
const TITLES: Array[String] = ["Скелет", "Зомби", "Вурдалак", "Некромант", "Голем плоти", "Лич"]
const COLORS: Array[Color] = [Color("88b96b"), Color("ec9b49"), Color("df5654"), Color("5295ef"), Color("b66dea")]
const LABELS: Dictionary = {"walk_loop":"Движение", "attack":"Атака", "hit":"Попадание", "death":"Смерть", "spawn_or_intro":"Появление", "bone_shield":"Костяной щит", "regenerate":"Восстановление", "dash":"Рывок", "heal":"Лечение союзника", "summon_skeletons":"Призыв скелетов", "assemble_flesh":"Сборка голема", "retinue":"Свита скелетов", "bone_cover":"Костяной покров", "grave_bell":"Погребальный звон"}
const NOTES: Dictionary = {"walk_loop":"Покачивание головы, шаги и движение оружия. Перемещение врага выполняет gameplay.", "attack":"Короткая подготовка → удар → восстановление. У голема плоти работают обе руки.", "hit":"Короткий отклик и вспышка. Переключи скорость на 0.5× для проверки стыков.", "death":"Потеря опоры и короткое исчезновение. ↺ восстанавливает позу.", "spawn_or_intro":"Фиолетовые лучи призыва, вспышка, дым и светящиеся искры.", "bone_shield":"Светящаяся оболочка, энергетические дуги и вращающиеся костяные осколки.", "regenerate":"Зелёное свечение, восходящие искры и редкие знаки лечения.", "dash":"Фиолетовый шлейф энергии, световые искры и дым под ногами. Без root motion.", "heal":"Поток светящихся частиц соединяет посох с раненым союзником справа.", "summon_skeletons":"Два фиолетовых всплеска: наши лучи призыва, искры и расходящийся дым.", "assemble_flesh":"Три останка с потоками душ стягиваются к печати. Затем вспышка призывает голема.", "retinue":"Три фиолетовых всплеска призыва скелетов вокруг лича.", "bone_cover":"Энергетическая оболочка охватывает лича целиком; кости и искры вращаются по краю.", "grave_bell":"Колебание колокола, светящиеся волны и вихри душ."}

@onready var overview: Node2D = $Center/Overview
@onready var focus: Node2D = $Center/Focus
@onready var asset_select: OptionButton = $Center/Controls/Asset
@onready var animation_select: OptionButton = $Center/Controls/Animation
@onready var repeat_toggle: CheckButton = $Center/Controls/Repeat
@onready var pause_button: Button = $Center/Controls/Pause
@onready var auto_button: Button = $Center/Controls/Auto
@onready var note: Label = $Center/Focus/Note
@onready var replay_timer: Timer = $ReplayTimer
@onready var auto_timer: Timer = $AutoTimer

var _overview_actors: Array[UndeadEnemyVisual] = []
var _focus_actors: Array[UndeadEnemyVisual] = []
var _samples: Array[UndeadEnemyVisual] = []
var _asset: int = 0
var _level: int = 5
var _clip: StringName = &"walk_loop"
var _focus_mode: bool = false
var _paused: bool = false
var _speed: float = 1.0
var _auto: bool = false
var _auto_clip: int = 0
var _callback: JavaScriptObject
var _events: Dictionary[StringName, int] = {}


func _ready() -> void:
	for i: int in KEYS.size():
		_overview_actors.append(overview.get_node("Card%d/Actor" % i) as UndeadEnemyVisual)
		_overview_actors[i].visual_animation_finished.connect(_on_finished.bind(i))
		_focus_actors.append(focus.get_node("Actors/" + String(KEYS[i]).to_pascal_case()) as UndeadEnemyVisual)
		_samples.append(focus.get_node("Samples/" + String(KEYS[i]).to_pascal_case()) as UndeadEnemyVisual)
		_focus_actors[i].effect_requested.connect(_on_effect.bind(i))
		_focus_actors[i].visual_animation_finished.connect(_on_finished.bind(i))
	_update_levels()
	_update_views()
	_update_animation_choices()
	_play()
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(_web_command)
		JavaScriptBridge.get_interface("window").graveyardAnimation = _callback
		var query_asset: String = str(JavaScriptBridge.eval("new URL(window.location.href).searchParams.get('asset') || ''"))
		var query_clip: String = str(JavaScriptBridge.eval("new URL(window.location.href).searchParams.get('clip') || ''"))
		if query_asset.is_valid_int():
			select_asset(int(query_asset))
		if not query_clip.is_empty() and _focus_actors[_asset].available_animations().has(StringName(query_clip)):
			set_clip(StringName(query_clip))


func _update_levels() -> void:
	for i: int in KEYS.size():
		var value: int = maxi(_level, 4) if i == 4 else _level
		for actor: UndeadEnemyVisual in [_overview_actors[i], _focus_actors[i], _samples[i]]:
			actor.set_level(value)
		var label: Label = overview.get_node("Card%d/Level" % i)
		label.text = "Некро Lv%d" % value if i == 4 else "Lv%d" % value
		label.modulate = COLORS[value - 1]
	for i: int in 5:
		var button: Button = get_node("Center/Controls/Level%d" % (i+1))
		button.button_pressed = i + 1 == _level
		button.disabled = _focus_mode and _asset == 4 and i < 3


func _update_views() -> void:
	overview.visible = not _focus_mode
	focus.visible = _focus_mode
	$Center/OverviewButton.button_pressed = not _focus_mode
	$Center/FocusButton.button_pressed = _focus_mode
	for i: int in KEYS.size():
		_overview_actors[i].set_animation_paused(_focus_mode or _paused)
		_focus_actors[i].visible = i == _asset
		_samples[i].visible = i == _asset
		_focus_actors[i].set_animation_paused(not _focus_mode or i != _asset or _paused)
		_samples[i].set_animation_paused(not _focus_mode or i != _asset or _paused)
	asset_select.select(_asset)
	_update_levels()


func _update_animation_choices() -> void:
	animation_select.clear()
	var clips: Array[StringName] = _focus_actors[_asset].available_animations()
	if not clips.has(_clip):
		_clip = &"walk_loop"
	for clip: StringName in clips:
		animation_select.add_item(LABELS.get(String(clip), String(clip)))
		animation_select.set_item_metadata(animation_select.item_count - 1, clip)
	animation_select.select(clips.find(_clip))
	note.text = NOTES.get(String(_clip), "")
	$Center/Focus/Title.text = TITLES[_asset] + " · " + str(_focus_actors[_asset].level)


func _play() -> void:
	replay_timer.stop()
	_events.clear()
	_prepare_context()
	for i: int in KEYS.size():
		var clip: StringName = _clip if _overview_actors[i].available_animations().has(_clip) else &"walk_loop"
		_overview_actors[i].play_animation(clip)
	_focus_actors[_asset].play_animation(_clip)
	_samples[_asset].play_animation(_clip)
	for list: Array[UndeadEnemyVisual] in [_overview_actors, _focus_actors, _samples]:
		for actor: UndeadEnemyVisual in list:
			actor.set_playback_speed(_speed)
	_update_views()


func _prepare_context() -> void:
	var peers: Node2D = focus.get_node("Peers")
	for child: Node in peers.get_children():
		if child is Node2D:
			(child as Node2D).visible = false
		if child is UndeadEnemyVisual:
			(child as UndeadEnemyVisual).set_animation_paused(true)
	if _focus_mode and _clip == &"heal":
		var buddy: UndeadEnemyVisual = peers.get_node("SkeletonA")
		buddy.position = Vector2(230, 20)
		buddy.visible = true
		buddy.play_animation(&"walk_loop")
		buddy.set_animation_paused(true)


func _on_effect(effect_name: StringName, asset_index: int) -> void:
	if not _focus_mode or asset_index != _asset:
		return
	_events[effect_name] = _events.get(effect_name, 0) + 1
	var peers: Node2D = focus.get_node("Peers")
	if effect_name in [&"summon_skeletons", &"retinue"]:
		var count: int = 3 if effect_name == &"retinue" else 2
		var positions: Array[Vector2] = []
		positions.assign([Vector2(-170,20),Vector2(165,20),Vector2(260,15)] if count == 3 else [Vector2(180,20),Vector2(260,15)])
		for i: int in count:
			var buddy: UndeadEnemyVisual = peers.get_node(["SkeletonA","SkeletonB","SkeletonC"][i])
			buddy.position = positions[i]
			buddy.visible = true
			buddy.set_level(1)
			buddy.play_animation(&"spawn_or_intro")
			buddy.set_playback_speed(_speed)
	elif effect_name == &"flesh_arrives":
		var buddy: UndeadEnemyVisual = peers.get_node("Flesh")
		buddy.visible = true
		buddy.set_level(5 if _level >= 5 else 4)
		buddy.play_animation(&"spawn_or_intro")
		buddy.set_playback_speed(_speed)


func select_asset(index: int) -> void:
	_auto = false
	auto_button.button_pressed = false
	auto_timer.stop()
	_asset = clampi(index, 0, KEYS.size()-1)
	_focus_mode = true
	_clip = &"walk_loop"
	if _asset == 4:
		_level = maxi(_level, 4)
	_update_views()
	_update_animation_choices()
	_play()


func set_level(value: int) -> void:
	_level = clampi(value, 1, 5)
	_update_levels()
	_update_animation_choices()
	_play()


func set_clip(value: StringName) -> void:
	_auto = false
	auto_button.button_pressed = false
	auto_timer.stop()
	_clip = value
	_update_animation_choices()
	_play()


func _on_asset_selected(index: int) -> void:
	select_asset(index)


func _on_animation_selected(index: int) -> void:
	set_clip(StringName(animation_select.get_item_metadata(index)))


func show_overview() -> void:
	_focus_mode = false
	_clip = &"walk_loop"
	_auto = false
	auto_timer.stop()
	auto_button.button_pressed = false
	_update_animation_choices()
	_play()


func show_focus() -> void:
	_focus_mode = true
	_update_views()
	_update_animation_choices()
	_play()


func replay() -> void:
	_play()


func toggle_pause() -> void:
	_paused = not _paused
	pause_button.text = "Продолжить" if _paused else "Пауза"
	replay_timer.paused = _paused
	auto_timer.paused = _paused
	_update_views()
	for child: Node in focus.get_node("Peers").get_children():
		if child is UndeadEnemyVisual:
			(child as UndeadEnemyVisual).set_animation_paused(_paused or not (child as UndeadEnemyVisual).visible)


func set_speed(value: float) -> void:
	_speed = value
	for list: Array[UndeadEnemyVisual] in [_overview_actors, _focus_actors, _samples]:
		for actor: UndeadEnemyVisual in list:
			actor.set_playback_speed(value)
	for child: Node in focus.get_node("Peers").get_children():
		if child is UndeadEnemyVisual:
			(child as UndeadEnemyVisual).set_playback_speed(value)
	for i: int in 3:
		(get_node("Center/Controls/Speed%d" % i) as Button).button_pressed = is_equal_approx(value, [0.5,1.0,2.0][i])


func _on_finished(_clip_name: StringName, index: int) -> void:
	if index == _asset and not _auto and repeat_toggle.button_pressed:
		replay_timer.start(0.65 / _speed)


func toggle_auto() -> void:
	_auto = not _auto
	auto_button.button_pressed = _auto
	_auto_clip = 0
	if _auto:
		_focus_mode = true
		_level = 5
		_auto_step()
	else:
		auto_timer.stop()


func _auto_step() -> void:
	if not _auto:
		return
	_update_levels()
	var clips: Array[StringName] = _focus_actors[_asset].available_animations()
	if _auto_clip >= clips.size():
		_auto_clip = 0
		_asset = (_asset + 1) % KEYS.size()
		clips = _focus_actors[_asset].available_animations()
	_clip = clips[_auto_clip]
	_auto_clip += 1
	_update_animation_choices()
	_play()
	var length: float = _focus_actors[_asset].animation_player.get_animation(_clip).length
	auto_timer.start((maxf(2.2, length) if _clip == &"walk_loop" else length + 0.8) / _speed)


func _web_command(args: Array) -> void:
	var command: String = str(args[0]) if not args.is_empty() else "snapshot"
	var value: Variant = args[1] if args.size() > 1 else null
	match command:
		"asset": select_asset(int(value))
		"level": set_level(int(value))
		"animation": set_clip(StringName(value))
		"replay": replay()
		"pause": toggle_pause()
		"speed": set_speed(float(value))
		"overview": show_overview()
		"focus": show_focus()
		"auto": toggle_auto()
		"repeat": repeat_toggle.button_pressed = bool(value)
	JavaScriptBridge.get_interface("window").graveyardAnimationJSON = JSON.stringify(snapshot())


func snapshot() -> Dictionary:
	var actor: UndeadEnemyVisual = _focus_actors[_asset]
	var particles: int = 0
	for node: Node in find_children("*", "CPUParticles2D", true, false):
		if (node as CPUParticles2D).is_visible_in_tree() and (node as CPUParticles2D).emitting:
			particles += (node as CPUParticles2D).amount
	var head: Bone2D = actor.get_node("Skeleton2D/Root/Body/Head")
	return {"entity":String(KEYS[_asset]),"level":actor.level,"clip":String(_clip),"available":actor.available_animations(),"focus":_focus_mode,"paused":_paused,"speed":_speed,"auto":_auto,"bones":actor.get_node("Skeleton2D").get_bone_count(),"effects":actor.effects.get_child_count(),"particle_budget":particles,"fps":Engine.get_frames_per_second(),"time":actor.animation_player.current_animation_position,"head_rotation":head.rotation,"events":_events,"alpha":actor.get_node("Skeleton2D/Root").modulate.a}


func _exit_tree() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").graveyardAnimation = null
