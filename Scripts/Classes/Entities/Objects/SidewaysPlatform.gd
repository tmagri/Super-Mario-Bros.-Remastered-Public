extends AnimatableBody2D

var destroyed := false
var destroy_velocity := Vector2.ZERO
var destroy_rotation := 0.0

func _physics_process(delta: float) -> void:
	if destroyed:
		destroy_velocity.y += Global.entity_gravity * delta * 50
		global_position += destroy_velocity * delta
		rotation += destroy_rotation * delta
		if global_position.y > 480:
			queue_free()
		return

func destroy_platform(dir: float) -> void:
	if destroyed: return
	destroyed = true
	
	# Unparent from animated parent to allow free falling
	var old_global_pos = global_position
	var level = get_tree().current_scene
	if level and get_parent() != level:
		# If parent has AnimationPlayer, stop it
		if get_parent().has_node("AnimationPlayer"):
			get_parent().get_node("AnimationPlayer").stop()
			
		get_parent().remove_child(self)
		level.add_child(self)
		global_position = old_global_pos

	sync_to_physics = false
	z_index = 10 
	
	# Give it a "knock-out" toss
	destroy_velocity = Vector2(dir * 200, -300)
	destroy_rotation = dir * 10.0
	# Disable collision safely
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	# Play a kick/break sound
	AudioManager.play_sfx("kick", global_position)
