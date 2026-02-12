extends Node

signal time_changed(new_time)
signal game_started
signal game_over(winner_id)
signal incoming_enemy(enemy_type)
signal incoming_item_roulette
signal roulette_stopped(item: String)
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
var is_practice := false

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
var difficulty_mode := 0 # 0: FIRST QUEST, 1: SECOND QUEST
var game_seed := 0
var rng = RandomNumberGenerator.new()

# Targeting
enum TargetMode { RANDOM, LOWEST_TIME, ATTACKERS, MOST_COINS }
var current_target_mode := TargetMode.RANDOM
var current_target_id := 0

var coin_roulette_active := false
var current_roulette_item := ""
var is_timer_paused := false
var enemy_queue: Array[String] = []
var spawn_timer := 0.0
var session_points: Dictionary = {} # peer_id -> int (Persists between games)
var levels_played := 0 # Counter for randomization weighting
var last_level_path := "" # Prevent back-to-back repeats
const SPAWN_INTERVAL = 1.0 # Seconds between spawns (Faster for more pressure)

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
	if not game_active or is_timer_paused:
		return
		
	# Personal timer only ticks if alive
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	var is_alive = true
	if my_id in player_statuses:
		is_alive = player_statuses[my_id].alive
	
	if not is_alive:
		return
		
	# Decrease timer
	var old_int_time = int(current_time)
	current_time -= delta
	
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
		var my_kills = player_statuses.get(my_id, {}).get("kills", 0)
		Mario35Network.broadcast_stats(int(current_time), coins, current_target_id, my_kills)
		# Also re-evaluate target if auto-targeting logic requires it
		if current_target_mode != TargetMode.RANDOM:
			update_target()

func start_game(time_setting: int = DEFAULT_START_TIME, max_time_setting: int = DEFAULT_MAX_TIME) -> void:
	print("[M35] start_game called, is_practice = ", is_practice)
	start_time = time_setting
	max_time = max_time_setting
	current_time = float(start_time)
	game_active = true
	Global.second_quest = (difficulty_mode == 1)
	levels_played = 0
	last_level_path = ""
	Global.score = 0
	coins = 0
	Global.lives = 1 # Start with 1 life in BR
	
	# Disable pausing in Battle Royale (unless practice/debug mode)
	if is_practice or Global.debug_mode:
		Global.can_pause = true
	else:
		Global.can_pause = false
	
	if game_seed == 0:
		game_seed = randi()
	rng.seed = game_seed
	
	# Initialize player statuses
	player_statuses = {}
	last_known_stats = {} # Clear stale stats from previous match
	session_points = {} # Reset session points for a fresh match
	for id in Mario35Network.players:
		player_statuses[id] = {
			"name": Mario35Network.players[id].get("name", "Player %d" % id),
			"alive": true,
			"rank": 0,
			"kills": 0,
			"driver_score": 0
		}
		session_points[id] = 0
	alive_count = player_statuses.size()
	
	game_started.emit()
	time_changed.emit(int(current_time))
	print("[M35] game started, is_practice = ", is_practice)

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
		Mario35Network.notify_death.rpc(my_id, rank)
		player_status_changed.emit()
		_check_win_condition()

func sync_death(id: int, rank: int) -> void:
	if id in player_statuses and player_statuses[id].alive:
		player_statuses[id].alive = false
		player_statuses[id].rank = rank
		alive_count -= 1
		player_status_changed.emit()
		_check_win_condition()

var last_match_ranks := {} # peer_id -> rank

func _check_win_condition() -> void:
	if not game_active: return
	
	# Check if all players are eliminated OR if there's a last survivor (non-debug only)
	var should_end = false
	var winner_id = 0
	
	if alive_count == 0:
		# All players eliminated - end match
		should_end = true
	elif alive_count == 1 and not is_practice:
		# Last survivor in non-debug mode - end match
		should_end = true
		for id in player_statuses:
			if player_statuses[id].alive:
				winner_id = id
				player_statuses[id].rank = 1
				break
	
	if should_end:
		# Cache ranks and award points before ending game
		last_match_ranks = {}
		for id in player_statuses:
			last_match_ranks[id] = player_statuses[id].rank
		
		_award_placement_points()
		
		game_active = false
		game_over.emit(winner_id)
		
		# Delayed return to lobby (unless in debug mode)
		if is_practice:
			get_tree().paused = false
			Global.transition_to_scene("res://Scenes/UI/Mario35Lobby.tscn")
			return
			
		await get_tree().create_timer(5.0, false).timeout
		get_tree().paused = false
		Global.transition_to_scene("res://Scenes/UI/Mario35Lobby.tscn")

func _award_placement_points() -> void:
	var pts_table = [15, 12, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
	for id in player_statuses:
		var r = player_statuses[id].rank
		if r > 0 and r <= pts_table.size():
			var earned = pts_table[r - 1]
			session_points[id] = session_points.get(id, 0) + earned
			print("[M35] Player %s earned %d placement points (Rank %d)" % [player_statuses[id].name, earned, r])

func get_driver_score(id: int) -> float:
	if not id in player_statuses: return 0.0
	var s = player_statuses[id]
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	var c = coins if id == my_id else last_known_stats.get(id, {}).get("coins", 0)
	var k = s.kills
	
	# Score = (Kills * 10) + (Coins * 1) + (Survival Factor)
	var alive_factor = current_time * 0.1 if s.alive else 0.0
	return (k * 10.0) + (c * 1.0) + alive_factor

func _on_player_disconnected(id: int) -> void:
	if id in player_statuses and player_statuses[id].alive:
		# Treat disconnect as death for ranking
		sync_death(id, alive_count)
	
	if id == current_target_id:
		update_target()
	
	last_known_stats.erase(id)

func add_time_with_combo(combo_level: int) -> void:
	var idx = clampi(combo_level, 0, COMBO_TIME_REWARDS.size() - 1)
	add_time(COMBO_TIME_REWARDS[idx])

func on_enemy_killed(enemy: Node, time_reward: int = 2) -> void:
	if not game_active:
		return
	
	# Eliminated players cannot send enemies
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	if my_id in player_statuses:
		if not player_statuses[my_id].alive:
			return
		player_statuses[my_id].kills += 1
		player_status_changed.emit()
		
	# Special case: don't double add if Player.gd already added via combo?
	# Actually, Player.gd adds combo time, and this sends the enemy.
	# We'll use the reward if provided.
	add_time(time_reward)
	
	# Determine enemy type
	var type = enemy.scene_file_path
	incoming_enemy.emit(type) # Update HUD (local visual feedback of what you sent?)
	
	# Send to target
	if is_practice:
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
		# Ensure its spawned off right of view (e.g. 480px)
		# Set Y to 0 (ground level relative to player) for standard enemies
		var spawn_offset = Vector2(480, 0) 
		
		if "Lakitu" in type:
			# Lakitu needs to be high up to stay in the sky (approx 10 tiles above player)
			spawn_offset = Vector2(480, -160) 
		elif "Bowser" in type:
			# Bowser should be slightly above ground to fall safely
			spawn_offset = Vector2(480, -32)
		elif "LeapingCheepCheep" in type:
			# Leap from below the screen
			# Range from slightly behind player to well ahead
			spawn_offset = Vector2(randf_range(-64, 384), 240)
		elif "CheepCheep" in type or "Blooper" in type:
			# Aquatic enemies at random heights
			spawn_offset = Vector2(480, randf_range(-180, -32))
		elif "HammerBro" in type or "BulletBill" in type:
			# Hammer Bros and Bills usually have some air height
			spawn_offset = Vector2(480, -64)
			
		
		# Collision Check: Ensure not spawning in wall
		var target_pos = player.global_position + spawn_offset
		
		# Raycast for floor detection
		var needs_snapping = true
		if "Lakitu" in type or "BulletBill" in type or "CheepCheep" in type or "Blooper" in type or "LeapingCheepCheep" in type:
			needs_snapping = false
			
		if needs_snapping:
			var space_state = player.get_world_2d().direct_space_state
			var ray_params = PhysicsRayQueryParameters2D.create(target_pos, target_pos + Vector2(0, 320), 6) # Check down 20 tiles
			var result = space_state.intersect_ray(ray_params)
			
			if not result.is_empty():
				# Found ground, spawn there
				target_pos = result.position
			
			# Ensure we aren't spawning inside a block/wall at this position
			var point_params = PhysicsPointQueryParameters2D.new()
			point_params.collision_mask = 6 # Terrain/Blocks
			
			# If we are inside a wall, move up until we are free
			for i in range(16): # Check up to 16 tiles up
				point_params.position = target_pos - Vector2(0, 8) # Check slightly above point
				var hits = space_state.intersect_point(point_params, 1)
				if hits.is_empty():
					break
				target_pos.y -= 16
		
		enemy.global_position = target_pos
		
		# Visual feedback for sent enemies
		if enemy is Enemy or enemy.has_method("set_is_sent_enemy") or "is_sent_enemy" in enemy:
			enemy.is_sent_enemy = true
			
		Global.current_level.add_child(enemy)
		enemy_spawned.emit(type)

func get_attackers_count() -> int:
	var count = 0
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	for id in last_known_stats:
		# Only count attackers who are actually in the game and alive
		if id in player_statuses and player_statuses[id].alive:
			if last_known_stats[id].get("target", 0) == my_id:
				count += 1
	return count


func try_use_item() -> void:
	# Eliminated players cannot use items
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	if my_id in player_statuses and not player_statuses[my_id].alive:
		return
	
	if coin_roulette_active:
		stop_roulette()
	else:
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
	AudioManager.play_global_sfx("coin")
	
	var items = ["Mushroom", "Flower", "Star"]
	match item_pool_mode:
		0: items.append("Lucky Star")
		2: items.append_array(["Lucky Star", "Wing", "Hammer", "P-Switch"])
		
	current_roulette_item = items.pick_random()
	incoming_item_roulette.emit()
	
	# Auto-stop after 1.5 seconds if user doesn't stop it manually
	await get_tree().create_timer(1.5).timeout
	if coin_roulette_active:
		confirm_item()

func stop_roulette() -> void:
	if not coin_roulette_active: return
	confirm_item()

func confirm_item() -> void:
	if not coin_roulette_active: return
	coin_roulette_active = false
	
	roulette_stopped.emit(current_roulette_item)
	AudioManager.play_global_sfx("correct")
	
	# Short delay for HUD blinking effect before applying
	await get_tree().create_timer(0.5).timeout 
	
	apply_item(current_roulette_item)
	current_roulette_item = ""

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
			AudioManager.set_music_override(AudioManager.MUSIC_OVERRIDES.STAR, 1, false)
		"Lucky Star":
			# Standard SMB35 POW effect: Kills all enemies on screen
			get_tree().call_group("Enemies", "die_from_object", player)
			AudioManager.play_global_sfx("lucky_star")
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

func receive_stats(id: int, time: int, coins: int, target: int, kills: int) -> void:
	last_known_stats[id] = {"time": time, "coins": coins, "target": target, "kills": kills}
	# Also update player_statuses for leaderboard
	if id in player_statuses:
		player_statuses[id].kills = kills


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
		"game_version": game_version,
		"difficulty_mode": difficulty_mode
	}

func apply_settings(settings: Dictionary) -> void:
	if "start_time" in settings: start_time = settings.start_time
	if "max_time" in settings: max_time = settings.max_time
	if "allow_all_levels" in settings: allow_all_levels = settings.allow_all_levels
	if "item_pool_mode" in settings: item_pool_mode = settings.item_pool_mode
	if "physics_mode" in settings: physics_mode = settings.physics_mode
	if "game_seed" in settings: game_seed = settings.game_seed
	if "game_version" in settings: game_version = settings.game_version
	if "difficulty_mode" in settings: difficulty_mode = settings.difficulty_mode

func randomize_seed() -> void:
	game_seed = randi()
	print("[M35] New game seed generated: ", game_seed)

func get_next_level_path() -> String:
	# Determine game version prefix
	var version_enum = game_version
	if version_enum == GameVersion.RANDOM:
		# Randomize between the core three for "Mixed" feel
		version_enum = [GameVersion.SMB1, GameVersion.SMBLL, GameVersion.SMBS].pick_random()
	
	var max_w = 8
	var prefix = "SMB1"
	
	match version_enum:
		GameVersion.SMB1:
			prefix = "SMB1"
			max_w = 8
		GameVersion.SMBLL:
			prefix = "SMBLL"
			max_w = 13 # SMBLL has up to World D (13)
		GameVersion.SMBANN:
			prefix = "SMBANN"
			max_w = 8
		GameVersion.SMBS:
			prefix = "SMBS"
			max_w = 4 # Usually 4 worlds for special editions
	
	# --- World Selection with Weighting ---
	var w = 1
	# Favor earlier worlds in initial rounds
	if levels_played < 2: # First 2 levels
		# 80% chance for World 1-2
		if rng.randf() < 0.8:
			w = rng.randi_range(1, 2)
		else:
			w = rng.randi_range(1, max_w)
	elif levels_played < 5: # Levels 3-5
		# 60% chance for World 1-4
		if rng.randf() < 0.6:
			w = rng.randi_range(1, 4)
		else:
			w = rng.randi_range(1, max_w)
	else:
		# Standard randomization
		w = rng.randi_range(1, max_w)
	
	# --- Level Selection with Weighting ---
	# Priority for X-1 stages, especially in round 1
	var l = 1
	var l_weights = [0.25, 0.25, 0.25, 0.25] # Default uniform
	
	if levels_played == 0:
		# First level: zero chance for castle level
		l_weights = [0.90, 0.07, 0.03, 0.0] 
	elif levels_played < 10:
		# Early rounds: strongly favor X-1/X-2
		l_weights = [0.5, 0.3, 0.15, 0.05]
	else:
		# Later rounds: more balanced
		l_weights = [0.35, 0.25, 0.20, 0.20]
	
	var roll = rng.randf()
	var weight_sum = 0.0
	for i in range(l_weights.size()):
		weight_sum += l_weights[i]
		if roll <= weight_sum:
			l = i + 1
			break
	
	levels_played += 1
	var world_str = str(w)
	var level_str = "%d-%d" % [w, l]
	
	# Sync Global variables for HUD and transitions
	Global.world_num = w
	Global.level_num = l
	
	var level_path = "res://Scenes/Levels/%s/World%s/%s.tscn" % [prefix, world_str, level_str]
	
	# Prevent back-to-back repeats (retry up to 3 times)
	if level_path == last_level_path and levels_played > 1:
		for _retry in range(3):
			w = rng.randi_range(1, max_w)
			l = rng.randi_range(1, 4)
			world_str = str(w)
			level_str = "%d-%d" % [w, l]
			level_path = "res://Scenes/Levels/%s/World%s/%s.tscn" % [prefix, world_str, level_str]
			if level_path != last_level_path:
				break
		Global.world_num = w
		Global.level_num = l
	
	last_level_path = level_path
	print("[M35] Randomized next level (Round %d): %s" % [levels_played, level_path])
	return level_path
