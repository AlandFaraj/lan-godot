extends CharacterBody3D

const SPEED = 5.0
const MOUSE_SENSITIVITY = 0.002
const JUMP_VELOCITY = 4.5

@export var bullet_scene: PackedScene

var health = 100
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var sync_position = Vector3.ZERO
var sync_rotation = Vector3.ZERO
var sync_camera_rotation = Vector3.ZERO

@onready var camera_mount = $CameraMount
@onready var health_bar = $HealthBar3D/SubViewport/ProgressBar
@onready var bullet_spawn = $CameraMount/BulletSpawn
@onready var camera = $CameraMount/Camera3D


func _ready():
	if not multiplayer.is_server():
		position = sync_position
		rotation = sync_rotation
		camera_mount.rotation = sync_camera_rotation
	$MultiplayerSynchronizer.set_multiplayer_authority(str(name).to_int())
	
	# Only enable camera and input for the player we control
	if $MultiplayerSynchronizer.get_multiplayer_authority() == multiplayer.get_unique_id():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		$CameraMount/Camera3D.current = true
	else:
		$CameraMount/Camera3D.current = false

func _unhandled_input(event):
	if $MultiplayerSynchronizer.get_multiplayer_authority() != multiplayer.get_unique_id():
		return
		
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_mount.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_mount.rotation.x = clamp(camera_mount.rotation.x, -PI / 2, PI / 2)
		
		sync_rotation = rotation
		sync_camera_rotation = camera_mount.rotation

func _physics_process(delta):
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
	else:
		push_error("Could not find root node!")
		bullet.queue_free()

@rpc("any_peer", "call_local")
func take_damage(amount: int):
	health -= amount
	health_bar.value = health
	
	if health <= 0:
		respawn.rpc()

@rpc("any_peer", "call_local")
func respawn():
	health = 100
	health_bar.value = health
	var scene_manager = get_parent()
	if scene_manager.has_method("get_random_spawn_point"):
		position = scene_manager.get_random_spawn_point()
