extends Control

const MENU_SCENE = "res://scenes/multiplayer/multiplayerMenuScene.tscn"
@export var Address = "127.0.0.1"
@export var port = 8910
var peer
var last_joined_ip = ""

# Called when the node enters the scene tree for the first time.
func _ready():
	multiplayer.peer_connected.connect(peer_connected)
	multiplayer.peer_disconnected.connect(peer_disconnected)
	multiplayer.connected_to_server.connect(connected_to_server)
	multiplayer.connection_failed.connect(connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if "--server" in OS.get_cmdline_args():
		hostGame()
	
	$ServerBrowser.joinGame.connect(JoinByIP)
	pass # Replace with function body.


# this get called on the server and clients
func peer_connected(id):
	print("Player Connected " + str(id))
	if multiplayer.is_server() and id != multiplayer.get_unique_id():
		StartGame.rpc_id(id)
	
# this get called on the server and clients
func peer_disconnected(id):
	print("Player Disconnected " + str(id))
	GameManager.Players.erase(id)
	var players = get_tree().get_nodes_in_group("Player")
	for i in players:
		if i.name == str(id):
			i.queue_free()
# called only from clients
func connected_to_server():
	print("connected To Sever!")
	SendPlayerInformation.rpc_id(1, $MainPanel/MarginContainer/VBoxContainer/PlayerSetupContainer/LineEdit.text, multiplayer.get_unique_id())

# called only from clients
func connection_failed():
	print("Couldnt Connect")

@rpc("any_peer")
func SendPlayerInformation(player_name, id):
	if !GameManager.Players.has(id):
		GameManager.Players[id] = {
			"name": player_name,
			"id": id,
			"score": 0
		}
	
	if multiplayer.is_server():
		for i in GameManager.Players:
			SendPlayerInformation.rpc(GameManager.Players[i].name, i)

@rpc("any_peer", "call_local")
func StartGame():
	print("StartGame called on peer: ", multiplayer.get_unique_id())
	# Make sure we're not already in the game scene
	for child in get_tree().root.get_children():
		if child.scene_file_path == "res://scenes/levels/testScene3D.tscn":
			print("Game scene already exists, skipping")
			return
			
	print("Loading game scene")
	# Load and setup the game scene
	var scene = load("res://scenes/levels/testScene3D.tscn").instantiate()
	
	# Add to root but make sure it's properly setup for networking
	print("Adding scene to tree")
	get_tree().root.add_child(scene, true)
	
	# Hide the menu
	self.hide()
	
	# Make sure the scene is not paused
	get_tree().paused = false
	
	# Set is_hosting_game true if this is the server - ONLY after the scene is ready
	if multiplayer.is_server():
		$ServerBrowser.is_hosting_game = true
		
	print("Game scene setup complete")

func hostGame():
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 2)
	if error != OK:
		print("cannot host: " + error)
		return
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	
	multiplayer.set_multiplayer_peer(peer)
	print("Waiting For Players!")
	
	
func _on_host_button_down():
	hostGame()
	var player_name = $MainPanel/MarginContainer/VBoxContainer/PlayerSetupContainer/LineEdit.text
	var server_name = $MainPanel/MarginContainer/VBoxContainer/PlayerSetupContainer/ServerNameEdit.text
	if server_name.strip_edges() == "":
		server_name = player_name + "'s server"
	SendPlayerInformation(player_name, multiplayer.get_unique_id())
	$ServerBrowser.setUpBroadCast(server_name)
	
	# Auto-start the game when hosting
	print("Auto-starting game as host...")
	StartGame.rpc()

func _on_start_game_button_down():
	StartGame.rpc()
	pass # Replace with function body.


func _on_button_button_down():
	GameManager.Players[GameManager.Players.size() + 1] = {
			"name": "test",
			"id": 1,
			"score": 0
		}
	pass # Replace with function body.

func _on_quit_button_pressed():
	# Set is_hosting_game false when quitting
	$ServerBrowser.is_hosting_game = false
	get_tree().quit()

func _on_manual_join_pressed():
	var ip_text = $MainContainer/VBoxContainer/ServerList/ManualIPContainer/ManualIPEdit.text
	if ip_text.strip_edges() != "":
		JoinByIP(ip_text)
	else:
		# Could add a visual feedback here like a popup
		print("Please enter a valid IP address")

func JoinByIP(ip):
	last_joined_ip = ip
	GameManager.last_joined_ip = ip
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, port)
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.set_multiplayer_peer(peer)

func get_joined_ip():
	return last_joined_ip

func _on_server_disconnected():
	print("Server disconnected, returning to menu")
	multiplayer.set_multiplayer_peer(null)
	# Free any leftover game scene instances to stop their scripts from running
	for child in get_tree().root.get_children():
		if child.scene_file_path == "res://scenes/levels/testScene3D.tscn":
			child.queue_free()
	get_viewport().warp_mouse(get_viewport().size / 2)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(MENU_SCENE)
