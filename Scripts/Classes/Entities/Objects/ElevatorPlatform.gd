extends AnimatableBody2D

@export var vertical_direction := 1
const MOVE_SPEED := 50
@export var top := -244
@export var bottom := 64

var destroyed := false
var destroy_velocity := Vector2.ZERO
var destroy_rotation := 0.0

func _ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	if destroyed:
		destroy_velocity.y += Global.entity_gravity * delta * 50
		global_position += destroy_velocity * delta
		rotation += destroy_rotation * delta
		if global_position.y > 480:
			queue_free()
		return
		
	var speed_mult = 1.0
	var player = get_tree().get_first_node_in_group("Players")
	if is_instance_valid(player) and player.is_on_floor():
		# Check if player is standing on this platform
		var dx = abs(player.global_position.x - global_position.x)
		var dy = player.global_position.y - global_position.y
		if dx < 32 and dy > -8 and dy < 4:
			if player.has_mega_mushroom:
				speed_mult = 2.0 if vertical_direction == 1 else 0.2
	
	global_position.y += (MOVE_SPEED * speed_mult * delta) * vertical_direction
	
	# Wrap around without creating a velocity spike in AnimatableBody2D.
	# Directly setting global_position causes a huge delta that the physics
	# engine interprets as velocity, pushing the player. Use PhysicsServer2D
	# to teleport the body's transform without affecting velocity computation.
	if global_position.y > bottom or global_position.y < top:
		var wrapped_y = wrapf(global_position.y, top, bottom)
		var new_transform = Transform2D(global_transform.x, global_transform.y, Vector2(global_position.x, wrapped_y))
		PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, new_transform)
		global_transform = new_transform
		reset_physics_interpolation()

func destroy_platform(dir: float) -> void:
	if destroyed: return
	destroyed = true
	# Give it a "knock-out" toss
	destroy_velocity = Vector2(dir * 200, -300)
	destroy_rotation = dir * 10.0
	# Disable collision safely
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	# Play a kick/break sound
	AudioManager.play_sfx("kick", global_position)
