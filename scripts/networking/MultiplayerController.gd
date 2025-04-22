extends Control

const MENU_SCENE = "res://scenes/multiplayer/multiplayerMenuScene.tscn"
@export var Address = "127.0.0.1"
@export var port = 8910
var peer
var last_joined_ip = ""
var player_color = Color(0.2, 0.6, 1, 1) # Default player color

# --- Node References (Updated for TabContainer structure) ---
@onready var player_name_edit = $MainPanel/MarginContainer/VBoxContainer/TabContainer/Profile/MarginContainer/VBoxContainer/PlayerNameEdit
@onready var selected_color_rect = $MainPanel/MarginContainer/VBoxContainer/TabContainer/Profile/MarginContainer/VBoxContainer/ColorPickerContainer/SelectedColorRect
@onready var color_picker_button = $MainPanel/MarginContainer/VBoxContainer/TabContainer/Profile/MarginContainer/VBoxContainer/ColorPickerContainer/ColorPickerButton
@onready var server_name_edit = $MainPanel/MarginContainer/VBoxContainer/TabContainer/Host/MarginContainer/VBoxContainer/ServerNameEdit
@onready var manual_ip_edit = $MainPanel/MarginContainer/VBoxContainer/TabContainer/Join/MarginContainer/VBoxContainer/ManualIPContainer/ManualIPEdit
@onready var server_browser = $ServerBrowser
# --------------------------------------------------------------


# Called when the node enters the scene tree for the first time.
func _ready():
	multiplayer.peer_connected.connect(peer_connected)
	multiplayer.peer_disconnected.connect(peer_disconnected)
	multiplayer.connected_to_server.connect(connected_to_server)
	multiplayer.connection_failed.connect(connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if "--server" in OS.get_cmdline_args():
		hostGame()
	
	server_browser.joinGame.connect(JoinByIP)
	
	# Initialize UI elements
	selected_color_rect.color = player_color
	color_picker_button.color = player_color


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
	var player_name = player_name_edit.text
	if player_name.strip_edges() == "":
		player_name = "Player"
	# Locally store our own player info so spawn_player won't default to white
	var my_id = multiplayer.get_unique_id()
	GameManager.init_player_stats(my_id, player_name, player_color)
	# Send our player info to the server (id 1)
	SendPlayerInformation.rpc_id(1, player_name, my_id, player_color)

# called only from clients
func connection_failed():
	print("Couldnt Connect")

@rpc("any_peer")
func SendPlayerInformation(player_name, id, color):
	if !GameManager.Players.has(id):
		GameManager.init_player_stats(id, player_name, color)
	else:
		# Update existing player data - important for color updates
		GameManager.Players[id].name = player_name
		GameManager.Players[id].color = color
	
	# Update player color if the player already exists in the scene
	update_existing_player_color(id, color)
	
	if multiplayer.is_server():
		# Broadcast to all clients (including the origin) so they get their own colors
		for i in GameManager.Players:
			SendPlayerInformation.rpc(GameManager.Players[i].name, i, GameManager.Players[i].color)

# Update an existing player's color if they're already in the scene
func update_existing_player_color(player_id, color):
	var scene_tree = get_tree()
	if scene_tree:
		var root = scene_tree.root
		for child in root.get_children():
			# Look for game scene
			if child.scene_file_path == "res://scenes/levels/testScene3D.tscn":
				# Check if player with this ID exists
				if child.has_node(str(player_id)):
					var player = child.get_node(str(player_id))
					if player.has_method("set_player_color"):
						player.player_color = color
						return true
	return false

@rpc("any_peer", "call_local")
func StartGame():
	# Make sure we're not already in the game scene
	for child in get_tree().root.get_children():
		if child.scene_file_path == "res://scenes/levels/testScene3D.tscn":
			return
	
	# If we're the server, we should make sure all connected clients have the latest player info
	if multiplayer.is_server():
		# Ensure all players have the latest info before starting the game
		for i in GameManager.Players:
			SendPlayerInformation.rpc(GameManager.Players[i].name, i, GameManager.Players[i].color)
			
	# Load and setup the game scene
	var scene = load("res://scenes/levels/testScene3D.tscn").instantiate()
	
	# Add to root but make sure it's properly setup for networking
	get_tree().root.add_child(scene, true)
	
	# Hide the menu
	self.hide()
	
	# Make sure the scene is not paused
	get_tree().paused = false
	
	# Set is_hosting_game true if this is the server - ONLY after the scene is ready
	if multiplayer.is_server():
		server_browser.is_hosting_game = true

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
	var player_name = player_name_edit.text
	var server_name = server_name_edit.text
	if server_name.strip_edges() == "":
		server_name = player_name + "'s server" if player_name.strip_edges() != "" else "Unnamed Server"
	SendPlayerInformation(player_name, multiplayer.get_unique_id(), player_color)
	server_browser.setUpBroadCast(server_name)
	
	# Auto-start the game when hosting
	print("Auto-starting game as host...")
	StartGame.rpc()

func _on_quit_button_pressed():
	# Set is_hosting_game false when quitting
	server_browser.is_hosting_game = false
	get_tree().quit()

func _on_manual_join_pressed():
	var ip_text = manual_ip_edit.text
	if ip_text.strip_edges() != "":
		var player_name = player_name_edit.text
		if player_name.strip_edges() == "":
			player_name = "Player"
		JoinByIP(ip_text)
	else:
		# Could add a visual feedback here like a popup
		print("Please enter a valid IP address")

func JoinByIP(ip):
	# Create a safe ID even if multiplayer peer is null
	var my_id
	if multiplayer.multiplayer_peer:
		my_id = multiplayer.get_unique_id()
	else:
		# Generate a temporary ID if no peer exists yet
		my_id = randi_range(100000000, 999999999)
	
	# Store our player info locally
	var player_name = player_name_edit.text
	if player_name.strip_edges() == "": player_name = "Player"
	
	# Initialize player in GameManager
	GameManager.init_player_stats(my_id, player_name, player_color)
	
	# Save connection info for reconnection purposes
	last_joined_ip = ip
	GameManager.last_joined_ip = ip
	
	# Close any existing peer connection first
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.set_multiplayer_peer(null)
	
	# Create a new peer for connection
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, port)
	if err != OK:
		print("Error creating client: ", err)
		return
		
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	
	# Set the new peer
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

# Updated function for the new ColorPickerButton
func _on_color_picker_color_changed(color):
	player_color = color
	selected_color_rect.color = color
