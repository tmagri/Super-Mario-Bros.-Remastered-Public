extends Node

signal time_changed(new_time)
signal game_started
signal game_over(winner_id)
signal incoming_enemy(enemy_type)
signal incoming_item_roulette
signal enemy_spawned(enemy_type) # New signal for HUD sync
signal target_changed(new_target_type) # 0: Random, 1: Lowest Time, 2: Attackers, 3: Most Coins
signal player_status_changed

const MIN_TIME = 0
const DEFAULT_START_TIME = 35
const DEFAULT_MAX_TIME = 400
const COMBO_TIME_REWARDS = [2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15] # Seconds added per combo level

var game_active := false
var current_time := 0.0
var max_time := DEFAULT_MAX_TIME
var start_time := DEFAULT_START_TIME

var coins: int:
	get:
		return Global.coins
	set(value):
		Global.coins = value
		# Emit signal if needed for HUD update

# Settings
enum GameVersion { SMB1, SMBLL, SMBANN, SMBS, RANDOM }
var game_version := GameVersion.SMB1
var allow_all_levels := true
var item_pool_mode := 0 # 0: STANDARD, 1: CLASSIC, 2: REMASTERED
var physics_mode := 0 # 0: REMASTERED, 1: CLASSIC
var game_seed := 0
var rng = RandomNumberGenerator.new()

# Targeting
enum TargetMode { RANDOM, LOWEST_TIME, ATTACKERS, MOST_COINS }
var current_target_mode := TargetMode.RANDOM
var current_target_id := 0

var coin_roulette_active := false
var enemy_queue: Array[String] = []
var spawn_timer := 0.0
const SPAWN_INTERVAL = 3.0 # Seconds between spawns

# Player status tracking
# Player status tracking
var player_statuses := {} # peer_id -> { "name": String, "alive": bool, "rank": int }
var alive_count := 0
var last_known_stats := {} # peer_id -> { "time": int, "coins": int, "target": int }
var stat_broadcast_timer := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Mario35Network.player_disconnected.connect(_on_player_disconnected)

func _process(delta: float) -> void:
	if not game_active:
		return
		
	# Decrease timer
	var old_int_time = int(current_time)
	current_time -= delta
	
	if Global.debug_mode and current_time < 1.0:
		if int(current_time) == 0:  # Only print once when it clamps
			print("[M35] DEBUG MODE: Clamping time at 1.0")
		current_time = 1.0
	
	# Constantly override Global.time to ensure personal timer is source of truth
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		Global.time = int(current_time)
		Global.can_time_tick = false
	
	if int(current_time) != old_int_time:
		time_changed.emit(int(current_time))
		# Force update Global.time for UI
		Global.time = int(current_time)
	

	
	if current_time <= 0:
		_on_timeout()
		
	# Spawn enemy logic
	if not enemy_queue.is_empty():
		spawn_timer -= delta
		if spawn_timer <= 0:
			spawn_from_queue()
			spawn_timer = SPAWN_INTERVAL
		
		
	# Periodic stat broadcast (1Hz)
	stat_broadcast_timer -= delta
	if stat_broadcast_timer <= 0:
		stat_broadcast_timer = 1.0
		Mario35Network.broadcast_stats(int(current_time), coins, current_target_id)
		# Also re-evaluate target if auto-targeting logic requires it
		if current_target_mode != TargetMode.RANDOM:
			update_target()

func start_game(time_setting: int = DEFAULT_START_TIME, max_time_setting: int = DEFAULT_MAX_TIME) -> void:
	print("[M35] start_game called, debug_self_attack = ", Global.debug_mode)
	start_time = time_setting
	max_time = max_time_setting
	current_time = float(start_time)
	game_active = true
	coins = 0
	Global.lives = 1 # Start with 1 life in BR
	
	# Disable pausing in Battle Royale (unless debug mode)
	if Global.debug_mode:
		Global.can_pause = true
	else:
		Global.can_pause = false
	
	if game_seed == 0:
		game_seed = randi()
	rng.seed = game_seed
	
	# Initialize player statuses
	player_statuses = {}
	for id in Mario35Network.players:
		player_statuses[id] = {
			"name": Mario35Network.players[id].get("name", "Player %d" % id),
			"alive": true,
			"rank": 0
		}
	alive_count = player_statuses.size()
	
	game_started.emit()
	time_changed.emit(int(current_time))
	print("[M35] game started, debug_self_attack = ", Global.debug_mode)

func add_time(amount: int) -> void:
	current_time += amount
	if current_time > max_time:
		current_time = float(max_time)
	time_changed.emit(int(current_time))

func add_item_time_bonus() -> void:
	add_time(15) # Fixed bonus for duplicate powerup

func _on_timeout() -> void:
	if not game_active: return
	var player = get_tree().get_first_node_in_group("Players")
	if is_instance_valid(player):
		player.die() # This will trigger on_local_player_death() via Player.gd hook

func on_local_player_death() -> void:
	if not game_active: return
	
	var my_id = multiplayer.get_unique_id()
	if my_id in player_statuses and player_statuses[my_id].alive:
		var rank = alive_count
		player_statuses[my_id].alive = false
		player_statuses[my_id].rank = rank
		alive_count -= 1
		
		# Sync death to others
		Mario35Network.notify_death(my_id, rank)
		player_status_changed.emit()
		_check_win_condition()

func sync_death(id: int, rank: int) -> void:
	if id in player_statuses and player_statuses[id].alive:
		player_statuses[id].alive = false
		player_statuses[id].rank = rank
		alive_count -= 1
		player_status_changed.emit()
		_check_win_condition()

func _check_win_condition() -> void:
	if not game_active: return
	
	if alive_count <= 1:
		var winner_id = 0
		for id in player_statuses:
			if player_statuses[id].alive:
				winner_id = id
				player_statuses[id].rank = 1
				break
		
		game_active = false
		game_over.emit(winner_id)
		
		# Delayed return to lobby
		await get_tree().create_timer(5.0).timeout
		get_tree().paused = false
		Global.transition_to_scene("res://Scenes/Levels/TitleScreen.tscn")

func _on_player_disconnected(id: int) -> void:
	if id in player_statuses and player_statuses[id].alive:
		# Treat disconnect as death for ranking
		sync_death(id, alive_count)
	
	if id == current_target_id:
		update_target()

func add_time_with_combo(combo_level: int) -> void:
	var idx = clampi(combo_level, 0, COMBO_TIME_REWARDS.size() - 1)
	add_time(COMBO_TIME_REWARDS[idx])

func on_enemy_killed(enemy: Node, time_reward: int = 2) -> void:
	if not game_active:
		return
		
	# Special case: don't double add if Player.gd already added via combo?
	# Actually, Player.gd adds combo time, and this sends the enemy.
	# We'll use the reward if provided.
	add_time(time_reward)
	
	# Determine enemy type
	var type = enemy.scene_file_path
	incoming_enemy.emit(type) # Update HUD (local visual feedback of what you sent?)
	
	# Send to target
	if Global.debug_mode:
		# Self-attack at reduced rate (50%)
		if randf() < 0.5:
			receive_enemy(type)
	elif current_target_id != 0:
		Mario35Network.send_enemy.rpc_id(current_target_id, type)
	else:
		# If no target (e.g. initial random), pick one?
		update_target()
		if current_target_id != 0:
			Mario35Network.send_enemy.rpc_id(current_target_id, type)

func receive_enemy(type: String) -> void:
	# Add to incoming queue
	enemy_queue.append(type)
	# Emit signal for HUD
	incoming_enemy.emit(type)

func spawn_from_queue() -> void:
	if enemy_queue.is_empty(): return
	var type = enemy_queue.pop_front()
	
	if not is_instance_valid(Global.current_level): return
	var player = get_tree().get_first_node_in_group("Players")
	if not is_instance_valid(player): return
	
	var scn = load(type)
	if scn:
		# Shell Replacement Logic
		if "Shell" in type:
			if "GreenKoopa" in type:
				scn = load("res://Scenes/Prefabs/Entities/Enemies/GreenKoopaTroopa.tscn")
				type = scn.resource_path # Update type for signal
			elif "RedKoopa" in type:
				scn = load("res://Scenes/Prefabs/Entities/Enemies/RedKoopaTroopa.tscn")
				type = scn.resource_path
			elif "Buzzy" in type:
				scn = load("res://Scenes/Prefabs/Entities/Enemies/BuzzyBeetle.tscn")
				type = scn.resource_path
	
		var enemy = scn.instantiate()
		
		# Spawn Position Logic
		var spawn_offset = Vector2(320, -128) # Default: Ahead and mid-air
		
		if "Lakitu" in type:
			# Lakitu needs to be high up to stay in the sky
			spawn_offset = Vector2(320, -220) 
		elif "Bowser" in type:
			# Bowser should be closer to the ground so he doesn't fall too far / get stuck
			spawn_offset = Vector2(320, -48)
		elif "CheepCheep" in type or "Blooper" in type:
			# If water level, random height? 
			# For now, default is okay, gravity/swim logic handles them.
			spawn_offset = Vector2(320, randf_range(-180, -32))
			
		enemy.global_position = player.global_position + spawn_offset
		
		# Raycast to find ground? Or just let them fall from a safe height ahead.
		# Ideally we want them to "appear from the right". 
		# If we spawn them high up ahead, they will fall into view as the player approaches.
		
		if enemy is Enemy:
			enemy.is_sent_enemy = true
		Global.current_level.add_child(enemy)
		enemy_spawned.emit(type)

func get_attackers_count() -> int:
	var count = 0
	var my_id = multiplayer.get_unique_id()
	for id in last_known_stats:
		if last_known_stats[id].get("target", 0) == my_id:
			count += 1
	return count


func try_use_item() -> void:
	spin_roulette()
	
func spend_coins(amount: int) -> bool:
	if coins >= amount:
		coins -= amount
		return true
	return false

func spin_roulette() -> void:
	if coin_roulette_active: return
	if not spend_coins(20): return
	
	coin_roulette_active = true
	incoming_item_roulette.emit()
	
	var items = ["Mushroom", "Flower", "Star"]
	match item_pool_mode:
		0: items.append("Lucky Star")
		2: items.append_array(["Lucky Star", "Wing", "Hammer", "P-Switch"])
		
	var picked = items.pick_random()
	
	# Wait for animation (handled by HUD mostly, but logic waits here)
	await get_tree().create_timer(3.0).timeout
	
	apply_item(picked)
	coin_roulette_active = false

func apply_item(item: String) -> void:
	var player = get_tree().get_first_node_in_group("Players")
	if not is_instance_valid(player):
		return
		
	match item:
		"Mushroom":
			if player.power_state.state_name == "Small":
				player.power_up_animation("Big")
			else:
				add_time(10)
		"Flower":
			player.power_up_animation("Fire")
		"Star":
			player.super_star()
		"Lucky Star":
			# Standard SMB35 POW effect: Kills all enemies on screen
			get_tree().call_group("Enemies", "die_from_object", player)
			AudioManager.play_sfx("stomp")
		"Wing":
			player.wing_get()
		"Hammer":
			player.hammer_get()
		"P-Switch":
			Global.activate_p_switch()

func cycle_target_mode(direction: int) -> void:
	var modes = TargetMode.values()
	var new_index = (int(current_target_mode) + direction) % modes.size()
	current_target_mode = TargetMode.values()[new_index]
	target_changed.emit(current_target_mode)
	update_target()

func update_target() -> void:
	var potential_targets = []
	for id in player_statuses:
		if id != multiplayer.get_unique_id() and player_statuses[id].alive:
			potential_targets.append(id)
			
	if potential_targets.is_empty():
		current_target_id = 0
		return
		
	match current_target_mode:
		TargetMode.RANDOM:
			# If current target is invalid or dead, pick new
			if not current_target_id in potential_targets:
				current_target_id = potential_targets.pick_random()
				
		TargetMode.LOWEST_TIME:
			var lowest_id = potential_targets[0]
			var lowest_val = 9999
			for id in potential_targets:
				var time = last_known_stats.get(id, {}).get("time", 999)
				if time < lowest_val:
					lowest_val = time
					lowest_id = id
			current_target_id = lowest_id
			
		TargetMode.MOST_COINS:
			var highest_id = potential_targets[0]
			var highest_val = -1
			for id in potential_targets:
				var c = last_known_stats.get(id, {}).get("coins", 0)
				if c > highest_val:
					highest_val = c
					highest_id = id
			current_target_id = highest_id
			
		TargetMode.ATTACKERS:
			# Find who represents YOU as target
			var attackers = []
			var my_id = multiplayer.get_unique_id()
			for id in potential_targets:
				if last_known_stats.get(id, {}).get("target", 0) == my_id:
					attackers.append(id)
			
			if not attackers.is_empty():
				current_target_id = attackers.pick_random()
			else:
				# Fallback to random if no attackers
				if not current_target_id in potential_targets:
					current_target_id = potential_targets.pick_random()

func receive_stats(id: int, time: int, coins: int, target: int) -> void:
	last_known_stats[id] = {"time": time, "coins": coins, "target": target}


# Call this when hosting to distribute settings
func get_settings_dictionary() -> Dictionary:
	if game_seed == 0:
		game_seed = randi()
		
	return {
		"start_time": start_time,
		"max_time": max_time,
		"allow_all_levels": allow_all_levels,
		"item_pool_mode": item_pool_mode,
		"physics_mode": physics_mode,
		"game_seed": game_seed,
		"game_version": game_version
	}

func apply_settings(settings: Dictionary) -> void:
	if "start_time" in settings: start_time = settings.start_time
	if "max_time" in settings: max_time = settings.max_time
	if "allow_all_levels" in settings: allow_all_levels = settings.allow_all_levels
	if "item_pool_mode" in settings: item_pool_mode = settings.item_pool_mode
	if "physics_mode" in settings: physics_mode = settings.physics_mode
	if "game_seed" in settings: game_seed = settings.game_seed
	if "game_version" in settings: game_version = settings.game_version

func get_next_level_path() -> String:
	# Determine game version prefix
	var version_enum = game_version
	if version_enum == GameVersion.RANDOM:
		version_enum = rng.randi_range(0, 3) # Pick one of the four versions
	
	var prefix = "SMB1"
	var w_range = [1, 8]
	var l_range = [1, 4]
	
	match version_enum:
		GameVersion.SMB1:
			prefix = "SMB1"
		GameVersion.SMBLL:
			prefix = "SMBLL"
			w_range = [1, 13] # SMBLL has up to World D (13)
		GameVersion.SMBANN:
			prefix = "SMBANN"
		GameVersion.SMBS:
			prefix = "SMBS"
	
	var w = rng.randi_range(w_range[0], w_range[1])
	var l = rng.randi_range(l_range[0], l_range[1])
	
	# Special case for SMBLL folder naming if World > 8
	var world_str = str(w)
	var level_str = "%d-%d" % [w, l]
	
	return "res://Scenes/Levels/%s/World%s/%s.tscn" % [prefix, world_str, level_str]
