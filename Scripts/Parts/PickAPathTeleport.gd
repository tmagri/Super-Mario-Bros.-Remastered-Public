extends Node2D

@export var reset_pos := Vector2.ZERO

static var last_teleport_time := 0.0
const SMOKE_PARTICLE = preload("res://Scenes/Prefabs/Particles/SmokeParticle.tscn")

signal player_teleported

func on_player_entered(_player: Player) -> void:
	if get_child_count() <= 1:
		for i in get_tree().get_nodes_in_group("Players"):
			teleport_player(i)
		return
	for i in get_children():
		if i is PickAPathPoint:
			if not i.crossed:
				for x in get_tree().get_nodes_in_group("Players"):
					teleport_player(x)
				return
	queue_free()

func teleport_player(player: Player) -> void:
	if Global.is_teleporting: return
	Global.is_teleporting = true
	
	for i in get_children():
		if i is PickAPathPoint:
			i.crossed = false
	
	# Handle Mega Mario shrink before warp
	if player.has_mega_mushroom:
		player.on_mega_timeout()
		# Wait for the shrink animation to finish (approx 1s)
		# We check if it's still transforming to be safe
		while player.transforming:
			await get_tree().process_frame
	
	# Visual "Out"
	player.do_smoke_effect()
	player.hide()
	if player.state_machine:
		player.state_machine.transition_to("Freeze")
	
	await get_tree().create_timer(0.4, false).timeout
	
	Level.spawn_position_override = reset_pos
	LevelPersistance.reset_enemies()
	Global.transition_to_scene(get_tree().current_scene.scene_file_path, true)
	player_teleported.emit()
