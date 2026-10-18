extends Control

@export_file("*.tscn") var menu_scene_path: String = "res://scenes/main_menu.tscn"

@onready var back_button: Button = $Header/Back
@onready var overlay: Control = $Details
@onready var panel: Panel = $Details/Panel

var _selected: ShopProduct
var _request_id: int = 0
var _leaving: bool = false
var _factor: float = 1.0


func _ready() -> void:
	AudioService.play_music(&"menu")
	for card: ShopProductCard in $Products.get_children():
		card.selected.connect(_show_details)
	SessionProgress.crystals_changed.connect(_update_balance)
	ShopService.completed.connect(_on_purchase_completed)
	ShopService.ownership_changed.connect(_refresh)
	resized.connect(_queue_layout)
	_refresh()
	back_button.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


func _refresh() -> void:
	$Header/Title.text = tr("Soul Shop")
	$Footer.text = tr("Crystals for permanent upgrades")
	$TestBadge.text = tr("TEST SHOP — no real charges")
	$TestBadge.visible = ShopService.is_available()
	for card: ShopProductCard in $Products.get_children():
		card.refresh()
	_update_balance(SessionProgress.crystals)
	_queue_layout()


func _update_balance(total: int) -> void:
	UiNumbers.show_value($Wallet/Balance, total)
	_queue_layout()


func _queue_layout() -> void:
	_layout.call_deferred()


func _layout() -> void:
	if not is_inside_tree():
		return
	var horizontal: bool = size.x > size.y
	var phone: bool = horizontal and size.x / size.y >= 1.6
	_factor = size.y / 390.0 if phone else minf(size.x / 1024.0, size.y / 768.0) if horizontal else minf(size.x / 390.0, size.y / 844.0)
	var f: float = _factor
	var pad: Vector2 = Vector2(20, 12) * f if phone else Vector2(40, 24) * f if horizontal else Vector2(18, 18) * f
	var header_height: float = (43.0 if phone else 64.0 if horizontal else 50.0) * f
	_place($Header, Rect2(pad, Vector2(size.x - pad.x * 2, header_height)))
	_place(back_button, Rect2(Vector2.ZERO, Vector2.ONE * (41.0 if phone else 62.0 if horizontal else 46.0) * f))
	$Header/Title.add_theme_font_size_override("font_size", roundi((27 if phone else 44 if horizontal else 29) * f))
	_place($Header/Title, Rect2(60 * f, 0, $Header.size.x - 120 * f, header_height))
	_place($Header/Spark, Rect2($Header.size.x - 36 * f, 6 * f, 32 * f, 36 * f))
	$Header/Spark.visible = not horizontal
	$Wallet/Balance.add_theme_font_size_override("font_size", roundi((26 if phone else 36 if horizontal else 34) * f))
	$Wallet/Icon.custom_minimum_size = Vector2(25, 30) * f if phone else Vector2(32, 38) * f
	$Wallet.add_theme_constant_override("separation", roundi(10 * f))
	$Wallet.reset_size()
	var grid_top: float = pad.y + header_height + 12 * f
	if horizontal:
		$Wallet.position = Vector2(size.x - pad.x - $Wallet.size.x, pad.y + (header_height - $Wallet.size.y) * 0.5)
	else:
		$Wallet.position = Vector2((size.x - $Wallet.size.x) * 0.5, grid_top)
		grid_top += maxf(47 * f, $Wallet.size.y) + 12 * f
	var footer_height: float = (36 if ShopService.is_available() else 18) * f
	var grid_size: Vector2 = Vector2(size.x - pad.x * 2, size.y - grid_top - pad.y - footer_height)
	_place($Products, Rect2(Vector2(pad.x, grid_top), grid_size))
	var gap: float = (12 if horizontal else 11) * f
	var columns: int = 3 if horizontal else 2
	var rows: int = 2 if horizontal else 3
	var card_size: Vector2 = (grid_size - Vector2(columns - 1, rows - 1) * gap) / Vector2(columns, rows)
	for index: int in $Products.get_child_count():
		var card: ShopProductCard = $Products.get_child(index) as ShopProductCard
		@warning_ignore("integer_division")
		var cell: Vector2 = Vector2(index % columns, index / columns)
		var card_factor: float = minf(f, card_size.x / 260.0) if phone else f * 1.4 if horizontal else f
		card.arrange(Rect2(cell * (card_size + Vector2.ONE * gap), card_size), phone, card_factor)
	$Footer.add_theme_font_size_override("font_size", roundi(13 * f))
	$TestBadge.add_theme_font_size_override("font_size", roundi(13 * f))
	_place($Footer, Rect2(pad.x, size.y - pad.y - footer_height + 4 * f, grid_size.x, 18 * f))
	_place($TestBadge, Rect2(pad.x, size.y - pad.y - 16 * f, grid_size.x, 18 * f))
	$Status.add_theme_font_size_override("font_size", roundi(15 * f))
	_place($Status, Rect2(pad.x, size.y - pad.y - footer_height + 4 * f, grid_size.x, 20 * f))
	if overlay.visible:
		_layout_details()


static func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
	# После смены ширины/шрифта Label пересчитывает высоту переноса отложенно.
	if control is Label:
		control.set_deferred("size", rect.size)


func _show_details(product: ShopProduct) -> void:
	if _leaving or overlay.visible:
		return
	_selected = product
	$Status.hide()
	$Footer.show()
	$Details/Panel/Art.texture = product.icon
	$Details/Panel/Title.text = tr(product.title)
	$Details/Panel/Quantity/Amount.text = ShopProduct.grouped(product.crystals)
	var ads: bool = product.kind == ShopProduct.Kind.NO_ADS
	$Details/Panel/Quantity.visible = not ads
	$Details/Panel/Info.text = tr("One purchase — forever") if ads else ""
	$Details/Panel/Info.visible = ads
	$Details/Panel/Benefits.visible = ads
	$Details/Panel/Benefits/Revive/Title.text = tr("Revive +50 HP")
	$Details/Panel/Benefits/Revive/Limit.text = tr("Once per run")
	$Details/Panel/Benefits/Reroll/Title.text = tr("Reroll cards")
	$Details/Panel/Benefits/Reroll/Limit.text = tr("Once per boss wave")
	$Details/Panel/Benefits/Double/Title.text = tr("Crystals ×2")
	$Details/Panel/Benefits/Double/Limit.text = tr("Once on the results screen")
	$Details/Panel/Availability.text = tr("Rewards without watching ads") if ads else ""
	if not ShopService.is_available():
		$Details/Panel/Availability.text = tr("Purchases are not available yet")
	$Details/Panel/Price.text = product.price_text()
	$Details/Panel/Buy.text = tr("Purchased") if ads and ShopService.has_no_ads() else tr("Test purchase") if ShopService.is_available() else tr("Unavailable")
	$Details/Panel/Buy.disabled = not ShopService.is_available() or (ads and ShopService.has_no_ads())
	$Details/Panel/Outcomes.hide()
	$Details/Panel/TestPrompt.hide()
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = product.tier_color
	panel.add_theme_stylebox_override("panel", style)
	back_button.disabled = true
	for card: ShopProductCard in $Products.get_children():
		card.price_button.disabled = true
	overlay.show()
	_layout_details()
	$Details/Panel/Close.grab_focus()


func _layout_details() -> void:
	var horizontal: bool = size.x > size.y and size.x / size.y >= 1.6
	var ads: bool = _selected.kind == ShopProduct.Kind.NO_ADS
	if not ads:
		_layout_crystal_details(horizontal)
		return
	$Details/Panel/Availability.visible = not (horizontal and ads)
	var f: float = minf(_factor, 1.4) if size.x > size.y and not horizontal else _factor
	var design: Vector2 = Vector2(740, 320) if horizontal else Vector2(350, 595 if ads else 445)
	f = minf(f, minf((size.x - 32) / design.x, (size.y - 32) / design.y))
	_place(panel, Rect2((size - design * f) * 0.5, design * f))
	var width: float = design.x
	var left: float = 184 if horizontal else 24
	var content_width: float = width - left - 24
	_place($Details/Panel/Close, Rect2((width - 43) * f, 10 * f, 33 * f, 33 * f))
	_place($Details/Panel/Art, Rect2(15 * f, 80 * f, 154 * f, 155 * f) if horizontal else Rect2(90 * f, 24 * f, 170 * f, 136 * f))
	_place($Details/Panel/Title, Rect2(left * f, (20 if horizontal else 170) * f, content_width * f, 36 * f))
	$Details/Panel/Title.add_theme_font_size_override("font_size", roundi(28 * f))
	_place($Details/Panel/Info, Rect2(left * f, (62 if horizontal else 213) * f, content_width * f, (24 if ads else 55) * f))
	$Details/Panel/Info.add_theme_font_size_override("font_size", roundi(16 * f))
	$Details/Panel/Quantity/Amount.add_theme_font_size_override("font_size", roundi(39 * f))
	$Details/Panel/Quantity/Icon.custom_minimum_size = Vector2(28, 34) * f
	_place($Details/Panel/Quantity, Rect2(left * f, (123 if horizontal else 283) * f, content_width * f, 48 * f))
	_place($Details/Panel/Benefits, Rect2(left * f, (103 if horizontal else 259) * f, content_width * f, (100 if horizontal else 167) * f))
	for index: int in $Details/Panel/Benefits.get_child_count():
		var row: Control = $Details/Panel/Benefits.get_child(index) as Control
		var row_width: float = content_width / 3.0 if horizontal else content_width
		_place(row, Rect2(index * row_width * f if horizontal else 0.0, 0 if horizontal else index * 56 * f, row_width * f, 100 * f if horizontal else 50 * f))
		_place(row.get_node("Icon"), Rect2((row_width - 27) * f * 0.5, 0, 27 * f, 28 * f) if horizontal else Rect2(0, 3 * f, 27 * f, 28 * f))
		var title: Label = row.get_node("Title") as Label
		var limit: Label = row.get_node("Limit") as Label
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if horizontal else HORIZONTAL_ALIGNMENT_LEFT
		limit.horizontal_alignment = title.horizontal_alignment
		title.add_theme_font_size_override("font_size", roundi((17 if horizontal else 19) * f))
		limit.add_theme_font_size_override("font_size", roundi((13 if horizontal else 14) * f))
		_place(title, Rect2(0, 35 * f, row_width * f, 25 * f) if horizontal else Rect2(36 * f, 0, (row_width - 36) * f, 26 * f))
		_place(limit, Rect2(0, 64 * f, row_width * f, 34 * f) if horizontal else Rect2(36 * f, 29 * f, (row_width - 36) * f, 20 * f))
	var bottom: float = design.y - 24
	_place($Details/Panel/Buy, Rect2(left * f, (bottom - 44) * f, content_width * f, 44 * f))
	_place($Details/Panel/Price, Rect2(left * f, (bottom - 94) * f, content_width * f, 38 * f))
	$Details/Panel/Price.add_theme_font_size_override("font_size", roundi(28 * f))
	_place($Details/Panel/Availability, Rect2(left * f, (bottom - 135) * f, content_width * f, 34 * f))
	$Details/Panel/Availability.add_theme_font_size_override("font_size", roundi(15 * f))
	$Details/Panel/Buy.add_theme_font_size_override("font_size", roundi(21 * f))
	_place($Details/Panel/Outcomes, Rect2(left * f, (bottom - 44) * f, content_width * f, 44 * f))
	for button: Button in $Details/Panel/Outcomes.get_children():
		button.add_theme_font_size_override("font_size", roundi(17 * f))
	_place($Details/Panel/TestPrompt, Rect2(left * f, (bottom - 95) * f, content_width * f, 44 * f))
	$Details/Panel/TestPrompt.add_theme_font_size_override("font_size", roundi(16 * f))
	$Details/Panel/Buy.visible = _request_id == 0
	$Details/Panel/Price.visible = _request_id == 0


func _layout_crystal_details(horizontal: bool) -> void:
	var design: Vector2 = Vector2(440, 232) if horizontal else Vector2(300, 308)
	var f: float = minf(_factor, 1.4) if size.x > size.y else _factor
	f = minf(f, minf((size.x-32) / design.x, (size.y-32) / design.y))
	_place(panel, Rect2((size-design*f)*0.5, design*f))
	var left: float = 160 if horizontal else 20
	var width: float = design.x-left-20
	_place($Details/Panel/Close, Rect2((design.x-43)*f, 10*f, 33*f, 33*f))
	_place($Details/Panel/Art, Rect2(12*f, 50*f, 136*f, 120*f) if horizontal else Rect2(82*f, 14*f, 136*f, 96*f))
	_place($Details/Panel/Title, Rect2(left*f, (18 if horizontal else 116)*f, (width-32 if horizontal else width)*f, 32*f))
	$Details/Panel/Title.add_theme_font_size_override("font_size", roundi((22 if horizontal else 24)*f))
	_place($Details/Panel/Quantity, Rect2(left*f, (60 if horizontal else 154)*f, width*f, 40*f))
	$Details/Panel/Quantity/Amount.add_theme_font_size_override("font_size", roundi(36*f))
	$Details/Panel/Quantity/Icon.custom_minimum_size = Vector2(28,34)*f
	_place($Details/Panel/Price, Rect2(left*f, (108 if horizontal else 198)*f, width*f, 32*f))
	$Details/Panel/Price.add_theme_font_size_override("font_size", roundi(26*f))
	_place($Details/Panel/Availability, Rect2(left*f, (142 if horizontal else 228)*f, width*f, 20*f))
	$Details/Panel/Availability.visible = not $Details/Panel/Availability.text.is_empty()
	$Details/Panel/Availability.add_theme_font_size_override("font_size", roundi(14*f))
	var buy_rect: Rect2 = Rect2(left*f, (166 if horizontal else 250)*f, width*f, (56 if horizontal else 44)*f)
	_place($Details/Panel/Buy, buy_rect)
	$Details/Panel/Buy.add_theme_font_size_override("font_size", roundi(20*f))
	_place($Details/Panel/Outcomes, buy_rect)
	for button: Button in $Details/Panel/Outcomes.get_children():
		button.add_theme_font_size_override("font_size", roundi(16*f))
	_place($Details/Panel/TestPrompt, Rect2(left*f, (112 if horizontal else 200)*f, width*f, 44*f))
	$Details/Panel/TestPrompt.add_theme_font_size_override("font_size", roundi(15*f))
	$Details/Panel/Buy.visible = _request_id == 0
	$Details/Panel/Price.visible = _request_id == 0


func _on_buy_pressed() -> void:
	if _selected == null or _request_id != 0:
		return
	_request_id = ShopService.begin_purchase(_selected.product_id)
	if _request_id == 0:
		return
	$Details/Panel/Outcomes.show()
	$Details/Panel/TestPrompt.text = tr("Test payment: choose an outcome")
	$Details/Panel/TestPrompt.show()
	_layout_details()
	$Details/Panel/Outcomes/Success.grab_focus()


func _on_success_pressed() -> void:
	ShopService.finish_purchase(_request_id, ShopService.Outcome.SUCCESS)


func _on_cancel_pressed() -> void:
	ShopService.finish_purchase(_request_id, ShopService.Outcome.CANCELED)


func _on_failure_pressed() -> void:
	ShopService.finish_purchase(_request_id, ShopService.Outcome.FAILED)


func _on_purchase_completed(product_id: StringName, outcome: ShopService.Outcome) -> void:
	_request_id = 0
	_close_details()
	var product: ShopProduct = ShopService.CATALOG.find(product_id)
	$Status.text = tr("Purchase canceled") if outcome == ShopService.Outcome.CANCELED else tr("Purchase failed. Try again.") if outcome == ShopService.Outcome.FAILED else tr("Rewards without ads activated") if product.kind == ShopProduct.Kind.NO_ADS else tr("Received %s crystals") % ShopProduct.grouped(product.crystals)
	$Status.show()
	$Footer.hide()


func _close_details() -> void:
	if _request_id != 0:
		var pending: int = _request_id
		_request_id = 0
		ShopService.finish_purchase(pending, ShopService.Outcome.CANCELED)
	overlay.hide()
	back_button.disabled = false
	for card: ShopProductCard in $Products.get_children():
		card.price_button.disabled = false
	if _selected != null:
		for card: ShopProductCard in $Products.get_children():
			if card.product == _selected:
				card.price_button.grab_focus()


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	_close_details()
	if get_tree().change_scene_to_file(menu_scene_path) != OK:
		_leaving = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if overlay.visible:
			_close_details()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _request_id != 0:
		ShopService.finish_purchase(_request_id, ShopService.Outcome.CANCELED)
