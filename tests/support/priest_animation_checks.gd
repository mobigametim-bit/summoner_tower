extends RefCounted


func run(review: Node) -> Dictionary:
	var actor: PriestVisual = review.hero
	review.replay_timer.stop()
	Engine.time_scale = 0.0
	var skeleton: Skeleton2D = actor.get_node("Skeleton2D") as Skeleton2D
	assert(skeleton.get_bone_count() == 8)
	for i: int in skeleton.get_bone_count():
		assert(not is_zero_approx(skeleton.get_bone(i).rest.determinant()))
	for level: int in range(1,6):
		actor.set_level(level)
		assert(actor.get_node(actor.part_paths[&"halo"]).visible == (level == 5))
		assert(actor.get_node(actor.part_paths[&"body"]).texture == actor.part_variants[&"body"][level-1])
	actor.set_meta("release_checks",0)
	var counter: Callable = func() -> void: actor.set_meta("release_checks",int(actor.get_meta("release_checks"))+1)
	actor.release.connect(counter)
	actor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.play_animation(&"cast")
	actor.animation_player.advance(0.17)
	assert(actor.get_meta("release_checks") == 0)
	actor.animation_player.advance(0.02)
	assert(actor.get_meta("release_checks") == 1)
	actor._emit_release()
	assert(actor.get_meta("release_checks") == 1)
	actor.enable_gameplay(false)
	actor.advance_gameplay(0.01,0.1,0.4,true)
	assert(actor._preparing)
	actor.cancel_preparation()
	assert(not actor._preparing and actor._active_animation == &"idle_loop")
	assert(actor.get_meta("release_checks") == 1)
	actor.release.disconnect(counter)
	actor.remove_meta("release_checks")
	actor._gameplay_mode = false
	actor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	Engine.time_scale = 1.0
	review.set_mode(0)
	return {"passed":true,"checks":["eight bones and valid rests","five texture levels and halo gate","release at 0.18, once","canceled anticipation emits no projectile"]}
