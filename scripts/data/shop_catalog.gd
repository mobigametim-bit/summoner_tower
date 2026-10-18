class_name ShopCatalog
extends Resource

@export var products: Array[ShopProduct] = []


func find(product_id: StringName) -> ShopProduct:
	for product: ShopProduct in products:
		if product.product_id == product_id:
			return product
	return null
