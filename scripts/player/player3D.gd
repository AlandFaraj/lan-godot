extends CharacterBody3D

const SPEED = 5.0
const MOUSE_SENSITIVITY = 0.002
const JUMP_VELOCITY = 4.5

@export var bullet_scene: PackedScene

var health = 100
# Use property setter/getter for player_color to ensure changes are applied immediately
var _player_color = Color(0.2, 0.6, 1, 1) # Default color - internal variable
var player_color: Color:
	get:
		return _player_color
	set(value):
		if _player_color == value: return # No change
		_player_color = value
		if is_inside_tree() and mesh != null:
			set_player_color(value)
			# print("Player color property updated to: ", value)

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var sync_position = Vector3.ZERO
var sync_rotation = Vector3.ZERO
var sync_camera_rotation = Vector3.ZERO
# Track kills and deaths
var kills = 0
var deaths = 0

@onready var camera_mount = $CameraMount
@onready var health_bar = $HealthBar3D/SubViewport/ProgressBar
@onready var bullet_spawn = $CameraMount/BulletSpawn
@onready var camera = $CameraMount/Camera3D
@onready var mesh = $MeshInstance3D

func _ready():
	# Add to Player group for easy reference
	add_to_group("Player")
	
	if not multiplayer.multiplayer_peer:
		return
		
	if not multiplayer.is_server():
		position = sync_position
		rotation = sync_rotation
		camera_mount.rotation = sync_camera_rotation
	$MultiplayerSynchronizer.set_multiplayer_authority(str(name).to_int())
	
	# Only enable camera and input for the player we control
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		$CameraMount/Camera3D.current = true
		
		# Hide 3D health bar for the local player
		$HealthBar3D.visible = false
		
		# Update UI health display
		update_ui_health_display()
		
		# Update kill/death display for local player
		update_ui_stats_display()
	else:
		$CameraMount/Camera3D.current = false
	
	# Set player color from GameManager 
	var player_id = str(name).to_int()
	# print("Player " + str(player_id) + " ready, checking color...")
	if GameManager.Players.has(player_id):
		# print("Player " + str(player_id) + " found in GameManager")
		if GameManager.Players[player_id].has("color"):
			# print("Player " + str(player_id) + " has color: ", GameManager.Players[player_id].color)
			self.player_color = GameManager.Players[player_id].color # Use setter
		# else:
			# print("Player " + str(player_id) + " has no color in GameManager")
	# else:
		# print("Player " + str(player_id) + " not found in GameManager")
		
	# Force apply the color
	set_player_color(_player_color)

# Update the UI health display
func update_ui_health_display():
	# Only update UI for the local player
	if not multiplayer.multiplayer_peer:
		return
		
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		var ui = get_tree().get_root().find_child("UI", true, false)
		if ui and ui.has_method("update_health_display"):
			ui.update_health_display(health, player_color)

# Update the UI kills/deaths display
func update_ui_stats_display():
	# Only update UI for the local player
	if not multiplayer.multiplayer_peer:
		return
		
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		var ui = get_tree().get_root().find_child("UI", true, false)
		if ui and ui.has_method("update_stats_display"):
			ui.update_stats_display(kills, deaths)

# Apply color to player mesh
func set_player_color(color):
	# print("Setting player " + name + " color to: ", color)
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	mesh.set_surface_override_material(0, material)
	
	# Also update the health bar tint
	health_bar.modulate = color

func _unhandled_input(event):
	if not multiplayer.multiplayer_peer or $MultiplayerSynchronizer.get_multiplayer_authority() != multiplayer.get_unique_id():
		return
		
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_mount.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_mount.rotation.x = clamp(camera_mount.rotation.x, -PI / 2, PI / 2)
		
		sync_rotation = rotation
		sync_camera_rotation = camera_mount.rotation

func _physics_process(delta):
	# Check if multiplayer peer exists to prevent errors when quitting
	if not multiplayer.multiplayer_peer:
		return
		
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		# Add gravity
		if not is_on_floor():
			velocity.y -= gravity * delta

		# Handle Jump
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

		# Handle shooting
		if Input.is_action_just_pressed("shoot"):
			shoot.rpc()

		# Get the input direction and handle the movement/deceleration
		var input_dir = Vector2.ZERO
		if Input.is_action_pressed("move_forward"):
			input_dir.y -= 1
		if Input.is_action_pressed("move_back"):
			input_dir.y += 1
		if Input.is_action_pressed("move_left"):
			input_dir.x -= 1
		if Input.is_action_pressed("move_right"):
			input_dir.x += 1
		input_dir = input_dir.normalized()
		
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)

		move_and_slide()
		
		# Update sync variables
		sync_position = position
		sync_rotation = rotation
		sync_camera_rotation = camera_mount.rotation
	else:
		# Interpolate position and rotation for remote players
		position = position.lerp(sync_position, 0.5)
		rotation = rotation.lerp(sync_rotation, 0.5)
		camera_mount.rotation = camera_mount.rotation.lerp(sync_camera_rotation, 0.5)

@rpc("any_peer", "call_local")
func shoot():
	if !bullet_spawn:
		push_error("BulletSpawn node not found!")
		return
		
	if !is_inside_tree():
		push_error("Player node not in scene tree!")
		return
		
	var bullet = bullet_scene.instantiate()
	if !bullet:
		push_error("Failed to instantiate bullet scene!")
		return
		
	# Add bullet to the game world first
	var root = get_tree().get_root()
	if root:
		root.add_child(bullet)
		
		# Now set transform after adding to scene tree
		var spawn_transform = bullet_spawn.global_transform
		bullet.global_position = spawn_transform.origin
		
		# Get the horizontal direction from the player's rotation
		var direction = - global_transform.basis.z
		direction.y = 0
		direction = direction.normalized()
		bullet.basis = global_transform.basis
		
		# Set the bullet's owner so we can track kills
		var player_id = str(name).to_int()
		bullet.owner_id = player_id
	else:
		push_error("Could not find root node!")
		bullet.queue_free()

@rpc("any_peer", "call_local")
func take_damage(amount: int, attacker_id: int = -1):
	health -= amount
	health_bar.value = health
	
	# Update UI health display
	update_ui_health_display()
	
	if health <= 0:
		print("Player " + name + " died, killed by " + str(attacker_id))
		
		# If we have a valid attacker, increment their kill count
		if attacker_id >= 0 and attacker_id != str(name).to_int():
			# Only the server or the player with authority over this player should count the kill
			if not multiplayer.multiplayer_peer:
				return
				
			if multiplayer.is_server() or $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
				var scene_root = get_tree().root
				for child in scene_root.get_children():
					if child.scene_file_path == "res://scenes/levels/testScene3D.tscn":
						if child.has_node(str(attacker_id)):
							var attacker = child.get_node(str(attacker_id))
							attacker.increment_kill.rpc()
							
							# Add kill feed entry on all clients
							add_kill_feed_entry.rpc(attacker_id, str(name).to_int())
		
		# Only the server should increment death count to avoid duplicate counting
		if multiplayer.is_server():
			increment_death.rpc()

@rpc("any_peer", "call_local")
func increment_kill():
	print("Incrementing kill for player " + name + ", previous kills: " + str(kills))
	kills += 1
	print("New kill count: " + str(kills))
	
	# Update in GameManager for persistence
	var player_id = str(name).to_int()
	if GameManager.Players.has(player_id):
		GameManager.Players[player_id]["kills"] = kills
	
	# Update the UI for the local player
	update_ui_stats_display()

@rpc("any_peer", "call_local")
func increment_death():
	print("Incrementing death for player " + name + ", previous deaths: " + str(deaths))
	deaths += 1
	print("New death count: " + str(deaths))
	
	# Update in GameManager for persistence
	var player_id = str(name).to_int()
	if GameManager.Players.has(player_id):
		GameManager.Players[player_id]["deaths"] = deaths
	
	# Update the UI for the local player
	update_ui_stats_display()
	
	# Respawn the player after death
	respawn.rpc()

@rpc("any_peer", "call_local")
func respawn():
	health = 100
	health_bar.value = health
	
	# Update UI health display
	update_ui_health_display()
	
	var scene_manager = get_parent()
	if scene_manager.has_method("get_random_spawn_point"):
		position = scene_manager.get_random_spawn_point()

@rpc("any_peer", "call_local")
func add_kill_feed_entry(killer_id, victim_id):
	var killer_name = "Unknown"
	var killer_color = Color.WHITE
	var victim_name = "Unknown"
	var victim_color = Color.WHITE
	
	# Get killer info
	if GameManager.Players.has(killer_id):
		killer_name = GameManager.Players[killer_id].get("name", "Player " + str(killer_id))
		killer_color = GameManager.Players[killer_id].get("color", Color.WHITE)
	else:
		killer_name = "Player " + str(killer_id)
	
	# Get victim info
	if GameManager.Players.has(victim_id):
		victim_name = GameManager.Players[victim_id].get("name", "Player " + str(victim_id))
		victim_color = GameManager.Players[victim_id].get("color", Color.WHITE)
	else:
		victim_name = "Player " + str(victim_id)
	
	# Update kill feed in UI
	var ui = get_tree().get_root().find_child("UI", true, false)
	if ui and ui.has_method("add_kill_feed_message"):
		ui.add_kill_feed_message(killer_name, killer_color, victim_name, victim_color)

# Method to prepare for cleanup - call this before removing the player
func prepare_for_cleanup():
	# Disable MultiplayerSynchronizer to prevent errors
	if has_node("MultiplayerSynchronizer"):
		var sync = get_node("MultiplayerSynchronizer")
		sync.set_process(false)
		sync.public_visibility = false
	
	# Disable processing
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	
	# This will help prevent errors during scene transitions
	if is_inside_tree():
		remove_from_group("Player")

# This gets called when the node is about to be removed
func _exit_tree():
	# Disable physics processing to stop further calculations
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	
	# Force free resources that might be keeping references
	if mesh and mesh.get_surface_override_material(0):
		mesh.set_surface_override_material(0, null)

# Also implement process mode change detection
func _notification(what):
	if what == NOTIFICATION_PAUSED:
		# Pause all processing when paused
		set_physics_process(false)
		set_process_input(false)
	
	if what == NOTIFICATION_UNPAUSED:
		# Only resume processing if we still have multiplayer running
		if multiplayer.multiplayer_peer:
			set_physics_process(true)
			set_process_input(true)
			
	if what == NOTIFICATION_PREDELETE:
		# Last chance for cleanup before the node is deleted
		print("Player " + name + " is being deleted")
		# Ensure we release any remaining resources
