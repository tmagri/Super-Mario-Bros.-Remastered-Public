extends Control

## Pre-match loading screen. Shown to all players after the host presses
## START GAME. Each client pre-loads the first level in the background,
## then signals the host that it is ready.  Once every connected player
## has reported in, the host fires `start_match` and everyone drops into
## the level simultaneously with a perfectly synchronised timer.

@onready var status_label: Label = $BG/VBox/StatusLabel
@onready var mario_sprite: TextureRect = $BG/VBox/MarioContainer/MarioSprite

var level_path := ""
var level_resource = null  # Will hold the loaded PackedScene
var reported_ready := false
var match_started := false

# Mario run animation
var mario_x := -32.0
var mario_frame := 0
var frame_timer := 0.0
const MARIO_SPEED := 80.0
const FRAME_INTERVAL := 0.12
var run_frames: Array[Rect2] = [
	Rect2(64, 0, 32, 32),   # Move frame 1
	Rect2(128, 0, 32, 32),  # Move frame 2
	Rect2(96, 0, 32, 32),   # Move frame 3
]

var dots_timer := 0.0
var dots_count := 0

func _ready() -> void:
	AudioManager.stop_all_music()
	
	# Determine the level we need to pre-load
	level_path = Mario35Handler.pending_level_path
	
	# Start threaded background load
	if not level_path.is_empty():
		ResourceLoader.load_threaded_request(level_path)
	
	# Setup Mario sprite from the spritesheet
	_setup_mario_sprite()
	
	# Dot animation for "LOADING..."
	status_label.text = "LOADING... PLEASE WAIT"

func _setup_mario_sprite() -> void:
	var tex = load("res://Assets/Sprites/Players/Mario/Small.png")
	if tex and mario_sprite:
		var atlas = AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = run_frames[0]
		mario_sprite.texture = atlas
		mario_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mario_sprite.custom_minimum_size = Vector2(64, 64)
		mario_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _process(delta: float) -> void:
	if match_started:
		return
	
	# Animate dots on status label
	dots_timer += delta
	if dots_timer >= 0.5:
		dots_timer = 0.0
		dots_count = (dots_count + 1) % 4
		var dots = ".".repeat(dots_count)
		if reported_ready:
			status_label.text = "WAITING FOR PLAYERS" + dots
		else:
			status_label.text = "LOADING" + dots + " PLEASE WAIT"
	
	# Animate Mario running across the screen
	_animate_mario(delta)
	
	# Check threaded load status
	if not reported_ready and not level_path.is_empty():
		var status = ResourceLoader.load_threaded_get_status(level_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			level_resource = ResourceLoader.load_threaded_get(level_path)
			reported_ready = true
			status_label.text = "WAITING FOR PLAYERS..."
			# Tell the host we are ready
			Mario35Network.client_scene_ready.rpc_id(1)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			# Fallback: load synchronously
			level_resource = load(level_path)
			reported_ready = true
			Mario35Network.client_scene_ready.rpc_id(1)

func _animate_mario(delta: float) -> void:
	if not mario_sprite:
		return
	
	# Move Mario across the screen
	var vp_width = get_viewport_rect().size.x
	mario_x += MARIO_SPEED * delta
	if mario_x > vp_width + 32:
		mario_x = -64.0
	
	# Position the MarioContainer's offset so it moves left-to-right
	var container = mario_sprite.get_parent()
	if container:
		# We move the sprite itself relative to its container
		mario_sprite.position.x = mario_x - mario_sprite.size.x / 2.0
	
	# Cycle run frames
	frame_timer += delta
	if frame_timer >= FRAME_INTERVAL:
		frame_timer = 0.0
		mario_frame = (mario_frame + 1) % run_frames.size()
		if mario_sprite.texture is AtlasTexture:
			mario_sprite.texture.region = run_frames[mario_frame]

func go_to_level() -> void:
	if match_started:
		return
	match_started = true
	
	# Unpause the game timer
	Mario35Handler.is_timer_paused = false
	
	# Transition to the loaded level
	if level_resource:
		get_tree().change_scene_to_packed(level_resource)
	else:
		# Fallback
		Global.transition_to_scene(level_path)
