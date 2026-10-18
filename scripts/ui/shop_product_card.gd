class_name ShopProductCard
extends Panel

signal selected(product: ShopProduct)

@export var product_index: int = 0

@onready var art: TextureRect = $Art
@onready var title: Label = $Title
@onready var quantity: HBoxContainer = $Quantity
@onready var rewards: HBoxContainer = $Rewards
@onready var hint: Label = $Hint
@onready var price_button: Button = $PriceButton

var product: ShopProduct


func _ready() -> void:
	product = ShopService.CATALOG.products[product_index]
	art.texture = product.icon
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = product.tier_color
	if product.kind == ShopProduct.Kind.NO_ADS:
		style.bg_color = Color("2b2c32")
	add_theme_stylebox_override("panel", style)
	for index: int in $Pips.get_child_count():
		var pip: ColorRect = $Pips.get_child(index) as ColorRect
		pip.color = product.tier_color
		pip.visible = index < product.tier
	ShopService.ownership_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if product == null:
		return
	title.text = tr(product.title)
	title.add_theme_color_override("font_color", Color("f4d080") if product.kind == ShopProduct.Kind.NO_ADS else Color("e6e9e7"))
	$Quantity/Amount.text = ShopProduct.grouped(product.crystals)
	price_button.text = tr("Purchased") if product.kind == ShopProduct.Kind.NO_ADS and ShopService.has_no_ads() else product.price_text()
	price_button.tooltip_text = tr(product.title)
	hint.text = tr("Rewards without viewing")
	quantity.visible = product.kind == ShopProduct.Kind.CRYSTALS
	rewards.visible = not quantity.visible
	hint.visible = rewards.visible


func arrange(rect: Rect2, horizontal: bool, factor: float) -> void:
	position = rect.position
	size = rect.size
	var ads: bool = product.kind == ShopProduct.Kind.NO_ADS
	var width: float = size.x
	var height: float = size.y
	var price_height: float = 38.0 * factor
	var title_size: int = roundi((21.0 if ads else 16.0) * factor)
	title.add_theme_font_size_override("font_size", title_size)
	$Quantity/Amount.add_theme_font_size_override("font_size", roundi(28 * factor))
	$Quantity/Icon.custom_minimum_size = Vector2(19, 23) * factor
	quantity.add_theme_constant_override("separation", roundi(5 * factor))
	for child: Node in rewards.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", roundi(17 * factor))
		elif child is TextureRect:
			child.custom_minimum_size = Vector2(18, 20) * factor
	rewards.add_theme_constant_override("separation", roundi(5 * factor))
	hint.add_theme_font_size_override("font_size", roundi(13 * factor))
	price_button.add_theme_font_size_override("font_size", roundi(23 * factor))
	$Pips.position = Vector2(10, 10) * factor
	for pip: Control in $Pips.get_children():
		pip.custom_minimum_size = Vector2(4, 4) * factor
	if horizontal:
		var content_left: float = 105.0 * factor
		_place(art, Rect2(Vector2(12, 18) * factor, Vector2(85, 96) * factor))
		_place(title, Rect2(content_left, 20 * factor, width - content_left - 12 * factor, 30 * factor))
		title.add_theme_font_size_override("font_size", roundi((21.0 if ads else 17.0) * factor))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_place(quantity, Rect2(content_left, 52 * factor, width - content_left - 12 * factor, 32 * factor))
		quantity.alignment = BoxContainer.ALIGNMENT_BEGIN
		_place(rewards, Rect2(content_left, 53 * factor, width - content_left - 12 * factor, 28 * factor))
		rewards.alignment = BoxContainer.ALIGNMENT_BEGIN
		hint.hide()
		_place(price_button, Rect2(content_left, height - 47 * factor, width - content_left - 12 * factor, price_height))
	else:
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quantity.alignment = BoxContainer.ALIGNMENT_CENTER
		rewards.alignment = BoxContainer.ALIGNMENT_CENTER
		var price_y: float = height - 10 * factor - price_height
		_place(price_button, Rect2(10 * factor, price_y, width - 20 * factor, price_height))
		var row_y: float = price_y - (47.0 if ads else 38.0) * factor
		_place(quantity, Rect2(4 * factor, row_y, width - 8 * factor, 34 * factor))
		_place(rewards, Rect2(4 * factor, row_y - 4 * factor, width - 8 * factor, 27 * factor))
		_place(hint, Rect2(4 * factor, price_y - 21 * factor, width - 8 * factor, 18 * factor))
		var title_y: float = row_y - (33.0 if ads else 26.0) * factor
		_place(title, Rect2(3 * factor, title_y, width - 6 * factor, 28 * factor))
		var art_height: float = minf((78.0 if ads else 92.0) * factor, title_y - 8 * factor)
		_place(art, Rect2((width - 132 * factor) * 0.5, maxf(8 * factor, (title_y - art_height) * 0.5), 132 * factor, art_height))


static func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _on_price_pressed() -> void:
	selected.emit(product)
