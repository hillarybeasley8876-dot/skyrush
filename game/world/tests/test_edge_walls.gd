extends Node
## The walls at the edge of the city (TerrainBuilder.build_edge_walls): a car that drives off the end of a road at the edge
## of the ground used to fall 60 m to the kill floor, be wrecked there, and (the police that followed it fell as well). The
## walls stand on the border of the ground and are high and deep enough for everything that drives or flies in the city.
## Run: python tools/gd.py test res://world/tests/test_edge_walls.gd

const TerrainBuilder := preload("res://world/build/terrain_builder.gd")
const Layers := preload("res://world/api/layers.gd")

const AREA := Rect2(-300.0, -200.0, 600.0, 400.0)

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS ", name, "  ", detail)
	else:
		_failures += 1
		print("FAIL ", name, "  ", detail)


## The first hit of a ray (the point), or Vector3.INF.
func _shoot(from: Vector3, to: Vector3) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD))
	return hit["position"] if not hit.is_empty() else Vector3.INF


func _run() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var terrain := TerrainBuilder.new()
	terrain.build_edge_walls(holder, AREA)
	for i in 4:
		await get_tree().physics_frame
	var centre := AREA.get_center()
	# from the middle of the area outwards, at several heights: the inner face of the wall is on the border
	for height in [-50.0, 0.5, 8.0, 60.0, 250.0]:
		var west := _shoot(Vector3(centre.x, height, centre.y), Vector3(AREA.position.x - 40.0, height, centre.y))
		var east := _shoot(Vector3(centre.x, height, centre.y), Vector3(AREA.end.x + 40.0, height, centre.y))
		var north := _shoot(Vector3(centre.x, height, centre.y), Vector3(centre.x, height, AREA.position.y - 40.0))
		var south := _shoot(Vector3(centre.x, height, centre.y), Vector3(centre.x, height, AREA.end.y + 40.0))
		_check("the walls close the area at a height of %.0f m" % height,
			absf(west.x - AREA.position.x) < 0.01 and absf(east.x - AREA.end.x) < 0.01
			and absf(north.z - AREA.position.y) < 0.01 and absf(south.z - AREA.end.y) < 0.01,
			"(W %.1f E %.1f N %.1f S %.1f)" % [west.x, east.x, north.z, south.z])
	# the corners: a ray along the diagonal does not slip between two walls
	var corner := _shoot(Vector3(AREA.end.x - 5.0, 1.0, AREA.end.y - 5.0), Vector3(AREA.end.x + 60.0, 1.0, AREA.end.y + 60.0))
	_check("the corners are closed", corner != Vector3.INF and (corner.x <= AREA.end.x + 0.01 or corner.z <= AREA.end.y + 0.01),
		"(%s)" % str(corner))
	# a car that is thrown at the wall does not get through
	var tunnelled := 0
	for speed in [50.0, 100.0, 200.0]:
		var body := RigidBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0, 1.0, 4.0)
		shape.shape = box
		body.add_child(shape)
		body.collision_layer = 2
		body.collision_mask = 1
		body.continuous_cd = true
		body.gravity_scale = 0.0
		holder.add_child(body)
		body.global_position = Vector3(AREA.end.x - 40.0, 1.0, centre.y)
		body.linear_velocity = Vector3(speed, 0.0, 0.0)
		for i in Engine.physics_ticks_per_second * 2:
			await get_tree().physics_frame
		if body.global_position.x > AREA.end.x:
			tunnelled += 1
		body.queue_free()
	_check("a body at 50, 100 and 200 m/s does not get through the wall", tunnelled == 0, "(%d got through)" % tunnelled)
	get_tree().quit(1 if _failures > 0 else 0)
