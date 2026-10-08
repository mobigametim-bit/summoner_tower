extends Node2D

@onready var tower: TowerVisual = $TowerVisual
@onready var energy: TowerCrystalEnergy = $TowerVisual/CrystalPivot/CrystalEnergy
@onready var idle_particles: CPUParticles2D = $TowerVisual/CrystalPivot/CrystalEnergy/IdleParticles

var idle_enabled: bool = true
var tap_requests: int = 0


func play_tap() -> void:
	tap_requests += 1
	tower.play_animation(&"tap")
	energy.set_idle_enabled(idle_enabled)
	energy.play_tap()


func set_idle_enabled(enabled: bool) -> void:
	idle_enabled = enabled
	energy.set_idle_enabled(enabled)
