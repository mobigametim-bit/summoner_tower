extends Control

const RATE: Array[float] = [1.0, 1.1, 1.2, 1.3, 1.4]
const RANGE: Array[float] = [1.0, 1.2, 1.4, 1.6, 1.8]
const BASE_RANGE: Array[float] = [150.0, 130.0, 140.0]
const BASE_INTERVAL: Array[float] = [0.5, 1.0, 0.6666666667]
const SHOT: PackedScene = preload("res://scenes/debug/progression/PreviewShot.tscn")
const AREA: PackedScene = preload("res://scenes/debug/progression/PreviewArea.tscn")
const EMBEDDED: PackedScene = preload("res://scenes/vfx/EmbeddedArrow.tscn")
const TEXTURES: Array[Texture2D] = [preload("res://assets/arrow.svg"), preload("res://assets/fireball.svg"), preload("res://assets/frost_bolt.svg")]
const COLORS: Array[Color] = ArcherVisual.CLOTH_COLORS
const NAMES: Array[String] = ["Лучник", "Огненный маг", "Ледяной маг"]
const DESCRIPTIONS: Array = [
	["Одна стрела", "Одна стрела · усиленные характеристики", "Две стрелы · промежуток 0,1 с", "Усиленная серия из двух стрел", "Две стрелы + шквальный выстрел каждые 3 с"],
	["Огненный снаряд", "Огненный снаряд + горение", "Взрыв по группе + горение", "Усиленный взрыв + горение", "Взрыв + метеор каждые 3 с"],
	["Ледяной снаряд + замедление", "Усиленное замедление", "Ледяной всплеск по группе", "Усиленный ледяной всплеск", "Всплеск + ледяная волна каждые 3 с"]
]

@onready var stage: Control = $Margin/Content/Stage
@onready var world: Node2D = $Margin/Content/Stage/World
@onready var effects: Node2D = $Margin/Content/Stage/World/Effects
@onready var shots: Node2D = $Margin/Content/Stage/World/Shots
@onready var range_preview: AttackRangePreview = $Margin/Content/Stage/World/Range
@onready var title: Label = $Margin/Content/Title
@onready var details: Label = $Margin/Content/Details
@onready var stats_label: Label = $Margin/Content/Stats
@onready var auto_button: Button = $Margin/Content/Actions/Auto
@onready var skill_button: Button = $Margin/Content/Actions/Skill
@onready var heroes: Array[Node2D] = [$Margin/Content/Stage/World/Archer, $Margin/Content/Stage/World/Mage, $Margin/Content/Stage/World/Frost]
@onready var enemies: Array[Node2D] = [$Margin/Content/Stage/World/Enemy1, $Margin/Content/Stage/World/Enemy2, $Margin/Content/Stage/World/Enemy3]
@onready var burns: Array[CPUParticles2D] = [$Margin/Content/Stage/World/Burn1, $Margin/Content/Stage/World/Burn2, $Margin/Content/Stage/World/Burn3]
@onready var burn_front: Array[CPUParticles2D] = [$Margin/Content/Stage/World/BurnFront1, $Margin/Content/Stage/World/BurnFront2, $Margin/Content/Stage/World/BurnFront3]
@onready var ice: Array[Node2D] = [$Margin/Content/Stage/World/Ice1, $Margin/Content/Stage/World/Ice2, $Margin/Content/Stage/World/Ice3]

var unit_kind: int = 0
var level: int = 1
var auto_play: bool = true
var attacks: int = 0
var hits: int = 0
var abilities: int = 0
var _cooldown: float = 0.4
var _skill_cooldown: float = 3.0
var _pending: bool = false
var _skill_pending: bool = false
var _jobs: Array[Dictionary] = []
var _burn_time: Array[float] = [0.0, 0.0, 0.0]
var _frost_time: Array[float] = [0.0, 0.0, 0.0]
var _freeze_time: Array[float] = [0.0, 0.0, 0.0]
var _zoom: float = 1.0
var _slow: bool = false
var _snapshot_callback: JavaScriptObject


func _ready() -> void:
	for hero: Node2D in heroes:
		hero.connect("release", _on_release)
	for enemy: Node2D in enemies:
		enemy.call("set_animation_paused", true)
	stage.resized.connect(_layout)
	select_unit(0)
	if OS.has_feature("web"):
		_snapshot_callback = JavaScriptBridge.create_callback(_publish_snapshot)
		JavaScriptBridge.get_interface("window").getUnitProgressionPreview = _snapshot_callback


func _layout() -> void:
	world.scale = Vector2.ONE * _zoom
	world.position = stage.size * 0.5 - Vector2(275.0, 335.0) * _zoom


func select_unit(kind: int) -> void:
	unit_kind = clampi(kind, 0, 2)
	_reset()


func select_level(value: int) -> void:
	level = clampi(value, 1, 5)
	_reset()


func _reset() -> void:
	_jobs.clear()
	_pending = false
	_skill_pending = false
	_cooldown = 0.4
	_skill_cooldown = 3.0
	attacks = 0
	hits = 0
	abilities = 0
	for container: Node2D in [shots, effects]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()
	for index: int in range(3):
		heroes[index].visible = index == unit_kind
		heroes[index].call("set_level", level)
		heroes[index].call("play_animation", &"idle_loop")
		heroes[index].call("set_playback_speed", 1.0)
		_burn_time[index] = 0.0
		_frost_time[index] = 0.0
		_freeze_time[index] = 0.0
		burns[index].emitting = false
		burns[index].hide()
		burn_front[index].emitting = false
		burn_front[index].hide()
		ice[index].hide()
		enemies[index].modulate = Color.WHITE
		for arrow: Node in enemies[index].get_children():
			if arrow.get_meta("preview_arrow", false):
				enemies[index].remove_child(arrow)
				arrow.queue_free()
	range_preview.configure(BASE_RANGE[unit_kind] * RANGE[level - 1], COLORS[level - 1])
	title.text = "%s · %d" % [NAMES[unit_kind], level]
	title.modulate = COLORS[level - 1]
	details.text = DESCRIPTIONS[unit_kind][level - 1]
	stats_label.text = "Радиус %s · %.2f атак/с" % [str(range_preview.radius), RATE[level - 1] / BASE_INTERVAL[unit_kind]]
	skill_button.disabled = level != 5
	for value: int in range(1, 6):
		$Margin/Content/Levels.get_node("Level%d" % value).modulate = COLORS[value - 1] if value == level else Color.WHITE
	_layout()


func _process(delta: float) -> void:
	for index: int in range(3):
		_burn_time[index] = maxf(0.0, _burn_time[index] - delta)
		_frost_time[index] = maxf(0.0, _frost_time[index] - delta)
		_freeze_time[index] = maxf(0.0, _freeze_time[index] - delta)
		burns[index].emitting = _burn_time[index] > 0.0
		burns[index].visible = _burn_time[index] > 0.0
		burn_front[index].emitting = _burn_time[index] > 0.0
		burn_front[index].visible = _burn_time[index] > 0.0
		enemies[index].modulate = Color("8ddafa") if _frost_time[index] > 0.0 else Color.WHITE
		# Обычное попадание не снимает глыбу до окончания отдельного таймера заморозки.
		ice[index].visible = _freeze_time[index] > 0.0
	for index: int in range(_jobs.size() - 1, -1, -1):
		_jobs[index].time -= delta
		if _jobs[index].time <= 0.0:
			var job: Dictionary = _jobs[index]
			_jobs.remove_at(index)
			_fire(job.target, job.special, job.meteor)
	if not auto_play:
		return
	_cooldown -= delta
	_skill_cooldown -= delta
	if level == 5 and _skill_cooldown <= 0.0:
		_skill_pending = true
	if _cooldown <= 0.0 and not _pending:
		replay()


func replay() -> void:
	if _pending:
		return
	_pending = true
	attacks += 1
	_cooldown = BASE_INTERVAL[unit_kind] / RATE[level - 1]
	heroes[unit_kind].call("play_animation", &"attack" if unit_kind == 0 else &"cast")
	var length: float = 0.52 if unit_kind == 0 else 0.42
	heroes[unit_kind].call("set_playback_speed", maxf(1.0, length / _cooldown))


func _on_release() -> void:
	if not _pending:
		return
	_pending = false
	_fire(0)
	if unit_kind == 0 and level >= 3:
		_jobs.append({"time": 0.1, "target": 0, "special": false, "meteor": false})
	if _skill_pending and level == 5:
		_skill_pending = false
		_skill_cooldown = 3.0
		abilities += 1
		if unit_kind == 0:
			var area: Node2D = AREA.instantiate()
			effects.add_child(area)
			area.position = enemies[0].position
			area.call("configure", 0, 70.0)
			for index: int in range(6):
				_jobs.append({"time": 0.07 * index, "target": index % 3, "special": true, "meteor": false})
		elif unit_kind == 1:
			var shot: Node2D = SHOT.instantiate()
			shots.add_child(shot)
			shot.connect("landed", _impact)
			shot.call("launch", TEXTURES[1], enemies[0].position + Vector2(-55.0, -210.0), enemies[0].position, 0, true, true)
		else:
			_impact(0, true)


func _fire(target: int, special: bool = false, meteor: bool = false) -> void:
	var shot: Node2D = SHOT.instantiate()
	shots.add_child(shot)
	var muzzle: Marker2D = heroes[unit_kind].get("release_point") as Marker2D
	shot.connect("landed", _impact)
	shot.call("launch", TEXTURES[unit_kind], world.to_local(muzzle.global_position), enemies[target].position, target, special, meteor, unit_kind == 0 and level >= 2)


func _impact(target: int, special: bool = false) -> void:
	hits += 1
	if unit_kind == 0:
		var count: int = 0
		for node: Node in enemies[target].get_children():
			if node.get_meta("preview_arrow", false):
				count += 1
		if count < 8:
			var arrow: Node2D = EMBEDDED.instantiate()
			arrow.set_meta("preview_arrow", true)
			enemies[target].add_child(arrow)
			arrow.position = Vector2(-12.0 + count * 3.0, -4.0 + (count % 3) * 7.0) / enemies[target].scale
			arrow.scale = Vector2.ONE / enemies[target].scale
			arrow.rotation = -0.25 if special else 0.1
		return
	var radius: float = (48.0 if level == 3 else 60.0) if level >= 3 else 18.0
	if special:
		radius = 85.0
	var effect: Node2D = AREA.instantiate()
	effects.add_child(effect)
	effect.position = enemies[target].position
	effect.call("configure", unit_kind, radius)
	for index: int in range(3):
		if enemies[index].position.distance_to(enemies[target].position) <= radius:
			if unit_kind == 1 and level >= 2:
				# Заполненное пламя появляется сразу; обновление горения не сбрасывает частицы.
				if _burn_time[index] <= 0.0:
					burns[index].restart()
					burn_front[index].restart()
				_burn_time[index] = 1.5
			elif unit_kind == 2:
				_frost_time[index] = 0.65 if special else 0.18
				if special:
					_freeze_time[index] = 0.65


func _on_skill() -> void:
	if level == 5:
		_skill_pending = true
		replay()


func _on_auto() -> void:
	auto_play = not auto_play
	auto_button.text = "Авто: вкл." if auto_play else "Авто: выкл."


func _on_zoom() -> void:
	_zoom = 2.0 if _zoom == 1.0 else 1.0
	$Margin/Content/View/Zoom.text = "Масштаб ×%.0f" % _zoom
	_layout()


func _on_speed() -> void:
	_slow = not _slow
	Engine.time_scale = 0.5 if _slow else 1.0
	$Margin/Content/View/Speed.text = "Скорость ×0,5" if _slow else "Скорость ×1"


func _publish_snapshot(_arguments: Array) -> void:
	var controls: Dictionary = {}
	for node: Node in find_children("*", "Button", true, false):
		var button: Button = node as Button
		var center: Vector2 = button.get_global_rect().get_center()
		controls[button.name] = [center.x, center.y]
	var state: Dictionary = {"kind": unit_kind, "level": level, "radius": range_preview.radius,
		"attacks": attacks, "hits": hits, "abilities": abilities, "auto": auto_play,
		"shots": shots.get_child_count(), "effects": effects.get_child_count(),
		"burning": burns[0].emitting, "frozen": ice[0].visible,
		"burn_remaining": _burn_time.duplicate(), "burn_front_visible": burn_front[0].visible,
		"burn_particle_counts": [burns[0].amount, burn_front[0].amount],
		"burn_alpha": [burns[0].modulate.a, burn_front[0].modulate.a],
		"freeze_remaining": _freeze_time.duplicate(), "ice_alpha": ice[0].modulate.a,
		"nodes": get_tree().get_node_count(), "controls": controls}
	JavaScriptBridge.eval("window.unitProgressionPreview = %s;" % JSON.stringify(state), true)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if _snapshot_callback != null:
		JavaScriptBridge.get_interface("window").getUnitProgressionPreview = null
		JavaScriptBridge.get_interface("window").unitProgressionPreview = null
