extends Panel

const SUPERSAMPLE = 4.0

@onready var name_label = %NameLabel
@onready var status_label = %StatusLabel
@onready var mario_sprite = %MarioSprite
@onready var vbox0 = $VBox

var is_stat := false
var current_chara_idx := 0
var current_power_idx := 0
var time_passed := 0.0

func _ready() -> void:
	# Manual asset loading skipped here as it's now handled by setup/setup_as_stat with correct character support
	pass

func _update_icon(chara_idx: int = 0, power_idx: int = 0) -> void:
	if not mario_sprite: return
	
	current_chara_idx = chara_idx
	current_power_idx = power_idx
	
	var chara_folder = Player.CHARACTERS[chara_idx]
	
	# Determine source PNG based on power level
	var source = "Small.png"
	match power_idx:
		1: source = "Big.png"
		2: source = "Fire.png"
		3: source = "Superball.png"
		4: source = "Big.png" # Mega uses Big.png internally
	
	# We use a standard 32x32 region for the HUD icon
	var rect_data = [0, 0, 32, 32]
	
	if power_idx == 4:
		time_passed = 0.0 # Reset pulse animation

	var img_path = ("res://Assets/Sprites/Players/").path_join(chara_folder).path_join(source)
	var pure_path = ResourceSetter.get_pure_resource_path(img_path)
	
	var tex = null
	if pure_path.begins_with("res://"):
		tex = load(pure_path)
	else:
		var img = Image.new()
		if img.load(pure_path) == OK:
			tex = ImageTexture.create_from_image(img)
	
	if tex:
		var atlas = AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(rect_data[0], rect_data[1], rect_data[2], rect_data[3])
		mario_sprite.texture = atlas
	
	# Handle Palette
	var palette_path = ("res://Assets/Sprites/Players/").path_join(chara_folder).path_join("ColourPalette.png")
	var pal_tex = load(palette_path)
	if pal_tex and mario_sprite.material:
		mario_sprite.material.set_shader_parameter("palette_sampler", pal_tex)
		mario_sprite.material.set_shader_parameter("palette_idx", power_idx)
		mario_sprite.material.set_shader_parameter("palette_height", 5)
	
	mario_sprite.visible = true

func _process(delta: float) -> void:
	# Mega Mario pulsating effect
	if mario_sprite and current_power_idx == 4:
		time_passed += delta
		var pulse = 1.0 + sin(time_passed * 10.0) * 0.15
		mario_sprite.scale = Vector2(pulse, pulse)
	elif mario_sprite:
		mario_sprite.scale = Vector2.ONE

	# Snapshot injected sizes from WidescreenHUD before mathematical alterations
	if custom_minimum_size.x > size.x:
		size = custom_minimum_size

	if not vbox0 or size.x <= 0 or size.y <= 0:
		return

	if is_stat:
		var target_w = size.x - 4
		var sprite_h = mario_sprite.size.y if mario_sprite and mario_sprite.visible else 0
		var remaining_h = size.y - sprite_h - 4
		
		# Give title more space (2/3 of remainder)
		var target_h_name = int(remaining_h * 0.7)
		var target_h_stat = int(remaining_h * 0.3)
		
		var fs_best = 24
		var font = name_label.get_theme_font("font") if name_label else null
		if font:
			for fs in range(24, 4, -1):
				var n_size = font.get_multiline_string_size(name_label.text, name_label.horizontal_alignment, target_w, fs)
				var s_size = font.get_multiline_string_size(status_label.text, status_label.horizontal_alignment, target_w, fs)
				if n_size.x <= target_w and n_size.y <= target_h_name and s_size.x <= target_w and s_size.y <= target_h_stat:
					fs_best = fs
					break
				fs_best = fs
		
		if name_label:
			name_label.add_theme_font_size_override("font_size", fs_best)
			name_label.add_theme_constant_override("line_spacing", 0)
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if status_label:
			status_label.add_theme_font_size_override("font_size", fs_best)
		
		if vbox0:
			vbox0.add_theme_constant_override("separation", 1)
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
	var chara_idx = int(player_data.get("character", 0))
	var power_idx = int(player_data.get("power_state", 0))
	_update_icon(chara_idx, power_idx)
	if name_label:
		name_label.text = player_data.get("name", "MARIO").to_upper()

func setup_as_stat(title: String, value: String) -> void:
	is_stat = true
	var chara_idx = int(Global.player_characters[0])
	_update_icon(chara_idx)
	
	if name_label:
		name_label.text = title
		name_label.visible = title != ""
		name_label.clip_text = false
		name_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if status_label:
		status_label.text = value
		status_label.visible = value != ""
		status_label.clip_text = false
		status_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	
	_update_style(Color.WHITE, Color.BLACK)

func update_state(is_alive: bool, coins: int, is_targeting_me: bool, theme: String = "Overworld", power_state: int = 0) -> void:
	if is_stat: return
	
	if power_state != current_power_idx:
		_update_icon(current_chara_idx, power_state)

	var bg_color = Color.CORNFLOWER_BLUE
	var text_color = Color.WHITE
	
	if not is_alive:
		bg_color = Color(1.0, 0.0, 0.0) # VIBRANT RED
		text_color = Color.WHITE
		if status_label:
			status_label.text = "KO"
	else:
		if status_label:
			status_label.text = ""
		
		match theme:
			"Underground":
				bg_color = Color(0.0, 0.0, 0.25) # Deep Dark Blue
			"Castle":
				bg_color = Color.BLACK
			"Underwater":
				bg_color = Color(0.1, 0.4, 0.7) # Ocean Blue
			"Snow":
				bg_color = Color(0.8, 0.9, 1.0) # Light Frost Blue
				text_color = Color.BLACK
			"Desert":
				bg_color = Color(0.8, 0.6, 0.2) # Sandy Orange
			"Jungle":
				bg_color = Color(0.1, 0.4, 0.1) # Forest Green
			_: # Overworld, etc.
				bg_color = Color(0.36, 0.58, 0.98) # Classic SMB Blue

	_update_style(bg_color, text_color)

	if is_targeting_me:
		modulate = Color(1.0, 0.8, 0.8)
	else:
		modulate = Color.WHITE

func _update_style(bg_color: Color, text_color: Color) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	add_theme_stylebox_override("panel", style)
	
	if name_label:
		name_label.add_theme_color_override("font_color", text_color)
	if status_label:
		status_label.modulate = Color.WHITE
		status_label.add_theme_color_override("font_color", text_color)
