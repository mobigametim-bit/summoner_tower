extends Node

signal crystals_changed(total: int)

# Баланс между сценами в текущей сессии; запись в user:// относится к фиче 12.
var crystals: int = 0


func add_crystals(amount: int) -> void:
	if amount <= 0:
		return
	crystals += amount
	crystals_changed.emit(crystals)
