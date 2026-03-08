extends Control

## Pre-match loading screen. Shown to all players after the host presses
## START GAME. Each client pre-loads the first level in the background,
## then signals the host that it is ready.  Once every connected player
## has reported in, the host fires `start_match` and everyone drops into
## the level simultaneously with a perfectly synchronised timer.
## Practice mode skips the wait and goes straight to the level.

@onready var status_label: Label = $BG/VBox/StatusLabel

var level_path := ""
var level_resource = null  # Will hold the loaded PackedScene
var reported_ready := false
var match_started := false

# Mario run animation — uses a Sprite2D added directly to the scene root
# so it's not clipped by the VBox layout
var mario_sprite: Sprite2D = null
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
	
	# Setup Mario sprite as a free Sprite2D (not constrained by VBox)
	_setup_mario_sprite()
	
	# Remove the placeholder MarioContainer from the scene tree if present
	var placeholder = get_node_or_null("BG/VBox/MarioContainer")
	if placeholder:
		placeholder.queue_free()
	
	status_label.text = "LOADING... PLEASE WAIT"

func _setup_mario_sprite() -> void:
	var tex = load("res://Assets/Sprites/Players/Mario/Small.json")
	if not tex:
		return
	
	mario_sprite = Sprite2D.new()
	mario_sprite.texture = AtlasTexture.new()
	mario_sprite.texture.atlas = tex
	mario_sprite.texture.region = run_frames[0]
	mario_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mario_sprite.scale = Vector2(2, 2) # 64×64 display size
	mario_sprite.z_index = 10
	add_child(mario_sprite)
	
	# Position vertically in the lower third of the screen
	var vp_h = get_viewport_rect().size.y
	mario_sprite.position.y = vp_h * 0.7

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
			if Mario35Handler.is_practice:
				status_label.text = "STARTING" + dots
			else:
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
			_on_load_complete()
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			# Fallback: load synchronously
			level_resource = load(level_path)
			_on_load_complete()

func _on_load_complete() -> void:
	reported_ready = true
	
	# Practice mode: skip waiting for other players, go straight to the level
	if Mario35Handler.is_practice:
		status_label.text = "STARTING..."
		# Small delay so the player can see the screen
		await get_tree().create_timer(0.5, false).timeout
		go_to_level()
		return
	
	status_label.text = "WAITING FOR PLAYERS..."
	# Tell the host we are ready
	Mario35Network.client_scene_ready.rpc_id(1)

func _animate_mario(delta: float) -> void:
	if not mario_sprite:
		return
	
	# Move Mario across the screen
	var vp_width = get_viewport_rect().size.x
	mario_x += MARIO_SPEED * delta
	if mario_x > vp_width + 32:
		mario_x = -64.0
	
	mario_sprite.position.x = mario_x
	# Keep vertical position updated for window resize
	mario_sprite.position.y = get_viewport_rect().size.y * 0.7
	
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
	
	# Use Global.transition_to_scene to properly manage the transitioning_scene flag.
	# Without this, the flag stays true and ALL subsequent transitions (pipe entry,
	# level completion, etc.) silently fail, freezing the game.
	Global.transition_to_scene(level_path)
