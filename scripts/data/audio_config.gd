class_name AudioConfig
extends Resource

@export var menu: AudioStream
@export var battle: AudioStream
@export var effects: Dictionary[StringName, AudioStream] = {}
@export var effect_volume_db: Dictionary[StringName, float] = {}
@export_range(0.01, 1.0) var combat_spacing: float = 0.12
@export_range(0.05, 2.0) var music_transition: float = 0.4
