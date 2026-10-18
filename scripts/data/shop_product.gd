class_name ShopProduct
extends Resource

enum Kind { CRYSTALS, NO_ADS }

@export var product_id: StringName
@export var title: String
@export var kind: Kind = Kind.CRYSTALS
@export var crystals: int = 0
@export var price_rub: int = 0
@export var icon: Texture2D
@export var tier_color: Color = Color.WHITE
@export_range(0, 5) var tier: int = 0


func price_text() -> String:
	# До GamePush это согласованный ориентир, а не цена платёжного каталога.
	return "%s ₽" % grouped(price_rub)


static func grouped(value: int) -> String:
	var digits: String = str(value)
	var result: String = ""
	for index: int in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += " "
		result += digits[index]
	return result
