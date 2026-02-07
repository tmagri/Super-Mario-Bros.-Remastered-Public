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

var game_active := false
var current_time := 0.0
var max_time := DEFAULT_MAX_TIME
var start_time := DEFAULT_START_TIME

var coins := 0

# Settings
var allow_all_levels := true
var item_pool_mode := 0 # 0: All, 1: Limited
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
func _ready() -> void:
	Mario35Network.player_disconnected.connect(_on_player_disconnected)

func _process(delta: float) -> void:
	if not game_active:
		return
		
	# Decrease timer
	var old_int_time = int(current_time)
	current_time -= delta
	
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
	
	if game_seed == 0:
		game_seed = randi()
	rng.seed = game_seed
	
	game_started.emit()

func add_time(amount: int) -> void:
	current_time += amount
	if current_time > max_time:
		current_time = float(max_time)
	time_changed.emit(int(current_time))

func _on_timeout() -> void:
	game_active = false
	# Handle death logic here
	# Global.player.die() or something similar

func _on_player_disconnected(id: int) -> void:
	if id == current_target_id:
		update_target()

func on_enemy_killed(enemy: Node) -> void:
	if not game_active:
		return
		
	add_time(2) # Configurable?
	
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
	var items = ["Mushroom", "Flower", "Star", "POW"]
	# "Wing" removed for now as it might break level design if not careful, but requested.
	# Adding Wing back if user wants standard SMB35 items.
	# User requirement: "Available items: Mushroom, Flower, Lucky Star, Wing, P-Switch"
	items.append("Wing")
	
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
				# Healing/Score if already big? SMB35 gives time?
				add_time(10)
		"Flower":
			player.power_up_animation("Fire")
		"Star":
			player.super_star()
		"Wing":
			player.wing_get()
		"POW":
			Global.activate_p_switch() # Or clear screen enemies logic
			# Standard SMB35 POW kills all enemies on screen.
			# activate_p_switch does coin blocks.
			# I should kill enemies too.
			get_tree().call_group("Enemies", "die_from_object", player)

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
		"game_seed": game_seed
	}

func apply_settings(settings: Dictionary) -> void:
	if "start_time" in settings: start_time = settings.start_time
	if "max_time" in settings: max_time = settings.max_time
	if "allow_all_levels" in settings: allow_all_levels = settings.allow_all_levels
	if "item_pool_mode" in settings: item_pool_mode = settings.item_pool_mode
	if "game_seed" in settings: game_seed = settings.game_seed

func get_next_level_path() -> String:
	# Randomize level
	# Assuming SMB1 campaign
	var w = rng.randi_range(1, 8)
	var l = rng.randi_range(1, 4)
	return "res://Scenes/Levels/SMB1/World%d/%d-%d.tscn" % [w, w, l]
