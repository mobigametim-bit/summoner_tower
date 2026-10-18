extends Control

signal continued

@onready var shade: Control = $Shade
@onready var panel: PanelContainer = $Panel
@onready var name_label: Label = $Panel/Margin/Stack/Header/Name
@onready var speech: Label = $Panel/Margin/Stack/Speech
@onready var next_button: Button = $Panel/Margin/Stack/Actions/Next
@onready var actions: HBoxContainer = $Panel/Margin/Stack/Actions
@onready var save_error: Label = $Panel/Margin/Stack/SaveError
@onready var portrait: TextureRect = $Portrait
@onready var pause_label: Label = $Pause
var _accept_after: int = 0


func _ready() -> void:
	hide()


func present(text: String, action: bool, welcome: bool, failed: bool, paused: bool) -> void:
	# Второй тап по старой цели не должен подтвердить новое объяснение.
	_accept_after = Time.get_ticks_msec() + 350
	speech.text = text
	name_label.text = TutorialLessons.ui("Бородаций", "Beardric")
	next_button.text = TutorialLessons.ui("Начать", "Start") if welcome else TutorialLessons.ui("Понятно", "Got it")
	next_button.visible = not action
	actions.visible = not action
	save_error.text = TutorialLessons.ui("Не удалось сохранить обучение. После перезапуска подсказки могут повториться.", "Tutorial progress could not be saved. Tips may repeat after restarting.")
	save_error.visible = failed
	pause_label.text = TutorialLessons.ui("II Пауза", "II Paused")
	pause_label.visible = paused
	show()
	if not action:
		next_button.grab_focus()


func arrange(rect: Rect2, action: bool, top: bool, start: Vector2 = Vector2.ZERO, finish: Vector2 = Vector2.ZERO) -> void:
	if ScreenLayout.landscape():
		_arrange_landscape(rect,action,top,start,finish)
		return
	panel.position.x = 24.0
	panel.size.x = maxf(size.x - 48.0, 1.0)
	panel.reset_size()
	var bottom: float = minf(size.y - panel.size.y - 36.0, 1050.0 - panel.size.y)
	panel.position.y = 172.0 if top else bottom
	if action and rect.has_area():
		var best: float = INF
		for y: float in [panel.position.y, 172.0, 420.0, bottom]:
			var candidate: Rect2 = Rect2(Vector2(24,y),panel.size)
			var score: float = candidate.intersection(rect).get_area()
			if start != finish:
				score = candidate.intersection(Rect2(start-Vector2(65,75),Vector2(130,150))).get_area()
				score += candidate.intersection(Rect2(finish-Vector2(65,75),Vector2(130,150))).get_area()
			if score < best:
				best = score
				panel.position.y = y
	# Окно ставится с противоположной стороны от цели; HUD по возможности остаётся свободным.
	panel.position.y = clampf(panel.position.y, 160.0, maxf(size.y - panel.size.y - 20.0, 160.0))
	portrait.position = panel.position + Vector2(0.0, -145.0)
	if rect.has_area() and portrait.get_rect().intersects(rect):
		portrait.position.x = panel.position.x + panel.size.x - portrait.size.x
	pause_label.position.x = size.x - 180.0
	if rect.has_area() and pause_label.get_rect().intersects(rect):
		pause_label.position.x = 24.0
	shade.configure(rect, action, start, finish)


func _arrange_landscape(rect: Rect2, action: bool, top: bool, start: Vector2, finish: Vector2) -> void:
	panel.size.x = minf(520.0,size.x*0.5-24.0) if action else minf(672.0,size.x-48.0)
	panel.reset_size()
	var best: float = INF
	var lower: float = maxf(160.0,size.y-panel.size.y-24.0)
	var xs: Array[float] = [24.0,maxf(24.0,size.x-panel.size.x-24.0)]
	var ys: Array[float] = [160.0,lower]
	if not top:
		ys.reverse()
	for x: float in xs:
		for y: float in ys:
			var candidate: Rect2 = Rect2(Vector2(x,y),panel.size)
			var score: float = candidate.intersection(rect).get_area()
			if start != finish:
				score = candidate.intersection(Rect2(start-Vector2(70,80),Vector2(140,160))).get_area()
				score += candidate.intersection(Rect2(finish-Vector2(70,80),Vector2(140,160))).get_area()
			if score < best:
				best = score
				panel.position = candidate.position
	portrait.position = panel.position+Vector2(0,-145)
	if portrait.get_rect().intersects(rect):
		portrait.position.x = panel.position.x+panel.size.x-portrait.size.x
	pause_label.position = Vector2(size.x-180,20)
	shade.configure(rect,action,start,finish)


func _on_next_pressed() -> void:
	if Time.get_ticks_msec() >= _accept_after:
		continued.emit()
