extends Control

const MODES: Array[StringName] = [&"idle_loop",&"cast",&"spawn",&"shot",&"mark",&"consecration"]
const NAMES: Array[String] = ["Покой","Выстрел","Появление","Снаряд света","Метка света","Освящение"]
const NOTES: Array[String] = ["Спокойное дыхание, движение головы, книги и посоха.","Движение рук и вспышка навершия. Отдельный просмотр анимации выстрела.","Белые лучи призыва и проявление на постаменте.","Крупный сгусток света: размер ×2, выраженный след и искры попадания.","Большое солнечное клеймо с ореолом и нисходящими лучами. Действует 3 с.","Солнечная печать, лучи и вспышка частиц. Метки на врагах в области."]
@export var shot_scene: PackedScene
@export var impact_scene: PackedScene
@export var mark_scene: PackedScene
@export var consecration_scene: PackedScene
@onready var hero: PriestVisual = $Center/Stage/Hero
@onready var sample: PriestVisual = $Center/Stage/Sample
@onready var effects: Node2D = $Center/Stage/Effects
@onready var replay_timer: Timer = $ReplayTimer
var _actors: Array[PriestVisual] = []
var _mode: int = 0
var _level: int = 5
var _speed: float = 1.0
var _paused: bool = false
var _mirror: bool = false
var _generation: int = 0
var _releases: int = 0
var _hits: int = 0
var _callback: JavaScriptObject
var _tweens: Array[Tween] = []
var _readout_clock: float = 0.0


func _ready() -> void:
	_actors.assign([hero,sample])
	for i: int in 5:
		_actors.append(get_node("Center/Stage/Levels/Level%d"%(i+1)) as PriestVisual)
	hero.release.connect(_on_release.bind(hero,$Center/Stage/Target,1.4))
	sample.release.connect(_on_release.bind(sample,$Center/Stage/RealTarget,1.0))
	for path: String in ["Center/Stage/Target/Actor","Center/Stage/RealTarget/Actor","Center/Stage/Target/PeerA","Center/Stage/Target/PeerB"]:
		var actor: UndeadEnemyVisual = get_node(path) as UndeadEnemyVisual
		actor.set_level(3)
		actor.set_animation_paused(true)
	if OS.has_feature("web"):
		_callback = JavaScriptBridge.create_callback(_web_command)
		JavaScriptBridge.get_interface("window").priestAnimation = _callback
		var requested: StringName = StringName(str(JavaScriptBridge.eval("new URL(location.href).searchParams.get('mode') || ''")))
		set_mode(maxi(MODES.find(requested),0))
	else:
		set_mode(0)


func set_mode(index: int) -> void:
	_mode = clampi(index,0,MODES.size()-1)
	if _mode == 4 and _level < 3:
		_level = 3
	if _mode == 5:
		_level = 5
	$Center/Mode.select(_mode)
	_update()
	replay()


func set_level(value: int) -> void:
	_level = clampi(value,1,5)
	if (_mode == 4 and _level < 3) or (_mode == 5 and _level < 5):
		_mode = 1
		$Center/Mode.select(_mode)
	_update()
	replay()


func _update() -> void:
	hero.set_level(_level)
	sample.set_level(_level)
	$Center/Description.text = NOTES[_mode]
	$Center/Stage/Target/PeerA.visible = _mode == 5
	$Center/Stage/Target/PeerB.visible = _mode == 5
	for i: int in 5:
		(get_node("Center/Level%d"%(i+1)) as Button).set_pressed_no_signal(i+1 == _level)


func replay() -> void:
	_generation += 1
	for tween: Tween in _tweens:
		if tween.is_valid():
			tween.kill()
	_tweens.clear()
	for child: Node in effects.get_children():
		child.queue_free()
	var clip: StringName = MODES[_mode] if _mode < 3 else &"cast"
	for actor: PriestVisual in _actors:
		var rays: CPUParticles2D = actor.get_node("SummonRays") as CPUParticles2D
		rays.emitting = false
		rays.visible = clip == &"spawn"
		actor.play_animation(clip)
		if clip == &"spawn":
			rays.restart()
			rays.emitting = true
	replay_timer.start(4.1 if _mode in [4,5] else (1.7 if _mode == 2 else 1.4))


func _on_release(actor: PriestVisual, target: Node2D, effect_scale: float) -> void:
	_releases += 1
	if _mode == 4:
		_mark_target(target,effect_scale)
		return
	if _mode not in [3,5]:
		return
	var shot: Node2D = shot_scene.instantiate() as Node2D
	effects.add_child(shot)
	shot.global_position = actor.release_point.global_position
	shot.scale = Vector2.ONE*effect_scale
	var goal: Vector2 = target.global_position
	var tween: Tween = create_tween()
	_tweens.append(tween)
	tween.tween_property(shot,"global_position",goal,0.38)
	tween.tween_callback(_arrive.bind(shot,target,effect_scale,_generation))


func _arrive(shot: Node2D, target: Node2D, effect_scale: float, generation: int) -> void:
	if is_instance_valid(shot):
		shot.queue_free()
	if generation != _generation or not is_instance_valid(target):
		return
	_hits += 1
	_effect(consecration_scene if _mode == 5 else impact_scene,target.global_position,effect_scale)
	if _mode == 5:
		_mark_target(target,effect_scale)
		if effect_scale > 1.0:
			for x: float in [-92.0,92.0]:
				_mark(target.global_position+Vector2(x,-70),0.65)


func _mark_target(target: Node2D, effect_scale: float) -> void:
	_mark(target.global_position+Vector2(0,-140 if effect_scale > 1.0 else -88),1.0 if effect_scale > 1.0 else 0.65)


func _effect(packed: PackedScene, point: Vector2, size_factor: float) -> void:
	var effect: Node2D = packed.instantiate() as Node2D
	effects.add_child(effect)
	effect.global_position = point
	effect.scale = Vector2.ONE*size_factor
	effect.call("start",1.0)


func _mark(point: Vector2, size_factor: float) -> void:
	_effect(mark_scene,point,size_factor)


func toggle_pause() -> void:
	_paused = not _paused
	Engine.time_scale = 0.0 if _paused else _speed
	$Center/Pause.icon = load("res://assets/debug/priest/play.svg" if _paused else "res://assets/debug/priest/pause.svg")


func set_speed(value: float) -> void:
	_speed = clampf(value,0.5,2.0)
	Engine.time_scale = 0.0 if _paused else _speed
	for i: int in 3:
		(get_node("Center/Speed%d"%i) as Button).set_pressed_no_signal(is_equal_approx(_speed,[0.5,1.0,2.0][i]))


func toggle_mirror() -> void:
	_mirror = not _mirror
	for actor: PriestVisual in _actors:
		actor.scale.x = absf(actor.scale.x)*(-1.0 if _mirror else 1.0)
	$Center/Mirror.set_pressed_no_signal(_mirror)


func _process(delta: float) -> void:
	_readout_clock += delta
	if _readout_clock >= 0.2:
		_readout_clock = 0.0
		$Center/Readout.text = "Lv%d · %s · %.1f× · release %d · %d FPS"%[_level,NAMES[_mode],_speed,_releases,Engine.get_frames_per_second()]


func snapshot() -> Dictionary:
	var types: Array[String] = []
	for effect: Node in effects.get_children():
		if not effect.is_queued_for_deletion():
			types.append(effect.scene_file_path.get_file().get_basename())
	return {"mode":str(MODES[_mode]),"level":_level,"speed":_speed,"paused":_paused,"mirror":_mirror,"releases":_releases,"hits":_hits,"effects":effects.get_child_count(),"effect_types":types,"bones":hero.get_node("Skeleton2D").get_bone_count(),"clip":str(hero._active_animation),"position":hero.animation_player.current_animation_position,"fps":Engine.get_frames_per_second()}


func _web_command(args: Array) -> void:
	var action: String = str(args[0]) if not args.is_empty() else "snapshot"
	var value: Variant = args[1] if args.size() > 1 else null
	match action:
		"mode": set_mode(int(value))
		"level": set_level(int(value))
		"speed": set_speed(float(value))
		"pause": toggle_pause()
		"mirror": toggle_mirror()
		"replay": replay()
	JavaScriptBridge.get_interface("window").priestAnimationJSON = JSON.stringify(snapshot())


func _exit_tree() -> void:
	Engine.time_scale = 1.0
