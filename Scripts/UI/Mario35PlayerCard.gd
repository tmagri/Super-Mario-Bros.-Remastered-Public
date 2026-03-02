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
		# Stat cards: font snapped to multiple of 4
		# VBox fills card via FULL_RECT anchors — no manual sizing needed
		var max_for_height = int(size.y * 0.48)
		var font_size = (max_for_height / 4) * 4
		font_size = clampi(font_size, 4, 16)
		if name_label:
			name_label.add_theme_font_size_override("font_size", font_size)
		if status_label:
			status_label.add_theme_font_size_override("font_size", font_size)
		return

	# --- Regular player cards: font fits both height and width ---
	# VBox fills card via FULL_RECT anchors — no manual sizing needed
	# Height constraint: each label gets ~half the card
	var max_for_height = int(size.y * 0.48)
	# Width constraint: "CPU-01" = 6 chars; each char ~= font_size at this pixel font
	var max_for_width = int(size.x / 6.0)
	# Pick the tighter constraint, snap to multiple of 4
	var limit = mini(max_for_height, max_for_width)
	var font_size = (limit / 4) * 4
	font_size = clampi(font_size, 4, 16)
	if name_label:
		name_label.add_theme_font_size_override("font_size", font_size)
	if status_label:
		status_label.add_theme_font_size_override("font_size", font_size)

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
