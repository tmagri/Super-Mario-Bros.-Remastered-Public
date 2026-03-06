extends Panel

const SUPERSAMPLE = 4.0
const COIN_JSON = preload("res://Assets/Sprites/Items/Coin.json")
const HAMMER_JSON = preload("res://Assets/Sprites/Items/HammerIcon.json")
const FONT_NORMAL = preload("res://Resources/ThemedResources/FontMario35.tres")
const FONT_TITLE = preload("res://Assets/Fonts/FontMario35Title.otf")

@onready var name_label = %NameLabel
@onready var status_label = %StatusLabel
@onready var mario_sprite = %MarioSprite
@onready var vbox0 = $VBox

var is_stat := false
var current_chara_idx := 0
var current_power_idx := 0
var time_passed := 0.0

# Special state flags for visual effects
var has_star := false
var has_hammer := false
var has_mega := false
var blink_timer := 0.0

var coin_icon: AnimatedSprite2D = null
var coin_rs: ResourceSetterNew = null
var _last_coin_theme := ""

var hammer_icon: AnimatedSprite2D = null
var hammer_rs: ResourceSetterNew = null

func _ready() -> void:
	# Create coin icon programmatically (same pattern as GameHUD.gd)
	coin_icon = AnimatedSprite2D.new()
	coin_icon.name = "CoinIcon"
	coin_icon.visible = false
	coin_icon.z_index = 10
	coin_icon.centered = true
	add_child(coin_icon)
	
	coin_rs = ResourceSetterNew.new()
	coin_rs.name = "CoinRS"
	coin_rs.node_to_affect = coin_icon
	coin_rs.property_name = "sprite_frames"
	coin_rs.resource_json = COIN_JSON
	coin_icon.add_child(coin_rs)
	coin_icon.play("default")
	
	# Create hammer icon programmatically
	hammer_icon = AnimatedSprite2D.new()
	hammer_icon.name = "HammerIcon"
	hammer_icon.visible = false
	hammer_icon.z_index = 10
	hammer_icon.centered = true
	add_child(hammer_icon)
	
	hammer_rs = ResourceSetterNew.new()
	hammer_rs.name = "HammerRS"
	hammer_rs.node_to_affect = hammer_icon
	hammer_rs.property_name = "sprite_frames"
	hammer_rs.resource_json = HAMMER_JSON
	hammer_icon.add_child(hammer_rs)
	hammer_icon.play("default")

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
	# Dynamic Scaling for any screen size (especially Ultrawide)
	if mario_sprite:
		var sprite_margin = 2.0
		var sprite_target_w = size.x - sprite_margin * 2.0
		var sprite_target_h = size.y * (0.5 if is_stat else 0.6) # Allocate portion of card to sprite
		
		var max_dim = 32.0 # Standard size
		var calc_scale = min(sprite_target_w / max_dim, sprite_target_h / max_dim)
		var base_scale = clamp(calc_scale, 0.15, 1.0) # Minimum 15% scale to remain visible
		
		mario_sprite.pivot_offset = mario_sprite.size / 2.0
		
		if has_mega or current_power_idx == 4: # Mega: blink effect
			time_passed += delta
			var pulse = base_scale + sin(time_passed * 10.0) * (base_scale * 0.15)
			mario_sprite.scale = Vector2(pulse, pulse)
			# Blinking visibility
			blink_timer += delta
			mario_sprite.modulate.a = 1.0 if fmod(blink_timer, 0.3) < 0.15 else 0.5
		elif has_star: # Star: palette cycle
			time_passed += delta
			mario_sprite.scale = Vector2(base_scale, base_scale)
			# The shader overrides modulate, so we cycle the palette index to blink!
			var cycle_idx = int(time_passed * 15.0) % 4
			mario_sprite.material.set_shader_parameter("palette_idx", cycle_idx)
		else:
			mario_sprite.scale = Vector2(base_scale, base_scale)
			mario_sprite.modulate = Color.WHITE
			blink_timer = 0.0
			mario_sprite.material.set_shader_parameter("palette_idx", current_power_idx)
	
	if (coin_icon and coin_icon.visible) or (hammer_icon and hammer_icon.visible):
		_position_icons()

	# Snapshot injected sizes from WidescreenHUD before mathematical alterations
	if custom_minimum_size.x > size.x:
		size = custom_minimum_size

	if not vbox0 or size.x <= 0 or size.y <= 0:
		return

	if is_stat:
		var target_w = size.x - 4
		var sprite_h = mario_sprite.size.y if mario_sprite and mario_sprite.visible else 0
		var top_pad = vbox0.offset_top if vbox0 else 0
		var remaining_h = size.y - sprite_h - top_pad - 4
		
		# Add a generous safety margin
		var safe_h = remaining_h - 4
		
		# Instead of counting lines mathematically, just calculate the best font size
		# using Godot's multiline bounds and arbitrarily shrink it to guarantee fit.
		var fs_best = 4 # Fallback to minimum
		var font = name_label.get_theme_font("font") if name_label else null
		if font:
			# Loop down to 4px to ensure it fits in tiny sidebars
			for fs in range(24, 4, -1):
				var n_size = font.get_multiline_string_size(name_label.text, name_label.horizontal_alignment, target_w, fs)
				var s_size = font.get_multiline_string_size(status_label.text, status_label.horizontal_alignment, target_w, fs)
				if n_size.x <= target_w and s_size.x <= target_w and (n_size.y + s_size.y) <= remaining_h + 2:
					# Force the font a couple points smaller unconditionally to prevent cutoff
					fs_best = max(4, fs - 2) 
					break
		
		# Apply the calculated font size
		if name_label:
			name_label.add_theme_font_size_override("font_size", fs_best)
			name_label.add_theme_constant_override("line_spacing", 0) # Natural spacing
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if status_label:
			status_label.add_theme_font_size_override("font_size", fs_best)
		
		if vbox0:
			vbox0.add_theme_constant_override("separation", 1)
		return

	# Iterate to find the best font size that fits the space
	var target_width = size.x - 4
	var target_height = int(size.y * 0.35) 
	
	var best_size = 4 # Fallback to minimum
	if name_label and name_label.text != "":
		var font = name_label.get_theme_font("font")
		if font:
			# Loop down to 4px to ensure it fits in tiny sidebars
			for fs in range(16, 4, -1):
				var string_size = font.get_string_size(name_label.text, name_label.horizontal_alignment, -1, fs)
				if string_size.x <= target_width and string_size.y <= target_height:
					best_size = fs
					break

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
		name_label.add_theme_font_override("font", FONT_NORMAL)
		name_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func setup_as_stat(title: String, value: String, power_state: int = 0, coins: int = 0, p_has_star: bool = false, p_has_hammer: bool = false, p_has_mega: bool = false) -> void:
	is_stat = true
	has_star = p_has_star
	has_hammer = p_has_hammer
	has_mega = p_has_mega
	var chara_idx = int(Global.player_characters[0])
	_update_icon(chara_idx, power_state)
	
	# Add padding above the Mario sprite for stat cards by pushing the VBox down
	if vbox0:
		vbox0.offset_top = 8
	
	if name_label:
		name_label.text = title
		name_label.visible = title != ""
		name_label.clip_text = false
		name_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_override("font", FONT_TITLE)
		name_label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if status_label:
		status_label.text = value
		status_label.visible = value != ""
		status_label.clip_text = false
		status_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	
	_update_style(Color.WHITE, Color.BLACK)
	
	# Show coin icon on stat cards when player has 20+ coins
	if coin_icon:
		var show_coin = coins >= 20
		coin_icon.visible = show_coin
		
	# Show hammer icon on stat cards when player has hammer
	if hammer_icon:
		hammer_icon.visible = has_hammer
		
	if (coin_icon and coin_icon.visible) or (hammer_icon and hammer_icon.visible):
		_position_icons()
		var theme = Global.level_theme if Global.level_theme else "Overworld"
		if coin_rs and _last_coin_theme != theme:
			_last_coin_theme = theme
			coin_rs.force_properties = {"Theme": theme}
			coin_rs.update_resource()

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

	if coin_icon:
		var show_coin = coins >= 20
		
		# Practice Mode: Force show on all cards for testing
		if Mario35Handler.is_practice:
			show_coin = true
		
		coin_icon.visible = show_coin
		
	if hammer_icon:
		hammer_icon.visible = has_hammer
		
	if (coin_icon and coin_icon.visible) or (hammer_icon and hammer_icon.visible):
		_position_icons()
		
		if coin_rs and _last_coin_theme != theme:
			_last_coin_theme = theme
			coin_rs.force_properties = {"Theme": theme}
			coin_rs.update_resource()
	else:
		_last_coin_theme = ""

func _position_icons() -> void:
	var mario_scale = mario_sprite.scale.x if mario_sprite else 0.5
	var icon_scale = mario_scale * 0.5
	
	var right_offset = 4
	if coin_icon and coin_icon.visible:
		coin_icon.position = Vector2(size.x - right_offset, right_offset)
		coin_icon.scale = Vector2(icon_scale, icon_scale)
		right_offset += 16 * icon_scale + 2
		
	if hammer_icon and hammer_icon.visible:
		hammer_icon.position = Vector2(size.x - right_offset, 4)
		hammer_icon.scale = Vector2(icon_scale, icon_scale)

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
