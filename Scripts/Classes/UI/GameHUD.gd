class_name GameHUD
extends CanvasLayer

var current_chara := 0

static var character_icons := [preload("res://Assets/Sprites/Players/Mario/LifeIcon.json"),preload("res://Assets/Sprites/Players/Luigi/LifeIcon.json"), preload("res://Assets/Sprites/Players/Toad/LifeIcon.json"), preload("res://Assets/Sprites/Players/Toadette/LifeIcon.json")]

const RANK_COLOURS := {"F": Color.DIM_GRAY, "D": Color.WEB_MAROON, "C": Color.PALE_GREEN, "B": Color.DODGER_BLUE, "A": Color.RED, "S": Color.GOLD, "P": Color.PURPLE}

const ITEM_SPRITES := {
	"Mushroom": preload("res://Assets/Sprites/Items/SuperMushroom.png"),
	"Flower": preload("res://Assets/Sprites/Items/FireFlower.png"),
	"Star": preload("res://Assets/Sprites/Items/SuperStar.png"),
	"Lucky Star": preload("res://Assets/Sprites/Items/SuperStar.png"), # Placeholder/Tint
	"Wing": preload("res://Assets/Sprites/Items/Wings.png"),
	"Hammer": preload("res://Assets/Sprites/Items/Hammer.png"),
	"P-Switch": preload("res://Assets/Sprites/Items/PSwitch.png")
}

var delta_time := 0.0

func _ready() -> void:
	Global.level_theme_changed.connect(update_character_info)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		Mario35Handler.time_changed.connect(update_br_timer)
		Mario35Handler.target_changed.connect(update_br_target)
		Mario35Handler.target_changed.connect(update_br_target)
		Mario35Handler.incoming_enemy.connect(add_incoming_enemy_icon)
		Mario35Handler.incoming_item_roulette.connect(show_item_roulette)
		Mario35Handler.game_over.connect(_on_game_over)
		update_br_target(Mario35Handler.current_target_mode)
		update_br_leaderboard()
		
	# Ensure HUD is set up
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		setup_br_hud()

func setup_br_hud() -> void:
	if %BattleRoyaleHUD.has_node("ItemBox"): return
	
	var box = Panel.new()
	box.name = "ItemBox"
	box.size = Vector2(64, 64)
	box.position = Vector2(192 - 32, 24) # Center top below timer
	box.modulate = Color(1, 1, 1, 0.8)
	
	var coin_label = Label.new()
	coin_label.name = "CoinLabel"
	coin_label.text = "20"
	coin_label.position = Vector2(0, 48)
	coin_label.size = Vector2(64, 16)
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(coin_label)
	
	var icon = TextureRect.new()
	icon.name = "RouletteIcon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(48, 48)
	icon.position = Vector2(8, 0)
	icon.texture = preload("res://Assets/Sprites/Items/SuperMushroom.png") # Default
	icon.modulate = Color(0.5, 0.5, 0.5, 0.5) # Dimmed when inactive
	box.add_child(icon)
	
	%BattleRoyaleHUD.add_child(box)

func _process(delta: float) -> void:
	if not get_tree().paused and $Timer.paused:
		delta_time += delta
	if delta_time >= 1:
		delta_time -= 1
		on_timeout()
	handle_main_hud()
	handle_pausing()

func handle_main_hud() -> void:
	# Hide HUD completely in Battle Royale mode
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		$Main.visible = false
		$ModernHUD.visible = false
		%BattleRoyaleHUD.visible = self.visible # Only show if GameHUD itself is visible
		handle_br_input()
		
		# Update ItemBox coin count
		var item_box = %BattleRoyaleHUD.get_node_or_null("ItemBox")
		if item_box:
			var lbl = item_box.get_node("CoinLabel")
			lbl.text = "%d / 20" % Mario35Handler.coins
			if Mario35Handler.coins >= 20:
				lbl.modulate = Color.YELLOW
			else:
				lbl.modulate = Color.WHITE
		
		# Watch out warning
		%WarningLabel.visible = Mario35Handler.get_attackers_count() > 0
		
		# Spectating status
		var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
		if my_id in Mario35Handler.player_statuses:
			if not Mario35Handler.player_statuses[my_id].alive:
				%BRTimer.text = "ELIMINATED"
				%BRTimer.modulate = Color.GRAY
		
		return
	%BattleRoyaleHUD.visible = false
	
	$Main.visible = not Settings.file.visuals.modern_hud
	$ModernHUD.visible = Settings.file.visuals.modern_hud
	$Main/RedCoins.hide()
	$Main/CoinCount.show()
	%IGT.hide()
	%Combo.hide()
	$Timer.paused = Settings.file.difficulty.time_limit == 2
	$%Time.show()
	%Stopwatch.hide()
	%PB.hide()
	$Main/CoinCount/KeyCount.visible = KeyItem.total_collected > 0
	%KeyAmount.text = "*" + str(KeyItem.total_collected).pad_zeros(2)
	$Main.set_anchors_preset(Control.PRESET_CENTER_TOP if Settings.file.video.hud_size == 1 else Control.PRESET_TOP_WIDE, true)
	$ModernHUD.set_anchors_preset(Control.PRESET_CENTER_TOP if Settings.file.video.hud_size == 1 else Control.PRESET_TOP_WIDE, true)
	%Score.text = str(Global.score).pad_zeros(6)
	%CoinLabel.text = "*" + str(Global.coins).pad_zeros(2)
	if current_chara != Global.player_characters[0]:
		update_character_info()
	%CharacterIcon.get_node("Shadow").texture = %CharacterIcon.texture
	%ModernLifeCount.text = "*" + (str(Global.lives).pad_zeros(2) if Settings.file.difficulty.inf_lives == 0 else "∞")
	%CharacterIcon.visible = Global.current_game_mode != Global.GameMode.BOO_RACE
	%ModernLifeCount.visible = Global.current_game_mode != Global.GameMode.BOO_RACE
	var world_num := str(Global.world_num)
	if int(world_num) >= 10:
		world_num = ["A", "B", "C", "D"][int(world_num) % 10]
	elif int(world_num) < 1:
		world_num = " "
#	else:
#		print(Global.world_num)
	%LevelNum.text = world_num + "-" + str(Global.level_num)
	%Crown.visible = Global.second_quest
	%Time.text = " " + str(Global.time).pad_zeros(3)
	if Settings.file.difficulty.time_limit == 0:
		%Time.text = " ---"
	%Time.visible = get_tree().get_first_node_in_group("Players") != null
	handle_modern_hud()
	if Global.current_game_mode == Global.GameMode.CHALLENGE:
		handle_challenge_mode_hud()
	
	if DiscoLevel.in_disco_level:
		handle_disco_combo()
	
	if SpeedrunHandler.show_timer:
		handle_speedrun_timer()

func update_character_info() -> void:
	%CharacterName.text = tr(Player.CHARACTER_NAMES[int(Global.player_characters[0])])
	%CharacterIcon.get_node("ResourceSetterNew").resource_json = (character_icons[int(Global.player_characters[0])])
	current_chara = Global.player_characters[0]

func handle_modern_hud() -> void:
	$ModernHUD/TopLeft/RedCoins.hide()
	$ModernHUD/TopLeft/CoinCount.show()
	%ModernPB.hide()
	%ModernIGT.hide()
	%ModernCoinCount.text = "*" + str(Global.coins).pad_zeros(2)
	%ModernScore.text = str(Global.score).pad_zeros(9)
	%ModernTime.text = "⏲" + str(Global.time).pad_zeros(3)
	%ModernKeyCount.visible = KeyItem.total_collected > 0
	%ModernKeyAmount.text = "*" + str(KeyItem.total_collected).pad_zeros(2)
	if get_tree().get_first_node_in_group("Players") == null or Settings.file.difficulty.time_limit == 0:
		%ModernTime.text = "⏲---"

func handle_disco_combo() -> void:
	%Combo.show()
	%ComboAmount.text = "Combo*" + str(DiscoLevel.combo_amount)
	%ComboMeter.value = DiscoLevel.combo_meter
	%ComboMeter.modulate = Color.PURPLE if DiscoLevel.combo_breaks <= 0 else Color.WHITE
	%MedalIcon.region_rect.position.x = ("FDCBASP".find(DiscoLevel.current_rank) + 1) * 16

func handle_challenge_mode_hud() -> void:
	$Main/RedCoins.show()
	$ModernHUD/TopLeft/RedCoins.show()
	$ModernHUD/TopLeft/CoinCount.hide()
	$Main/CoinCount.hide()
	%ModernLifeCount.hide()
	%CharacterIcon.hide()
	var red_coins_collected = ChallengeModeHandler.current_run_red_coins_collected

	if Global.world_num > 8:
		return
	if Global.in_title_screen:
		red_coins_collected = int(ChallengeModeHandler.red_coins_collected[Global.world_num - 1][Global.level_num - 1])
	
	var idx := 0
	for i in [$Main/RedCoins/Coin1, $Main/RedCoins/Coin2, $Main/RedCoins/Coin3, $Main/RedCoins/Coin4, $Main/RedCoins/Coin5]:
		i.frame = int(ChallengeModeHandler.is_coin_collected(idx, red_coins_collected))
		idx += 1
	idx = 0
	for i in [$Main/RedCoins/Coin1Transparent, $Main/RedCoins/Coin2Transparent, $Main/RedCoins/Coin3Transparent, $Main/RedCoins/Coin4Transparent, $Main/RedCoins/Coin5Transparent]:
		i.visible = false
		if ChallengeModeHandler.is_coin_permanently_collected(idx) and not ChallengeModeHandler.is_coin_collected(idx, red_coins_collected):
			i.visible = true
			i.frame = 1
		idx += 1
	
	$Main/RedCoins/ScoreMedal.frame = 0
	$Main/RedCoins/ScoreMedalTransparent.visible = false
	var score_target = ChallengeModeHandler.CHALLENGE_TARGETS[Global.current_campaign][Global.world_num - 1][Global.level_num - 1]
	if Global.score >= score_target or ChallengeModeHandler.top_challenge_scores[Global.world_num - 1][Global.level_num - 1] >= score_target:
		$Main/RedCoins/ScoreMedal.frame = 1
	elif Global.score > 0 and (Global.score + (Global.time * 50)) >= score_target:
		$Main/RedCoins/ScoreMedalTransparent.frame = 1
		$Main/RedCoins/ScoreMedalTransparent.visible = true
	
	if ChallengeModeHandler.is_coin_collected(ChallengeModeHandler.CoinValues.YOSHI_EGG, red_coins_collected):
		$Main/RedCoins/YoshiEgg.frame = Global.level_num
	else:
		$Main/RedCoins/YoshiEgg.frame = 0
	
	handle_yoshi_radar()
	
	for i in $Main/RedCoins.get_children():
		i.get_node("Shadow").frame = i.frame
		i.get_node("Shadow").visible = i.visible
	for i in $ModernHUD/TopLeft/RedCoins.get_child_count():
		$ModernHUD/TopLeft/RedCoins.get_child(i).frame = $Main/RedCoins.get_child(i).frame
		$ModernHUD/TopLeft/RedCoins.get_child(i).visible = $Main/RedCoins.get_child(i).visible
		$ModernHUD/TopLeft/RedCoins.get_child(i).get_node("Shadow").frame = $Main/RedCoins.get_child(i).frame
		$ModernHUD/TopLeft/RedCoins.get_child(i).get_node("Shadow").visible = $Main/RedCoins.get_child(i).visible

func handle_yoshi_radar() -> void:
	if not is_instance_valid(Global.current_level) or ChallengeModeHandler.is_coin_collected(ChallengeModeHandler.CoinValues.YOSHI_EGG):
		%Radar.get_node("AnimationPlayer").play("RESET")
		%ModernRadar.get_node("AnimationPlayer").play("RESET")
		return
	
	var has_egg = false
	var egg_position = Vector2.ZERO
	var distance = 999
	for i in get_tree().get_nodes_in_group("Blocks"):
		if i.item != null:
			if i.item.resource_path == "res://Scenes/Prefabs/Entities/Items/YoshiEgg.tscn":
				has_egg = true
				egg_position = i.global_position
				break
	if has_egg:
		var player_position = get_tree().get_first_node_in_group("Players").global_position
		distance = (egg_position - player_position).length()
		
	%Radar.frame = Global.level_num
		
	if distance < 512:
		%Radar.get_node("AnimationPlayer").speed_scale = (250 / distance)
		%ModernRadar.get_node("AnimationPlayer").speed_scale = $Main/RedCoins/YoshiEgg/Radar/AnimationPlayer.speed_scale
		%Radar.get_node("AnimationPlayer").play("Flash")
		%ModernRadar.get_node("AnimationPlayer").play("Flash")
	elif ChallengeModeHandler.is_coin_permanently_collected(ChallengeModeHandler.CoinValues.YOSHI_EGG):
		%Radar.get_node("AnimationPlayer").play("AlwaysOn")
		%ModernRadar.get_node("AnimationPlayer").play("AlwaysOn")
	else:
		%Radar.get_node("AnimationPlayer").play("RESET")
		%ModernRadar.get_node("AnimationPlayer").play("RESET")

func handle_speedrun_timer() -> void:
	%Time.hide()
	%Stopwatch.show()
	%IGT.show()
	%IGT.modulate.a = int([Global.GameMode.MARATHON, Global.GameMode.MARATHON_PRACTICE].has(Global.current_game_mode) and get_tree().get_first_node_in_group("Players") != null)
	%IGT.text = "⏲" + (str(Global.time).pad_zeros(3))
	%ModernIGT.visible = %IGT.modulate.a == 1
	%ModernIGT.text = %IGT.text
	var late = SpeedrunHandler.timer > SpeedrunHandler.best_time
	var diff = SpeedrunHandler.best_time - SpeedrunHandler.timer
	%PB.visible = SpeedrunHandler.best_time > 0 and (SpeedrunHandler.timer > 0 or Global.current_level != null)
	%ModernPB.visible = %PB.visible
	var time_string = SpeedrunHandler.gen_time_string(SpeedrunHandler.format_time(SpeedrunHandler.timer))
	%Stopwatch.text = time_string
	%ModernTime.text = "⏲" + time_string
	%PB.text = ("+" if late else "-") + SpeedrunHandler.gen_time_string(SpeedrunHandler.format_time(diff))
	%PB.modulate = Color.RED if late else Color.GREEN
	%ModernPB.text = %PB.text
	%ModernPB.modulate = %PB.modulate

func handle_pausing() -> void:
	if get_tree().get_first_node_in_group("Players") != null and Global.can_pause and (Global.current_game_mode != Global.GameMode.LEVEL_EDITOR) and (Global.current_game_mode != Global.GameMode.MARIO_35):
		if get_tree().paused == false and Global.game_paused == false:
			# Battle Royale Pause Override
			if Global.current_game_mode == Global.GameMode.MARIO_35:
				# Pause is remapped to Target Change, so we don't open the menu here
				# UNLESS we are in debug mode
				if not Global.debug_mode:
					return
			
			if Input.is_action_just_pressed("pause"):
				activate_pause_menu()

func activate_pause_menu() -> void:
	match Global.current_game_mode:
		Global.GameMode.BOO_RACE:
			$BooRacePause.open()
		Global.GameMode.MARATHON:
			$MarathonPause.open()
		Global.GameMode.MARATHON_PRACTICE:
			$MarathonPause.open()
		_:
			$StoryPause.open()




const HURRY_UP = preload("res://Assets/Audio/BGM/HurryUp.mp3")

func on_timeout() -> void:
	if Global.can_time_tick and is_instance_valid(Global.current_level) and Settings.file.difficulty.time_limit > 0:
		if Global.level_editor != null:
			if Global.level_editor.current_state != LevelEditor.EditorState.PLAYTESTING:
				return
		if Global.time == 0:
			get_tree().call_group("Players", "time_up")
			return
		Global.time -= 1
		if Global.time == 100:
			AudioManager.set_music_override(AudioManager.MUSIC_OVERRIDES.TIME_WARNING, 5, true)

func update_br_timer(time: int) -> void:
	%BRTimer.text = str(time)
	if time <= 10:
		%BRTimer.modulate = Color.RED
	else:
		%BRTimer.modulate = Color.YELLOW

func update_br_target(mode: int) -> void:
	var text = "RANDOM"
	match mode:
		Mario35Handler.TargetMode.RANDOM: text = "RANDOM"
		Mario35Handler.TargetMode.LOWEST_TIME: text = "LOWEST_TIME"
		Mario35Handler.TargetMode.ATTACKERS: text = "ATTACKERS"
		Mario35Handler.TargetMode.MOST_COINS: text = "MOST_COINS"
	%TargetLabel.text = text

func handle_br_input():
	# Targeting: Cycle with 'Pause' (Start) or D-Pad
	# Only if NOT in debug mode (Pause is Pause in debug)
	if Input.is_action_just_pressed("pause") and not Global.debug_mode:
		Mario35Handler.cycle_target_mode(1)
		
	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right_0"):
		Mario35Handler.cycle_target_mode(1)
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left_0"):
		Mario35Handler.cycle_target_mode(-1)

	# Item Use: 'drop_item' (Select) or 'ui_focus_next' (Tab)
	if Input.is_action_just_pressed("ui_focus_next") or Input.is_action_just_pressed("drop_item"): 
		Mario35Handler.try_use_item()

func add_incoming_enemy_icon(type: String) -> void:
	# Create a visual representation
	var icon = TextureRect.new()
	# Try to load texture from scene (simplified for now, ideally use a lookup)
	# For now, just use a generic warning icon or Goomba
	# We can use the generic goomba sprite from assets if available
	# Or just a colored rect
	var texture = preload("res://Assets/Sprites/Enemies/Goomba.png") # Fallback
	if "Goomba" in type:
		texture = preload("res://Assets/Sprites/Enemies/Goomba.png")
	elif "Koopa" in type:
		texture = preload("res://Assets/Sprites/Enemies/KoopaTroopa.png")
		
	# Check if we can load the scene and extract sprite
	# var scn = load(type)
	# if scn:
	# 	var inst = scn.instantiate()
	# 	if inst.has_node("Sprite"):
	# 		# Logic to get texture from AnimatedSprite is harder
	# 		pass
	# 	inst.queue_free()
	
	icon.texture = texture # Assign texture
	icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(16, 16)
	%IncomingBar.add_child(icon)
	
	icon.custom_minimum_size = Vector2(16, 16)
	%IncomingBar.add_child(icon)
	
	# Identify as queue item
	icon.set_meta("queue_item", true)

func _on_enemy_spawned(_type: String) -> void:
	if %IncomingBar.get_child_count() > 0:
		%IncomingBar.get_child(0).queue_free()

func show_item_roulette() -> void:
	var box = %BattleRoyaleHUD.get_node_or_null("ItemBox")
	if not box: return
	var icon = box.get_node("RouletteIcon")
	
	icon.modulate = Color.WHITE
	var keys = ITEM_SPRITES.keys()
	
	# Simple spin animation loop
	for i in range(20): # Spin 20 times (approx 2-3 seconds)
		var rand_key = keys.pick_random()
		icon.texture = ITEM_SPRITES[rand_key]
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(icon): return
		
	# Since Mario35Handler determines result asynchronously and applies it,
	# we don't know the result here easily unless we passed it or listen for it.
	# But wait, Mario35Handler calls apply_item *after* the timer.
	# We should sync the visual stop with the actual item.
	
	# Actually Mario35Handler.spin_roulette waits 3.0s.
	# We spun for ~2.0s. We can spin a bit more.
	
	# Ideally, specific signal with result would be better, but for now just fade out state.
	icon.modulate = Color(0.5, 0.5, 0.5, 0.5)

func update_br_leaderboard() -> void:
	# Clear existing
	for child in %IncomingBar.get_parent().get_children():
		if child.name.begins_with("LRB_"):
			child.queue_free()
	
	# Create a simple vertical list of players
	var statuses = Mario35Handler.player_statuses
	var sorted_ids = statuses.keys()
	sorted_ids.sort_custom(func(a, b):
		if statuses[a].alive != statuses[b].alive:
			return statuses[a].alive
		return statuses[a].rank < statuses[b].rank
	)
	
	var y_offset = 64
	for id in sorted_ids:
		var s = statuses[id]
		var label = Label.new()
		label.name = "LRB_" + str(id)
		label.text = "%s : %s" % [s.name, "ALIVE" if s.alive else "RANK %d" % s.rank]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color.WHITE if s.alive else Color.DARK_GRAY)
		label.position = Vector2(400 - 80, y_offset) # Position on right side
		%BattleRoyaleHUD.add_child(label)
		y_offset += 12

func _on_game_over(winner_id: int) -> void:
	update_br_leaderboard()
	
	var message = "GAME OVER"
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	if winner_id == my_id:
		message = "VICTORY!"
	elif winner_id != 0:
		var winner_name = Mario35Handler.player_statuses.get(winner_id, {}).get("name", "Unknown")
		message = "WINNER: " + winner_name
		
	var label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.position = Vector2(0, 100)
	label.size = Vector2(400, 32)
	%BattleRoyaleHUD.add_child(label)
	
	# Play victory/loss sfx
	if winner_id == my_id:
		AudioManager.play_global_sfx("level_clear")
	else:
		AudioManager.play_global_sfx("game_over")
