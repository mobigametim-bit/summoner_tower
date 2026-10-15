class_name ManaRewardPopup
extends Node2D

@export_range(0.2, 2.0) var duration: float = 0.9
@export_range(0.0, 160.0) var rise: float = 64.0

@onready var amount_label: Label = $Row/Amount


func play_reward(amount: int) -> void:
	if amount <= 0:
		queue_free()
		return
	UiNumbers.show_value(amount_label, amount, "+")
	scale = Vector2.ONE * 0.8
	var tween: Tween = create_tween().set_parallel(true)
	# У верхнего портала подпись остаётся внутри экрана до конца затухания.
	tween.tween_property(self, "position:y", maxf(28.0, position.y - rise), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, duration * 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration * 0.45).set_delay(duration * 0.55)
	tween.chain().tween_callback(queue_free)
