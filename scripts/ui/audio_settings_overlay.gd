extends Control

signal closed


func open() -> void:
	show()
	$Center/Panel/Stack/AudioControls/Music/Slider.grab_focus()


func close() -> void:
	hide()
	AudioService.save_settings()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
