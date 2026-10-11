extends Control

signal closed


func _ready() -> void:
	$Center/Panel/Stack/Language/Picker.item_selected.connect(_on_language_selected)
	LocaleService.language_changed.connect(_refresh_language)
	_refresh_language()


func _refresh_language() -> void:
	$Center/Panel/Stack/Language/Picker.select(LocaleService.LANGUAGES.find(LocaleService.language))
	$Center/Panel/Stack/LanguageSaveError.visible = LocaleService.last_save_error != OK


func _on_language_selected(index: int) -> void:
	LocaleService.set_language(LocaleService.LANGUAGES[index])


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
