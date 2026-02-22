extends Panel

const SUPERSAMPLE = 4.0

@onready var name_label = %NameLabel
@onready var status_label = %StatusLabel
@onready var vbox = $VBox

var is_stat := false

func _process(_delta: float) -> void:
	# Snapshot injected sizes from WidescreenHUD before mathematical alterations
	if custom_minimum_size.x > size.x:
		size = custom_minimum_size
	
	if not vbox or size.x <= 0 or size.y <= 0:
		return
	
	# Render VBox at SUPERSAMPLE resolution, scale down for smooth text
	var ss_mult = float(Settings.file.video.internal_res)
	if ss_mult == 0.0:
		var monitor_id = DisplayServer.window_get_current_screen()
		var monitor_y = DisplayServer.screen_get_size(monitor_id).y
		ss_mult = max(1.0, floor(monitor_y / 240.0))
		
	var ss_width = size.x * ss_mult
	var ss_height = size.y * ss_mult
	
	var inv_scale = 1.0 / ss_mult
	
	vbox.size = Vector2(ss_width, ss_height)
	vbox.scale = Vector2(inv_scale, inv_scale)
	vbox.position = Vector2.ZERO
	
	var target_font: int
	if is_stat:
		# Explicitly render exactly 24 integer pixels high, stretched by current monitor DPI.
		# This leverages the `3x by 2x` massive column allocation given by WidescreenHUD.
		target_font = int(24.0 * ss_mult)
	else:
		# Player names remain at proportional responsive box logic
		target_font = int(ss_width / 8.0)
	
	target_font = clamp(target_font, 8, 4096)
	if name_label:
		name_label.add_theme_font_size_override("font_size", target_font)
	if status_label:
		status_label.add_theme_font_size_override("font_size", target_font)

func setup(player_data: Dictionary) -> void:
	is_stat = false
	if name_label:
		name_label.text = player_data.get("name", "MARIO").to_upper()

func setup_as_stat(title: String, value: String) -> void:
	is_stat = true
	if name_label:
		name_label.text = title
		name_label.visible = title != ""
		name_label.clip_text = false
		name_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if status_label:
		status_label.text = value
		status_label.modulate = Color.YELLOW
		status_label.visible = value != ""
		status_label.clip_text = false
		status_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	modulate = Color.WHITE

func update_state(is_alive: bool, coins: int, is_targeting_me: bool) -> void:
	if status_label:
		if is_alive:
			status_label.text = ""
			status_label.modulate = Color.WHITE
		else:
			status_label.text = "KO"
			status_label.modulate = Color.RED
	
	if is_targeting_me:
		modulate = Color(1.0, 0.8, 0.8)
	else:
		modulate = Color.WHITE
