extends Node
## The bank walls of the Huangpu and the Suzhou Creek are solid, and they leave the roads that cross the water free.
##
## The walls were drawn and had no collision: a car that left the road at a bank drove through the drawn wall, fell 3.6 m onto the
## water (a solid floor 3 m under the road) and drove on the river, or fell through the holes of the floor of the creek at its bends
## to the kill floor (tools/fuzz_drive.gd: a drive at 178 km/h left the road at (-1062, -701) into the creek and fell through it at
## (-1024, -799)). The walls are boxes now (TerrainBuilder.build_banks), built after the lanes: a piece is left out where a lane
## crosses the bank at the height of the road (the bridges of the creek) or runs along it closer than a car.
## Run: python tools/gd.py test res://world/tests/test_bank_walls.gd -- --timeout=290 --stub=audio,menu,hud,rivals,traffic,police

const MAIN := "res://main.tscn"
const LaneSpatial := preload("res://world/api/lane_spatial.gd")
const TerrainBuilder := preload("res://world/build/terrain_builder.gd")
## The drive of the fuzz that left the road into the creek: the start, the direction and the speed.
const FUZZ_START := Vector3(-1065.4, 0.0, -689.6)
const FUZZ_DIRECTION := Vector3(0.23, 0.0, -0.97)
const FUZZ_KMH := 178.0
## No wall may stand this close (m) to a lane at the height of the road.
const LANE_CLEAR := 2.0
## A lane between these heights (m) is at the height of the road (a deck over it, a tunnel under it is not).
const ROAD_LOW := -4.0
const ROAD_HIGH := 5.0

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, "  ", detail)
	else:
		_failures += 1
		print("FAIL ", label, "  ", detail)


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	var builder: Object = Game.world.get("_builder")
	var lane_grid: LaneSpatial = builder.get("lane_grid")
	var bodies := get_tree().root.find_children("BankWallBody_*", "StaticBody3D", true, false)
	var shapes: Array[CollisionShape3D] = []
	for body in bodies:
		for child in body.get_children():
			if child is CollisionShape3D:
				shapes.append(child as CollisionShape3D)
	_check(bodies.size() >= 3, "the river and both banks of the creek have a wall body", "(%d bodies)" % bodies.size())
	_check(shapes.size() > 1000, "the walls are solid along the banks", "(%d pieces of wall)" % shapes.size())
	# no wall stands in a lane at the height of the road: the bridges of the creek cross the bank through a gap
	var close: Array[String] = []
	var crossing_gaps := 0
	for shape in shapes:
		var box := shape.shape as BoxShape3D
		var basis := shape.global_transform.basis
		var x_axis := basis.x.normalized()
		var to_water := basis.z.normalized()
		var land_face := shape.global_transform.origin - to_water * (box.size.z * 0.5)
		for s: float in [-0.5, 0.0, 0.5]:
			var p := land_face + x_axis * (box.size.x * s)
			var point := Vector3(p.x, 0.0, p.z)
			var near := lane_grid.query_near(point, LANE_CLEAR + 2.0)
			for lane_index in near["lanes"] as PackedInt32Array:
				var detail := lane_grid.detail(lane_index, point)
				var lane_point: Vector3 = detail["point"]
				if lane_point.y < ROAD_LOW or lane_point.y > ROAD_HIGH:
					continue
				if float(detail["distance"]) < LANE_CLEAR:
					close.append("(%.0f, %.0f) %.1f m from a lane" % [p.x, p.z, float(detail["distance"])])
	_check(close.is_empty(), "no bank wall stands in a lane", "(%d: %s)" % [close.size(), ", ".join(close.slice(0, 4))])
	# no hole along the banks: the ground reaches the wall on the land side, the floor of the water reaches it on the other side
	# (the ground stopped up to 7 m short of the bank, and the floor of the creek left a wedge open at every bend)
	var holes_land: Array[String] = []
	var holes_water: Array[String] = []
	var ray_space := get_viewport().get_world_3d().direct_space_state
	# the ground of the city (past it there is nothing, and the edge walls stand there) and the water bodies (a strip of land
	# between the river and the mouth of the creek has the water of the creek behind it)
	var area: Rect2 = (builder.get("data") as Object).call("window_rect").grow(TerrainBuilder.EDGE_RING)
	var waters: Array = (builder.get("_terrain") as Object).call("water_polygons")
	for shape in shapes:
		var box := shape.shape as BoxShape3D
		var to_water := shape.global_transform.basis.z.normalized()
		var land_face := shape.global_transform.origin - to_water * (box.size.z * 0.5)
		for d: float in [0.5, 2.5]:
			var land := land_face - to_water * d
			if not area.has_point(Vector2(land.x, land.z)):
				continue
			var land_y := _top_y(ray_space, land)
			if is_nan(land_y) or (land_y < -1.0 and not _in_water(waters, Vector2(land.x, land.z))):
				holes_land.append("(%.0f, %.0f) %s" % [land.x, land.z, "nothing" if is_nan(land_y) else "y %.1f" % land_y])
			var wet := land_face + to_water * (box.size.z + d)
			if is_nan(_top_y(ray_space, wet)):
				holes_water.append("(%.0f, %.0f)" % [wet.x, wet.z])
	_check(holes_land.is_empty(), "the ground reaches every bank wall", "(%d holes: %s)" % [holes_land.size(),
			", ".join(holes_land.slice(0, 4))])
	_check(holes_water.is_empty(), "the floor of the water reaches every bank wall", "(%d holes: %s)" % [holes_water.size(),
			", ".join(holes_water.slice(0, 4))])
	# the lanes that cross the water at the height of the road find a gap: their points over the bank line touch no wall
	var space := get_viewport().get_world_3d().direct_space_state
	var car_box := BoxShape3D.new()
	car_box.size = Vector3(1.9, 1.0, 1.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = car_box
	query.collision_mask = 1
	var blocked: Array[String] = []
	var water_polys: Array = []
	var terrain: Object = builder.get("_terrain")
	if terrain != null:
		water_polys = terrain.call("water_polygons")
	for lane: LanePath in Game.world.get_lane_paths():
		if lane.curve == null:
			continue
		var length := lane.curve.get_baked_length()
		var d := 0.0
		var was_in := false
		while d <= length:
			var p := lane.curve.sample_baked(d, true)
			d += 1.0
			if p.y < ROAD_LOW or p.y > ROAD_HIGH:
				was_in = false
				continue
			var inside := _in_water(water_polys, Vector2(p.x, p.z))
			if inside != was_in and d > 1.0:
				crossing_gaps += 1
				query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.9)
				for hit in space.intersect_shape(query, 4):
					var node := hit["collider"] as Node
					if node != null and String(node.name).begins_with("BankWallBody_"):
						blocked.append("(%.0f, %.1f, %.0f)" % [p.x, p.y, p.z])
						break
			was_in = inside
	_check(crossing_gaps > 0, "lanes cross the water at the height of the road", "(%d crossings of a bank)" % crossing_gaps)
	_check(blocked.is_empty(), "every lane that crosses a bank finds a gap in the wall",
			"(%d blocked: %s)" % [blocked.size(), ", ".join(blocked.slice(0, 4))])
	await _drive_into_the_bank()
	print("BANK WALL TESTS %s (%d failures)" % ["OK" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## The drive of the fuzz that went into the creek: the wall stops the car on the bank.
func _drive_into_the_bank() -> void:
	var car := Game.player as ArcadeCar
	if car == null:
		_check(false, "the player car is there")
		return
	var start := FUZZ_START
	var space := get_viewport().get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(start + Vector3.UP * 3.0, start - Vector3.UP * 5.0, 1)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		start.y = (hit["position"] as Vector3).y
	car.reset_to(Transform3D(Basis.looking_at(FUZZ_DIRECTION, Vector3.UP), start + Vector3.UP * 0.2))
	await get_tree().physics_frame
	car.health = car.max_health
	car.linear_velocity = FUZZ_DIRECTION * (FUZZ_KMH / 3.6)
	Input.action_press(&"accelerate")
	var lowest := INF
	var reported := false
	var last := car.global_position
	for i in int(3.0 * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		lowest = minf(lowest, car.global_position.y)
		if car.global_position.y < -0.5 and not reported:
			reported = true
			print("   the car went down at %s (the tick before at %s)" % [str(car.global_position.snapped(Vector3.ONE * 0.1)),
				str(last.snapped(Vector3.ONE * 0.1))])
			_print_banks_near(car.global_position)
		last = car.global_position
	Input.action_release(&"accelerate")
	_check(lowest > -1.5, "the car that drove at the bank of the creek stays on the bank",
			"(lowest y %.2f, the water is at %.1f; the car is at %s)" % [lowest, -3.0, str(car.global_position.snapped(Vector3.ONE * 0.1))])


## The wall pieces and the lanes around a point (where a car went into the water).
func _print_banks_near(point: Vector3) -> void:
	for body in get_tree().root.find_children("BankWallBody_*", "StaticBody3D", true, false):
		for child in body.get_children():
			var shape := child as CollisionShape3D
			if shape == null:
				continue
			var p := shape.global_transform.origin
			if Vector2(p.x - point.x, p.z - point.z).length() < 25.0:
				print("      wall piece %s at %s" % [body.name, str(p.snapped(Vector3.ONE * 0.1))])
	var builder: Object = Game.world.get("_builder")
	var lane_grid: LaneSpatial = builder.get("lane_grid")
	var near := lane_grid.query_near(Vector3(point.x, 0.0, point.z), 20.0)
	for lane_index in near["lanes"] as PackedInt32Array:
		var detail := lane_grid.detail(lane_index, Vector3(point.x, 0.0, point.z))
		print("      lane %d at %s, %.1f m away, direction %s" % [lane_index, str((detail["point"] as Vector3).snapped(Vector3.ONE * 0.1)),
			float(detail["distance"]), str((detail["tangent"] as Vector3).snapped(Vector3.ONE * 0.01))])


## The height of the highest surface under a point, or NAN when there is nothing: three rays a few centimetres apart (one ray
## can slip through the shared edge of two triangles of the ground; a car does not, its wheel probes are spheres).
static func _top_y(space: PhysicsDirectSpaceState3D, point: Vector3) -> float:
	var best := NAN
	for offset: Vector3 in [Vector3.ZERO, Vector3(0.04, 0.0, 0.0), Vector3(0.0, 0.0, 0.04)]:
		var p := point + offset
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 20.0, p.z), Vector3(p.x, -10.0, p.z), 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var y := (hit["position"] as Vector3).y
		if is_nan(best) or y > best:
			best = y
	return best


## True when a point of the plan is in one of the water polygons.
static func _in_water(polys: Array, point: Vector2) -> bool:
	for poly in polys:
		if Geometry2D.is_point_in_polygon(point, poly as PackedVector2Array):
			return true
	return false
