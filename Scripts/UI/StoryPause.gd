extends Control

var selected_index := 0

@export var options: Array[Label]
@onready var cursor: TextureRect = $Control/Cursor

var active := false

@export var can_exit := true
@export var is_pause := true

signal option_1_selected
signal option_2_selected
signal option_3_selected
signal option_4_selected

signal closed

func _process(_delta: float) -> void:
	if active:
		handle_inputs()
	cursor.global_position.y = options[selected_index].global_position.y + 4
	cursor.global_position.x = options[selected_index].global_position.x - 10

func handle_inputs() -> void:
	var move_dir = 0
	if Input.is_action_just_pressed("ui_down"):
		move_dir = 1
	elif Input.is_action_just_pressed("ui_up"):
		move_dir = -1
		
	if move_dir != 0:
		var temp_index = selected_index + move_dir
		while temp_index >= 0 and temp_index < options.size():
			if options[temp_index].visible:
				selected_index = temp_index
				break
			temp_index += move_dir

	if Input.is_action_just_pressed("ui_accept"):
		option_selected()
	elif (Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("ui_back")) and can_exit:
		close()

func option_selected() -> void:
	emit_signal("option_" + str(selected_index + 1) + "_selected")

func open_settings() -> void:
	active = false
	$SettingsMenu.open()
	await $SettingsMenu.closed
	active = true

func open() -> void:
	if options.size() >= 3:
		if Global.current_game_mode == Global.GameMode.MARIO_35 and Mario35Handler.is_practice:
			options[1].hide()
			options[2].hide()
		else:
			options[1].show()
			options[2].show()
			
	if is_pause:
		Global.game_paused = true
		AudioManager.play_global_sfx("pause")
		get_tree().paused = true
	show()
	await get_tree().create_timer(0.1).timeout
	active = true

func close() -> void:
	active = false
	selected_index = 0
	hide()
	closed.emit()
	await get_tree().create_timer(0.1).timeout
	Global.game_paused = false
	get_tree().paused = false