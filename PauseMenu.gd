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
	# Return to the multiplayer menu
	get_tree().root.get_node("MultiplayerController").show()
	get_parent().queue_free()
