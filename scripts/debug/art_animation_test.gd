extends Control

const ASSETS: Array[String] = ["Archer", "Goblin", "Mage", "FrostMage", "Orc", "Golem", "Boss", "Tower"]
const ARCHER_ANIMATIONS: Array[StringName] = [&"idle_loop", &"attack", &"spawn"]
const GOBLIN_ANIMATIONS: Array[StringName] = [&"walk_loop", &"attack", &"hit", &"death"]
const BOSS_ANIMATIONS: Array[StringName] = [&"walk_loop", &"attack", &"hit", &"death", &"spawn_or_intro"]
const MAGE_ANIMATIONS: Array[StringName] = [&"idle_loop", &"cast", &"spawn"]
const TOWER_ANIMATIONS: Array[StringName] = [&"crystal_pulse", &"tap", &"refund", &"hit", &"destroyed"]
const PAUSE_ICON: Texture2D = preload("res://assets/debug/animation_controls/pause.svg")
const PLAY_ICON: Texture2D = preload("res://assets/debug/animation_controls/play.svg")

@export_range(0, 7) var initial_asset_index: int = 0
@export_range(1, 5) var initial_difficulty_tier: int = 1

@onready var content: VBoxContainer = $Margin/Content
@onready var stage: Control = $Margin/Content/Stage
@onready var preview_host: Node2D = $Margin/Content/Stage/PreviewHost
@onready var entity_label: Label = $Margin/Content/AssetRow/Entity
@onready var animation_label: Label = $Margin/Content/AnimationRow/AnimationName
@onready var event_label: Label = $Margin/Content/Event
@onready var pause_button: Button = $Margin/Content/Playback/Pause
@onready var repeat_button: CheckButton = $Margin/Content/Options/Repeat
@onready var mirror_button: CheckButton = $Margin/Content/Options/Mirror
@onready var scale_picker: OptionButton = $Margin/Content/Options/Scale
@onready var repeat_timer: Timer = $RepeatTimer
@onready var difficulty_row: HBoxContainer = $Margin/Content/DifficultyRow
@onready var difficulty_picker: OptionButton = $Margin/Content/DifficultyRow/Level

var _visuals: Array[Node2D] = []
var _asset_index: int = 0
var _animation_index: int = 0
var _speed: float = 1.0
var _paused: bool = false
var _release_count: int = 0
var _difficulty_tier: int = 1
var _web_snapshot_callback: JavaScriptObject


func _ready() -> void:
	_difficulty_tier = initial_difficulty_tier
	if OS.has_feature("web"):
		var parameters: Variant = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(Object.fromEntries(new URL(window.location.href).searchParams))", true)))
		if parameters is Dictionary:
			var indices: Dictionary = {"goblin": 1, "orc": 4, "golem": 5}
			initial_asset_index = int(indices.get(parameters.get("asset", ""), initial_asset_index))
			_difficulty_tier = clampi(int(parameters.get("tier", initial_difficulty_tier)), 1, 5)
		_web_snapshot_callback = JavaScriptBridge.create_callback(_publish_equipment_snapshot)
		JavaScriptBridge.get_interface("window").getEnemyEquipmentReview = _web_snapshot_callback
	difficulty_picker.select(_difficulty_tier - 1)
	_select_asset(initial_asset_index)
	_set_speed(1.0)


func _animations() -> Array[StringName]:
	if _is_tower():
		return TOWER_ANIMATIONS
	if _asset_index == 6:
		return BOSS_ANIMATIONS
	if _is_enemy():
		return GOBLIN_ANIMATIONS
	return MAGE_ANIMATIONS if _asset_index >= 2 else ARCHER_ANIMATIONS


func _is_enemy() -> bool:
	return _asset_index == 1 or (_asset_index >= 4 and _asset_index <= 6)


func _is_tower() -> bool:
	return _asset_index == 7


func _canvas_size() -> float:
	match _asset_index:
		1: return GoblinVisual.GAMEPLAY_CANVAS_SIZE
		4: return 120.0
		5: return 140.0
		6: return BossVisual.GAMEPLAY_CANVAS_SIZE
		7: return TowerVisual.CANVAS_SIZE
	return 100.0


func _select_asset(index: int) -> void:
	repeat_timer.stop()
	_asset_index = posmod(index, ASSETS.size())
	_animation_index = 0
	entity_label.text = "FROST MAGE" if _asset_index == 3 else ASSETS[_asset_index].to_upper()
	var note: Label = content.get_node("Note")
	note.text = "SVG cutout · 0 bones · AnimationPlayer\nPreview only · gameplay unchanged" if _is_tower() else "SVG cutout · Bone2D · AnimationPlayer\nPreview only · gameplay unchanged"
	_visuals.clear()
	_select_host(preview_host)
	scale_picker.set_item_text(0, "Large preview")
	for columns: int in [6, 7, 8]:
		var cell: Control = content.get_node("Samples/Columns%d/Cell" % columns)
		var anchor: Node2D = cell.get_node("Anchor")
		var host: Node2D = anchor.get_node("UnitHost")
		var grid_size: float = 720.0 / float(columns)
		var cell_size: float = grid_size - 4.0
		var unit_scale: float = _sample_scale(columns)
		var ground: Sprite2D = anchor.get_node("Ground")
		ground.scale = Vector2.ONE * (cell_size + 4.0) / float(ground.texture.get_width())
		var pedestal: Sprite2D = anchor.get_node("Pedestal")
		pedestal.scale = Vector2.ONE * cell_size / 140.0
		pedestal.visible = not _is_enemy() and not _is_tower()
		var road: Sprite2D = anchor.get_node("Road")
		road.visible = _is_enemy() or _is_tower()
		road.scale = Vector2.ONE * grid_size / float(road.texture.get_width())
		host.position.y = 0.0 if _is_enemy() or _is_tower() else 26.0 * cell_size / 140.0 - 42.0 * unit_scale
		host.scale = Vector2.ONE * unit_scale
		_select_host(host)
		var canvas_size: float = _canvas_size()
		var size_label: Label = content.get_node("Samples/Columns%d/SizeLabel" % columns)
		size_label.text = "%d columns · %d px" % [columns, roundi(canvas_size * unit_scale)]
		scale_picker.set_item_text(columns - 5, "%d columns · %d px" % [columns, roundi(canvas_size * unit_scale)])
	_apply_difficulty()
	_layout_previews()
	replay()


func _apply_difficulty() -> void:
	var supported: bool = _asset_index in [1, 4, 5]
	difficulty_row.visible = supported
	if not supported:
		return
	var tier_color: Color = EnemyStats.TIER_COLORS[_difficulty_tier - 1]
	for visual: Node2D in _visuals:
		visual.call(&"set_difficulty", _difficulty_tier, tier_color)
	difficulty_picker.modulate = tier_color


func _on_difficulty_selected(index: int) -> void:
	_difficulty_tier = index + 1
	difficulty_picker.select(index)
	_apply_difficulty()


func _publish_equipment_snapshot(_arguments: Array) -> void:
	var parts: Array[Dictionary] = []
	if not _visuals.is_empty():
		for part: Node in _visuals[0].find_children("*", "Sprite2D", true, false):
			if part is EnemyEquipmentPart:
				parts.append({"path": String(_visuals[0].get_path_to(part)), "visible": part.visible, "texture": part.texture.resource_path})
	var snapshot: Dictionary = {
		"entity": ASSETS[_asset_index], "tier": _difficulty_tier,
		"animation": _animations()[_animation_index], "speed": _speed, "paused": _paused,
		"parts": parts, "fps": Engine.get_frames_per_second(), "impact_count": _release_count
	}
	JavaScriptBridge.get_interface("window").enemyEquipmentSnapshotJSON = JSON.stringify(snapshot)


func _select_host(host: Node2D) -> void:
	for index: int in ASSETS.size():
		var visual: Node2D = host.get_node(ASSETS[index] + "Visual")
		visual.visible = index == _asset_index
		visual.call(&"set_animation_paused", true)
		if visual.visible:
			_visuals.append(visual)


func _sample_scale(columns: int) -> float:
	var cell_size: float = 720.0 / float(columns)
	if _is_tower():
		return (cell_size - 4.0) / TowerVisual.CANVAS_SIZE
	return minf((cell_size - 12.0) / 140.0, 1.0) if _is_enemy() else minf((cell_size - 16.0) / 100.0, 1.0)


func _layout_previews() -> void:
	if not is_node_ready():
		return
	preview_host.position = stage.size * 0.5 + Vector2(0.0, 8.0)
	var large_scale: float = 1.25 if _is_tower() else 3.0
	var multiplier: float = large_scale if scale_picker.selected == 0 else _sample_scale(scale_picker.selected + 5)
	preview_host.scale = Vector2(-multiplier if mirror_button.button_pressed else multiplier, multiplier)
	for columns: int in [6, 7, 8]:
		var cell: Control = content.get_node("Samples/Columns%d/Cell" % columns)
		var anchor: Node2D = cell.get_node("Anchor")
		anchor.position = cell.size * 0.5
		var host: Node2D = anchor.get_node("UnitHost")
		host.scale.x = -absf(host.scale.x) if mirror_button.button_pressed else absf(host.scale.x)


func replay() -> void:
	repeat_timer.stop()
	_set_paused(false)
	_release_count = 0
	event_label.text = "Visual only" if _is_tower() else ("Impact: —" if _is_enemy() else "Release: —")
	var animation_name: StringName = _animations()[_animation_index]
	animation_label.text = String(animation_name)
	for visual: Node2D in _visuals:
		visual.call(&"set_playback_speed", _speed)
		visual.call(&"play_animation", animation_name)


func _on_previous_asset() -> void:
	_select_asset(_asset_index - 1)


func _on_next_asset() -> void:
	_select_asset(_asset_index + 1)


func _on_previous_animation() -> void:
	_animation_index = posmod(_animation_index - 1, _animations().size())
	replay()


func _on_next_animation() -> void:
	_animation_index = posmod(_animation_index + 1, _animations().size())
	replay()


func _on_pause() -> void:
	_set_paused(not _paused)


func _set_paused(paused: bool) -> void:
	_paused = paused
	pause_button.text = ""
	pause_button.tooltip_text = "Resume" if paused else "Pause"
	pause_button.icon = PLAY_ICON if paused else PAUSE_ICON
	repeat_timer.paused = paused
	for visual: Node2D in _visuals:
		visual.call(&"set_animation_paused", paused)


func _set_speed(multiplier: float) -> void:
	_speed = multiplier
	($Margin/Content/SpeedRow/Half as Button).set_pressed_no_signal(is_equal_approx(multiplier, 0.5))
	($Margin/Content/SpeedRow/Normal as Button).set_pressed_no_signal(is_equal_approx(multiplier, 1.0))
	($Margin/Content/SpeedRow/Double as Button).set_pressed_no_signal(is_equal_approx(multiplier, 2.0))
	for visual: Node2D in _visuals:
		visual.call(&"set_playback_speed", multiplier)


func _on_half_speed() -> void:
	_set_speed(0.5)


func _on_normal_speed() -> void:
	_set_speed(1.0)


func _on_double_speed() -> void:
	_set_speed(2.0)


func _on_scale_selected(_index: int) -> void:
	_layout_previews()


func _on_mirror_toggled(_enabled: bool) -> void:
	_layout_previews()


func _on_repeat_toggled(enabled: bool) -> void:
	if not enabled:
		repeat_timer.stop()


func _on_visual_release() -> void:
	if _is_enemy() or _is_tower():
		return
	_release_count += 1
	var release_time: float = MageVisual.CAST_RELEASE_TIME if _asset_index >= 2 else ArcherVisual.ATTACK_RELEASE_TIME
	event_label.text = "Release: %.2f s · %d event" % [release_time, _release_count]


func _on_visual_impact() -> void:
	if not _is_enemy():
		return
	_release_count += 1
	var impact_time: float = BossVisual.ATTACK_IMPACT_TIME if _asset_index == 6 else (GolemVisual.ATTACK_IMPACT_TIME if _asset_index == 5 else (OrcVisual.ATTACK_IMPACT_TIME if _asset_index == 4 else GoblinVisual.ATTACK_IMPACT_TIME))
	event_label.text = "Impact: %.2f s · %d event" % [impact_time, _release_count]


func _on_visual_animation_finished(_animation_name: StringName) -> void:
	if repeat_button.button_pressed:
		repeat_timer.start(0.6 / _speed)


func _on_repeat_timeout() -> void:
	replay()
