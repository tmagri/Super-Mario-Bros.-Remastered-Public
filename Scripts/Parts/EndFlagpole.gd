extends Node2D

const FLAG_POINTS := [100, 400, 800, 2000, 5000]

const FLAG_POINTS_MODERN := [100, 200, 800, 4000, 8000]

signal player_reached

signal sequence_begin

func on_area_entered(area: Area2D) -> void:
	if area.owner is Player:
		player_touch(area.owner)

func player_touch(player: Player) -> void:
	player_reached.emit()
	if Global.current_game_mode == Global.GameMode.MARATHON_PRACTICE:
		SpeedrunHandler.is_warp_run = false
		SpeedrunHandler.run_finished()
	Global.can_pause = false
	Global.can_time_tick = false
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		Mario35Handler.is_timer_paused = true
	if get_node_or_null("Top") != null:
		$Top.queue_free()
	$Hitbox.queue_free()
	get_tree().call_group("Enemies", "flag_die")
	give_points(player)
	if player.can_pose_anim == false:
		player.z_index = -2
	player.global_position.x = $Flag.global_position.x + 3
	$Animation.play("FlagDown")
	player.state_machine.transition_to("FlagPole")
	AudioManager.set_music_override(AudioManager.MUSIC_OVERRIDES.FLAG_POLE, 99, false)
	await get_tree().create_timer(1.5, false).timeout
	sequence_begin.emit()
	if Global.current_game_mode == Global.GameMode.BOO_RACE:
		AudioManager.set_music_override(AudioManager.MUSIC_OVERRIDES.RACE_WIN, 99, false)
	else:
		AudioManager.set_music_override(AudioManager.MUSIC_OVERRIDES.LEVEL_COMPLETE, 99, false)
	Global.level_complete_begin.emit()
	await get_tree().create_timer(1, false).timeout
	if [Global.GameMode.BOO_RACE, Global.GameMode.MARIO_35].has(Global.current_game_mode) == false:
		Global.tally_time()
	elif Global.current_game_mode == Global.GameMode.MARIO_35:
		Global.current_level.transition_to_next_level()

func give_points(player: Player) -> void:
	# Calculate player's relative position on the pole (0.0 = bottom, 1.0 = top)
	# Pole hitbox: Shape at local Y=-16, segment extends -152px upward
	var pole_bottom := global_position.y - 16.0
	var pole_top := global_position.y - 168.0
	var ratio := clampf(inverse_lerp(pole_bottom, pole_top, player.global_position.y), 0.0, 1.0)
	# Map to 5 score tiers matching original NES FlagpoleYPosData thresholds
	var value: int
	if ratio >= 0.92:
		value = 4  # Top of pole
	elif ratio >= 0.53:
		value = 3
	elif ratio >= 0.33:
		value = 2
	elif ratio > 0.0:
		value = 1
	else:
		value = 0  # Bottom of pole
	var nearest_value = FLAG_POINTS[value]
	if Settings.file.difficulty.flagpole_lives:
		nearest_value = FLAG_POINTS_MODERN[value]
	$Score.text = str(nearest_value)
	if nearest_value == 8000 and not [Global.GameMode.CHALLENGE, Global.GameMode.BOO_RACE].has(Global.current_game_mode) and not Settings.file.difficulty.inf_lives:
		AudioManager.play_sfx("1_up", global_position)
		Global.lives += 1
		$ScoreNoteSpawner.spawn_one_up_note()
	else:
		Global.score += nearest_value
		$Score/Animation2.play("ScoreRise")
