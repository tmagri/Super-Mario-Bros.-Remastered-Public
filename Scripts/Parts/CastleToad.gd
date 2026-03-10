extends Node2D

@export var play_end_music := false
var can_menu := false
const ENDING = preload("res://Assets/Audio/BGM/Ending.mp3")

func _ready() -> void:
	if $Sprite is AnimatedSprite2D and Global.current_campaign == "SMBANN":
		$Sprite.play("Idle")
	Global.level_complete_begin.connect(begin)
	for i in [$SpeedrunMSG/ThankYou, $StandardMSG/ThankYou]:
		i.text = tr(i.text).replace("{PLAYER}", tr(Player.CHARACTER_NAMES[int(Global.player_characters[0])]))
	
	# Explicitly hide all messages to prevent 1-frame glitch before drawing
	for node_name in ["StandardMSG", "SpeedrunMSG", "EndingSpeech"]:
		if has_node(node_name):
			for child_node in get_node(node_name).get_children():
				child_node.hide()

func begin() -> void:
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		Mario35Handler.is_timer_paused = true
		
	$StaticBody2D/CollisionShape2D.set_deferred("disabled", false)
	_center_messages_to_screen()
	
	%PBMessage.modulate.a = int(SpeedrunHandler.timer < SpeedrunHandler.best_time)
	if play_end_music:
		Global.game_beaten = true
		SaveManager.write_save()
		play_music()
	%Time.text = tr(%Time.text).replace("{TIME}", SpeedrunHandler.gen_time_string(SpeedrunHandler.format_time(SpeedrunHandler.timer)))
	$CameraRightLimit._enter_tree()
	await get_tree().create_timer(3, false).timeout
	
	_center_messages_to_screen()
	
	if Global.current_game_mode == Global.GameMode.MARATHON_PRACTICE or (Global.current_game_mode == Global.GameMode.MARATHON and play_end_music):
		show_message($SpeedrunMSG)
	else:
		show_message($StandardMSG)
	if not play_end_music:
		await get_tree().create_timer(7, false).timeout
		exit_level()

func _center_messages_to_screen() -> void:
	var cam = get_viewport().get_camera_2d()
	if not cam: return
	var center_x = cam.get_screen_center_position().x
	
	for node_name in ["StandardMSG", "SpeedrunMSG", "EndingSpeech"]:
		if has_node(node_name):
			get_node(node_name).global_position.x = center_x

func exit_level() -> void:
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		Mario35Handler.is_timer_paused = false
	
	match Global.current_game_mode:
		Global.GameMode.MARIO_35:
			Global.current_level.transition_to_next_level()
		Global.GameMode.MARATHON_PRACTICE:
			Global.open_marathon_results()
		Global.GameMode.CUSTOM_LEVEL:
			Global.transition_to_scene("res://Scenes/Levels/CustomLevelMenu.tscn")
		Global.GameMode.LEVEL_EDITOR:
			Global.level_editor.stop_testing()
		_:
			if Global.current_campaign == "SMBANN":
				Global.open_disco_results()
				return
			if Global.world_num < 1:
				Global.transition_to_scene("res://Scenes/Levels/TitleScreen.tscn")
			else:
				Global.current_level.transition_to_next_level()

func do_tally() -> void:
	pass

func play_music() -> void:
	await AudioManager.music_override_player.finished
	AudioManager.set_music_override(AudioManager.MUSIC_OVERRIDES.ENDING, 999999, false)
	if [Global.GameMode.MARATHON, Global.GameMode.MARATHON_PRACTICE].has(Global.current_game_mode) == false:
		_center_messages_to_screen()
		show_message($EndingSpeech)
		await get_tree().create_timer(5, false).timeout
		can_menu = true
	else:
		can_menu = true

func _process(_delta: float) -> void:
	if can_menu and Input.is_action_just_pressed("jump_0"):
		can_menu = false
		peach_level_exit()

func show_message(message_node: Node) -> void:
	var players = get_tree().get_nodes_in_group("Players")
	if players.size() > 0:
		var mario = players[0]
		var prev_x = mario.global_position.x - 10.0
		# Wait until Mario reaches the wall and actually stops moving
		while abs(mario.global_position.x - prev_x) > 0.1:
			prev_x = mario.global_position.x
			await get_tree().physics_frame

	_center_messages_to_screen()
	await get_tree().process_frame # Let Godot update parent positions
	
	for i in message_node.get_children():
		_center_messages_to_screen() # Re-center before each reveal to prevent 1-frame position glitch
		i.show()
		await get_tree().create_timer(1).timeout

func peach_level_exit() -> void:
	if Global.current_game_mode == Global.GameMode.MARIO_35:
		Mario35Handler.is_timer_paused = false
		
	match Global.current_game_mode:
		Global.GameMode.MARIO_35:
			Global.current_level.transition_to_next_level()
		Global.GameMode.MARATHON:
			Global.open_marathon_results()
		Global.GameMode.MARATHON_PRACTICE:
			Global.open_marathon_results()
		Global.GameMode.CUSTOM_LEVEL:
			Global.transition_to_scene("res://Scenes/Levels/CustomLevelMenu.tscn")
		Global.GameMode.LEVEL_EDITOR:
			Global.level_editor.play_toggle()
		_:
			if Global.current_campaign == "SMBLL" and Global.world_num == 8:
				Global.current_level.transition_to_next_level()
			elif Global.current_game_mode == Global.GameMode.CAMPAIGN:
				CreditsLevel.go_to_title_screen = true
				Global.transition_to_scene("res://Scenes/Levels/Credits.tscn")
			else: Global.transition_to_scene("res://Scenes/Levels/TitleScreen.tscn")
