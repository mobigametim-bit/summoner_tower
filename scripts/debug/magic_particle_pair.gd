extends Node2D

@export var frost: bool = false
@export var impact_scene: PackedScene

@onready var mage: Node2D = $Mage
@onready var enemy: GoblinVisual = $Enemy
@onready var staff_particles: CPUParticles2D = $StaffParticles
@onready var projectile: Sprite2D = $Projectile
@onready var impact_host: Node2D = $ImpactHost
@onready var impact_player: GFFPlayer = $ImpactHost/GFFPlayer

var hits: int = 0
var _shot_pending: bool = false
var _flight: Tween


func _ready() -> void:
	# Отдельная аура превью заменяет встроенную, чтобы не удваивать частицы.
	mage.staff_particles.emitting = false
	mage.staff_particles.visible = false
	mage.release.connect(_on_release)
	enemy.play_animation(&"walk_loop")
	enemy.set_animation_paused(true)


func _process(_delta: float) -> void:
	# В превью отдельный emitter следует опорной точке посоха.
	staff_particles.global_position = mage.release_point.to_global(Vector2(7.0, -12.0))


func cast() -> void:
	if _shot_pending:
		return
	_shot_pending = true
	mage.play_animation(&"cast")


func _on_release() -> void:
	if not _shot_pending:
		return
	projectile.position = to_local(mage.release_point.global_position)
	projectile.visible = true
	_flight = create_tween()
	_flight.tween_property(projectile, "position", enemy.position, 0.3)
	_flight.tween_callback(_hit)


func _hit() -> void:
	projectile.visible = false
	_shot_pending = false
	hits += 1
	enemy.show_hit()
	var effect: GFFParticles = GFFParticles.new()
	effect.particle_scene = impact_scene
	effect.emit_count = 28
	effect.duration = 0.8
	effect.label = "magic_preview_impact"
	effect.overlap_strategy = GFFEffect.OverlapStrategy.IGNORE
	impact_player.play(effect)


func set_idle_enabled(enabled: bool) -> void:
	staff_particles.visible = enabled
	staff_particles.emitting = enabled


func _exit_tree() -> void:
	if _flight != null:
		_flight.kill()
	if is_instance_valid(impact_player):
		impact_player.stop()
