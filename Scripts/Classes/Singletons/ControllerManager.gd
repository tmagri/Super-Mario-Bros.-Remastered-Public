extends Node

# Auto-assigns connected controllers to player slots
# Maps standard actions (jump_N, run_N, etc.) to the specific device ID

const MAX_PLAYERS = 4
const ACTIONS_TO_MAP = [
	"jump",
	"run",
	"action",
	"move_left",
	"move_right",
	"move_up",
	"move_down"
]

const UI_ACTIONS = [
	"ui_left",
	"ui_right",
	"ui_up",
	"ui_down",
	"ui_accept",
	"ui_cancel",
	"ui_select",
	"pause"
]

# Map player index to device ID. -1 means no controller assigned.
var player_devices = [-1, -1, -1, -1]

func _ready():
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	refresh_controllers()

func refresh_controllers():
	var connected_joypads = Input.get_connected_joypads()
	print("Connected Joypads: ", connected_joypads)
	
	# Reset assignments
	for i in range(MAX_PLAYERS):
		player_devices[i] = -1
	
	# Assign connected controllers to players sequentially
	var player_idx = 0
	for device_id in connected_joypads:
		if player_idx < MAX_PLAYERS:
			assign_controller(player_idx, device_id)
			player_idx += 1

func _on_joy_connection_changed(device_id: int, connected: bool):
	var name = Input.get_joy_name(device_id)
	if connected:
		print("Controller connected: " + name + " (Device " + str(device_id) + ")")
	else:
		print("Controller disconnected: " + name + " (Device " + str(device_id) + ")")
	
	# Refresh assignments on any change
	refresh_controllers()

func assign_controller(player_index: int, device_id: int):
	print("Assigning Device " + str(device_id) + " to Player " + str(player_index))
	player_devices[player_index] = device_id
	
	var suffix = "_" + str(player_index)
	
	# Map Player Specific Actions
	for action_base in ACTIONS_TO_MAP:
		var action_name = action_base + suffix
		_remap_action_to_device(action_name, device_id)
	
	# If this is Player 0, also map UI actions
	if player_index == 0:
		for action_name in UI_ACTIONS:
			_remap_action_to_device(action_name, device_id)

	print("Input mapped for Player " + str(player_index))

func _remap_action_to_device(action_name: String, device_id: int):
	if not InputMap.has_action(action_name):
		# push_warning("Action not found: " + action_name)
		return

	var events = InputMap.action_get_events(action_name)
	var joy_events_to_add = []
	
	for event in events:
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			var new_event = event.duplicate()
			new_event.device = device_id
			joy_events_to_add.append(new_event)
			# Remove old event
			InputMap.action_erase_event(action_name, event)
	
	for event in joy_events_to_add:
		InputMap.action_add_event(action_name, event)


