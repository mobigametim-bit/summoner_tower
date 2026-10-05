class_name UpgradeChoice
extends Control

signal upgrade_chosen(index: int)

@onready var cards: Array[Button] = [
	$Center/Panel/Stack/Card0, $Center/Panel/Stack/Card1, $Center/Panel/Stack/Card2
]


func show_choices(choices: Array[RunUpgrade], bonuses: RunBonuses) -> void:
	for index: int in cards.size():
		var upgrade: RunUpgrade = choices[index]
		cards[index].get_node("Margin/Row/Content/Title").text = upgrade.title
		cards[index].get_node("Margin/Row/Content/Description").text = upgrade.description
		cards[index].get_node("Margin/Row/Icon").texture = upgrade.icon
		var picked: int = bonuses.count(upgrade.kind)
		var rank: Label = cards[index].get_node("Margin/Row/Content/Rank")
		rank.visible = picked > 0
		rank.text = "PREVIOUSLY PICKED: %d" % picked
		cards[index].disabled = false
	show()
	cards[0].grab_focus()


func close_choice() -> void:
	hide()
	for card: Button in cards:
		card.disabled = true


func _choose(index: int) -> void:
	if not visible or cards[index].disabled:
		return
	for card: Button in cards:
		card.disabled = true
	upgrade_chosen.emit(index)


func _on_card_0_pressed() -> void:
	_choose(0)


func _on_card_1_pressed() -> void:
	_choose(1)


func _on_card_2_pressed() -> void:
	_choose(2)
