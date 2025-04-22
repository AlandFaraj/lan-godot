extends Control

func _ready():
	hide()

func _input(event):
	if event.is_action_pressed("ui_cancel"): # ESC key
		toggle_pause_menu()

func toggle_pause_menu():
	if visible:
		hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_resume_button_pressed():
	toggle_pause_menu()

func _on_quit_button_pressed():
	# Hide the pause menu first to prevent it from being visible during transition
	hide()
	
	# Reset mouse mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Make all UI elements invisible to avoid visual glitches during transition
	var ui_parent = get_parent()
	if ui_parent:
		for child in ui_parent.get_children():
			child.visible = false
	
	# Properly prepare player nodes for cleanup
	var player_nodes = get_tree().get_nodes_in_group("Player")
	for player in player_nodes:
		if player.has_method("prepare_for_cleanup"):
			player.prepare_for_cleanup()
			print("Prepared player", player.name, "for cleanup")
	
	# Delay a frame to allow visibility changes to propagate
	await get_tree().process_frame
	
	# Force player nodes to be removed from the scene
	for player in player_nodes:
		if is_instance_valid(player) and not player.is_queued_for_deletion():
			player.queue_free()
	
	# Properly cleanup multiplayer in a specific order
	# First store the current peer to close it later (if it exists)
	var current_peer = null
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		current_peer = multiplayer.multiplayer_peer
	
	# Set multiplayer peer to null FIRST to stop RPC calls
	multiplayer.set_multiplayer_peer(null)
	
	# Clear GameManager player data to allow proper rejoining
	if GameManager.has_method("reset_player_data"):
		GameManager.reset_player_data()
	else:
		# Reset the Players dictionary directly if method doesn't exist
		GameManager.Players.clear()
		
	# Now properly close the peer connection
	if current_peer:
		current_peer.close()
		
	# Explicitly set the current scene to pause mode to stop all processing
	var current_scene = get_tree().current_scene
	if current_scene:
		current_scene.process_mode = Node.PROCESS_MODE_DISABLED
		
	# Use call_deferred to safely change the scene after cleanup 
	call_deferred("_safely_change_scene")

func _safely_change_scene():
	# Ensure GameManager is in a clean state
	if GameManager.Players.size() > 0:
		print("Resetting player data before scene change")
		GameManager.reset_player_data()
	
	# Ensure there are no lingering player nodes
	var player_nodes = get_tree().get_nodes_in_group("Player")
	if not player_nodes.is_empty():
		print("Cleaning up", player_nodes.size(), "remaining player nodes")
		for player in player_nodes:
			if is_instance_valid(player):
				player.queue_free()
	
	# Delay slightly to allow nodes to be freed
	await get_tree().process_frame
	
	# Change to menu scene
	var err = get_tree().change_scene_to_file("res://scenes/multiplayer/multiplayerMenuScene.tscn")
	if err != OK:
		print("Error changing scene: ", err)
