extends Node

signal time_changed(new_time)
signal game_started
signal game_over(winner_id)
signal incoming_enemy(enemy_type)
signal incoming_item_roulette
signal target_changed(new_target_type) # 0: Random, 1: Lowest Time, 2: Attackers, 3: Most Coins

const MIN_TIME = 0
const DEFAULT_START_TIME = 35
const DEFAULT_MAX_TIME = 400
const COMBO_TIME_REWARDS = [2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15] # Seconds added per combo level

var game_active := false
var current_time := 0.0
var max_time := DEFAULT_MAX_TIME
var start_time := DEFAULT_START_TIME

var coins := 0

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
var player_statuses := {} # peer_id -> { "name": String, "alive": bool, "rank": int }
var alive_count := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Mario35Network.player_disconnected.connect(_on_player_disconnected)

func _process(delta: float) -> void:
	if not game_active:
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
	
	if current_time <= 0:
		_on_timeout()
		
	# Spawn enemy logic
	if not enemy_queue.is_empty():
		spawn_timer -= delta
		if spawn_timer <= 0:
			spawn_from_queue()
			spawn_timer = SPAWN_INTERVAL
		
	# Speed up music if low time (logic to be added via AudioManager interaction)

func start_game(time_setting: int = DEFAULT_START_TIME, max_time_setting: int = DEFAULT_MAX_TIME) -> void:
	start_time = time_setting
	max_time = max_time_setting
	current_time = float(start_time)
	game_active = true
	coins = 0
	Global.can_pause = false # Disable pausing in Battle Royale
	
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

func add_time(amount: int) -> void:
	current_time += amount
	if current_time > max_time:
		current_time = float(max_time)
	time_changed.emit(int(current_time))

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
		_check_win_condition()

func sync_death(id: int, rank: int) -> void:
	if id in player_statuses and player_statuses[id].alive:
		player_statuses[id].alive = false
		player_statuses[id].rank = rank
		alive_count -= 1
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

func _on_player_disconnected(id: int) -> void:
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
	if current_target_id != 0:
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
		var enemy = scn.instantiate()
		enemy.global_position = player.global_position + Vector2(randf_range(-64, 64), -180) # Spawn above
		enemy.modulate = Color(1, 1, 1, 0.6) # Ghost effect
		Global.current_level.add_child(enemy)


func try_use_item() -> void:
	if coin_roulette_active or Global.coins < 20:
		return
	
	Global.coins -= 20
	coin_roulette_active = true
	incoming_item_roulette.emit() # For HUD visuals
	
	# Roulette logic
	var items = ["Mushroom", "Flower", "Star"]
	match item_pool_mode:
		0: # STANDARD
			items.append("Lucky Star")
		1: # CLASSIC
			pass # Just Mushroom, Flower, Star
		2: # REMASTERED
			items.append_array(["Lucky Star", "Wing", "Hammer", "P-Switch"])
	
	var picked = items.pick_random()
	
	await get_tree().create_timer(3.0).timeout # Roulette spin time
	
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
	# Placeholder for actual targeting logic based on mode
	# Needs access to other players' states (time, coins, etc)
	# For now, just pick random if not self
	pass


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
