extends Node
## The roadblocks (ref/gameplay/DOSSIER.md §6.3).
##
##   tools/godot.sh test res://ai/police/tests/test_roadblock.gd
##
## The block stands 350-450 m ahead of the player on his route, out of sight, broadside across
## the carriageway. Up to heat 3 it has exactly one body-to-body gap of three metres; from heat
## 4 it is closed and a spike strip lies in front of it. Every prop stands BEFORE the cars (a
## positive z), so the driver sees the block coming. A parked car that is hit hard enough is
## shoved off the road.

const T := preload("res://ai/police/tests/police_test.gd")
## The space a broadside car takes across the road (m).
const CAR_SPAN := 4.79 * cos(deg_to_rad(12.0)) + 2.08 * sin(deg_to_rad(12.0))
## The gap of the block up to heat 3 (m).
const GAP := 3.1
## The tolerance of the gap (m).
const GAP_TOLERANCE := 0.2
## The width of the box that has to find the gap (m).
const CAST_WIDTH := 2.2
## The step of the cast across the road (m).
const CAST_STEP := 0.5
## The step of the walk along the route (m).
const ROUTE_STEP := 10.0
## How near the route has to come to the block to count (m).
const ROUTE_NEAR := 10.0


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-400.0))
	# A camera makes the "out of sight" rule real.
	var camera := Camera3D.new()
	camera.far = 900.0
	t.tree.root.add_child(camera)
	camera.current = true
	# The camera looks back, so the block ahead of the player is out of sight: that is the
	# situation the dispatcher waits for.
	camera.global_position = t.player.global_position + Vector3(0.0, 3.0, 6.0)
	camera.look_at(t.player.global_position - Vector3(20.0, 0.0, 0.0), Vector3.UP)
	t.director.spawn_enabled = false
	# The test builds its own blocks, so the dispatcher does not put a second one on the road.
	t.director.blockade.auto_spawn = false
	await _check_block(t, 3, true)
	await _check_block(t, 4, false)
	await _check_widths(t)
	await _check_ram(t)
	t.expect(24)
	t.finish()


## A roadblock at the given heat.
func _check_block(t: T, heat: int, has_gap: bool) -> void:
	t.director.force_heat(heat)
	t.director.remove_all_units()
	t.director.blockade.clear_blocks()
	var made := t.director.spawn_roadblock_now()
	t.check(made, "the roadblock is set up at heat %d" % heat)
	await t.idle(0.2)
	if t.director.blockade.blocks.is_empty():
		t.check(false, "the roadblock exists at heat %d" % heat)
		return
	var block: PoliceRoadblock = t.director.blockade.blocks[0]
	# The distance along the route of the player (not the straight line).
	var distance := _route_distance(t, block.global_position)
	t.check(distance >= 350.0 and distance <= 450.0,
			"the roadblock is 350-450 m ahead (%.0f m)" % distance)
	# Every prop stands before the cars, so the driver sees the block coming.
	var behind := 0
	for child in block.get_children():
		if child is Node3D and (child as Node3D).position.z < -0.01:
			behind += 1
	t.check(behind == 0, "every prop stands before the cars (%d behind)" % behind)
	# The gap: the free space between the cars.
	var gaps := _gaps_of(block)
	var open_m := 0.0
	for g: float in gaps:
		open_m += maxf(g - CAR_SPAN, 0.0)
	if has_gap:
		var three := false
		for g: float in gaps:
			if absf(g - (CAR_SPAN + GAP)) <= GAP_TOLERANCE:
				three = true
		t.check(three, "the block has one gap of three metres (%s)" % str(gaps))
		t.check(absf(open_m - GAP) <= GAP_TOLERANCE + 0.3,
				"the block is closed apart from the gap (%.2f m open)" % open_m)
		t.check(block.active_strips().is_empty(), "the block has no spikes at heat %d" % heat)
	else:
		t.check(open_m <= 0.2, "the block is closed at heat %d (%.2f m open)" % [heat, open_m])
		t.check(not block.active_strips().is_empty(),
				"the closed block has a spike strip at heat %d" % heat)
	# The cast across the road: only the gap lets a car through.
	var openings := _openings(t, block, _carriageway(t))
	if has_gap:
		t.check(openings.size() > 0, "the gap lets a car through (%d openings)" % openings.size())
		t.check(_one_run(openings), "the block has only one opening (%s)" % str(openings))
	else:
		t.check(openings.is_empty(), "the closed block has no opening (%s)" % str(openings))


## The x positions (across the road) where a car of CAST_WIDTH fits through the block.
func _openings(t: T, block: PoliceRoadblock, carriageway: float) -> Array[float]:
	var space := t.tree.root.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(CAST_WIDTH, 1.6, 1.2)
	var out: Array[float] = []
	var across := block.global_transform.basis.x
	var half := carriageway * 0.5
	var x := -half
	while x <= half:
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis(), block.global_position + across * x
				+ Vector3.UP * 0.8)
		params.collision_mask = 2
		params.collide_with_areas = false
		if space.intersect_shape(params, 1).is_empty():
			out.append(x)
		x += CAST_STEP
	return out


## True when the openings are one single run.
func _one_run(openings: Array[float]) -> bool:
	if openings.size() <= 1:
		return true
	for i in range(1, openings.size()):
		if openings[i] - openings[i - 1] > CAST_STEP * 1.5:
			return false
	return true


## A parked car that is hit hard enough is shoved off the road.
func _check_ram(t: T) -> void:
	t.director.force_heat(3)
	t.director.remove_all_units()
	t.director.blockade.clear_blocks()
	t.director.spawn_roadblock_now()
	await t.idle(0.2)
	if t.director.blockade.blocks.is_empty():
		t.check(false, "the roadblock exists for the ram test")
		return
	var block: PoliceRoadblock = t.director.blockade.blocks[0]
	if block.active_cars().is_empty():
		t.check(false, "the block has cars for the ram test")
		return
	var car := _car_in_front(t, block)
	var before := _positions(block)
	# The player stops a metre before the cars: the block must not move.
	t.player.reset_to(_before_car(block, car, 3.2))
	await t.idle(1.5)
	var frozen := true
	for parked in block.active_cars():
		if not parked.freeze:
			frozen = false
	t.check(frozen, "the cars of the block stay frozen (%s)" % str(frozen))
	# The player rams the block at 60 km/h: a car is shoved off the road. The cars of a block
	# stand at an angle, so the player hits the corner of one of them first.
	t.player.reset_to(_before_car(block, car, 12.0))
	await t.drive(2.0, 0.0, 60.0)
	var shoved := 0.0
	for parked in block.active_cars():
		if not parked.freeze:
			shoved = maxf(shoved, 1.0)
		shoved = maxf(shoved, parked.global_position.distance_to(before[parked.get_instance_id()]))
	t.check(shoved >= 1.0, "a parked car is shoved off the road (%.2f m)" % shoved)


## The places of the cars of the block, by instance id.
func _positions(block: PoliceRoadblock) -> Dictionary:
	var out: Dictionary = {}
	for car in block.active_cars():
		out[car.get_instance_id()] = car.global_position
	return out


## The car of the block that stands in the lane of the player.
func _car_in_front(t: T, block: PoliceRoadblock) -> PoliceCar:
	var across := block.global_transform.basis.x
	var lateral := (t.player.global_position - block.global_position).dot(across)
	var best: PoliceCar = block.cars[0]
	var best_distance := INF
	for car in block.active_cars():
		var d: float = absf((car.global_position - block.global_position).dot(across) - lateral)
		if d < best_distance:
			best_distance = d
			best = car
	return best


## The place of the player `distance` metres before a car of the block, facing the traffic.
func _before_car(block: PoliceRoadblock, car: PoliceCar, distance: float) -> Transform3D:
	var forward := -block.global_transform.basis.z
	var yaw := atan2(-forward.x, -forward.z)
	return Transform3D(Basis(Vector3.UP, yaw),
			car.global_position + block.global_transform.basis.z * distance)


## The distances between the cars of the block, from the left to the right.
func _gaps_of(block: PoliceRoadblock) -> Array[float]:
	var out: Array[float] = []
	var positions: Array[float] = []
	for car in block.active_cars():
		positions.append(car.global_position.dot(block.global_transform.basis.x))
	positions.sort()
	for i in range(1, positions.size()):
		out.append(positions[i] - positions[i - 1])
	return out


## The distance from the player to a point along his route (m).
##
## The route is walked in steps of ten metres: the distance of the block is the place where
## the route comes closest to it.
func _route_distance(t: T, point: Vector3) -> float:
	var graph := t.director.spawner.ctx.graph
	var lane := t.director.lane
	var s := t.director.lane_offset
	var distance := 0.0
	var best := INF
	while distance < 600.0:
		s += ROUTE_STEP
		distance += ROUTE_STEP
		while s >= graph.lane_length(lane):
			s -= graph.lane_length(lane)
			var next := PoliceRoute.successor(graph, lane)
			if next < 0:
				return best
			lane = next
		var on_route := graph.position_at(lane, s)
		best = minf(best, on_route.distance_to(point))
		if best < ROUTE_NEAR:
			return distance
	return best


## The width of the road the player drives on (the outer lane edges plus a shoulder).
func _carriageway(t: T) -> float:
	var graph := t.director.spawner.ctx.graph
	return PoliceRoadWidth.width_at(graph, t.director.spawner.grid, t.director.lane,
			t.director.lane_offset)


## A block of a given width: the barriers are not stretched, the cars do not overlap and the
## cones are never on the same spot.
func _check_widths(t: T) -> void:
	var widths := [7.0, 10.5, 13.5, 22.1]
	for width: float in widths:
		var block := _make_block(t)
		block.setup(Transform3D(Basis(), t.player.global_position + Vector3(0.0, 0.0, 60.0)),
				Vector3.RIGHT, width, 4, 7)
		await t.idle(0.1)
		# The barriers are never stretched (ART.md §8: no stretched textures).
		var stretched := 0
		for barrier in block.barriers():
			if not barrier.visible:
				continue
			if not barrier.transform.basis.get_scale().is_equal_approx(Vector3.ONE):
				stretched += 1
		t.check(stretched == 0, "no barrier of a %.1f m block is stretched (%d)"
				% [width, stretched])
		# The cars of a closed block do not overlap.
		var min_car := INF
		var cars := block.active_cars()
		for i in cars.size():
			for j in range(i + 1, cars.size()):
				min_car = minf(min_car, cars[i].global_position.distance_to(
						cars[j].global_position))
		t.check(cars.size() < 2 or min_car >= CAR_SPAN - 0.01,
				"the cars of a %.1f m block do not overlap (%.2f m)" % [width, min_car])
		# The cones are never on the same spot.
		var min_cone := INF
		var cones: Array[Node3D] = []
		for cone in block.cones():
			if cone.visible:
				cones.append(cone)
		for i in cones.size():
			for j in range(i + 1, cones.size()):
				min_cone = minf(min_cone, cones[i].position.distance_to(cones[j].position))
		t.check(cones.size() < 2 or min_cone >= 0.8,
				"the cones of a %.1f m block stand apart (%.2f m)" % [width, min_cone])
		block.queue_free()


## A block of the test (the pool of the dispatcher has its own).
func _make_block(t: T) -> PoliceRoadblock:
	var block := PoliceRoadblock.new()
	t.tree.root.add_child(block)
	block.build_pool(t.director.spawner.ctx, t.director.spawner.grid)
	return block
