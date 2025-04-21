extends CharacterBody3D

const SPEED = 30.0
const DAMAGE = 20

func _physics_process(delta):
	velocity = -transform.basis.z * SPEED
	
	var collision = move_and_collide(velocity * delta)
	if collision:
		var collider = collision.get_collider()
		if collider.has_method("take_damage"):
			collider.take_damage.rpc(DAMAGE)
		queue_free()

func _on_timer_timeout():
	queue_free()
