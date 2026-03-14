extends AnimatableBody2D

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

	if $PlayerDetect.get_overlapping_areas().any(is_player):
		var speed_mult = 1.0
		var player = get_tree().get_first_node_in_group("Players")
		if is_instance_valid(player) and player.has_mega_mushroom:
			speed_mult = 2.5
		position.y += 96 * speed_mult * delta

func destroy_platform(dir: float) -> void:
	if destroyed: return
	destroyed = true
	destroy_velocity = Vector2(dir * 200, -300)
	destroy_rotation = dir * 10.0
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	AudioManager.play_sfx("kick", global_position)

func is_player(area: Area2D) -> bool:
	if area.owner is Player:
		return area.owner.is_on_floor() and area.owner.global_position.y - 4 <= global_position.y
	return false
