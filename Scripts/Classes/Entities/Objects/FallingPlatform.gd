extends AnimatableBody2D

var destroyed := false
var destroy_velocity := Vector2.ZERO
var destroy_rotation := 0.0

func _ready() -> void:
	pass

var falling := false
var momentum_timer := 0.0

func _physics_process(delta: float) -> void:
	if destroyed:
		destroy_velocity.y += Global.entity_gravity * delta * 50
		global_position += destroy_velocity * delta
		rotation += destroy_rotation * delta
		if global_position.y > 480:
			queue_free()
		return

	var is_stood_on = $PlayerDetect.get_overlapping_areas().any(is_player)
	
	if is_stood_on:
		falling = true
		momentum_timer = 0.1 # Persistence for 0.1s
	
	if momentum_timer > 0:
		momentum_timer -= delta
		if momentum_timer <= 0:
			falling = false

	if falling:
		var speed_mult = 1.0
		var player = get_tree().get_first_node_in_group("Players")
		if is_instance_valid(player) and player.has_mega_mushroom:
			speed_mult = 4.0
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
		var player_node: Player = area.owner
		var height_diff = 4
		if player_node.has_mega_mushroom:
			height_diff = 16
		return player_node.is_actually_on_floor() and player_node.global_position.y - height_diff <= global_position.y
	return false
