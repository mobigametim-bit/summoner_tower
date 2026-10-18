extends Control

@export_file("*.tscn") var menu_scene_path: String = "res://scenes/main_menu.tscn"

@onready var crystal_balance: Label = $Center/Stack/Wallet/Amount
@onready var back_button: Button = $Center/Stack/Header/BackButton

var _leaving: bool = false


func _ready() -> void:
	AudioService.play_music(&"menu")
	_update_crystals(SessionProgress.crystals)
	SessionProgress.crystals_changed.connect(_update_crystals)
	back_button.grab_focus()
	Tutorial.enter_meta.call_deferred(self)
	resized.connect(_layout)
	_layout.call_deferred()


func _layout() -> void:
	var stack: VBoxContainer = $Center/Stack
	var scroll: ScrollContainer = $Center/Stack/Scroll
	stack.custom_minimum_size = Vector2(minf(864,size.x-96),size.y-96) if ScreenLayout.landscape() else Vector2(624,1160)
	scroll.custom_minimum_size = Vector2(stack.custom_minimum_size.x,maxf(180,stack.custom_minimum_size.y-240))
	stack.reset_size()


func _update_crystals(total: int) -> void:
	UiNumbers.show_value(crystal_balance, total)


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	back_button.disabled = true
	var error: Error = get_tree().change_scene_to_file(menu_scene_path)
	if error != OK:
		_leaving = false
		back_button.disabled = false
		push_error("Cannot open menu: %s (error %s)" % [menu_scene_path, error])
