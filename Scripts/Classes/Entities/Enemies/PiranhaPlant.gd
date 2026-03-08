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
		if has_node("VisibleOnScreenEnabler2D"):
			$VisibleOnScreenEnabler2D.queue_free()
		
		# Override the autoplay "Hide" animation — stop and force visible
		$Animation.stop()
		
		$Sprite.visible = true
		$Sprite.position = Vector2(0, -12) # Sprite drawn above origin
		$Sprite.play("default") # Biting animation
		$Sprite/Hitbox.monitoring = true
		
		z_index = 0
		collision_layer = 16
		collision_mask = 50
		
		# Ensure the plant can't be disabled by parent process mode changes
		process_mode = Node.PROCESS_MODE_INHERIT
		
		# Add a ground collision shape so it sits on terrain
		var shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(12, 12)
		shape.shape = rect
		shape.position.y = -6
		add_child(shape)

func _ready() -> void:
	if is_equal_approx(abs(global_rotation_degrees), 180) == false:
		if has_node("Sprite/Hitbox/UpsideDownExtension"):
			$Sprite/Hitbox/UpsideDownExtension.queue_free()
	
	if is_sent_enemy:
		# Stop the pipe-pop timer — sent plants don't use it
		$Timer.stop()
		# Re-force sprite visible in case _ready ran after autoplay "Hide"
		$Sprite.visible = true
	else:
		$Timer.start()

func _physics_process(_delta: float) -> void:
	# Sent Piranha Plants are stationary — no movement at all
	if is_sent_enemy:
		velocity = Vector2.ZERO
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

