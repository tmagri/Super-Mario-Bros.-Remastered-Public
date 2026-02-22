extends PowerUpState

var superball_amount := 0
var auto_fire_cooldown := 0.0
const AUTO_FIRE_DELAY := 0.5 # Seconds between auto-superballs
const SUPERBALL = preload("res://Scenes/Prefabs/Entities/Items/SuperballProjectile.tscn")
func update(delta: float) -> void:
	if delta <= 0: return
	
	# Tick auto-fire cooldown
	if auto_fire_cooldown > 0:
		auto_fire_cooldown -= delta

	# Manual Fire
	if Global.player_action_just_pressed("action", player.player_id) and superball_amount < 2 and player.state_machine.state.name == "Normal":
		throw_superball()
		
	# Assist Mode Auto Fire (with cooldown)
	elif Global.assist_mode and superball_amount < 2 and player.state_machine.state.name == "Normal" and auto_fire_cooldown <= 0:
		check_auto_fire()

func check_auto_fire() -> void:
	var my_pos = player.global_position
	var facing = player.direction
	var is_athletic = Global.level_theme == "Skyland"
	
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy): continue
		if "dead" in enemy and enemy.dead: continue
		
		# Skip enemies that aren't visible (hidden in pipes, etc.)
		if not enemy.visible: continue
		
		# Skip enemies whose hitbox isn't active (Piranha Plants hiding in pipes, etc.)
		var hitbox_active = false
		if enemy.has_node("Sprite/Hitbox"):
			hitbox_active = enemy.get_node("Sprite/Hitbox").monitoring
		elif enemy.has_node("Hitbox"):
			hitbox_active = enemy.get_node("Hitbox").monitoring
		else:
			hitbox_active = true # No hitbox node found, assume targetable
		
		if not hitbox_active: continue
		
		# Skip winged Koopas (Paratroopers) on Athletic stages — they're used as platforms
		if is_athletic and "winged" in enemy and enemy.winged:
			continue
		
		# Check range and direction
		var dist_vec = enemy.global_position - my_pos
		if abs(dist_vec.x) < 160 and abs(dist_vec.y) < 64:
			if sign(dist_vec.x) == facing:
				throw_superball()
				auto_fire_cooldown = AUTO_FIRE_DELAY
				break

func throw_superball() -> void:
	var node = SUPERBALL.instantiate()
	node.character = player.character
	node.global_position = player.global_position - Vector2(-4 * player.direction, 16 * player.gravity_vector.y)
	node.direction = player.direction
	node.velocity = Vector2(150 * player.direction, 150)
	player.call_deferred("add_sibling", node)
	superball_amount += 1
	node.tree_exited.connect(func(): superball_amount -= 1)
	AudioManager.play_sfx("superball", player.global_position)
	player.attacking = true
	await get_tree().create_timer(0.1, false).timeout
	player.attacking = false
