extends Node
## Regression test for the contact convention the damage unit depends on (dossier §7.2):
##   n = the contact normal, pointing OUT of the other body
##   v_rel = my_velocity - other_velocity
##   v_n = max(0, -v_rel.dot(n))   -> the closing speed
##
## The test proves three things about the engine:
##   1. `state.get_contact_local_normal()` is a WORLD-space normal (it does not follow the
##      body's own rotation),
##   2. it points out of the other body (against the closing direction),
##   3. the velocity seen in `_integrate_forces` at the contact tick is the pre-impact
##      velocity (so the closing speed is the real one, not a post-bounce remainder).

const SPEED := 20.0


class ProbeBody:
	extends RigidBody3D
	var normal := Vector3.ZERO
	var velocity := Vector3.ZERO
	var point := Vector3.ZERO
	var hits: int = 0
	var other: Object = null

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if state.get_contact_count() == 0 or hits > 0:
			return
		normal = state.get_contact_local_normal(0)
		velocity = state.linear_velocity
		point = state.get_contact_local_position(0)
		other = state.get_contact_collider_object(0)
		hits += 1


func _ready() -> void:
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 20.0, 1.0)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	add_child(wall)

	# The car is rotated 90 degrees about Y on purpose: a local-space normal would then
	# differ from the world-space one.
	var car := ProbeBody.new()
	car.name = "Car"
	var car_shape := CollisionShape3D.new()
	var car_box := BoxShape3D.new()
	car_box.size = Vector3(1.9, 1.4, 4.4)
	car_shape.shape = car_box
	car.add_child(car_shape)
	car.freeze = false
	car.contact_monitor = true
	car.max_contacts_reported = 8
	car.collision_layer = 2
	car.collision_mask = 1
	add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, 0.7, -12.0))
	car.linear_velocity = Vector3(0.0, 0.0, SPEED)

	await get_tree().create_timer(1.5).timeout

	var ok := true
	var msg := ""
	if car.hits == 0:
		ok = false
		msg = "no contact was reported"
	else:
		var n := car.normal
		var closing := car.velocity.dot(n)
		msg = "normal=%s velocity=%s point=%s" % [n, car.velocity, car.point]
		# 1. world space: the wall's face points -Z (the car comes from -Z).
		if absf(n.dot(Vector3.FORWARD)) < 0.9:
			ok = false
			msg += " -> the normal is not a world-space axis normal"
		# 2. it points out of the wall, against the closing direction.
		if closing > 0.0:
			ok = false
			msg += " -> the normal does not point out of the other body"
		# 3. the contact point is in world space: it sits on the wall face (z = -0.5).
		if absf(car.point.z + 0.5) > 0.4:
			ok = false
			msg += " -> the contact point is not in world space"
	print(("PASS" if ok else "FAIL") + " contact convention: " + msg)
	get_tree().quit(0 if ok else 1)
