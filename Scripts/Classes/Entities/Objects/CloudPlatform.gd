extends AnimatableBody2D

var active := false
var destroyed := false
var destroy_velocity := Vector2.ZERO
var destroy_rotation := 0.0

@onready var starting_position := global_position

func _physics_process(delta: float) -> void:
	if destroyed:
		destroy_velocity.y += Global.entity_gravity * delta * 50
		global_position += destroy_velocity * delta
		rotation += destroy_rotation * delta
		if global_position.y > 480:
			queue_free()
		return
		
	if active:
		global_position.x += 48 * delta

func on_player_entered(player: Player) -> void:
	if player.velocity.y > -player.calculate_speed_param("FALL_GRAVITY"):
		active = true

func destroy_platform(dir: float) -> void:
	if destroyed: return
	destroyed = true
	destroy_velocity = Vector2(dir * 200, -300)
	destroy_rotation = dir * 10.0
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	AudioManager.play_sfx("kick", global_position)

func reset() -> void:
	global_position = starting_position
	reset_physics_interpolation()
	active = false
