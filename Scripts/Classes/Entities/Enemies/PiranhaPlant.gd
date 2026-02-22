extends Enemy

@export var player_range := 24

@export_enum("Up", "Down", "Left", "Right") var plant_direction := 0

func _enter_tree() -> void:
	if not is_sent_enemy:
		$Animation.play("Hide")
	else:
		# Sent Piranha Plants: visible, stationary, no animation, gravity + collision like Goomba
		$Animation.stop()
		$Sprite.visible = true
		$Sprite.position.y = -12
		$Sprite/Hitbox.monitoring = true
		
		z_index = 0
		collision_layer = 16
		collision_mask = 50
		
		var shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(12, 15)
		shape.shape = rect
		shape.position.y = -7.5
		add_child(shape)

func _ready() -> void:
	if is_equal_approx(abs(global_rotation_degrees), 180) == false:
		if has_node("Sprite/Hitbox/UpsideDownExtension"):
			$Sprite/Hitbox/UpsideDownExtension.queue_free()
	
	if not is_sent_enemy:
		$Timer.start()

func _physics_process(delta: float) -> void:
	if is_sent_enemy:
		# Gravity + collision like Goomba, but no horizontal movement
		apply_enemy_gravity(delta)
		velocity.x = 0
		move_and_slide()

func on_timeout() -> void:
	if is_sent_enemy:
		return
		
	var player = get_tree().get_first_node_in_group("Players")
	if plant_direction < 2:
		if abs(player.global_position.x - global_position.x) >= player_range:
			$Animation.play("Rise")
	elif (abs(player.global_position.y - global_position.y) >= player_range and abs(player.global_position.x - global_position.x) >= player_range * 2):
		$Animation.play("Rise")
