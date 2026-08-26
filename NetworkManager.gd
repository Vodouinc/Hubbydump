extends Node

const DEFAULT_PORT: int = 7777

var peer: ENetMultiplayerPeer = null
var upnp: UPNP = null
var upnp_thread: Thread = null
var is_upnp_active: bool = false

# Signals for your UI
signal host_created(invite_code: String)
signal host_failed(error_message: String)
signal join_success()
signal join_failed(error_message: String)

func _ready() -> void:
	# Ensure port is released if the game is closed
	process_mode = Node.PROCESS_MODE_ALWAYS

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		cleanup_network()

# ------------------------------------------------------------------------------
# 1. HOSTING WITH UPNP (Threaded to prevent UI freeze)
# ------------------------------------------------------------------------------
func host_game(port: int = DEFAULT_PORT) -> void:
	cleanup_network()
	
	upnp_thread = Thread.new()
	upnp_thread.start(_thread_setup_upnp.bind(port))

func _thread_setup_upnp(port: int) -> void:
	upnp = UPNP.new()
	var discover_err = upnp.discover(2000, 2, "InternetGatewayDevice")
	var external_ip: String = ""

	if discover_err == UPNP.UPNP_RESULT_SUCCESS:
		var gateway = upnp.get_gateway()
		if gateway and gateway.is_valid_gateway():
			var map_udp = upnp.add_port_mapping(port, port, "Godot_Admech_UDP", "UDP")
			if map_udp == UPNP.UPNP_RESULT_SUCCESS:
				is_upnp_active = true
				external_ip = upnp.query_external_address()
				print("[UPnP] Successfully mapped UDP port ", port, " on IP: ", external_ip)
			else:
				print("[UPnP] Port mapping failed with code: ", map_udp)
		else:
			print("[UPnP] No valid gateway router found.")
	else:
		print("[UPnP] UPnP discovery failed with code: ", discover_err)

	# Return to main thread to start the server
	_finish_host_on_main_thread.call_deferred(port, external_ip)

func _finish_host_on_main_thread(port: int, external_ip: String) -> void:
	if upnp_thread and upnp_thread.is_started():
		upnp_thread.wait_to_finish()
		upnp_thread = null

	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, 4) # Up to 4 players
	if err != OK:
		emit_signal("host_failed", "Failed to start server on port %d (Error: %s)" % [port, str(err)])
		return

	multiplayer.multiplayer_peer = peer

	# Prioritize external public IP, fallback to local network IP for LAN
	var final_ip = external_ip if not external_ip.is_empty() else _get_local_ip()
	var code = generate_invite_code(final_ip, port)
	
	print("[Network] Server active! Invite Code: ", code, " (Target IP: ", final_ip, ")")
	emit_signal("host_created", code)

# ------------------------------------------------------------------------------
# 2. JOINING WITH INVITE CODE
# ------------------------------------------------------------------------------
func join_game(invite_code: String) -> void:
	cleanup_network()

	var connection_info = decode_invite_code(invite_code.strip_edges())
	if connection_info.is_empty() or not connection_info.has("ip"):
		emit_signal("join_failed", "Invalid Invite Code format!")
		return

	var target_ip = connection_info["ip"]
	var target_port = connection_info.get("port", DEFAULT_PORT)

	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(target_ip, target_port)
	if err != OK:
		emit_signal("join_failed", "Cannot initiate connection to " + target_ip)
		return

	multiplayer.multiplayer_peer = peer
	
	# Hook into connection signals
	multiplayer.connected_to_server.connect(_on_connected, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)

func _on_connected() -> void:
	print("[Network] Successfully connected to host!")
	emit_signal("join_success")

func _on_connection_failed() -> void:
	print("[Network] Connection timed out or rejected.")
	cleanup_network()
	emit_signal("join_failed", "Connection timed out. Host port may be closed or firewalled.")

# ------------------------------------------------------------------------------
# 3. HELPERS (Invite Code Generator & Cleanup)
# ------------------------------------------------------------------------------
func generate_invite_code(ip: String, port: int) -> String:
	var payload = "%s:%d" % [ip, port]
	return Marshalls.utf8_to_base64(payload)

func decode_invite_code(code: String) -> Dictionary:
	var raw = Marshalls.base64_to_utf8(code)
	if ":" in raw:
		var parts = raw.split(":")
		return {"ip": parts[0], "port": int(parts[1])}
	elif raw.is_valid_ip_address():
		return {"ip": raw, "port": DEFAULT_PORT}
	return {}

func _get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or (ip.begins_with("172.") and not ip.begins_with("172.16.")):
			return ip
	return "127.0.0.1"

func cleanup_network() -> void:
	if is_upnp_active and upnp:
		upnp.delete_port_mapping(DEFAULT_PORT, "UDP")
		is_upnp_active = false
		print("[UPnP] Cleaned up port mapping.")

	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null

	if peer:
		peer.close()
		peer = null
