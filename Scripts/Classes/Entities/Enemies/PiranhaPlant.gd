extends Enemy

@export var player_range := 24

@export_enum("Up", "Down", "Left", "Right") var plant_direction := 0

func _enter_tree() -> void:
	if not is_sent_enemy:
		$Animation.play("Hide")
	else:
		# Sent Piranha Plants: visible, stationary biter (no gravity, no pipe logic)
		
		# CRITICAL: Disable the VisibleOnScreenEnabler so it doesn't disable
		# the plant when spawned off-screen (enemies spawn at x+480)
		var enabler = get_node_or_null("VisibleOnScreenEnabler2D")
		if enabler:
			on_screen_enabler = null
			enabler.process_mode = Node.PROCESS_MODE_DISABLED
			remove_child(enabler)
			enabler.queue_free()
		
		# Override the autoplay "Hide" animation — stop and force visible
		$Animation.stop()
		
		$Sprite.visible = true
		$Sprite.position = Vector2(0, -12) # sitting ON the origin (ground)
		$Sprite.play("default") # Biting animation
		
		# [FIX]: Ensure the hitbox is correctly positioned and monitoring.
		# Hitbox global position needs to be below ground for BlockBouncingDetection.
		# Sprite is at -12. Hitbox at Sprite + 13 = +1 relative to root (1.5px overlap).
		$Sprite/Hitbox.position = Vector2(0, 13)
		$Sprite/Hitbox.collision_mask = 7 # [FIX]: Include Layers 1, 2, and 3 (Blocks)
		$Sprite/Hitbox.monitoring = true
		
		z_index = -5 # Maintain behind-pipes look if needed, but above ground
		collision_layer = 16
		collision_mask = 50 # Match Goomba (excl. Layer 3/Blocks)
		
		# [FIX]: Add a CollisionShape2D to the root CharacterBody2D.
		# Piranha Plants in pipes don't have one because they are moved by AnimationPlayer,
		# but "Grounded" Piranha Plants need one for move_and_slide() floor detection.
		var shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(12, 16) # Standard enemy size
		shape.shape = rect
		shape.position = Vector2(0, -8) # Center of the 16px height
		add_child(shape)
		
func _ready() -> void:
	if is_equal_approx(abs(global_rotation_degrees), 180) == false:
		if has_node("Sprite/Hitbox/UpsideDownExtension"):
			$Sprite/Hitbox/UpsideDownExtension.queue_free()
	
	# [FIX]: Dedicated block hit area to securely overlap grid-placed blocks.
	# Standard Piranhas lack gravity so their root stays 16px above the block.
	# Sent Piranhas rest on the block directly.
	var block_detect_area = Area2D.new()
	block_detect_area.collision_layer = 0
	# Mask 7 allows detecting Layers 1, 2, and 3 (the block layers).
	block_detect_area.collision_mask = 7
	var block_shape = CollisionShape2D.new()
	var block_rect = RectangleShape2D.new()
	block_rect.size = Vector2(10, 20)
	block_shape.shape = block_rect
	# Positioned downward to reach the block below the Piranha Plant.
	block_shape.position = Vector2(0, 16)
	block_detect_area.add_child(block_shape)
	add_child(block_detect_area)
	block_detect_area.owner = self
	
	# Enable block-hit detection using the dedicated area
	var bounce_detect = BlockBouncingDetection.new()
	bounce_detect.detection_type = 1 # Hitbox
	bounce_detect.hitbox = block_detect_area
	bounce_detect.block_bounced.connect(die_from_object)
	add_child(bounce_detect)
	bounce_detect.owner = self

	if is_sent_enemy:
		# Stop the pipe-pop timer — sent plants don't use it
		$Timer.stop()
		# Completely disable the AnimationPlayer to prevent `autoplay` from resetting properties
		$Animation.active = false
		$Animation.autoplay = ""
		$Animation.stop()
		
		# Re-force sprite visible and position in case _ready ran after autoplay "Hide"
		$Sprite.visible = true
		$Sprite.position = Vector2(0, -12)
		# Re-force hitbox settings in case animation reset them
		$Sprite/Hitbox.position = Vector2(0, 13)
		$Sprite/Hitbox.collision_mask = 7
		$Sprite/Hitbox.set_deferred("monitoring", true)
	else:
		$Timer.start()

func _physics_process(delta: float) -> void:
	# Sent Piranha Plants are stationary horizontally but still fall
	if is_sent_enemy:
		velocity.x = 0
		apply_enemy_gravity(delta)
		move_and_slide()
		if global_position.y > 600: # Cleanup falling off screen
			queue_free()
		return

func on_timeout() -> void:
	if is_sent_enemy:
		return
		
	var player = get_tree().get_first_node_in_group("Players")
	if plant_direction < 2:
		if abs(player.global_position.x - global_position.x) >= player_range:
			$Animation.play("Rise")
	elif (abs(player.global_position.y - global_position.y) >= player_range and abs(player.global_position.x - global_position.x) >= player_range * 2):
		$Animation.play("Rise")

func flag_die() -> void:
	# Piranha Plants should always die on flagpole clear, even if off-screen (in pipes)
	_check_br_kill()
	if score_note_adder != null:
		if score_note_adder.add_score == false:
			Global.score += 500
		score_note_adder.spawn_note(500)
	queue_free()

