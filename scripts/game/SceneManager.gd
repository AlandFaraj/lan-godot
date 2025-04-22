extends Node3D

@export var PlayerScene: PackedScene
var used_spawn_points = []

# Called when the node enters the scene tree for the first time.
func _ready():
	# Make sure the scene is visible for all clients
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(add_player)
		multiplayer.peer_disconnected.connect(del_player)
		
		# Spawn already connected players
		for id in multiplayer.get_peers():
			add_player(id)
			
		# Spawn local player
		add_player(1)
		
		# Update IP display for server
		update_ip_display()
	else:
		# Client setup: make scene visible
		get_tree().set_pause(false)
		# Spawn existing players (server and other clients)
		for id in multiplayer.get_peers():
			spawn_player(id)
		# Spawn local player
		var my_id = multiplayer.get_unique_id()
		spawn_player(my_id)
		# Now request spawn from server for other clients
		request_spawn.rpc_id(1)
		
		# Update IP display for client
		update_ip_display()

func update_ip_display():
	var ip_label = $UI/IPAddressDisplay
	if ip_label:
		var ip_text = "IP: "
		if multiplayer.is_server():
			ip_text += get_local_ip()
		else:
			# Get the joined IP from GameManager singleton
			if GameManager.last_joined_ip != "":
				ip_text += GameManager.last_joined_ip
			else:
				ip_text += "Unknown"
		ip_label.text = ip_text

func get_local_ip() -> String:
	var ip_addresses = IP.get_local_addresses()
	for ip in ip_addresses:
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1" # Fallback to localhost if no local IP found

func get_random_spawn_point() -> Vector3:
	var spawn_points = $SpawnPoints.get_children()
	var available_points = spawn_points.filter(func(point): return not used_spawn_points.has(point))
	
	if available_points.is_empty():
		used_spawn_points.clear()
		available_points = spawn_points
	
	var spawn_point = available_points.pick_random()
	used_spawn_points.append(spawn_point)
	return spawn_point.global_position

# Called by server when a peer connects
func add_player(id: int):
	spawn_player.rpc(id)

@rpc("any_peer")
func request_spawn():
	if multiplayer.is_server():
		var id = multiplayer.get_remote_sender_id()
		spawn_player.rpc(id)

@rpc("any_peer", "call_local")
func spawn_player(id: int):
	if has_node(str(id)):
		return
		
	var character = PlayerScene.instantiate()
	character.name = str(id)
	
	# Apply player color immediately on spawn
	if GameManager.Players.has(id) and GameManager.Players[id].has("color"):
		character.player_color = GameManager.Players[id].color
	
	add_child(character, true)
	character.global_position = get_random_spawn_point()

func del_player(id: int):
	if not has_node(str(id)):
		return
	get_node(str(id)).queue_free()
