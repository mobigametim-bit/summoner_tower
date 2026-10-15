class_name UpgradeChoice
extends Control

signal upgrade_chosen(index: int)
signal reroll_requested
signal rewarded_reroll_requested

@onready var cards: Array[Button] = [
	$Center/Panel/Stack/Card0, $Center/Panel/Stack/Card1, $Center/Panel/Stack/Card2,
	$Center/Panel/Stack/Card3
]
@onready var reroll_button: Button = $Center/Panel/Stack/Rerolls/Reroll
@onready var rewarded_reroll_button: Button = $Center/Panel/Stack/Rerolls/RewardedReroll
var _layout_revision: int = 0
var _minimum_card_height: float = 166.0


func _ready() -> void:
	_minimum_card_height = cards[0].custom_minimum_size.y
	for card: Button in cards:
		card.set_meta(&"skip_ui_sound", true)


func show_choices(choices: Array[RunUpgrade], bonuses: RunBonuses, rerolls: int = 0, rewarded_available: bool = true) -> void:
	for index: int in cards.size():
		cards[index].visible = index < choices.size()
		if index >= choices.size():
			cards[index].disabled = true
			continue
		var upgrade: RunUpgrade = choices[index]
		cards[index].get_node("Margin/Row/Content/Title").text = tr(upgrade.title)
		cards[index].get_node("Margin/Row/Content/Description").text = upgrade.description_text()
		cards[index].get_node("Margin/Row/Icon").texture = upgrade.icon
		_apply_tier_style(cards[index], upgrade.tier)
		var picked: int = bonuses.count(upgrade.kind)
		var rank: HBoxContainer = cards[index].get_node("Margin/Row/Content/RankRow")
		rank.visible = picked > 0
		UiNumbers.show_value(rank.get_node("Count"), picked, "×")
		rank.tooltip_text = tr("Previously picked: %d") % picked
		cards[index].disabled = false
	reroll_button.visible = rerolls > 0
	reroll_button.disabled = rerolls <= 0
	reroll_button.text = str(rerolls)
	rewarded_reroll_button.disabled = not rewarded_available
	rewarded_reroll_button.text = "1" if rewarded_available else "0"
	show()
	cards[0].grab_focus()
	_layout_revision += 1
	_fit_card_heights(_layout_revision)


func _apply_tier_style(card: Button, tier: int) -> void:
	var color: Color = SummonSlot.MERGE_COLORS[clampi(tier - 1, 0, 4)]
	for state_name: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var style: StyleBoxFlat = card.get_theme_stylebox(state_name).duplicate() as StyleBoxFlat
		style.border_color = color
		style.set_border_width_all(3 if state_name != &"focus" else 5)
		card.add_theme_stylebox_override(state_name, style)
	card.get_node("Margin/Row/Content/Title").add_theme_color_override("font_color", color.lightened(0.18))
	card.get_node("Margin/Row/Icon/TierAccent").color = color


func _fit_card_heights(revision: int) -> void:
	# Button не передаёт minimum size дочернего MarginContainer наружу.
	# Ждём известной ширины: высота переносимых строк зависит от неё.
	await get_tree().process_frame
	if not is_inside_tree() or not visible or revision != _layout_revision:
		return
	for card: Button in cards:
		if not card.visible:
			continue
		var margin: MarginContainer = card.get_node("Margin")
		card.custom_minimum_size.y = maxf(_minimum_card_height, margin.get_combined_minimum_size().y)


func close_choice() -> void:
	_layout_revision += 1
	hide()
	for card: Button in cards:
		card.disabled = true
	reroll_button.disabled = true
	rewarded_reroll_button.disabled = true


func set_interaction_enabled(enabled: bool) -> void:
	for card: Button in cards:
		card.disabled = not enabled or not card.visible
	reroll_button.disabled = not enabled or not reroll_button.visible
	rewarded_reroll_button.disabled = not enabled


func _choose(index: int) -> void:
	if not visible or cards[index].disabled:
		return
	for card: Button in cards:
		card.disabled = true
	upgrade_chosen.emit(index)


func _on_card_3_pressed() -> void:
	_choose(3)


func _on_reroll_pressed() -> void:
	if not visible or reroll_button.disabled:
		return
	reroll_button.disabled = true
	reroll_requested.emit()


func _on_rewarded_reroll_pressed() -> void:
	if not visible or rewarded_reroll_button.disabled:
		return
	rewarded_reroll_button.disabled = true
	rewarded_reroll_requested.emit()


func _on_card_0_pressed() -> void:
	_choose(0)


func _on_card_1_pressed() -> void:
	_choose(1)


func _on_card_2_pressed() -> void:
	_choose(2)
