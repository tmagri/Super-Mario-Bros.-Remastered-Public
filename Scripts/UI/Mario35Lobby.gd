extends Control

@onready var name_input = $BG/Border/Content/ScrollContainer/VBoxContainer/NameInput
@onready var ip_input = $BG/Border/Content/ScrollContainer/VBoxContainer/IPInput
@onready var status_label = $BG/Border/Content/ScrollContainer/VBoxContainer/StatusLabel
@onready var player_list = $BG/Border/Content/ScrollContainer/VBoxContainer/PlayerList
@onready var start_button = $BG/Border/Content/ScrollContainer/VBoxContainer/StartButton

var music_player: AudioStreamPlayer = null

var focus_cursor: TextureRect = null
var char_indicator: RichTextLabel = null

const CHARACTERS = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
var controller_cursor_index := 0
var is_controller_mode := false
var is_editing_name := false
var is_editing_setting := false
var last_input_was_mouse := false

func _ready():
	Global.current_game_mode = Global.GameMode.MARIO_35
	# Music setup
	music_player = AudioStreamPlayer.new()
	music_player.stream = load("res://Assets/Audio/BGM/Setup.mp3")
	music_player.bus = "Music"
	add_child(music_player)
	if Settings.file.audio.menu_bgm == 1:
		music_player.play()
	
	if Global.has_node("GameHUD"):
		Global.get_node("GameHUD").hide()
	
	Mario35Network.player_list_changed.connect(refresh_player_list)
	Mario35Network.connection_failed.connect(_on_connection_failed)
	Mario35Network.server_disconnected.connect(_on_server_disconnected)
	Mario35Network.server_found.connect(_on_server_found)
	
	$BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/HostButton.pressed.connect(_on_host_pressed)
	$BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/JoinButton.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	$BG/Border/Content/ScrollContainer/VBoxContainer/BackButton.pressed.connect(_on_back_pressed)
	
	# Initial focus for controller
	await get_tree().process_frame
	name_input.grab_focus()
	
	# Setup focus cursor
	focus_cursor = TextureRect.new()
	focus_cursor.texture_filter = TEXTURE_FILTER_NEAREST
	focus_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	focus_cursor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	focus_cursor.custom_minimum_size = Vector2(16, 16)
	focus_cursor.size = Vector2(16, 16)
	focus_cursor.modulate = Color.WHITE
	focus_cursor.z_index = 10
	add_child(focus_cursor)
	focus_cursor.hide()
	
	# Use ResourceSetterNew to load the correct cursor texture from JSON
	# Ensuring we have a basic theme set so ResourceSetter works
	if Global.level_theme == "":
		Global.level_theme = "Overworld"
		
	var rs = ResourceSetterNew.new()
	rs.node_to_affect = focus_cursor
	rs.property_name = "texture"
	rs.mode = ResourceSetterNew.ResourceMode.TEXTURE
	rs.resource_json = load("res://Assets/Sprites/UI/Cursor.json")
	add_child(rs)
	
	# Setup character indicator (Zelda II Style)
	# Use RichTextLabel for perfect transparency-based overlay
	char_indicator = RichTextLabel.new()
	char_indicator.bbcode_enabled = true
	char_indicator.texture_filter = TEXTURE_FILTER_NEAREST
	char_indicator.clip_contents = false
	char_indicator.scroll_active = false
	char_indicator.autowrap_mode = TextServer.AUTOWRAP_OFF
	char_indicator.add_theme_font_override("normal_font", name_input.get_theme_font("font"))
	char_indicator.add_theme_font_size_override("normal_font_size", name_input.get_theme_font_size("font_size"))
	add_child(char_indicator)
	char_indicator.hide()
	
	name_input.caret_blink = false # Hide standard caret
	
	# Blink animation for indicator
	var b_tween = create_tween().set_loops()
	b_tween.tween_property(char_indicator, "modulate:a", 0.0, 0.4)
	b_tween.tween_property(char_indicator, "modulate:a", 1.0, 0.4)
	
	# Setup neighbors for clunky navigation
	var host_btn = $BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/HostButton
	var join_btn = $BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/JoinButton
	var back_btn = $BG/Border/Content/ScrollContainer/VBoxContainer/BackButton
	
	name_input.focus_neighbor_bottom = ip_input.get_path()
	ip_input.focus_neighbor_top = name_input.get_path()
	ip_input.focus_neighbor_bottom = %RoomKeyInput.get_path()
	
	%RoomKeyInput.focus_neighbor_top = ip_input.get_path()
	%RoomKeyInput.focus_neighbor_bottom = host_btn.get_path()
	
	host_btn.focus_neighbor_top = %RoomKeyInput.get_path()
	host_btn.focus_neighbor_right = join_btn.get_path()
	host_btn.focus_neighbor_bottom = back_btn.get_path()
	
	join_btn.focus_neighbor_top = %RoomKeyInput.get_path()
	join_btn.focus_neighbor_left = host_btn.get_path()
	join_btn.focus_neighbor_bottom = back_btn.get_path()
	
	back_btn.focus_neighbor_top = host_btn.get_path()
	
	%SettingsButton.pressed.connect(func(): 
		%SettingsPopup.show()
		_set_lobby_interaction_active(false)
		%StartTimeInput.get_line_edit().grab_focus()
	)
	%CloseSettingsButton.pressed.connect(func(): 
		_update_settings()
		%SettingsPopup.hide()
		_set_lobby_interaction_active(true)
		%SettingsButton.grab_focus()
	)
	
	# Convert input to uppercase as user types
	name_input.text_changed.connect(_on_name_input_changed)
	
	if name_input.text.is_empty():
		name_input.text = "PLAYER"
	
	name_input.focus_entered.connect(_on_focus_entered.bind(name_input))
	name_input.focus_exited.connect(_on_focus_exited.bind(name_input))
	ip_input.focus_entered.connect(_on_focus_entered.bind(ip_input))
	ip_input.focus_exited.connect(_on_focus_exited.bind(ip_input))
	%RoomKeyInput.focus_entered.connect(_on_focus_entered.bind(%RoomKeyInput))
	%RoomKeyInput.focus_exited.connect(_on_focus_exited.bind(%RoomKeyInput))
	%RoomKeyInput.text_changed.connect(_on_room_key_changed)
	
	for btn in [$BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/HostButton, 
				$BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/JoinButton,
				start_button, 
				%SettingsButton,
				$BG/Border/Content/ScrollContainer/VBoxContainer/BackButton]:
		btn.focus_entered.connect(_on_focus_entered.bind(btn))
		btn.focus_exited.connect(_on_focus_exited.bind(btn))
		btn.mouse_entered.connect(btn.grab_focus)
		
	# Connect focus signals for all settings
	var settings_nodes = [
		%StartTimeInput.get_line_edit(), 
		%MaxTimeInput.get_line_edit(), 
		%ItemOption, 
		%LevelOption, 
		%NetworkOption,
		%PhysicsOption,
		%CloseSettingsButton
	]
	
	for node in settings_nodes:
		node.focus_entered.connect(_on_focus_entered.bind(node))
		node.focus_exited.connect(_on_focus_exited.bind(node))
		node.mouse_entered.connect(node.grab_focus)
		
	# Connect SpinBox internal LineEdits for editing
	for sb in [%StartTimeInput, %MaxTimeInput]:
		sb.get_line_edit().gui_input.connect(_on_spinbox_input.bind(sb))
	
	# Setup Level Version options
	%LevelOption.clear()
	%LevelOption.add_item("SMB1", Mario35Handler.GameVersion.SMB1)
	%LevelOption.add_item("SMBLL", Mario35Handler.GameVersion.SMBLL)
	%LevelOption.add_item("ANN", Mario35Handler.GameVersion.SMBANN)
	%LevelOption.add_item("SPECIAL", Mario35Handler.GameVersion.SMBS)
	%LevelOption.add_item("RANDOM", Mario35Handler.GameVersion.RANDOM)
	%LevelOption.selected = 0

func _process(_delta: float) -> void:
	if not get_tree().paused:
		# Sync music with settings
		if music_player:
			music_player.stream_paused = Settings.file.audio.menu_bgm == 0
			if not music_player.is_playing() and Settings.file.audio.menu_bgm == 1:
				music_player.play()
				
	if is_editing_name:
		_update_char_indicator()

func _on_focus_entered(node: Control) -> void:
	node.modulate = Color(1.2, 1.2, 1.2) # Slight glow
	if node == name_input:
		is_controller_mode = true
		_update_char_indicator()
		
	if is_instance_valid(focus_cursor) and not last_input_was_mouse:
		focus_cursor.show()
		# Use call_deferred to ensure layout has settled for new focus nodes
		_update_cursor_pos.call_deferred(node)
		
	AudioManager.play_sfx("menu_move") # Use a small click/blip sound if available, stomp is a good placeholder

func _update_cursor_pos(node: Control) -> void:
	if not is_instance_valid(focus_cursor) or not is_instance_valid(node): return
	
	# Refine centering and offset to prevent hiding at the top/sides
	var center_y = node.size.y / 2
	var offset_x = -16 # Slightly closer to the button
	
	var cursor_pos = node.global_position + Vector2(offset_x, center_y - 8)
	
	# Clamp position to avoid going off screen boundaries (preventing "hidden at top")
	cursor_pos.y = max(cursor_pos.y, 8) 
	cursor_pos.x = max(cursor_pos.x, 8)
	
	var c_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c_tween.tween_property(focus_cursor, "global_position", cursor_pos, 0.1)

func _on_focus_exited(node: Control) -> void:
	node.modulate = Color.WHITE
	if node == name_input:
		is_controller_mode = false
		is_editing_name = false
		char_indicator.hide()
	
	if is_editing_setting:
		is_editing_setting = false

func _update_char_indicator() -> void:
	if not is_controller_mode:
		char_indicator.hide()
		return
	
	char_indicator.show()
	var font_size = name_input.get_theme_font_size("font_size")
	
	# Match LineEdit's size and alignment
	char_indicator.size = name_input.size
	char_indicator.global_position = name_input.global_position # Reverted -1px shift
	
	# Horizontal alignment mapping for BBCode
	var align_tag = "left"
	match name_input.alignment:
		HORIZONTAL_ALIGNMENT_CENTER: align_tag = "center"
		HORIZONTAL_ALIGNMENT_RIGHT: align_tag = "right"
	
	# Zelda II Style: Blinking character via BBCode transparency
	var full_text = name_input.text
	if full_text.length() <= controller_cursor_index:
		full_text = full_text.rpad(controller_cursor_index + 1, " ")
	
	var prefix = full_text.substr(0, controller_cursor_index)
	var target = full_text[controller_cursor_index]
	var suffix = full_text.substr(controller_cursor_index + 1)
	
	# We use [color=#00000000] to make non-selected chars invisible
	# This ensures the yellow character is EXACTLY where the LineEdit draws it
	var blink_color = "yellow" if (Time.get_ticks_msec() / 250) % 2 == 0 else "#00000000"
	char_indicator.text = "[%s][color=#00000000]%s[/color][color=%s]%s[/color][color=#00000000]%s[/color][/%s]" % [align_tag, prefix, blink_color, target, suffix, align_tag]
	
	# Vertical centering: RichTextLabel doesn't handle this well, so we offset the whole node
	char_indicator.global_position.y = name_input.global_position.y + (name_input.size.y / 2 - font_size / 2)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		last_input_was_mouse = true
		if is_instance_valid(focus_cursor): focus_cursor.hide()
	elif event is InputEventJoypadButton or event is InputEventKey:
		last_input_was_mouse = false
		
	# Handle SpinBox editing first if active
	if is_editing_setting:
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused.get_parent() is SpinBox:
			var sb = focused.get_parent() as SpinBox
			if event.is_action_pressed("ui_up"):
				sb.value += sb.step
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed("ui_down"):
				sb.value -= sb.step
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
				is_editing_setting = false
				focused.modulate = Color(1.2, 1.2, 1.2) # Return to normal glow
				AudioManager.play_sfx("menu_move")
				get_viewport().set_input_as_handled()
				return

	if not name_input.has_focus():
		# Special handling for starting SpinBox edits
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused.get_parent() is SpinBox and event.is_action_pressed("ui_accept"):
			is_editing_setting = true
			focused.modulate = Color(2.0, 2.0, 1.0) # Intense yellow glow for edit mode
			AudioManager.play_sfx("menu_move")
			get_viewport().set_input_as_handled()
		return
		
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		is_editing_name = !is_editing_name
		if is_editing_name:
			AudioManager.play_sfx("menu_move")
		get_viewport().set_input_as_handled()
		_update_char_indicator()
		return
		
	if not is_editing_name:
		return

	# Block standard UI navigation while editing name
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		if event.is_action_pressed("ui_up"):
			_cycle_char(1)
		else:
			_cycle_char(-1)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_left"):
		_move_cursor(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_move_cursor(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"): # Backspace
		_backspace()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"): # OK / Next
		_handle_confirm()
		get_viewport().set_input_as_handled()

func _backspace() -> void:
	if controller_cursor_index > 0:
		var current_text = name_input.text
		# Remove character and move back
		var new_text = ""
		for i in current_text.length():
			if i != controller_cursor_index - 1:
				new_text += current_text[i]
		
		name_input.text = new_text
		controller_cursor_index -= 1
		name_input.caret_column = controller_cursor_index + 1
	elif name_input.text.length() > 0:
		# Just clear first char if at start? Or do nothing. 
		# Standard Zelda: B usually goes back a space and clears.
		pass

func _handle_confirm() -> void:
	# If we are at the end, or they just want to move on
	# Focus the Next button (likely Host/Join)
	ip_input.grab_focus()

func _cycle_char(direction: int) -> void:
	var current_text = name_input.text
	if current_text.length() <= controller_cursor_index:
		current_text = current_text.rpad(controller_cursor_index + 1, " ")
	
	var current_char = current_text[controller_cursor_index]
	var char_idx = CHARACTERS.find(current_char)
	if char_idx == -1: char_idx = 0
	
	char_idx = (char_idx + direction + CHARACTERS.length()) % CHARACTERS.length()
	var new_char = CHARACTERS[char_idx]
	
	var new_text = current_text
	new_text[controller_cursor_index] = new_char
	name_input.text = new_text.strip_edges() # Keep it clean but maybe allow trailing spaces for editing?
	# Better to keep length consistent for editing
	name_input.text = new_text
	name_input.caret_column = controller_cursor_index + 1
	_update_char_indicator()

func _move_cursor(direction: int) -> void:
	controller_cursor_index = clampi(controller_cursor_index + direction, 0, 15) # Max 16 chars
	if name_input.text.length() <= controller_cursor_index:
		name_input.text = name_input.text.rpad(controller_cursor_index + 1, " ")
	name_input.caret_column = controller_cursor_index + 1
	_update_char_indicator()

func _on_name_input_changed(new_text: String) -> void:
	var caret_pos = name_input.caret_column
	name_input.text = new_text.to_upper()
	name_input.caret_column = caret_pos

func _on_room_key_changed(new_text: String) -> void:
	var caret_pos = %RoomKeyInput.caret_column
	%RoomKeyInput.text = new_text.to_upper()
	%RoomKeyInput.caret_column = caret_pos

func _exit_tree() -> void:
	if Global.has_node("GameHUD"):
		Global.get_node("GameHUD").show()

func _on_host_pressed():
	if name_input.text.strip_edges().is_empty():
		status_label.text = "ENTER NAME"
		return
	
	Mario35Network.player_info.name = name_input.text.strip_edges().to_upper()
	var key = %RoomKeyInput.text.strip_edges().to_upper()
	var use_upnp = %NetworkOption.selected == 0 # 0: GLOBAL
	
	var err = Mario35Network.host_game(key, use_upnp)
	if err == OK:
		status_label.text = "HOSTING"
		if not key.is_empty():
			status_label.text += " (KEY: %s)" % key
		start_button.visible = true
		%SettingsButton.visible = true
		
		# DYNAMICALLY RELINK NEIGHBORS
		# Now that Start and Settings are visible, we must insert them into the focus chain
		var host_btn = $BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/HostButton
		var join_btn = $BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/JoinButton
		var back_btn = $BG/Border/Content/ScrollContainer/VBoxContainer/BackButton
		var settings_btn = %SettingsButton
		
		# Host/Join now point down to Start Game
		host_btn.focus_neighbor_bottom = start_button.get_path()
		join_btn.focus_neighbor_bottom = start_button.get_path()
		
		# Start Game points up to Host and down to Settings
		start_button.focus_neighbor_top = host_btn.get_path()
		start_button.focus_neighbor_bottom = settings_btn.get_path()
		
		# Settings points up to Start and down to Back
		settings_btn.focus_neighbor_top = start_button.get_path()
		settings_btn.focus_neighbor_bottom = back_btn.get_path()
		
		# Back counts points up to Settings
		back_btn.focus_neighbor_top = settings_btn.get_path()
		
		refresh_player_list()
	else:
		status_label.text = "HOST FAILED " + str(err)

func _on_join_pressed():
	if name_input.text.strip_edges().is_empty():
		status_label.text = "ENTER NAME"
		return
		
	Mario35Network.player_info.name = name_input.text.strip_edges().to_upper()
	var key = %RoomKeyInput.text.strip_edges().to_upper()
	var err = Mario35Network.join_game(ip_input.text, key)
	if err == OK:
		status_label.text = "JOINING..."
		start_button.visible = false
		%SettingsButton.visible = false
		
		# RESET NEIGHBORS (Bypass Start/Settings)
		var host_btn = $BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/HostButton
		var join_btn = $BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/JoinButton
		var back_btn = $BG/Border/Content/ScrollContainer/VBoxContainer/BackButton
		
		host_btn.focus_neighbor_bottom = back_btn.get_path()
		join_btn.focus_neighbor_bottom = back_btn.get_path()
		back_btn.focus_neighbor_top = host_btn.get_path()
		
		refresh_player_list()
	else:
		status_label.text = "JOIN FAILED " + str(err)

func _on_player_list_changed(_id = 0, _info = null):
	refresh_player_list()

func refresh_player_list():
	player_list.clear()
	var count = Mario35Network.players.size()
	var my_id = multiplayer.get_unique_id()
	for id in Mario35Network.players:
		var p = Mario35Network.players[id]
		var suffix = " (YOU)" if id == my_id else ""
		player_list.add_item(p.name.to_upper() + suffix)
	
	# Start Game requirements (2+ players)
	if multiplayer.is_server():
		start_button.disabled = (count < 2)
		if count < 2:
			status_label.text = "WAITING FOR PLAYERS (%d/2)" % count
		else:
			status_label.text = "HOSTING"
			if not Mario35Network.room_key.is_empty():
				status_label.text += " (KEY: %s)" % Mario35Network.room_key
	elif not multiplayer.is_server():
		start_button.visible = false
		%SettingsButton.visible = false
		if count > 0:
			status_label.text = "CONNECTED"

func _on_server_found(ip: String, info: Dictionary):
	if ip_input.text.is_empty() or ip_input.text == Mario35Network.DEFAULT_SERVER_IP:
		ip_input.text = ip
		# Only update status if we aren't already busy in a session (Hosting, Waiting, or Connected)
		var s = status_label.text
		if s == "" or s == "ENTER NAME" or s.begins_with("SEARCHING") or s.begins_with("LOCAL GAME FOUND"):
			status_label.text = "LOCAL GAME FOUND: " + info.name.to_upper()

func _on_connection_failed():
	status_label.text = "CONNECTION FAILED"

func _on_server_disconnected():
	status_label.text = "SERVER DISCONNECTED"
	start_button.visible = false
	player_list.clear()

func _on_start_pressed():
	_update_settings()
	var settings = Mario35Handler.get_settings_dictionary()
	Mario35Network.start_game.rpc(settings)

func _update_settings():
	Mario35Handler.start_time = int(%StartTimeInput.value)
	Mario35Handler.max_time = int(%MaxTimeInput.value)
	Mario35Handler.item_pool_mode = %ItemOption.selected
	Mario35Handler.physics_mode = %PhysicsOption.selected
	Mario35Handler.game_version = %LevelOption.selected

func _on_back_pressed():
	Mario35Network.leave_game()
	Global.current_game_mode = Global.GameMode.NONE
	Global.transition_to_scene("res://Scenes/Levels/TitleScreen.tscn")

func _set_lobby_interaction_active(active: bool) -> void:
	var mode = Control.FOCUS_ALL if active else Control.FOCUS_NONE
	var filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	
	# Group all lobby background elements
	var lobby_nodes = [
		name_input, 
		ip_input, 
		%RoomKeyInput,
		player_list, 
		start_button, 
		%SettingsButton,
		$BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/HostButton,
		$BG/Border/Content/ScrollContainer/VBoxContainer/HBoxContainer/JoinButton,
		$BG/Border/Content/ScrollContainer/VBoxContainer/BackButton
	]
	
	for node in lobby_nodes:
		if is_instance_valid(node):
			node.focus_mode = mode
			node.mouse_filter = filter
	
	# Also disable the scroll container to be sure
	$BG/Border/Content/ScrollContainer.mouse_filter = filter

func _on_spinbox_input(event: InputEvent, sb: SpinBox):
	# Fallback for mouse/keyboard if needed, but the main logic is in _input for controller
	pass
