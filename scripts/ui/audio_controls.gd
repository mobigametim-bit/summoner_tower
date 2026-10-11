extends VBoxContainer

@onready var music_slider: HSlider = $Music/Slider
@onready var effects_slider: HSlider = $Effects/Slider
@onready var _save_error: Label = $SaveError


func _ready() -> void:
	music_slider.value_changed.connect(_on_music_changed)
	effects_slider.value_changed.connect(_on_effects_changed)
	AudioService.volumes_changed.connect(refresh)
	AudioService.settings_save_failed.connect(_on_save_failed)
	AudioService.settings_saved.connect(_on_saved)
	visibility_changed.connect(_on_visibility_changed)
	refresh()


func refresh() -> void:
	music_slider.set_value_no_signal(roundi(AudioService.music_volume * 100.0))
	effects_slider.set_value_no_signal(roundi(AudioService.effects_volume * 100.0))
	$Music/Value.text = "%d%%" % roundi(music_slider.value)
	$Effects/Value.text = "%d%%" % roundi(effects_slider.value)
	_save_error.visible = AudioService.last_save_error != OK


func _on_music_changed(value: float) -> void:
	AudioService.set_music_volume(value / 100.0)


func _on_effects_changed(value: float) -> void:
	AudioService.set_effects_volume(value / 100.0)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		refresh()
	else:
		AudioService.save_settings()


func _on_save_failed(_error: int) -> void:
	_save_error.show()


func _on_saved() -> void:
	_save_error.hide()
