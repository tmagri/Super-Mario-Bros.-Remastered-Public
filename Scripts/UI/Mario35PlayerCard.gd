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

	if is_stat:
		var target_w = size.x - 8
		var target_h = int(size.y * 0.45)
		var fs_best = 24 # Stats can be slightly larger
		var font = name_label.get_theme_font("font") if name_label else null
		if font:
			# Measure both labels if they exist and pick the one that fits both
			for fs in range(24, 7, -1):
				var n_size = font.get_string_size(name_label.text, name_label.horizontal_alignment, -1, fs) if name_label and name_label.text != "" else Vector2.ZERO
				var s_size = font.get_string_size(status_label.text, status_label.horizontal_alignment, -1, fs) if status_label and status_label.text != "" else Vector2.ZERO
				if n_size.x <= target_w and n_size.y <= target_h and s_size.x <= target_w and s_size.y <= target_h:
					fs_best = fs
					break
				fs_best = fs
		if name_label:
			name_label.add_theme_font_size_override("font_size", fs_best)
		if status_label:
			status_label.add_theme_font_size_override("font_size", fs_best)
		return

	# Iterate to find the best font size that fits the space
	var target_width = size.x - 6 # Increased margin for safety
	var target_height = int(size.y * 0.45) # Nearly half the height
	
	var best_size = 16 
	if name_label and name_label.text != "":
		var font = name_label.get_theme_font("font")
		if font:
			# Loop down to 4px to ensure it fits in tiny sidebars
			for fs in range(16, 3, -1):
				var string_size = font.get_string_size(name_label.text, name_label.horizontal_alignment, -1, fs)
				if string_size.x <= target_width and string_size.y <= target_height:
					best_size = fs
					break
				best_size = fs 

	if name_label:
		name_label.add_theme_font_size_override("font_size", best_size)
	if status_label:
		status_label.add_theme_font_size_override("font_size", best_size)

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
