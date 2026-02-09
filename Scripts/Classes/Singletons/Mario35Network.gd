extends Node

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected
signal connection_failed
signal player_list_changed
signal server_found(ip, info)

const PORT = 7000
const BROADCAST_PORT = 7001
const DEFAULT_SERVER_IP = "127.0.0.1"

var room_key := ""
var udp_server := PacketPeerUDP.new()
var discovery_listener := PacketPeerUDP.new()
var broadcast_timer: Timer = null

var peer: ENetMultiplayerPeer = null
var players = {}
var registration_timer: Timer = null
var player_info = {
	"name": "Player",
	"character": 0, # Mario
	"skin_id": "0" # Default skin
}

func register_player(data_json):
	var data = JSON.parse_string(data_json)
	if not data: return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var actual_id = sender_id if sender_id != 0 else 1
	
	print("[SYNC] Registering ID ", actual_id, ": ", data.get("name", "Unknown"))
	players[actual_id] = data
	
	if multiplayer.is_server():
		_broadcast_list()

func update_list(json_list):
	var data = JSON.parse_string(json_list)
	if not data: return
	
	print("[SYNC] List update received. Size: ", data.size())
	players = {}
	for k in data:
		players[int(k)] = data[k]
	
	player_list_changed.emit()

func verify_key(key):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if not room_key.is_empty() and key != room_key:
		print("[HOST] Kick player ", sender_id)
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)

func start_game(settings = {}):
	if not settings.is_empty():
		Mario35Handler.apply_settings(settings)
	Mario35Handler.start_game(Mario35Handler.start_time, Mario35Handler.max_time)
	Global.transition_to_scene(Mario35Handler.get_next_level_path())

func send_enemy(type):
	Mario35Handler.receive_enemy(type)

func notify_death(id, rank):
	Mario35Handler.sync_death(int(id), int(rank))

func broadcast_stats(time: int, coins: int, target: int, kills: int) -> void:
	receive_stats.rpc(time, coins, target, kills)

@rpc("any_peer", "call_remote", "unreliable") # Unreliable is fine for freq stats
func receive_stats(time: int, coins: int, target: int, kills: int) -> void:
	var sender = multiplayer.get_remote_sender_id()
	Mario35Handler.receive_stats(sender, time, coins, target, kills)

func _broadcast_list():
	if multiplayer.is_server():
		# Use rpc_id(0) to ensure it reaches everyone even in manual mode
		update_list.rpc(JSON.stringify(players))
# --------------------------------------------------

func _ready():
	print("[NETWORK] Mario35Network Initialized. Version: 2026-02-08-v15-BR-OVERHAUL")
	
	# MANUAL RPC CONFIGURATION (Godot 4 fallback)
	var config_any = {
		"rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER,
		"transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE,
		"call_local": true,
		"channel": 0
	}
	var config_auth = {
		"rpc_mode": MultiplayerAPI.RPC_MODE_AUTHORITY,
		"transfer_mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE,
		"call_local": true,
		"channel": 0
	}
	
	rpc_config("register_player", config_any)
	rpc_config("update_list", config_any) # Set to any_peer for easier cross-platform match
	rpc_config("verify_key", config_any)
	rpc_config("start_game", config_any) # Should be auth-only, but using any for debug
	rpc_config("send_enemy", config_any)
	rpc_config("notify_death", config_any)
	rpc_config("receive_stats", config_any) # Using reliable config for simplicity even if func unchecked
	# Dedicated server support
	if "--server" in OS.get_cmdline_args():
		print("Starting dedicated server...")
		host_game()
	
	process_mode = PROCESS_MODE_ALWAYS # Ensure networking stays alive during transitions
	
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Setup discovery
	udp_server.set_broadcast_enabled(true)
	discovery_listener.bind(BROADCAST_PORT)

func _process(_delta):
	# Poll for LAN broadcasts
	if discovery_listener.get_available_packet_count() > 0:
		var packet = discovery_listener.get_packet().get_string_from_utf8()
		var ip = discovery_listener.get_packet_ip()
		var info = JSON.parse_string(packet)
		if info:
			server_found.emit(ip, info)

func host_game(key: String = "", use_upnp: bool = true):
	_cleanup()
	room_key = key
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	
	# Register self locally
	players[1] = player_info
	player_list_changed.emit()
	
	# Start LAN broadcasting
	_start_broadcasting()
	
	# Attempt UPNP in a thread to avoid blocking if enabled
	if use_upnp and not "--no-upnp" in OS.get_cmdline_args():
		var thread = Thread.new()
		thread.start(_upnp_setup)
	
	return OK

func _start_broadcasting():
	if is_instance_valid(broadcast_timer):
		broadcast_timer.queue_free()
	
	broadcast_timer = Timer.new()
	broadcast_timer.wait_time = 2.0
	broadcast_timer.autostart = true
	broadcast_timer.timeout.connect(_broadcast_presence)
	add_child(broadcast_timer)

func _broadcast_presence():
	var server_info = {
		"name": player_info.name,
		"players": players.size(),
		"has_key": not room_key.is_empty()
	}
	var packet = JSON.stringify(server_info).to_utf8_buffer()
	udp_server.set_dest_address("255.255.255.255", BROADCAST_PORT)
	udp_server.put_packet(packet)

func _upnp_setup():
	var upnp = UPNP.new()
	var discover_result = upnp.discover()
	if discover_result == UPNP.UPNP_RESULT_SUCCESS:
		if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
			upnp.add_port_mapping(PORT, PORT, "SMB1R Battle Royale", "UDP") # ENet is UDP
			print("UPNP Port Mapping Successful. External IP: " + upnp.query_external_address())

func join_game(address: String = "", key: String = ""):
	_cleanup()
	room_key = key
	
	if address.is_empty():
		address = DEFAULT_SERVER_IP
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK

func leave_game():
	_cleanup()

func _cleanup():
	players.clear()
	room_key = "" # HARD RESET
	player_list_changed.emit()
	
	if is_instance_valid(registration_timer):
		registration_timer.stop()
	
	if is_instance_valid(broadcast_timer):
		broadcast_timer.queue_free()
		broadcast_timer = null
		
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if peer:
		peer.close()
		peer = null

func _on_player_connected(id):
	print("[NETWORK] Peer connected: ", id)
	if multiplayer.is_server():
		# If host, ask joiner for key if one is set
		if not room_key.is_empty():
			# Just call the verify logic directly or via RPC if needed
			# Given sync issues, we'll wait for them to send it
			pass
	elif id == 1:
		# Client side: We see the server.
		print("[CLIENT] Detected host (1). Registering...")
		register_player.rpc_id(1, JSON.stringify(player_info))

func _on_player_disconnected(id):
	print("[NETWORK] Peer disconnected: ", id)
	players.erase(id)
	player_disconnected.emit(id)
	
	if multiplayer.is_server():
		# Host broadcasts updated list after someone leaves
		_broadcast_list()
	
	player_list_changed.emit()

func _on_connected_ok():
	var my_id = multiplayer.get_unique_id()
	print("[CLIENT] Connection established. My ID: ", my_id)
	
	# Add self locally for immediate feedback
	players[my_id] = player_info
	player_list_changed.emit()
	
	# Register self to host
	register_player.rpc_id(1, JSON.stringify(player_info))
	
	# If client joins a keyed room, send the key immediately
	if not room_key.is_empty():
		verify_key.rpc_id(1, room_key)

func _on_connected_fail():
	print("[CLIENT] Connection failed")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()

func _on_server_disconnected():
	print("[CLIENT] Server disconnected")
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()
	player_list_changed.emit()

# Removed obsolete functions
