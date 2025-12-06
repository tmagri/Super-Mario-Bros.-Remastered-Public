extends PowerUpItem

const MOVE_SPEED := 60

func _ready() -> void:
	$BasicEnemyMovement.gravity_scale = 1.0 # Matches NES relative to Global base (10 vs 38)
	$BasicEnemyMovement.move_speed = 60.0 # Matches NES 1.0 px/frame

func _physics_process(delta: float) -> void:
	$BasicEnemyMovement.handle_movement(delta)

func on_area_entered(area: Area2D) -> void:
	if area.owner is Player:
		if has_meta("is_poison"):
			area.owner.damage()
			queue_free()
		elif has_meta("is_oneup"):
			give_life(area.owner)
		else:
			collect_item(area.owner)

func give_life(_player: Player) -> void:
	DiscoLevel.combo_amount += 1
	AudioManager.play_sfx("1_up", global_position)
	if [Global.GameMode.CHALLENGE, Global.GameMode.BOO_RACE].has(Global.current_game_mode) or Settings.file.difficulty.inf_lives:
		Global.score += 2000
		$ScoreNoteSpawner.spawn_note(2000)
	else:
		Global.lives += 1
		$ScoreNoteSpawner.spawn_one_up_note()
	queue_free()
