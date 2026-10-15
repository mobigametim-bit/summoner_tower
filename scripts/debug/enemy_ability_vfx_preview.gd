extends Node2D

const TYPES: Array[String] = ["goblin", "orc", "golem", "boss", "boss", "boss"]
const LEVELS: Array[int] = [5, 5, 5, 3, 4, 5]
const TITLES: Array[String] = ["1. Гоблин · Рывок", "2. Орк · Ярость", "3. Голем · Каменный панцирь", "4. Босс Lv3 · Тёмный щит", "5. Босс Lv4 · Призыв свиты", "6. Босс Lv5 · Последний натиск"]
const DESCRIPTIONS: Array[String] = [
	"Сбор светлой энергии · поток воздушных частиц и искр.",
	"Всплеск красных искр · поднимающиеся частицы ярости.",
	"Фиолетовые значки над HP · размер +20% · исчезают по одному.",
	"Щит вокруг всего босса · вихрь искр и электрические дуги.",
	"Белая вспышка · лучи призыва · появление двух орков Lv2.",
	"Сбор энергии · плотный поток огненных частиц и золотых искр."]
const LARGE_SCALE: float = 2.6
const FIELD_SCALE: float = (90.0 - 12.0) / 140.0

@onready var large: Node2D = $Stage/Large
@onready var small: Node2D = $Stage/Small
@onready var title: Label = $Interface/Content/Title
@onready var description: Label = $Interface/Content/Description
@onready var phase_label: Label = $Interface/Content/Phase
@onready var pause_button: Button = $Interface/Content/Playback/Pause
@onready var selection: GridContainer = $Interface/Content/Selection

var selected: int = 0
var _elapsed: float = 0.0
var _event_index: int = 0
var _actors: Array[ApproachingEnemy] = []
var _retinue: Array[ApproachingEnemy] = []
var _paused: bool = false
var _speed: float = 1.0
var _snapshot_callback: JavaScriptObject
var _command_callback: JavaScriptObject


func _ready() -> void:
	if OS.has_feature("web"):
		selected = clampi(int(JavaScriptBridge.eval("Number(new URL(location.href).searchParams.get('effect')) || 1", true)) - 1, 0, 5)
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		_command_callback = JavaScriptBridge.create_callback(_web_command)
		JavaScriptBridge.get_interface("window").getEnemyVfxPreview = _snapshot_callback
		JavaScriptBridge.get_interface("window").enemyVfxPreviewCommand = _command_callback
	_restart()


func _restart() -> void:
	for actor: ApproachingEnemy in _actors + _retinue:
		if is_instance_valid(actor):
			actor.stop()
			actor.queue_free()
	_actors.clear()
	_retinue.clear()
	for holder: Node2D in [large, small]:
		for child: Node in holder.get_children():
			if not child.is_queued_for_deletion():
				child.queue_free()
	_elapsed = 0.0
	_event_index = 0
	large.scale = Vector2.ONE * (1.8 if selected == 4 else LARGE_SCALE)
	large.position.y = 610.0 if selected == 2 else 570.0
	for holder: Node2D in [large, small]:
		var enemy: ApproachingEnemy = _make_enemy(TYPES[selected], LEVELS[selected], holder)
		enemy.retinue_requested.connect(_on_retinue_requested)
		_actors.append(enemy)
		if selected == 3 and holder == large:
			var radius: Vector2 = enemy.abilities.effects.get("shield_radius")
			large.scale = Vector2.ONE * minf(LARGE_SCALE, 190.0 / radius.x)
		if selected == 0:
			# Укорочено только ожидание в стенде, длительность самой способности исходная.
			enemy.abilities._dash_clock = 0.8
	title.text = TITLES[selected]
	description.text = DESCRIPTIONS[selected]
	phase_label.text = "До срабатывания"
	for index: int in selection.get_child_count():
		(selection.get_child(index) as Button).modulate = Color("97e5ec") if index == selected else Color.WHITE
	Engine.time_scale = _speed
	get_tree().paused = _paused


func _make_enemy(kind: String, tier: int, holder: Node2D) -> ApproachingEnemy:
	var path: String = "res://scenes/%s.tscn" % ("enemy" if kind == "goblin" else kind)
	var enemy: ApproachingEnemy = load(path).instantiate() as ApproachingEnemy
	holder.add_child(enemy)
	enemy.configure(holder.global_position, 100000.0, enemy.stats.base_health * (1 << (tier - 1)), tier)
	enemy.set_physics_process(false)
	enemy.health_bar.hide()
	enemy._animated_visual.play_animation(&"walk_loop")
	enemy.health_bar.visible = kind == "golem"
	return enemy


func _process(delta: float) -> void:
	_elapsed += delta
	for actor: ApproachingEnemy in _actors + _retinue:
		if is_instance_valid(actor):
			actor.abilities.advance(delta)
			actor._animated_visual.advance_gameplay(delta, INF, Vector2.ZERO)
	if _elapsed >= 6.5:
		_restart()
		return
	match selected:
		0:
			if _elapsed >= 0.8:
				phase_label.text = "Сбор частиц · 0,3 с" if _elapsed < 1.1 else ("Воздушный рывок · 0,8 с" if _elapsed < 1.9 else "После рывка")
		1:
			if _elapsed >= 0.8 and _event_index == 0:
				_event_index = 1
				for actor: ApproachingEnemy in _actors:
					actor.take_damage(actor.max_health * 0.5)
				phase_label.text = "Ярость: красные искры и частицы"
		2:
			var hit_times: Array[float] = [1.0, 2.2, 3.4]
			if _event_index < hit_times.size() and _elapsed >= hit_times[_event_index]:
				_event_index += 1
				for actor: ApproachingEnemy in _actors:
					actor.take_damage(40.0)
				phase_label.text = "Осталось пластин: %d" % (3 - _event_index)
		3:
			if _elapsed >= 0.8 and _event_index == 0:
				_event_index = 1
				for actor: ApproachingEnemy in _actors:
					actor.take_damage(actor.max_health * 0.5)
				phase_label.text = "Щит появился"
			elif _elapsed >= 2.2 and _event_index == 1:
				_event_index = 2
				for actor: ApproachingEnemy in _actors:
					actor.take_damage(actor.abilities.shield_health * 0.5)
				phase_label.text = "Щит поглотил попадание · осталось 50%"
			elif _elapsed >= 3.5 and _event_index == 2:
				_event_index = 3
				for actor: ApproachingEnemy in _actors:
					actor.take_damage(actor.abilities.shield_health)
				phase_label.text = "Щит разрушен"
		4, 5:
			if _elapsed >= 0.8 and _event_index == 0:
				_event_index = 1
				for actor: ApproachingEnemy in _actors:
					# Отдельный показ настоящей способности без перекрывающих её эффектов.
					actor.abilities._queue.append(&"summon" if selected == 4 else &"rush")
					actor.abilities._start_next()
				phase_label.text = "Подготовка призыва" if selected == 4 else "Сбор энергии · 0,35 с"
			if _elapsed >= (1.4 if selected == 4 else 1.15):
				phase_label.text = "Свита появилась · два орка Lv2" if selected == 4 else "Натиск: огненный поток и искры"


func _on_retinue_requested(caster: ApproachingEnemy) -> void:
	var holder: Node2D = caster.get_parent() as Node2D
	for side: int in [-1, 1]:
		var enemy: ApproachingEnemy = _make_enemy("orc", 2, holder)
		# Только раскладка стенда: раздельно показываем вспышки двух прибывших орков.
		enemy.position = Vector2(float(side) * 48.0, 58.0)
		enemy.show_retinue_arrival()
		_retinue.append(enemy)


func _on_select(index: int) -> void:
	selected = clampi(index, 0, 5)
	_restart()


func _on_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	pause_button.icon = load("res://assets/debug/animation_controls/play.svg" if _paused else "res://assets/debug/animation_controls/pause.svg")


func _on_speed(multiplier: float) -> void:
	_speed = multiplier
	Engine.time_scale = multiplier
	for button: Button in $Interface/Content/Playback.get_children():
		if button.name in [&"Half", &"Normal", &"Double"]:
			button.modulate = Color("97e5ec") if button.text == ("0.5×" if multiplier == 0.5 else ("1×" if multiplier == 1.0 else "2×")) else Color.WHITE


func _web_command(arguments: Array) -> void:
	if arguments.is_empty():
		return
	match str(arguments[0]):
		"select": _on_select(int(arguments[1]))
		"replay": _restart()
		"pause": _on_pause()
		"speed": _on_speed(float(arguments[1]))


func _publish_snapshot(_arguments: Array) -> void:
	var actors: Array[Dictionary] = []
	for actor: ApproachingEnemy in _actors:
		var fx: EnemyAbilityVisual = actor.abilities.effects
		actors.append({"type":str(actor.stats.enemy_type), "tier":actor.difficulty_tier,
			"armor":actor.abilities.armor_remaining, "shield":actor.abilities.shield_health,
			"rage":actor.abilities.raging, "rush":actor.abilities.rushing,
			"dash":actor.abilities._dash_remaining, "scale":actor.global_scale.x,
			"particles":fx.aura_particles.emitting,
			"shield_particles":fx.get_node("ShieldSparks").emitting,
			"lightning":fx.get_node("ShieldBolts").emitting,
			"armor_y":fx.get("armor_y"), "hp_top":actor.health_bar.position.y,
			"fx_script":fx.get_script().resource_path})
	JavaScriptBridge.eval("window.enemyVfxPreview = %s" % JSON.stringify({"effect":selected + 1,
		"elapsed":_elapsed, "phase":phase_label.text, "actors":actors,
		"retinue":_retinue.size(), "paused":_paused, "speed":_speed,
		"nodes":get_tree().get_node_count()}), true)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	if _snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getEnemyVfxPreview = null
		JavaScriptBridge.get_interface("window").enemyVfxPreviewCommand = null
