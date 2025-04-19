extends Node3D

@export var PlayerScene: PackedScene
var used_spawn_points = []

# Called when the node enters the scene tree for the first time.
func _ready():
	print("Scene ready. Is server: ", multiplayer.is_server())
	# Make sure the scene is visible for all clients
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if multiplayer.is_server():
		print("Server setting up connections")
		multiplayer.peer_connected.connect(add_player)
		multiplayer.peer_disconnected.connect(del_player)
		
		# Spawn already connected players
		for id in multiplayer.get_peers():
			print("Spawning existing peer: ", id)
			add_player(id)
			
		# Spawn local player
		print("Spawning server player")
		add_player(1)
	else:
		print("Client setup starting")
		# Client setup
		# Make sure client can see the world
		get_tree().set_pause(false)
		
		# Request spawn from server
		print("Client requesting spawn")
		request_spawn.rpc_id(1)

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
	print("add_player called for id: ", id)
	spawn_player.rpc(id)

@rpc("any_peer")
func request_spawn():
	print("request_spawn received from: ", multiplayer.get_remote_sender_id())
	if multiplayer.is_server():
		var id = multiplayer.get_remote_sender_id()
		print("Server handling spawn request for id: ", id)
		spawn_player.rpc(id)

@rpc("any_peer", "call_local")
func spawn_player(id: int):
	print("spawn_player called for id: ", id, " on peer: ", multiplayer.get_unique_id())
	if has_node(str(id)):
		print("Player ", id, " already exists, skipping spawn")
		return
		
	print("Creating player instance for id: ", id)
	var character = PlayerScene.instantiate()
	character.name = str(id)
	add_child(character, true)
	character.global_position = get_random_spawn_point()
	print("Player ", id, " spawned at position: ", character.global_position)
	
func del_player(id: int):
	if not has_node(str(id)):
		return
	get_node(str(id)).queue_free()
