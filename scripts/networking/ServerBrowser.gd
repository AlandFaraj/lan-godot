extends Control

signal joinGame(ip)
var broadcastTimer: Timer

var RoomInfo = {"name": "name", "playerCount": 0}
var broadcaster: PacketPeerUDP
var discovery_broadcaster: PacketPeerUDP # For additional discovery
var listner: PacketPeerUDP
@export var listenPort: int = 8911
@export var broadcastPort: int = 8912
@export var broadcastAddress: String = "255.255.255.255" # Global broadcast for better discovery

# Known ports to try initially (will dynamically add more)
var broadcast_ports = [8911, 49152, 49153, 49154, 49155]
var known_servers = {} # Track known servers with timestamps
var discovery_cooldown = {} # Prevent duplicate discovery processing
var cooldown_time = 3.0 # Seconds between processing discoveries
var instance_id: String # Unique identifier for this instance
var server_list_update_timer: Timer # Timer for periodic UI updates
var server_entry_nodes = {} # Track UI nodes for each server
var is_hosting_game = false

@export var serverInfo: PackedScene

# Path to the container where server entries are added
var server_list_container_path = "/root/Control/MainPanel/MarginContainer/VBoxContainer/ServerListContainer/ServerListScroll/ServerContainer"

# Called when the node enters the scene tree for the first time.
func _ready():
	broadcastTimer = $BroadcastTimer
	instance_id = str(randi()).substr(0, 4)
	print("Instance ID: ", instance_id)
	setUp()
	setup_discovery()
	setup_server_list_update_timer()
	
func setUp():
	listner = PacketPeerUDP.new()
	
	# Try to bind to the default listen port
	var ok = listner.bind(listenPort)
	
	# If binding to the default port fails, try binding to any available port (0)
	if ok != OK:
		print("Default listen port " + str(listenPort) + " is busy, trying alternative...")
		ok = listner.bind(0) # Bind to any available port
		if ok != OK:
			printerr("Failed to bind to any listen port!")
			return
		else:
			# Successfully bound to an alternative port
			var actual_port = listner.get_local_port()
			print("Listening on alternative port: " + str(actual_port))
			# Update the listenPort to the new port so we know where to listen
			listenPort = actual_port
			
			# Add this port to our broadcast list
			if not broadcast_ports.has(actual_port):
				broadcast_ports.append(actual_port)
	else:
		print("Listening for servers on port: " + str(listenPort))

func setup_discovery():
	# Discovery socket for all clients (browser and host)
	discovery_broadcaster = PacketPeerUDP.new()
	discovery_broadcaster.set_broadcast_enabled(true)
	
	# Bind to any available port for discovery
	if discovery_broadcaster.bind(0) != OK:
		printerr("Failed to bind discovery broadcaster!")
		return
		
	print("Discovery service bound to port: ", discovery_broadcaster.get_local_port())
	
	# Send initial discovery broadcast
	_send_discovery_broadcast()
	
	# Set up a timer for regular discovery broadcasts
	var discovery_timer = Timer.new()
	discovery_timer.wait_time = 2.0
	discovery_timer.autostart = true
	discovery_timer.one_shot = false
	discovery_timer.timeout.connect(_on_discovery_timer_timeout)
	add_child(discovery_timer)

func setup_server_list_update_timer():
	# Set up a timer for periodically updating the server list UI
	server_list_update_timer = Timer.new()
	server_list_update_timer.wait_time = 1.0
	server_list_update_timer.autostart = true
	server_list_update_timer.one_shot = false
	server_list_update_timer.timeout.connect(_on_server_list_update_timer_timeout)
	add_child(server_list_update_timer)

func setUpBroadCast(roomName):
	RoomInfo.name = roomName
	RoomInfo.playerCount = GameManager.Players.size()
	RoomInfo.instance_id = instance_id
	RoomInfo.listen_port = listenPort
	
	broadcaster = PacketPeerUDP.new()
	broadcaster.set_broadcast_enabled(true)
	
	# Try binding to the broadcast port
	var ok = broadcaster.bind(broadcastPort)
	if ok != OK:
		print("Default broadcast port busy, trying alternative...")
		ok = broadcaster.bind(0) # Bind to any available port if specific one fails
		if ok != OK:
			printerr("Failed to bind broadcaster to any port.")
			broadcaster = null # Clear broadcaster if bind failed
			return
		else:
			print("Bound broadcaster to available port: ", broadcaster.get_local_port())
	else:
		print("Bound broadcaster to port: ", broadcastPort)
	
	$BroadcastTimer.start()
	
	# Only add the local server entry if actually hosting the game
	if is_hosting_game:
		var info = {
			"name": RoomInfo.name,
			"playerCount": RoomInfo.playerCount,
			"instance_id": instance_id,
			"listen_port": listenPort,
			"is_hosting_game": true
		}
		update_server_info("127.0.0.1", info)
	
	# Send initial broadcasts to all known ports
	_broadcast_to_all_ports()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	if listner and listner.get_available_packet_count() > 0:
		var server_ip = listner.get_packet_ip()
		var bytes = listner.get_packet()
		var data = bytes.get_string_from_ascii()
		
		# Use JSON validation for safety
		var result = JSON.parse_string(data)
		if not result or typeof(result) != TYPE_DICTIONARY:
			# Skip invalid data
			return
			
		# Check if this is a discovery message or game info
		if result.has("message_type") and result.message_type == "discovery":
			_handle_discovery_message(server_ip, result)
		elif result.has("name") and result.has("playerCount"):
			# Don't process our own broadcasts unless from localhost and we're hosting
			if result.has("instance_id") and result.instance_id == instance_id:
				if not is_hosting_game:
					return # Don't process our own info if not hosting
				elif server_ip != "127.0.0.1":
					return # Skip non-localhost messages from our instance
			
			# Process the room info by updating server tracking
			update_server_info(server_ip, result)
			
			# Add the sender's port to our broadcast list
			if result.has("listen_port"):
				var sender_port = int(result.listen_port)
				if sender_port > 0 and not broadcast_ports.has(sender_port):
					broadcast_ports.append(sender_port)
					print("Added new port to broadcast list: ", sender_port)

func _handle_discovery_message(ip, data):
	# Only process discovery messages from actual hosts
	if not data.has("is_hosting_game") or not data.is_hosting_game:
		return
	# always skip our own discovery
	if data.has("from_instance") and data.from_instance == instance_id:
		return
	# Create a unique identifier for this server
	var server_id = "%s:%s" % [ip, data.from_instance]
	
	# Convert port to integer
	var server_port = int(data.listen_port)
	
	# Check if we've processed a discovery from this server recently
	var current_time = Time.get_unix_time_from_system()
	if discovery_cooldown.has(server_id):
		if current_time - discovery_cooldown[server_id] < cooldown_time:
			return # Too soon to process again
	
	# Update cooldown time
	discovery_cooldown[server_id] = current_time
	
	# First time we're seeing this server or cooldown has expired
	if not known_servers.has(server_id):
		print("Discovered new server at %s on port %d" % [ip, server_port])
		
		# Add to our known servers
		known_servers[server_id] = {
			"ip": ip,
			"instance_id": data.from_instance,
			"listen_port": server_port,
			"last_seen": current_time,
			"server_name": "Unknown Server", # Default name until we get game info
			"player_count": 0 # Default player count
		}
		
		# Add this port to our broadcast list
		if server_port > 0 and not broadcast_ports.has(server_port):
			broadcast_ports.append(server_port)
			print("Added new port to broadcast list: ", server_port)
		
		# Send direct discovery response
		_send_direct_discovery(ip, server_port)
	else:
		# Update last seen time
		known_servers[server_id].last_seen = current_time

# Updates the internal server info and marks it for UI update
func update_server_info(ip: String, info: Dictionary):
	var current_time = Time.get_unix_time_from_system()
	var server_id = "%s:%s" % [ip, info.get("instance_id", "unknown")]
	
	# Skip updating info for our own server if we're not hosting
	if info.get("instance_id", "") == instance_id and not is_hosting_game:
		return
	# Only add/update servers that are actually hosting
	if not info.has("is_hosting_game") or not info.is_hosting_game:
		return
	# Check if this server already exists in our list
	if known_servers.has(server_id):
		# Update existing entry
		known_servers[server_id].last_seen = current_time
		known_servers[server_id].server_name = info.name
		known_servers[server_id].player_count = int(info.playerCount)
	else:
		# Add new server to tracking list
		known_servers[server_id] = {
			"ip": ip,
			"instance_id": info.get("instance_id", "unknown"),
			"listen_port": int(info.get("listen_port", 8911)),
			"last_seen": current_time,
			"server_name": info.name,
			"player_count": int(info.playerCount)
		}

# UI is only updated from the timer callback to avoid excessive updates
func _on_server_list_update_timer_timeout():
	# Get the server container, where all the server entries are displayed
	var server_container = get_node_or_null(server_list_container_path)
	if not server_container:
		return
		
	# First, remove any servers from UI that are not in our known_servers list
	var existing_nodes = server_entry_nodes.keys()
	for server_id in existing_nodes:
		if not known_servers.has(server_id):
			if server_entry_nodes.has(server_id):
				var node = server_entry_nodes[server_id]
				if is_instance_valid(node) and node.is_inside_tree():
					node.queue_free()
				server_entry_nodes.erase(server_id)
	
	# Then update or add entries for all known servers
	for server_id in known_servers:
		var server = known_servers[server_id]
		var ip = server.ip
		var server_name = server.get("server_name", "Unknown Server")
		var player_count = server.get("player_count", 0)
		
		if server_entry_nodes.has(server_id):
			# Update existing node
			var node = server_entry_nodes[server_id]
			if is_instance_valid(node) and node.is_inside_tree():
				node.get_node("PlayerCount").text = str(player_count)
		else:
			# Add new node
			var info_node = serverInfo.instantiate()
			var node_name = server_name + "@" + ip.replace(".", "_")
			info_node.name = node_name
			info_node.get_node("Name").text = server_name
			info_node.get_node("Ip").text = ip
			info_node.get_node("PlayerCount").text = str(player_count)
			server_container.add_child(info_node)
			info_node.joinGame.connect(joinbyIp)
			
			# Store reference to the node
			server_entry_nodes[server_id] = info_node

# Helper function to add or update server entries in the UI - DEPRECATED, use update_server_info instead
func add_or_update_server_entry(ip: String, info: Dictionary):
	# Just update the internal tracking, actual UI updates are done by the timer
	update_server_info(ip, info)

func _broadcast():
	if broadcaster:
		RoomInfo.playerCount = GameManager.Players.size()
		# Broadcast to all known ports
		_broadcast_to_all_ports()
	else:
		printerr("Broadcaster not initialized, cannot broadcast.")

func _broadcast_to_all_ports():
	if not broadcaster:
		return
		
	# Make sure our info includes listen port and instance ID
	RoomInfo.listen_port = listenPort
	RoomInfo.instance_id = instance_id
	RoomInfo.is_hosting_game = is_hosting_game
	
	var data = JSON.stringify(RoomInfo)
	var packet = data.to_ascii_buffer()
	
	# Broadcast to all known ports
	for port in broadcast_ports:
		if broadcaster.set_dest_address(broadcastAddress, port) == OK:
			broadcaster.put_packet(packet)
	
	# Also send targeted game info to any servers we know about
	for id in known_servers:
		var server = known_servers[id]
		if broadcaster.set_dest_address(server.ip, server.listen_port) == OK:
			broadcaster.put_packet(packet)
			
	# Log once every 5 broadcasts
	if broadcastTimer.time_left < 0.2 or broadcastTimer.time_left > 0.8:
		print("Broadcasting Game to %d ports and %d known servers" % [broadcast_ports.size(), known_servers.size()])

func _send_discovery_broadcast():
	if not is_hosting_game:
		return
	var message = {
		"message_type": "discovery",
		"from_instance": instance_id,
		"listen_port": listenPort,
		"is_hosting_game": is_hosting_game
	}
	
	var data = JSON.stringify(message)
	var packet = data.to_ascii_buffer()
	
	# Broadcast to all known ports
	for port in broadcast_ports:
		if discovery_broadcaster.set_dest_address(broadcastAddress, port) == OK:
			discovery_broadcaster.put_packet(packet)

func _send_direct_discovery(ip, port):
	if not is_hosting_game:
		return
	var message = {
		"message_type": "discovery",
		"from_instance": instance_id,
		"listen_port": listenPort,
		"is_hosting_game": is_hosting_game
	}
	
	var data = JSON.stringify(message)
	var packet = data.to_ascii_buffer()
	
	if discovery_broadcaster.set_dest_address(ip, port) == OK:
		discovery_broadcaster.put_packet(packet)

func _on_discovery_timer_timeout():
	_send_discovery_broadcast()
	
	# Clean up old servers
	var current_time = Time.get_unix_time_from_system()
	var to_remove = []
	
	for id in known_servers:
		# Remove our own server if we're not hosting
		if known_servers[id].get("instance_id", "") == instance_id and not is_hosting_game:
			to_remove.append(id)
			continue
			
		if current_time - known_servers[id].last_seen > 10:
			to_remove.append(id)
	
	for id in to_remove:
		known_servers.erase(id)
		print("Removed server: ", id)
		
	# Clean up old cooldown entries
	var cooldown_remove = []
	for id in discovery_cooldown:
		if current_time - discovery_cooldown[id] > cooldown_time * 2:
			cooldown_remove.append(id)
	
	for id in cooldown_remove:
		discovery_cooldown.erase(id)

func _on_broadcast_timer_timeout():
	_broadcast()

func cleanUp():
	if listner:
		listner.close()
		listner = null
	if discovery_broadcaster:
		discovery_broadcaster.close()
		discovery_broadcaster = null
	if server_list_update_timer:
		server_list_update_timer.stop()
		server_list_update_timer = null
	$BroadcastTimer.stop()
	if broadcaster:
		broadcaster.close()
		broadcaster = null
	
	# Clear all server entries from UI
	var server_container = get_node_or_null(server_list_container_path)
	if server_container:
		for child in server_container.get_children():
			child.queue_free()

func _exit_tree():
	cleanUp()

func joinbyIp(ip):
	joinGame.emit(ip)

func refresh_servers():
	# Clear UI
	var server_container = get_node_or_null(server_list_container_path)
	if server_container:
		for child in server_container.get_children():
			child.queue_free()
	
	# Clear tracking
	known_servers.clear()
	server_entry_nodes.clear()
	
	print("Refreshing server list...")
	
	# Re-send discovery broadcasts
	_send_discovery_broadcast()
	
	# If hosting, re-add local server immediately after clearing
	if is_hosting_game and broadcaster: # Check if we are currently hosting the game
		update_server_info("127.0.0.1", RoomInfo)

# Utility function to get local non-loopback IP (may not work on all platforms/configs)
func get_local_ip() -> String:
	var host_ips = IP.get_local_addresses()
	for ip in host_ips:
		if ip != "127.0.0.1" and not ip.begins_with("::") and not ip.begins_with("fe80"):
			return ip
	return "127.0.0.1" # Fallback
