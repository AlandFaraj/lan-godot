extends CharacterBody3D

const SPEED = 30.0
const DAMAGE = 20

var owner_id = -1 # Store the ID of the player who shot this bullet

func _physics_process(delta):
	velocity = - transform.basis.z * SPEED
	
	var collision = move_and_collide(velocity * delta)
	if collision:
		var collider = collision.get_collider()
		if collider.has_method("take_damage"):
			# Debug to track bullet hits and damage application
			print("Bullet hit from player " + str(owner_id) + " to " + collider.name)
			
			# Only the server should decide who takes damage to avoid double counting
			if multiplayer.is_server():
				# Apply damage locally on all peers via RPC
				collider.take_damage.rpc(DAMAGE, owner_id)
				print("Server: Damage applied from player " + str(owner_id))
		queue_free()

func _on_timer_timeout():
	queue_free()
