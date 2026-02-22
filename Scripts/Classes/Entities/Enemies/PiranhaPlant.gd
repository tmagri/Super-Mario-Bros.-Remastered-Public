extends Enemy

@export var player_range := 24

@export_enum("Up", "Down", "Left", "Right") var plant_direction := 0

func _enter_tree() -> void:
	if not is_sent_enemy:
		$Animation.play("Hide")
	else:
		# Sent Piranha Plants: visible, stationary biter (no gravity, no pipe logic)
		$Animation.play("Rise")
		$Sprite.visible = true
		$Sprite/Hitbox.monitoring = true
		
		z_index = 0
		collision_layer = 16
		collision_mask = 50
		
		# Add a ground collision shape so it sits on terrain
		var shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(12, 15)
		shape.shape = rect
		shape.position.y = -7.5
		add_child(shape)
		
		# Snap to floor via raycast so it doesn't float mid-air
		await get_tree().process_frame
		var space_state = get_world_2d().direct_space_state
		var ray = PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0, 320), 6)
		ray.exclude = [self.get_rid()]
		var result = space_state.intersect_ray(ray)
		if not result.is_empty():
			global_position.y = result.position.y

func _ready() -> void:
	if is_equal_approx(abs(global_rotation_degrees), 180) == false:
		if has_node("Sprite/Hitbox/UpsideDownExtension"):
			$Sprite/Hitbox/UpsideDownExtension.queue_free()
	
	if not is_sent_enemy:
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

