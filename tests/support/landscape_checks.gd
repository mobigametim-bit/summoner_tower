extends RefCounted


static func run() -> Dictionary:
	var checked: int = 0
	for path: String in ["res://resources/balance/battlefield_config.tres","res://resources/biomes/graveyard_battlefield.tres"]:
		var source: BattlefieldConfig = load(path)
		var original: Rect2 = source.playable_rect
		for horizontal: bool in [false,true]:
			var config: BattlefieldConfig = source.duplicate()
			if horizontal:
				config.column_range = Vector2i(9,9)
				config.playable_rect = Rect2(0,0,1080,720)
				config.portal_max_y = 360
			for fallback: bool in [false,true]:
				config.generation_attempts = 0 if fallback else source.generation_attempts
				var generator: BattlefieldGenerator = BattlefieldGenerator.new(config)
				for portals: int in [1,2,3]:
					for slots: int in [10,15]:
						var layout: BattlefieldLayout = generator.generate(17,9 if horizontal else 6,slots,portals)
						assert(generator.is_valid(layout),"Invalid battlefield: %s %s %d %d"%[path,horizontal,portals,slots])
						assert(layout.grid_size == (Vector2i(9,6) if horizontal else Vector2i(6,9)))
						assert(layout.slot_cells.size()==slots and layout.portal_cells.size()==portals)
						if fallback: assert(layout.used_fallback)
						checked += 1
		assert(source.playable_rect==original and source.column_range==Vector2i(6,6))
	return {"maps":checked,"biomes":2,"fallback":true,"source_resources_unchanged":true}
