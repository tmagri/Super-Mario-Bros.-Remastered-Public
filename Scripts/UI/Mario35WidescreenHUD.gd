extends Control

const MAX_DISPLAYED_PLAYERS = 34
var player_card_scene = preload("res://Scenes/Prefabs/UI/Mario35PlayerCard.tscn")
var cards := {} # id -> instance
var stat_cards := {} # name -> instance

@onready var left_grid = %LeftGrid
@onready var right_grid = %RightGrid

var current_card_size := Vector2(32, 40)

func _process(delta: float) -> void:
	if not visible: return
	
	# --- Resize Logic ---
	var vp_size = get_viewport_rect().size
	var target_game_width = 256.0
	var total_extra = max(vp_size.x - target_game_width, 0.0)
	var side_width = total_extra / 2.0
	
	var h_sep = 2.0 # matches GridContainer h_separation
	var v_sep = 2.0 # matches GridContainer v_separation
	var card_w = max((side_width - h_sep * 2.0) / 3.0, 8.0)
	var card_h = max((vp_size.y - v_sep * 5.0) / 6.0, 8.0)
	current_card_size = Vector2(card_w, card_h)
	
	if %LeftPanel:
		%LeftPanel.visible = side_width >= 30.0
		%LeftPanel.custom_minimum_size.x = side_width
		%LeftPanel.size = Vector2(side_width, vp_size.y)
		%LeftPanel.position = Vector2.ZERO
		var vbox = %LeftPanel.get_node_or_null("VBox")
		if vbox:
			vbox.size = Vector2(side_width, vp_size.y)
			vbox.position = Vector2.ZERO
			
	if %RightPanel:
		%RightPanel.visible = side_width >= 30.0
		%RightPanel.custom_minimum_size.x = side_width
		%RightPanel.size = Vector2(side_width, vp_size.y)
		%RightPanel.position.x = vp_size.x - side_width
		%RightPanel.position.y = 0
		var vbox = %RightPanel.get_node_or_null("VBox")
		if vbox:
			vbox.size = Vector2(side_width, vp_size.y)
			vbox.position = Vector2.ZERO
		
	# --- Sync Players ---
	sync_players()

func sync_players() -> void:
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	var all_ids = Mario35Handler.player_statuses.keys()
	var others = []
	for id in all_ids:
		if id != my_id:
			others.append(id)
			
	others.sort_custom(func(a, b):
		var stat_a = Mario35Handler.player_statuses[a]
		var stat_b = Mario35Handler.player_statuses[b]
		
		var a_targeting_me = stat_a.get("target", 0) == my_id
		var b_targeting_me = stat_b.get("target", 0) == my_id
		
		if a_targeting_me and not b_targeting_me: return true
		if b_targeting_me and not a_targeting_me: return false
		
		var a_alive = stat_a.get("alive", true)
		var b_alive = stat_b.get("alive", true)
		if a_alive and not b_alive: return true
		if b_alive and not a_alive: return false
		
		var a_coins = stat_a.get("coins", 0)
		var b_coins = stat_b.get("coins", 0)
		if a_coins > b_coins: return true
		if b_coins > a_coins: return false
		
		return false
	)
	
	# Cap to MAX
	var display_ids = others.slice(0, MAX_DISPLAYED_PLAYERS)
	
	# --- Practice Mode Preview ---
	if Mario35Handler.is_practice:
		var needed = MAX_DISPLAYED_PLAYERS - display_ids.size()
		if needed > 0:
			for i in range(needed):
				display_ids.append(-100 - i)
	
	# Remove stale player cards
	var current_card_ids = cards.keys()
	for id in current_card_ids:
		if not id in display_ids:
			cards[id].queue_free()
			cards.erase(id)
			
	if not left_grid or not right_grid:
		return

	# --- Layout Injection ---
	# Left: 0, 1, [LEVEL], 2, 3...
	# Right: [ALIVE], 0, 1, 2...
	
	# Ensure stat cards exist
	for stat_name in ["LevelStat", "AliveStat"]:
		if not stat_cards.has(stat_name):
			var card = player_card_scene.instantiate()
			stat_cards[stat_name] = card
			# Initial add to left_grid, will be reparented if needed
			left_grid.add_child(card)
	
	# Update Stats
	var level_name = "X-X"
	if is_instance_valid(Global.current_level):
		level_name = str(Global.world_num) + "-" + str(Global.level_num)
	
	var camp = Global.current_campaign
	if camp == "SMB1": camp = "SMB"
	stat_cards["LevelStat"].setup_as_stat(camp, level_name)
	
	var alive_count = Mario35Handler.alive_count
	var total_count = Mario35Handler.player_statuses.size()
	stat_cards["AliveStat"].setup_as_stat("", "%d/%d" % [alive_count, total_count])

	# Placement Logic
	for i in range(18): # Left Grid
		var target_node = null
		if i == 2:
			target_node = stat_cards["LevelStat"]
		else:
			var p_idx = i if i < 2 else i - 1
			if p_idx < display_ids.size():
				var pid = display_ids[p_idx]
				target_node = _get_or_create_player_card(pid)
		
		if target_node:
			if target_node.get_parent() != left_grid:
				target_node.reparent(left_grid)
			left_grid.move_child(target_node, i)
			target_node.custom_minimum_size = current_card_size
			_update_card_data(target_node, target_node.get_meta("player_id", 0) if target_node.has_meta("player_id") else 0)

	for i in range(18): # Right Grid
		var target_node = null
		if i == 0:
			target_node = stat_cards["AliveStat"]
		else:
			var p_idx = 17 + (i - 1)
			if p_idx < display_ids.size():
				var pid = display_ids[p_idx]
				target_node = _get_or_create_player_card(pid)
		
		if target_node:
			if target_node.get_parent() != right_grid:
				target_node.reparent(right_grid)
			right_grid.move_child(target_node, i)
			target_node.custom_minimum_size = current_card_size
			_update_card_data(target_node, target_node.get_meta("player_id", 0) if target_node.has_meta("player_id") else 0)

func _get_or_create_player_card(pid: int) -> Control:
	if cards.has(pid):
		return cards[pid]
	var card = player_card_scene.instantiate()
	card.set_meta("player_id", pid)
	cards[pid] = card
	return card

func _update_card_data(card: Control, pid: int) -> void:
	if pid == 0: return # Stat card
	
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	var data = {}
	var is_targeting_me = false
	
	if pid < -90:
		data = { "name": "CPU-%02d" % (abs(pid) - 99), "alive": true, "coins": (abs(pid) * 3) % 99 }
		if (abs(pid) % 5) == 0: is_targeting_me = true
	else:
		if not Mario35Handler.player_statuses.has(pid): return
		data = Mario35Handler.player_statuses[pid]
		is_targeting_me = data.get("target", 0) == my_id
	
	if card.has_method("setup"): card.setup(data)
	if card.has_method("update_state"): card.update_state(data.get("alive", true), data.get("coins", 0), is_targeting_me)
