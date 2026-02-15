extends Panel

const SUPERSAMPLE = 4.0

@onready var name_label = %NameLabel
@onready var status_label = %StatusLabel
@onready var vbox = $VBox

var is_stat := false

func _process(_delta: float) -> void:
	if not vbox or size.x <= 0 or size.y <= 0:
		return
	
	# Render VBox at SUPERSAMPLE resolution, scale down for smooth text
	var ss_mult = float(Settings.file.video.internal_res + 1)
	var ss_width = size.x * ss_mult
	var ss_height = size.y * ss_mult
	
	# Clamp max VBox dimensions to avoid rendering issues
	ss_width = min(ss_width, 512.0)
	ss_height = min(ss_height, 512.0)
	
	var scale_x = ss_width / max(size.x, 1.0)
	var inv_scale = 1.0 / max(scale_x, 0.01)
	
	vbox.size = Vector2(ss_width, ss_height)
	vbox.scale = Vector2(inv_scale, inv_scale)
	vbox.position = Vector2.ZERO
	
	# Scale font to fit across the supersampled width
	# For stats, we want to fill the available height (~48% of card height per label)
	# For players, we follow the width divisor (~8 chars)
	var target_font: int
	if is_stat:
		target_font = int(ss_height * 0.48)
	else:
		target_font = int(ss_width / 8.0)
	
	target_font = clamp(target_font, 8, 256)
	
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
	if status_label:
		status_label.text = value
		status_label.modulate = Color.YELLOW
		status_label.visible = value != ""
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
