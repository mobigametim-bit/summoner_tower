class_name UiNumbers
extends RefCounted

const SUFFIXES: Array[String] = ["", "K", "M", "B", "T", "Q"]


@warning_ignore("integer_division")
static func compact(value: int) -> String:
	if value > -1000 and value < 1000:
		return str(value)
	var amount: int = absi(value)
	var divisor: int = 1
	var suffix: int = 0
	while suffix < SUFFIXES.size() - 1 and amount / divisor >= 1000:
		divisor *= 1000
		suffix += 1
	var whole: int = amount / divisor
	var decimals: int = 2 if whole < 10 else (1 if whole < 100 else 0)
	var scale: int = 100 if decimals == 2 else (10 if decimals == 1 else 1)
	# Отбрасываем остаток: отображаемая валюта не обещает больше, чем есть у игрока.
	var fraction: int = (amount % divisor) / (divisor / scale)
	var digits: String = str(fraction).pad_zeros(decimals).rstrip("0") if decimals > 0 else ""
	return ("-" if value < 0 else "") + str(whole) + ("." + digits if not digits.is_empty() else "") + SUFFIXES[suffix]


static func show_value(label: Label, value: int, prefix: String = "") -> void:
	label.text = prefix + compact(value)
	label.tooltip_text = prefix + str(value)
