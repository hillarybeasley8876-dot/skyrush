extends "res://assets/cars/roadster/tests/roadster_checks.gd"
## The checks of the hero Roadster (part 2): the surfaces, the hinges, the wing, the lights and
## the markers of the contract.

## every surface of the car has a material
func check_surfaces(by_name: Dictionary) -> void:
	var bare: Array[String] = []
	var count := 0
	for n in by_name.keys():
		var mi := mesh(by_name, str(n))
		if mi == null:
			continue
		for s in mi.mesh.get_surface_count():
			count += 1
			if mi.get_active_material(s) == null:
				bare.append("%s[%d]" % [str(n), s])
	check(bare.is_empty(), "all %d surfaces have a material%s"
		% [count, "" if bare.is_empty() else " (bare: %s)" % ", ".join(bare)])


## the doors turn on the front edge: the node origin is the hinge, the door lies behind it
func check_hinges(by_name: Dictionary) -> void:
	var wrong: Array[String] = []
	for n in ["Door_L", "Door_R"]:
		var door := mesh(by_name, n)
		if door == null:
			wrong.append(n + " missing")
			continue
		var box := door.mesh.get_aabb()
		# the car faces -Z: behind the hinge is +Z, and the hinge is at the front edge of the door
		if box.position.z < -0.02 or box.size.z < 1.2:
			wrong.append("%s spans z %.2f..%.2f" % [n, box.position.z, box.end.z])
		var outer := absf(door.position.x)
		if outer < 0.8 or outer > 1.1:
			wrong.append("%s hinge at x %.2f" % [n, door.position.x])
	check(wrong.is_empty(), "the doors are hinged on their front edge%s"
		% ["" if wrong.is_empty() else " (%s)" % ", ".join(wrong)])


## the lights: the head lamps and the tail bar are lit, the brake box is red and strong enough to double
func check_lights(by_name: Dictionary) -> void:
	var bad: Array[String] = []
	for n in ["Lamp_FL", "Lamp_FR", "LightBar_Rear", "Brake_Light"]:
		var mi := mesh(by_name, n)
		if mi == null:
			bad.append("%s missing" % n)
			continue
		var mat := mi.get_active_material(0) as BaseMaterial3D
		if mat == null or not mat.emission_enabled:
			bad.append("%s is not emissive" % n)
			continue
		if n == "Brake_Light" or n == "LightBar_Rear":
			var c := mat.emission
			if c.r < 0.6 or c.g > 0.25 or c.b > 0.25:
				bad.append("%s is not red (%s)" % [n, str(c)])
			if mat.emission_energy_multiplier < 2.0:
				bad.append("%s energy %.1f" % [n, mat.emission_energy_multiplier])
	check(bad.is_empty(), "the lamps and the brake lights are emissive, the brake lights red%s"
		% ["" if bad.is_empty() else " (%s)" % ", ".join(bad)])
	var plate := mesh(by_name, "Plate_Rear")
	check(plate != null and world_aabb(plate).get_center().z > 1.5, "the plate is at the tail")


## the wing: origin on the hinge, the four poses in the extras, in the tail of the car
func check_wing(by_name: Dictionary) -> void:
	var wing := by_name.get("Wing") as Node3D
	if wing == null:
		check(false, "the wing carries the poses")
		return
	var extras: Dictionary = wing.get_meta("extras", {})
	var poses: Variant = extras.get("poses", null)
	var ok := poses is Dictionary
	if ok:
		for pose in ["stowed", "low_drag", "high_downforce", "air_brake"]:
			ok = ok and (poses as Dictionary).has(pose)
	check(ok, "the wing carries the poses property")
	var box := (wing as MeshInstance3D).mesh.get_aabb()
	var middle := box.get_center()
	check(middle.length() < 0.06 and wing.position.z > 1.6 and wing.position.y > 0.8 and box.size.x > 1.0,
		"the wing turns about its own middle, at the tail (%.2f, %.2f, %.2f)"
		% [wing.position.x, wing.position.y, wing.position.z])
	check(wing.rotation.length() < 0.001, "the wing is stowed in the glb")


## the markers: the rear nozzles fire back, the lift nozzles down, the yaw nozzles sideways
func check_markers(by_name: Dictionary) -> void:
	var wrong: Array[String] = []
	var expected := {
		"Nozzle_R1": Vector3.BACK, "Nozzle_R2": Vector3.BACK, "Nozzle_R3": Vector3.BACK,
		"Nozzle_R4": Vector3.BACK, "Nozzle_P1": Vector3.DOWN, "Nozzle_P2": Vector3.DOWN,
		"Nozzle_P3": Vector3.DOWN, "Nozzle_P4": Vector3.DOWN, "Nozzle_P5": Vector3.LEFT,
		"Nozzle_P6": Vector3.RIGHT, "Light_Front": Vector3.FORWARD, "Light_Rear": Vector3.BACK,
	}
	for n in expected:
		var marker := by_name.get(n) as Node3D
		if marker == null:
			wrong.append(n + " missing")
			continue
		var jet := -marker.global_transform.basis.z
		if jet.dot(expected[n]) < 0.95:
			wrong.append("%s points %s" % [n, str(jet.snapped(Vector3(0.01, 0.01, 0.01)))])
	check(wrong.is_empty(), "the markers point where the contract says (-Z is the jet)%s"
		% ["" if wrong.is_empty() else " (%s)" % ", ".join(wrong)])
	var body := mesh(by_name, "Body")
	var hull := world_aabb(body).grow(0.05)
	var outside: Array[String] = []
	for n in by_name.keys():
		var s := str(n)
		if s.begins_with("Nozzle_") and by_name[n] is Node3D and not hull.has_point((by_name[n] as Node3D).global_position):
			outside.append(s)
	check(outside.is_empty(), "every nozzle marker is on the body%s"
		% ["" if outside.is_empty() else " (outside: %s)" % ", ".join(outside)])
	var rear := (by_name["Nozzle_R1"] as Node3D).position
	var cam := by_name.get("Camera_Hood") as Node3D
	var seat := by_name.get("Seat_Driver") as Node3D
	check(rear.z > 1.8 and cam != null and cam.position.z < -0.8 and cam.position.y > 0.8
		and seat != null and seat.position.y > 0.3 and seat.position.y < 0.9,
		"the rear nozzles are at the tail, the hood camera over the hood, the seat in the cabin")


## the front and the rear of the car are where the physics expects them: the lamps ahead of the front axle
func check_ends(by_name: Dictionary) -> void:
	var lamp := mesh(by_name, "Lamp_FL")
	var tail := mesh(by_name, "LightBar_Rear")
	var front := by_name.get("Wheel_FL") as Node3D
	var rear := by_name.get("Wheel_RL") as Node3D
	var ok := lamp != null and tail != null and front != null and rear != null
	if ok:
		ok = world_aabb(lamp).get_center().z < front.position.z - 0.4 \
			and world_aabb(tail).get_center().z > rear.position.z + 0.1
	check(ok, "the lamps are ahead of the front axle, the tail lights behind the rear axle")
