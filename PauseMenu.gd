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
	# Properly cleanup multiplayer
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	# Reset mouse mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Get the current scene root (game scene)
	var current_scene = get_tree().get_root().get_node("TestScene")
	if current_scene:
		current_scene.queue_free()
	
	# Change to menu scene
	get_tree().change_scene_to_file("res://multiplayerScene.tscn")
