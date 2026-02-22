extends PlayerState

var can_land := true

@export var castle: Node = null

func enter(_msg := {}) -> void:
	player.direction = 1
	player.stop_all_timers()
	# Pause Mario 35 timer immediately on flagpole touch & award level completion bonus
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		Mario35Handler.is_timer_paused = true
		Mario35Handler.add_time(20)
	await Global.level_complete_begin
	state_machine.transition_to("LevelExit")

func physics_update(_delta: float) -> void:
	player.velocity.y = 125
	player.velocity.x = 0
	player.sprite.scale.x = player.direction
	if player.is_on_floor():
		if can_land:
			can_land = false
			player.global_position.x += 10
			player.direction = -1
		player.sprite.speed_scale = 0
	else:
		player.sprite.speed_scale = 2
	player.play_animation("FlagSlide")
	player.move_and_slide()
