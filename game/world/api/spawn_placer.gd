extends RefCounted
## The spawn points of the world: a point on a lane, facing the traffic, with a clear road
## ahead and the height of the road under it (the lanes of the roads unit are a few decimetres
## above the collision mesh of the deck, so a car that trusts the raw height floats or sinks).

const LaneIndex := preload("res://world/api/lane_index.gd")

## The height of a lane counts more than its distance when the lane below is compared.
const HEIGHT_WEIGHT := 3.0
## The height of a car above the road.
const LANE_LIFT := 0.6
## How far ahead the direction of a lane is looked at.
const LOOK_AHEAD := 4.0
## The collision mask of the road surface.
const SURFACE_MASK := 1
## How far below a lane point the road is looked for.
const SURFACE_REACH := 4.0
## How far above a lane point the ray down starts. The lanes lie on their road (99.6 % of the lane points are less than 0.1 m
## above it); a ray that started 4 m up met whatever was over the lane first and put the car on top of it: the roof of a toll
## booth, the Bund promenade, the deck of an elevated road, the ground over a tunnel, the deck of the Waibaidu bridge (334 of
## 68,000 lane points, tools/spawn_height_probe.gd). A wreck respawned the player there, in the air over the road.
const SURFACE_ABOVE := 0.5
## How far ahead of a spawn has to be clear.
const CLEAR_AHEAD := 30.0
## The box of the car at a respawn (the whole car, from 0.4 m over the road to 1.8 m; the corridor ahead starts at the origin
## of the car and 0.7 m over the road, so the back of the car and a low beam over it were not looked at: a respawn put the car
## with its roof in the structure of an elevated road).
const SPOT_BOX := Vector3(2.0, 1.4, 4.6)
const SPOT_LIFT := 0.5
## The step of the clear corridor.
const CLEAR_STEP := 4.0
## The box of the clear corridor in front of a spawn.
const CLEAR_BOX := Vector3(2.2, 1.4, 30.0)
## The collision mask of the clear corridor (the world and the trigger layers).
const CLEAR_MASK := 1 | 4
## How close another lane may come to the corridor.
const CLEAR_LANE_DISTANCE := 2.5
## How many steps a spawn walks along its lane when the road ahead is not clear.
const SPAWN_STEPS := 64
## How many steps a respawn walks along its lane, in the direction of its drive, to find a clear road ahead.
const RESPAWN_STEPS := 30

var lanes: Array[LanePath] = []
var index: LaneIndex
var _clear_box: BoxShape3D
var _spot_box: BoxShape3D


func setup(lanes: Array[LanePath], index: LaneIndex) -> void:
	self.lanes = lanes
	self.index = index


## A spawn point on the closest lane with a clear road ahead.
func spawn_transform(node: Node3D, position: Vector3) -> Transform3D:
	var found := closest_lane(position)
	if found.is_empty():
		return Transform3D(Basis.IDENTITY, position + Vector3.UP * LANE_LIFT)
	var lane: LanePath = found["lane"]
	return spawn_on_lane(node, lane, found["offset"])


## The lane point `offset` metres along the lane, advanced until the road ahead is clear.
func spawn_on_lane(node: Node3D, lane: LanePath, offset: float) -> Transform3D:
	if lane.curve == null:
		return Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var length := lane.curve.get_baked_length()
	var distance := fposmod(offset, maxf(length, 0.001))
	var lane_index := lanes.find(lane)
	for step in SPAWN_STEPS:
		var xform := lane_transform(node, lane, distance)
		if is_clear(node, xform, lane_index):
			return xform
		distance += CLEAR_STEP
		if distance > length:
			break
	return lane_transform(node, lane, distance)


## True when the 30 m ahead of the spawn are free (no props, no other lane).
func is_clear(node: Node3D, xform: Transform3D, lane_index: int) -> bool:
	if not _physics_clear(node, xform):
		return false
	return _lanes_clear(xform, lane_index)


## A respawn on a lane: the point `offset` metres along it, facing `direction` (on a lane that runs against it the car drives
## the other way: it must drive away from its wreck), moved along the lane in the direction of the drive until the 30 m ahead
## are clear of the world and the props. The wreck flow sends the car off at 60 km/h or more, and the nearest lane point was
## taken as it was: 10 of 58 respawns hit a tree, a lamp or a wall in their first 4 s, one of them 0.13 s after the respawn
## (tools/respawn_probe.gd). The other lanes are not looked at: a respawn may be in a junction.
func respawn_on_lane(node: Node3D, lane: LanePath, offset: float, direction: Vector3) -> Transform3D:
	var length := lane.curve.get_baked_length()
	var first := lane_transform(node, lane, offset)
	var against := (-first.basis.z).dot(Vector3(direction.x, 0.0, direction.z)) < 0.0
	if against:
		first.basis = first.basis.rotated(Vector3.UP, PI)
	var distance := offset
	for step in RESPAWN_STEPS:
		var xform := lane_transform(node, lane, distance)
		if against:
			xform.basis = xform.basis.rotated(Vector3.UP, PI)
		if _spot_clear(node, xform) and _physics_clear(node, xform):
			return xform
		distance += -CLEAR_STEP if against else CLEAR_STEP
		if distance < 0.0 or distance > length:
			break
	return first


## A shape query of the corridor in front of the spawn (the world and the trigger layers).
func _physics_clear(node: Node3D, xform: Transform3D) -> bool:
	if not node.is_inside_tree():
		return true
	var space := node.get_world_3d().direct_space_state
	if space == null:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clear_shape()
	query.collision_mask = CLEAR_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var forward := -xform.basis.z
	query.transform = Transform3D(xform.basis,
		xform.origin + forward * (CLEAR_AHEAD * 0.5) + Vector3.UP * 0.8)
	return space.intersect_shape(query, 1).is_empty()


## True when the place of the car itself is free of the world and the props.
func _spot_clear(node: Node3D, xform: Transform3D) -> bool:
	if not node.is_inside_tree():
		return true
	var space := node.get_world_3d().direct_space_state
	if space == null:
		return true
	if _spot_box == null:
		_spot_box = BoxShape3D.new()
		_spot_box.size = SPOT_BOX
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _spot_box
	query.collision_mask = CLEAR_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * SPOT_LIFT)
	return space.intersect_shape(query, 1).is_empty()


## True when no other lane crosses the corridor in front of the spawn.
func _lanes_clear(xform: Transform3D, lane_index: int) -> bool:
	if index == null:
		return true
	var forward := -xform.basis.z
	for step in range(1, int(CLEAR_AHEAD / CLEAR_STEP) + 1):
		var point := xform.origin + forward * (float(step) * CLEAR_STEP)
		for candidate in index.candidates(point, 16.0):
			if candidate == lane_index:
				continue
			var lane := lanes[candidate]
			if lane.curve == null:
				continue
			var offset := lane.curve.get_closest_offset(point)
			var closest := lane.curve.sample_baked(offset, true)
			if Vector2(closest.x - point.x, closest.z - point.z).length() < CLEAR_LANE_DISTANCE:
				return false
	return true


## The lane closest to a point: {"lane", "offset", "distance"}.
func closest_lane(pos: Vector3) -> Dictionary:
	var best := -1
	var best_score := INF
	var best_offset := 0.0
	var candidates: Array[int] = []
	if index != null:
		candidates = index.candidates(pos, 96.0)
	if candidates.is_empty():
		# Further than 96 m from every lane (the river, the edge of the city): every lane is a candidate.
		# (`range()` is an untyped Array: assigning it to the Array[int] is a script error that made the
		# whole function return nothing, so a car that was lost far from the roads was never put back.)
		for lane_number in lanes.size():
			candidates.append(lane_number)
	for candidate in candidates:
		var lane := lanes[candidate]
		if lane.curve == null:
			continue
		var offset := lane.curve.get_closest_offset(pos)
		var point := lane.curve.sample_baked(offset, true)
		var flat := Vector2(point.x - pos.x, point.z - pos.z).length()
		# The height decides between the elevated deck and the road below it.
		var score := flat + absf(point.y - pos.y) * HEIGHT_WEIGHT
		if score < best_score:
			best_score = score
			best = candidate
			best_offset = offset
	if best < 0:
		return {}
	return {"lane": lanes[best], "offset": best_offset, "distance": best_score}


## The box of the corridor in front of a spawn (one shape for all the queries).
func _clear_shape() -> BoxShape3D:
	if _clear_box == null:
		_clear_box = BoxShape3D.new()
		_clear_box.size = CLEAR_BOX
	return _clear_box


## A transform on a lane, `distance` metres along it, facing the traffic direction.
func lane_transform(node: Node3D, lane: LanePath, distance: float) -> Transform3D:
	var curve := lane.curve
	var length := curve.get_baked_length()
	var offset := fposmod(distance, maxf(length, 0.001))
	var point := curve.sample_baked(offset, true)
	# The direction is taken from the point ahead; at the end of the lane there is none (the wrap went to the start of the
	# lane and turned the car round), so the point behind gives it.
	var ahead := point
	if offset + LOOK_AHEAD <= length:
		ahead = curve.sample_baked(offset + LOOK_AHEAD, true)
	if ahead.distance_to(point) < 0.05:
		ahead = point - (curve.sample_baked(maxf(offset - LOOK_AHEAD, 0.0), true) - point)
	var y := surface_y(node, point)
	var here := Vector3(point.x, y, point.z)
	var there := Vector3(ahead.x, y, ahead.z)
	if there.distance_to(here) < 0.01:
		return Transform3D(Basis.IDENTITY, here)
	return Transform3D(Basis.IDENTITY, here).looking_at(there, Vector3.UP)


## The height of the road under a point: the surface plus the clearance of the car.
func surface_y(node: Node3D, point: Vector3) -> float:
	if not node.is_inside_tree():
		return point.y + LANE_LIFT
	var space := node.get_world_3d().direct_space_state
	if space == null:
		return point.y + LANE_LIFT
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * SURFACE_ABOVE, point - Vector3.UP * SURFACE_REACH, SURFACE_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return point.y + LANE_LIFT
	return (hit["position"] as Vector3).y + LANE_LIFT
