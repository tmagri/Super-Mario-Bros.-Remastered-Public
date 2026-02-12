extends PowerUpItem

func on_area_entered(area: Area2D) -> void:
	if area.owner is Player:
		AudioManager.play_sfx("hachisuke", global_position)
		DiscoLevel.combo_amount += 1
		if Global.current_game_mode == Global.GameMode.MARIO_35:
			Mario35Handler.add_time(20) # Same time reward as 1-Up
		else:
			$ScoreNoteSpawner.spawn_note(8000)
		queue_free()
