extends Node

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected
signal connection_failed
signal player_list_changed

const PORT = 7000
const DEFAULT_SERVER_IP = "127.0.0.1" # Localhost for now, can be changed later

var peer: WebSocketMultiplayerPeer = null
var players = {}
var player_info = {
	"name": "Player",
	"character": 0, # Mario
	"skin_id": "0" # Default skin
}

func _ready():
	if "--server" in OS.get_cmdline_args():
		print("Starting dedicated server...")
		host_game()
	
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game():
	_cleanup()
	
	peer = WebSocketMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	
	# Attempt UPNP in a thread to avoid blocking
	if not "--no-upnp" in OS.get_cmdline_args():
		Thread.new().start(_upnp_setup)
	
	# Attempt UPNP

func _upnp_setup():
	var upnp = UPNP.new()
	var discover_result = upnp.discover()
	if discover_result == UPNP.UPNP_RESULT_SUCCESS:
		if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
			upnp.add_port_mapping(PORT, PORT, "SMB1R Battle Royale", "TCP")
			print("UPNP Port Mapping Successful. External IP: " + upnp.query_external_address())
	
	# Register self
	players[1] = player_info
	player_list_changed.emit()
	return OK

func join_game(address: String = ""):
	_cleanup()
	
	if address.is_empty():
		address = DEFAULT_SERVER_IP
	
	peer = WebSocketMultiplayerPeer.new()
	var error = peer.create_client("ws://" + address + ":" + str(PORT))
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK

func leave_game():
	_cleanup()
	players.clear()
	player_list_changed.emit()

func _cleanup():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if peer:
		peer.close()
		peer = null

func _on_player_connected(id):
	# Upon connection, register self to the new player (or server)
	_register_player.rpc_id(id, player_info)

func _on_player_disconnected(id):
	players.erase(id)
	player_disconnected.emit(id)
	player_list_changed.emit()

func _on_connected_ok():
	# Only meaningful for client
	pass

func _on_connected_fail():
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
	player_list_changed.emit()

@rpc("any_peer", "reliable")
func _register_player(info):
	var id = multiplayer.get_remote_sender_id()
	players[id] = info
	player_connected.emit(id, info)
	player_list_changed.emit()

@rpc("call_local", "reliable")
func start_game(settings: Dictionary = {}):
	if not settings.is_empty():
		Mario35Handler.apply_settings(settings)
	
	Mario35Handler.start_game(Mario35Handler.start_time, Mario35Handler.max_time)
	
	# Transition to first level (randomized or fixed)
	# For now, start with World 1-1, but we should probably use a Randomizer logic here later
	Global.transition_to_scene("res://Scenes/Levels/World11.tscn")

@rpc("any_peer", "reliable")
func send_enemy(type: String):
	Mario35Handler.receive_enemy(type)
