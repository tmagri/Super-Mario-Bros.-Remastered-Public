extends Block

var _assist_tween: Tween

func _ready() -> void:
	# Assist Mode: show hidden blocks with blinking indicator
	if Global.assist_mode:
		_start_assist_blink()

func _start_assist_blink() -> void:
	if visuals:
		visuals.visible = true
		visuals.modulate = Color(1, 1, 1, 0.5)
		
		_assist_tween = create_tween().set_loops()
		_assist_tween.tween_property(visuals, "modulate:a", 0.15, 0.3)
		_assist_tween.tween_property(visuals, "modulate:a", 0.5, 0.3)

func on_area_entered(area: Area2D) -> void:
	if area.owner is Player:
		var player: Player = area.owner
		if player.velocity.y < 0 and player.global_position.y > $Hitbox.global_position.y and abs(player.global_position.x - global_position.x) < 8:
			# Stop blinking once hit
			if _assist_tween:
				_assist_tween.kill()
				_assist_tween = null
			if visuals:
				visuals.modulate = Color.WHITE
				visuals.visible = true
			player_block_hit.emit(area.owner)
			player.velocity.y = 0
			player.bump_ceiling()
			$Collision.set_deferred("disabled", false)
