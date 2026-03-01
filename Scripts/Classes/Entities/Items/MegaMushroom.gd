extends PowerUpItem

# Mega Mushroom item — spawns at 2× the size of a regular mushroom to signal it's special.
# When collected, triggers the mega_mushroom_get() effect on the player.

func _ready() -> void:
	$BasicEnemyMovement.gravity_scale = 3.8
	$BasicEnemyMovement.move_speed = 60.0
	# The item is displayed at 2× scale so it looks like a "big" mushroom coming out of the block
	scale = Vector2(2.0, 2.0)

func _physics_process(delta: float) -> void:
	$BasicEnemyMovement.handle_movement(delta)

func collect_item(player: Player) -> void:
	collected.emit()
	AudioManager.play_sfx("power_up", global_position)
	Global.score += 1000
	player.score_note_spawner.spawn_note(1000)
	player.mega_mushroom_get()
	queue_free()
