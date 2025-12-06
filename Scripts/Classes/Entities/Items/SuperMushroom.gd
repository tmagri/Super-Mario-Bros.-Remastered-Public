extends PowerUpItem

const MOVE_SPEED := 60

func _ready() -> void:
	$BasicEnemyMovement.gravity_scale = 3.8 # Normal volition gravity
	$BasicEnemyMovement.move_speed = 60.0 

var bounced_by_block := false

func block_bounce_up(block: Node2D) -> void:
	super.block_bounce_up(block)
	bounced_by_block = true
	$BasicEnemyMovement.gravity_scale = 1.0

func _physics_process(delta: float) -> void:
	if is_on_floor() and velocity.y >= 0:
		bounced_by_block = false
		$BasicEnemyMovement.gravity_scale = 3.8

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
