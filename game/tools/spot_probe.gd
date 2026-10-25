extends Node
## What stands at a place of the city and what the queries of a wheel cost there: the bodies and shapes within 12 m, the lanes
## within 10 m, the triangles of the ground under the point, and the sphere cast of a wheel probe (WheelMod: 6 cm, 0.9 m down)
## per collision layer and with the ground or the road tiles left out. A diagnostic tool, not a test.
##   python tools/gd.py test res://tools/spot_probe.gd -- --timeout=250 --stub=audio,menu,hud,rivals,traffic,police --at=-281,-542
##
## What it found (status/improve/SUMMARY.md, the frame rate): Godot's Jolt server answers a cast_motion with a binary search, about
## nine overlap tests against every body the cast reaches: 3-8 us a body that it hits, and a wheel on a road reaches the road tile
## and the ground 2 cm under it. A point on a vertex of the ground (round coordinates: where eight triangles meet) costs 40-80 us:
## measure inside a triangle.

const MAIN := "res://main.tscn"
const QUERIES := 1000


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	var parts := String(Game.option("at", "-281,-542")).split(",")
	var at := Vector3(float(parts[0]), 0.0, float(parts[1]))
	var space := get_viewport().get_world_3d().direct_space_state
	_bodies(space, at)
	_lanes(at)
	_ground_triangles(at)
	_cast_costs(space, at)
	get_tree().quit(0)


## The bodies within 12 m and their shapes (read through the physics server: the shapes of the built bodies have no owners).
func _bodies(space: PhysicsDirectSpaceState3D, at: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(24.0, 8.0, 24.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, 2.0, 0.0))
	q.collision_mask = 0xFFFFFFFF
	var seen := {}
	for h in space.intersect_shape(q, 64):
		var key := "%s:%d" % [str(h["rid"]), int(h["shape"])]
		if seen.has(key):
			continue
		seen[key] = true
		var collider := h["collider"] as Node
		var shape_rid: RID = PhysicsServer3D.body_get_shape(h["rid"], int(h["shape"]))
		var kind := PhysicsServer3D.shape_get_type(shape_rid)
		var data: Variant = PhysicsServer3D.shape_get_data(shape_rid)
		var extra := ""
		if kind == PhysicsServer3D.SHAPE_CONCAVE_POLYGON:
			extra = ", %d faces" % (((data as Dictionary)["faces"] as PackedVector3Array).size() / 3)
		elif kind == PhysicsServer3D.SHAPE_CONVEX_POLYGON:
			extra = ", %d points" % (data as PackedVector3Array).size()
		elif kind == PhysicsServer3D.SHAPE_BOX:
			extra = ", %s" % str(data)
		# where the shape stands (the bodies of the city are not moved: the shape transform is in world space)
		var xform: Transform3D = PhysicsServer3D.body_get_state(h["rid"], PhysicsServer3D.BODY_STATE_TRANSFORM) 				* PhysicsServer3D.body_get_shape_transform(h["rid"], int(h["shape"]))
		if kind != PhysicsServer3D.SHAPE_CONCAVE_POLYGON:
			extra += " at %s, its long axis %s" % [str(xform.origin.snapped(Vector3.ONE * 0.01)),
				str((xform.basis.z if kind == PhysicsServer3D.SHAPE_BOX else xform.basis.y).normalized().snapped(Vector3.ONE * 0.01))]
		print("SPOT body %s (layer %d): shape %d of type %d%s" % [collider.get_path(),
			(collider as CollisionObject3D).collision_layer if collider is CollisionObject3D else -1, int(h["shape"]), kind, extra])


func _lanes(at: Vector3) -> void:
	for lane: LanePath in Game.world.get_lane_paths():
		if lane.curve == null:
			continue
		var p := lane.curve.sample_baked(lane.curve.get_closest_offset(at), true)
		if p.distance_to(at) < 10.0:
			print("SPOT lane of %s %.1f m away at %s" % [String(lane.road_id), p.distance_to(at), str(p.snapped(Vector3.ONE * 0.1))])


## The triangles of the ground body whose box reaches the point, and the ones the point is inside.
func _ground_triangles(at: Vector3) -> void:
	var ground := get_tree().root.find_child("GroundBody", true, false)
	if ground == null:
		return
	var p2 := Vector2(at.x, at.z)
	var under := 0
	var near := 0
	for child in ground.get_children():
		if not child is CollisionShape3D:
			continue
		var concave := (child as CollisionShape3D).shape as ConcavePolygonShape3D
		if concave == null:
			continue
		var faces := concave.get_faces()
		for i in range(0, faces.size() - 2, 3):
			var a := Vector2(faces[i].x, faces[i].z)
			var b := Vector2(faces[i + 1].x, faces[i + 1].z)
			var c := Vector2(faces[i + 2].x, faces[i + 2].z)
			var lo := a.min(b).min(c) - Vector2(0.2, 0.2)
			var hi := a.max(b).max(c) + Vector2(0.2, 0.2)
			if p2.x < lo.x or p2.y < lo.y or p2.x > hi.x or p2.y > hi.y:
				continue
			near += 1
			if Geometry2D.point_is_inside_triangle(p2, a, b, c):
				under += 1
	print("SPOT ground: the point is inside %d triangles, %d reach it with their box" % [under, near])


## The sphere cast of a wheel probe from 0.8 m over the point, per layer and without the ground or the road tiles; a ray and a
## rest query for comparison.
func _cast_costs(space: PhysicsDirectSpaceState3D, at: Vector3) -> void:
	var ground := get_tree().root.find_child("GroundBody", true, false) as CollisionObject3D
	var roads: Array[RID] = []
	var roads_node := get_tree().root.find_child("Roads", true, false)
	if roads_node != null:
		for node in roads_node.find_children("*_surface", "StaticBody3D", true, false):
			roads.append((node as CollisionObject3D).get_rid())
	var sphere := SphereShape3D.new()
	sphere.radius = 0.06
	var cast := PhysicsShapeQueryParameters3D.new()
	cast.shape = sphere
	cast.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.8, 0.0))
	cast.motion = Vector3(0.0, -0.9, 0.0)
	var line := "SPOT the cast of a wheel probe:"
	for mask: int in [0b001, 0b010, 0b100, 0b111]:
		cast.collision_mask = mask
		line += " layers %d %.2f us," % [mask, _time_cast(space, cast)]
	cast.collision_mask = 0b111
	if ground != null:
		cast.exclude = [ground.get_rid()]
		line += " without the ground %.2f us," % _time_cast(space, cast)
	cast.exclude = roads
	line += " without the road tiles %.2f us" % _time_cast(space, cast)
	print(line)
	cast.exclude = []
	var t0 := Time.get_ticks_usec()
	for i in QUERIES:
		space.get_rest_info(cast)
	var t1 := Time.get_ticks_usec()
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 0.8, 0.0), at + Vector3(0.0, -0.1, 0.0), 0b111)
	for i in QUERIES:
		space.intersect_ray(ray)
	var t2 := Time.get_ticks_usec()
	print("SPOT a rest query %.2f us, a ray %.2f us" % [float(t1 - t0) / QUERIES, float(t2 - t1) / QUERIES])


func _time_cast(space: PhysicsDirectSpaceState3D, cast: PhysicsShapeQueryParameters3D) -> float:
	var t0 := Time.get_ticks_usec()
	for i in QUERIES:
		space.cast_motion(cast)
	return float(Time.get_ticks_usec() - t0) / QUERIES
