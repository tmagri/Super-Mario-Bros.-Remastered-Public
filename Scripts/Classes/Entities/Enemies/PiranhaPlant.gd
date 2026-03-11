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
		# In the original scene, the hitbox is child of Sprite and its local position is (0, 12).
		# Since we moved the Sprite to (0, -12), the hitbox's global position was at (0, 0),
		# which is LODGED in the ground. We need to move it to (0, 0) relative to Sprite.
		$Sprite/Hitbox.position = Vector2(0, 0)
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
	
	if is_sent_enemy:
		# Stop the pipe-pop timer — sent plants don't use it
		$Timer.stop()
		# Re-force sprite visible and position in case _ready ran after autoplay "Hide"
		$Animation.stop()
		$Sprite.visible = true
		$Sprite.position = Vector2(0, -12)
		# Re-force hitbox monitoring in case animation reset it
		$Sprite/Hitbox.position = Vector2(0, 0)
		$Sprite/Hitbox.monitoring = true
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

