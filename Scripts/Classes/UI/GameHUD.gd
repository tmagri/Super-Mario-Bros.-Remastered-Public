class_name GameHUD
extends CanvasLayer

var current_chara := 0

static var character_icons := [preload("res://Assets/Sprites/Players/Mario/LifeIcon.json"),preload("res://Assets/Sprites/Players/Luigi/LifeIcon.json"), preload("res://Assets/Sprites/Players/Toad/LifeIcon.json"), preload("res://Assets/Sprites/Players/Toadette/LifeIcon.json")]

const RANK_COLOURS := {"F": Color.DIM_GRAY, "D": Color.WEB_MAROON, "C": Color.PALE_GREEN, "B": Color.DODGER_BLUE, "A": Color.RED, "S": Color.GOLD, "P": Color.PURPLE}

const ITEM_JSONS := {
	"Mushroom": preload("res://Assets/Sprites/Items/SuperMushroom.json"),
	"Flower": preload("res://Assets/Sprites/Items/FireFlower.json"),
	"Star": preload("res://Assets/Sprites/Items/StarMan.json"), # StarMan.json? Checked list: StarMan.json exists. SuperStar.png exists.
	"Lucky Star": preload("res://Assets/Sprites/Items/LuckyStar.json"),
	"Wing": preload("res://Assets/Sprites/Items/WingItem.json"),
	"Hammer": preload("res://Assets/Sprites/Items/HammerIcon.json"),
	"P-Switch": preload("res://Assets/Sprites/Items/PSwitch.json"),
	"QuestionBlock": preload("res://Assets/Sprites/Blocks/QuestionBlock.json"),
	"ClearQuestionBlock": preload("res://Assets/Sprites/Blocks/ClearQuestionBlock.json")
}

var delta_time := 0.0
var is_item_displaying := false

func _ready() -> void:
	Global.level_theme_changed.connect(update_character_info)
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Always connect these, so we catch the signal even if GameHUD loads before the mode is set
	Mario35Handler.game_started.connect(_on_mario35_game_started)
	Mario35Handler.game_over.connect(_on_game_over)
	
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		_on_mario35_game_started()

func _on_mario35_game_started() -> void:
	if not Mario35Handler.time_changed.is_connected(update_br_timer):
		Mario35Handler.time_changed.connect(update_br_timer)
	if not Mario35Handler.target_changed.is_connected(update_hud_labels):
		Mario35Handler.target_changed.connect(update_hud_labels)
	if not Mario35Handler.incoming_item_roulette.is_connected(show_item_roulette):
		Mario35Handler.incoming_item_roulette.connect(show_item_roulette)
	if not Mario35Handler.roulette_stopped.is_connected(_on_roulette_stopped):
		Mario35Handler.roulette_stopped.connect(_on_roulette_stopped)
	
	update_hud_labels(Mario35Handler.current_target_mode)
	update_br_timer(int(Mario35Handler.current_time))
	# Hide IncomingBar as per user request
	%IncomingBar.visible = false
	
	# Robust Cleanup of previous game over / leaderboard
	for child in %BattleRoyaleHUD.get_children():
		if "GameOver" in child.name or child.name.begins_with("LRB_"):
			child.queue_free()
			
	setup_br_hud()
	%BattleRoyaleHUD.visible = true




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
		
		# Hide during level transitions to prevent overlap with "World X-X" black screen
		var in_transition = Global.transitioning_scene or get_tree().current_scene is LevelTransition
		%BattleRoyaleHUD.visible = self.visible and not in_transition
		
		handle_br_input()
		
		# Update ItemBox coin count
		var lbl = %BattleRoyaleHUD.get_node_or_null("CoinContainer/CoinLabel")
		if lbl:
			lbl.text = "%02d" % Mario35Handler.coins
			if Mario35Handler.coins >= 20:
				lbl.modulate = Color.YELLOW
			else:
				lbl.modulate = Color.WHITE
				
		# Visual cue for ItemBox (Swap Clear for Full when >= 20 coins)
		var box_rs = %BattleRoyaleHUD.get_node_or_null("ItemBox/RouletteIcon/Sprite/BoxRS")
		if box_rs and not is_item_displaying and not Mario35Handler.coin_roulette_active:
			var target_json = ITEM_JSONS["QuestionBlock"] if Mario35Handler.coins >= 20 else ITEM_JSONS["ClearQuestionBlock"]
			if box_rs.resource_json != target_json:
				box_rs.resource_json = target_json
		
		# Watch out warning
		%WarningLabel.visible = Mario35Handler.get_attackers_count() > 0
		
		# Spectating status
		var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
		if my_id in Mario35Handler.player_statuses:
			if not Mario35Handler.player_statuses[my_id].alive:
				%BRTimer.modulate = Color.GRAY
		
		# User requested removal of "random stuff" (P-Switches, Star) which are likely Challenge Mode or Combo elements
		# Explicitly hide them here to be safe
		%Combo.hide()
		%IGT.hide()
		%Stopwatch.hide()
		%PB.hide()
		$Main/RedCoins.hide()
		$ModernHUD/TopLeft/RedCoins.hide()
		
		# Additional potential stragglers
		%Radar.hide()
		%ModernRadar.hide()
		%MedalIcon.hide()
		%Crown.hide()
		%CharacterIcon.hide()
		%ModernLifeCount.hide()
		
		# Hide Main HUD elements if they are not children of Main/ModernHUD
		%Time.hide()
		%ModernTime.hide()
		%LevelNum.hide()
		%Score.hide()
		%ModernScore.hide()
		
		# Aggressive Hide for P-Switches/Stars (likely RedCoins logic or similar)
		if $Main:
			for c in $Main.get_children(): c.hide()
		if $ModernHUD:
			for c in $ModernHUD.get_children(): c.hide()
			
		# Final resort: Hide ALL direct children that aren't the BR HUD or Pause
		for child in get_children():
			if child is Control and child.name != "BattleRoyaleHUD" and not "Pause" in child.name and not "Results" in child.name:
				child.hide()
		
		return
	%BattleRoyaleHUD.visible = false
	
	$Main.visible = not Settings.file.visuals.modern_hud
	$ModernHUD.visible = Settings.file.visuals.modern_hud
	
	# Reset visibility of essential children (undoing aggressive hide from BR mode)
	if $Main.visible:
		for c in $Main.get_children(): c.show()
	if $ModernHUD.visible:
		# For ModernHUD, we can be more aggressive as it's cleaner structured
		for c in $ModernHUD.get_children(): c.show()
	$Main/RedCoins.hide()
	$Main/CoinCount.show()
	%IGT.hide()
	%Combo.hide()
	$Timer.paused = Settings.file.difficulty.time_limit == 2
	%Time.show()
	%Stopwatch.hide()
	%PB.hide()
	$Main/CoinCount/KeyCount.visible = KeyItem.total_collected > 0
	%KeyAmount.text = "*" + str(KeyItem.total_collected).pad_zeros(2)
	
	# Explicitly re-show standard labels (counteract BR mode hiding)
	%Score.show()
	%LevelNum.show()
	%Time.show()
	%CoinLabel.show()
	
	# RESTORE: Call update_hud_labels for standard game mode!
	update_hud_labels(Mario35Handler.current_target_mode)


func setup_br_hud() -> void:
	if %BattleRoyaleHUD.has_node("ItemBox"): return
	
	# Ensure HUD container is full rect for proper anchoring
	%BattleRoyaleHUD.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# --- Coins (Top Left, mimics standard HUD row 1/2 stack) ---
	var coin_container = Control.new()
	coin_container.name = "CoinContainer"
	coin_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	coin_container.position = Vector2(24, 16) # Shifted right 16 (2 chars)
	%BattleRoyaleHUD.add_child(coin_container)
	
	# MarioLabel (Far left, row 1)
	var mario_root = Control.new()
	mario_root.name = "MarioRoot"
	mario_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mario_root.position = Vector2(24, 16) # Shifted right 16 (2 chars)
	%BattleRoyaleHUD.add_child(mario_root)

	var mario_lbl = Label.new()
	mario_lbl.name = "MarioLabel"
	var my_name = Mario35Handler.player_statuses.get(multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1, {}).get("name", "MARIO")
	mario_lbl.text = my_name.to_upper()
	mario_lbl.add_theme_font_size_override("font_size", 8)
	mario_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	mario_lbl.add_theme_constant_override("shadow_offset_x", 1)
	mario_lbl.add_theme_constant_override("shadow_offset_y", 1)
	mario_lbl.position = Vector2(0, 0)
	mario_root.add_child(mario_lbl)
	
	var coin_icon_root = Control.new()
	coin_icon_root.name = "CoinIconRoot"
	coin_icon_root.position = Vector2(8, 16) # Row 2 relative to container y=16 -> y=24
	coin_container.add_child(coin_icon_root)
	
	var coin_sprite = AnimatedSprite2D.new()
	coin_sprite.scale = Vector2(1, 1)
	coin_icon_root.add_child(coin_sprite)
	var coin_rs = ResourceSetterNew.new()
	coin_rs.name = "ResourceSetterNew"
	coin_rs.node_to_affect = coin_sprite
	coin_rs.property_name = "sprite_frames"
	coin_rs.resource_json = preload("res://Assets/Sprites/UI/CoinIcon.json")
	coin_sprite.add_child(coin_rs)
	coin_sprite.play("default")
	
	var x_lbl = Label.new()
	x_lbl.text = "*" 
	x_lbl.add_theme_font_size_override("font_size", 8)
	x_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	x_lbl.add_theme_constant_override("shadow_offset_x", 1)
	x_lbl.add_theme_constant_override("shadow_offset_y", 1)
	x_lbl.position = Vector2(8, 8) # Row 2
	coin_container.add_child(x_lbl)
	
	var coin_val = Label.new()
	coin_val.name = "CoinLabel"
	coin_val.text = "00"
	coin_val.add_theme_font_size_override("font_size", 8)
	coin_val.add_theme_color_override("font_shadow_color", Color.BLACK)
	coin_val.add_theme_constant_override("shadow_offset_x", 1)
	coin_val.add_theme_constant_override("shadow_offset_y", 1)
	coin_val.position = Vector2(16, 8) # Row 2
	coin_container.add_child(coin_val)

	# --- Item Box (Top Center) ---
	var box = Panel.new()
	box.name = "ItemBox"
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-24, 16) # Aligned with Row 1 top
	box.size = Vector2(48, 48)
	var style = StyleBoxEmpty.new()
	box.add_theme_stylebox_override("panel", style)
	
	# Internal layout
	# Icon (Top)
	var icon_root = Control.new()
	icon_root.name = "RouletteIcon"
	icon_root.position = Vector2(24, 8) # Adjusted for alignment
	box.add_child(icon_root)
	
	var sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.scale = Vector2(1, 1) # Half size as requested
	sprite.modulate = Color.WHITE
	icon_root.add_child(sprite)
	
	# Sprite Frames ResourceSetter
	var rs = ResourceSetterNew.new()
	rs.name = "BoxRS"
	rs.node_to_affect = sprite
	rs.property_name = "sprite_frames"
	rs.resource_json = ITEM_JSONS["ClearQuestionBlock"]
	sprite.add_child(rs)

	%BattleRoyaleHUD.add_child(box)
	
	# --- Timer (Top Right, mimics standard HUD) ---
	var time_container = Control.new()
	time_container.name = "TimeContainer"
	time_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	time_container.position = Vector2(-56, 16) # Shifted right 16 (2 chars) from -72
	%BattleRoyaleHUD.add_child(time_container)
	
	var time_lbl_label = Label.new()
	time_lbl_label.text = "TIME"
	time_lbl_label.add_theme_font_size_override("font_size", 8)
	time_lbl_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	time_lbl_label.add_theme_constant_override("shadow_offset_x", 1)
	time_lbl_label.add_theme_constant_override("shadow_offset_y", 1)
	time_lbl_label.position = Vector2(0, 0)
	time_container.add_child(time_lbl_label)

	# Move existing label and style it
	%BRTimer.reparent(time_container)
	%BRTimer.position = Vector2(8, 8) # Row 2 relative to y=16 -> y=24
	%BRTimer.size = Vector2(50, 16)
	%BRTimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	%BRTimer.add_theme_font_size_override("font_size", 8) # Standard HUD size
	%BRTimer.add_theme_color_override("font_shadow_color", Color.BLACK)
	%BRTimer.add_theme_constant_override("shadow_offset_x", 1)
	%BRTimer.add_theme_constant_override("shadow_offset_y", 1)
	
	# --- Target Label (Top Center) ---
	#%TargetLabel.visible = true
	#%TargetLabel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	#%TargetLabel.position = Vector2(get_viewport().get_visible_rect().size.x / 2 - 100, 64) # Below top bar area
	#%TargetLabel.size = Vector2(200, 32)
	#%TargetLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	#%TargetLabel.add_theme_font_size_override("font_size", 16)
	#%TargetLabel.add_theme_color_override("font_outline_color", Color.BLACK)
	#%TargetLabel.add_theme_constant_override("outline_size", 4)
	

func update_hud_labels(mode: int) -> void:
	var text = "RANDOM"
	match mode:
		Mario35Handler.TargetMode.RANDOM: text = "RANDOM"
		Mario35Handler.TargetMode.LOWEST_TIME: text = "LOWEST TIME"
		Mario35Handler.TargetMode.ATTACKERS: text = "ATTACKERS"
		Mario35Handler.TargetMode.MOST_COINS: text = "MOST COINS"
	%TargetLabel.text = text
	%Score.text = str(Global.score).pad_zeros(6)
	%CoinLabel.text = "*" + str(Global.coins).pad_zeros(2)
	
	# Handle Battle Royale HUD specific updates
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		var br_coin_lbl = %BattleRoyaleHUD.get_node_or_null("CoinContainer/CoinLabel")
		if br_coin_lbl:
			br_coin_lbl.text = "%02d" % Mario35Handler.coins
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
	%Time.visible = get_tree().get_first_node_in_group("Players") != null or Global.in_title_screen
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
	var my_id = multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	if my_id in Mario35Handler.player_statuses and not Mario35Handler.player_statuses[my_id].alive:
		%BRTimer.text = "ELIMINATED"
		%BRTimer.modulate = Color.GRAY
		return
		
	%BRTimer.text = str(time).pad_zeros(3)
	if time <= 10:
		%BRTimer.modulate = Color.RED
	else:
		%BRTimer.modulate = Color.YELLOW



func handle_br_input():
	# Targeting: Cycle with 'Pause' (Start)
	# Only if NOT in debug mode (Pause is Pause in debug)
	if Input.is_action_just_pressed("pause") and not Global.debug_mode:
		Mario35Handler.cycle_target_mode(1)

	# Item Use: 'drop_item' (Select) or 'ui_focus_next' (Tab)
	if Input.is_action_just_pressed("ui_focus_next") or Input.is_action_just_pressed("drop_item"): 
		Mario35Handler.try_use_item()

func add_incoming_enemy_icon(_type: String) -> void:
	pass

func _on_enemy_spawned(_type: String) -> void:
	pass

func show_item_roulette() -> void:
	var box = %BattleRoyaleHUD.get_node_or_null("ItemBox")
	if not box: return
	var icon_root = box.get_node_or_null("RouletteIcon")
	if not icon_root: return
	var sprite = icon_root.get_node_or_null("Sprite")
	if not sprite: return
	var rs = sprite.get_node_or_null("BoxRS")
	if not rs: return
	
	sprite.modulate = Color.WHITE
	var keys = ITEM_JSONS.keys()
	keys.erase("QuestionBlock")
	keys.erase("ClearQuestionBlock")
	
	# Spin while logic is active
	while Mario35Handler.coin_roulette_active:
		var rand_key = keys.pick_random()
		if not is_instance_valid(rs): return
		rs.resource_json = ITEM_JSONS[rand_key]
		AudioManager.play_global_sfx("menu_move")
		await get_tree().create_timer(0.05).timeout
		if not is_instance_valid(sprite): return

func _on_roulette_stopped(item: String) -> void:
	var box = %BattleRoyaleHUD.get_node_or_null("ItemBox")
	if not box: return
	var icon_root = box.get_node_or_null("RouletteIcon")
	if not icon_root: return
	var sprite = icon_root.get_node_or_null("Sprite")
	if not sprite: return
	var rs = sprite.get_node_or_null("BoxRS")
	if not rs: return
	
	if not ITEM_JSONS.has(item): return
	
	is_item_displaying = true
	
	# Set final item
	rs.resource_json = ITEM_JSONS[item]
	sprite.modulate = Color.WHITE
	
	# Blink effect
	for i in range(6):
		sprite.visible = !sprite.visible
		await get_tree().create_timer(0.05).timeout
	sprite.visible = true
	
	# Keep item displayed for a couple of seconds
	await get_tree().create_timer(2.0, false).timeout
	is_item_displaying = false

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
		# Sort by dynamic driver score while alive
		return Mario35Handler.get_driver_score(a) > Mario35Handler.get_driver_score(b)
	)
	
	var y_offset = 64
	for id in sorted_ids:
		var s = statuses[id]
		var score = Mario35Handler.get_driver_score(id)
		var pts = Mario35Handler.session_points.get(id, 0)
		var label = Label.new()
		label.name = "LRB_" + str(id)
		
		var status_text = "ALIVE" if s.alive else "OUT"
		label.text = "%s : %s (%d PTS)" % [s.name, status_text, pts]
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		label.position = Vector2(-200, y_offset) # Centered horizontally
		label.size = Vector2(400, 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.add_theme_color_override("font_color", Color.WHITE if s.alive else Color.DARK_GRAY)
		%BattleRoyaleHUD.add_child(label)
		y_offset += 14 # Slightly more spacing

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
	label.name = "GameOverLabel"
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.size = Vector2(400, 36)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	%BattleRoyaleHUD.add_child(label)
	
	# Personal Rank Label (Bottom Left)
	if my_id in Mario35Handler.player_statuses:
		var status = Mario35Handler.player_statuses[my_id]
		var rank_lbl = Label.new()
		rank_lbl.name = "PersonalRankLabel"
		rank_lbl.text = _get_ordinal_rank(status.rank)
		rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rank_lbl.add_theme_font_size_override("font_size", 16)
		rank_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		rank_lbl.add_theme_constant_override("shadow_offset_x", 1)
		rank_lbl.add_theme_constant_override("shadow_offset_y", 1)
		rank_lbl.size = Vector2(100, 24)
		rank_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		rank_lbl.position = Vector2(16, -32) # Margin from bottom left
		%BattleRoyaleHUD.add_child(rank_lbl)
	
	# Play victory/loss sfx
	if winner_id == my_id:
		AudioManager.play_global_sfx("level_clear")
	else:
		AudioManager.play_global_sfx("game_over")

func _get_ordinal_rank(rank: int) -> String:
	var suffix = "TH"
	if rank % 100 < 11 or rank % 100 > 13:
		match rank % 10:
			1: suffix = "ST"
			2: suffix = "ND"
			3: suffix = "RD"
	return str(rank) + suffix
