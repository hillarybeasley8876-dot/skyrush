extends RefCounted
## The parking spot of the title stage: where the Roadster stands while the front end is up.
##
## The spot is derived from the lane data of the world and validated before the car is parked
## there: it must keep its distance from every lane centreline, stand on the ground, be clear of
## the props (a lamp, a tree, a wall), be in the open and be visible from the camera of every
## beat. The buildings have no collider, so they are found by their meshes and tested as boxes
## (`title_buildings.gd`).
##
## The world is built over several seconds, so the search only runs once `Game.world_ready()`
## has come back — before that there are no lanes and the car would stand in the traffic.

const TitleBuildings := preload("res://ui/menu/widgets/title_buildings.gd")

## The reference point of the search: the outer lane of the Bund road at z −300.
const SPOT_REFERENCE := Vector3(-132.0, 0.0, -300.0)
## The distance the car keeps from every lane centreline (the review asks for 3.75 m).
const MIN_CLEARANCE := 3.75
## How far the search looks from the reference point.
const SEARCH_STEP := 0.5
const SEARCH_RANGE := 42.0
## The step along the street (the Bund is a long strip: a spot 40 m further down may be open).
const Z_STEP := 8.0
## The lanes of the neighbourhood (around the reference point).
const NEARBY_RADIUS := 40.0
## The band of the lanes that matters for one row of the search.
const LANE_BAND := 26.0
## The room the car needs from the buildings (it may not stand in a narrow gap).
const BUILDING_ROOM := 3.0
## Two rooms that are this close are a tie (the closer spot wins).
const ROOM_TIE := 0.5
## The ground under the car has to be at this height.
const GROUND_TOLERANCE := 0.3
## The car must stand in the open: nothing may stand within this radius of it.
const OPEN_RADIUS := 6.0
## The height the rays that look for the open space around the car are cast at.
const OPEN_HEIGHT := 1.4
## The spot has to stand in the open: nothing may be above the car up to this height.
const SKY_HEIGHT := 60.0
## The height the camera aims at (the roof of the car).
const CAR_HEIGHT := 1.2
## The half width and the half length of the car.
const CAR_HALF_WIDTH := 1.0
const CAR_HALF_LENGTH := 2.2
## The directions of the rays that look for the props around the spot.
const RAY_DIRECTIONS: Array[Vector3] = [
	Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
	Vector3(0.7071, 0, 0.7071), Vector3(-0.7071, 0, 0.7071),
	Vector3(0.7071, 0, -0.7071), Vector3(-0.7071, 0, -0.7071),
]
## The collision layer of the world (the ground, the lamps, the trees, the walls).
const WORLD_LAYER := 1

## The spot that was found (zero when there is none).
var spot: Vector3 = Vector3.ZERO
## The distance the spot keeps from the nearest lane centreline.
var clearance: float = 0.0
## The boxes of the buildings of the world (the car may not stand inside one).
var buildings: Array[AABB] = []
## The node the search runs in (it needs the world and the physics space).
var node: Node3D = null
## The camera offsets of the beats (the spot has to be visible from them).
var camera_offsets: Array[Vector3] = []


## Searches the spot. Returns true when a spot was found.
func search() -> bool:
	spot = Vector3.ZERO
	clearance = 0.0
	if node == null:
		return false
	var lanes := _nearby_lane_points()
	if lanes.is_empty():
		print("[menu] title stage: the world has no lanes yet, the car is not parked")
		return false
	var axis := _road_axis(lanes)
	if axis.length_squared() < 0.01:
		return false
	var lateral := Vector3(-axis.z, 0.0, axis.x).normalized()
	buildings = _building_boxes()
	var started := Time.get_ticks_msec()
	var found := _search_spot(lanes, lateral)
	spot = found
	var ok := found != Vector3.ZERO
	if ok:
		print("[menu] title stage: spot=%.1f, %.1f, %.1f clearance=%.2f m (searched in %d ms)" % [
			spot.x, spot.y, spot.z, clearance, Time.get_ticks_msec() - started])
	return ok


## The search for the spot: outward in half metre steps on both sides of the road, up to
## SEARCH_RANGE, and along the street in Z_STEP steps.
##
## The candidate with the most room from the traffic wins (the promenade), as long as it stands
## on the ground, in the open, and the camera of every beat can see it.
func _search_spot(lanes: PackedVector3Array, lateral: Vector3) -> Vector3:
	var base := Vector3(SPOT_REFERENCE.x, 0.0, SPOT_REFERENCE.z)
	var steps := int(SEARCH_RANGE / SEARCH_STEP)
	var z_steps := int(SEARCH_RANGE / Z_STEP)
	var fallback := Vector3.ZERO
	var fallback_clearance := -1.0
	var best := Vector3.ZERO
	var best_room := -1.0
	var best_distance := INF
	# The best candidate that the camera of the first beat can see.
	var seen := Vector3.ZERO
	var seen_room := -1.0
	var seen_distance := INF
	# The rows of the search: the reference row first, then the ones further down the street.
	for row_index in range(0, z_steps * 2 + 1):
		var z_step := 0
		if row_index > 0:
			z_step = (row_index + 1) / 2
			if row_index % 2 == 0:
				z_step = -z_step
		var row := base + Vector3(0.0, 0.0, float(z_step) * Z_STEP)
		# The lanes of this row only (the ones further away do not matter).
		var near := _lanes_near(lanes, row.z)
		for step in range(1, steps + 1):
			for side: float in [-1.0, 1.0]:
				var candidate := row + lateral * (float(step) * SEARCH_STEP) * side
				candidate.y = 0.0
				var room := _lane_clearance(candidate, near)
				if room > fallback_clearance:
					fallback_clearance = room
					fallback = candidate
				if room < MIN_CLEARANCE:
					continue
				if _inside_a_building(candidate):
					continue
				if _distance_to_buildings(candidate) < BUILDING_ROOM:
					continue
				if not _check_spot(candidate):
					continue
				# The most open candidate wins: the car must not stand in a narrow gap
				# between two blocks, and it stands as close to the street as it can.
				var distance := candidate.distance_to(base)
				if _is_better(room, distance, best_room, best_distance):
					best = candidate
					best_room = room
					best_distance = distance
				if _visible_from_beats(candidate, 1):
					if _is_better(room, distance, seen_room, seen_distance):
						seen = candidate
						seen_room = room
						seen_distance = distance
		var chosen := seen if seen != Vector3.ZERO else best
		if chosen != Vector3.ZERO:
			clearance = _lane_clearance(chosen, _lanes_near(lanes, chosen.z))
			return chosen
	# Nothing qualified: the spot with the best clearance is used and reported.
	clearance = maxf(fallback_clearance, 0.0)
	print("[menu] title stage: no spot qualifies, using the best clearance %.2f m" % clearance)
	return fallback


## True when a candidate has more room from the buildings (or the same room and it is closer
## to the reference).
func _is_better(room: float, distance: float, best_room: float, best_distance: float) -> bool:
	if room > best_room + ROOM_TIE:
		return true
	if room < best_room - ROOM_TIE:
		return false
	return distance < best_distance


## The distance from a point to the buildings (zero when the point is inside one).
func _distance_to_buildings(point: Vector3) -> float:
	return TitleBuildings.distance_to(point, buildings)


## True when the camera of every beat can see the car (a wall between them is no use).
##
## The buildings have no collider, so the check uses their boxes: a ray would pass right
## through them. The props (a lamp, a tree) do have one, so they are found by a ray.
func _visible_from_beats(candidate: Vector3, beats: int = -1) -> bool:
	var count := camera_offsets.size() if beats < 0 else mini(beats, camera_offsets.size())
	for index in count:
		var from := candidate + camera_offsets[index]
		if _inside_a_building(from):
			return false
		# The whole car has to be clear: a lamp post in front of it is no use.
		for to: Vector3 in _car_points(candidate):
			if _crosses_a_building(from, to):
				return false
	return _clear_of_props(candidate, beats)


## True when no prop (a lamp, a tree) stands between the camera and the car.
func _clear_of_props(candidate: Vector3, beats: int) -> bool:
	var space := _space()
	if space == null:
		return true
	var count := camera_offsets.size() if beats < 0 else mini(beats, camera_offsets.size())
	for index in count:
		var from := candidate + camera_offsets[index]
		for to: Vector3 in _car_points(candidate):
			var query := PhysicsRayQueryParameters3D.create(from, to)
			query.collision_mask = WORLD_LAYER
			if not space.intersect_ray(query).is_empty():
				return false
	return true


## The points of the car that the camera has to see (its corners and its middle).
func _car_points(candidate: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	# A fan over the car: a lamp post in front of it is found by one of the rays.
	for height: float in [0.25, 0.7, 1.2, 1.5]:
		out.append(candidate + Vector3(0.0, height, 0.0))
		out.append(candidate + Vector3(-CAR_HALF_WIDTH, height, -CAR_HALF_LENGTH))
		out.append(candidate + Vector3(CAR_HALF_WIDTH, height, -CAR_HALF_LENGTH))
		out.append(candidate + Vector3(-CAR_HALF_WIDTH, height, CAR_HALF_LENGTH))
		out.append(candidate + Vector3(CAR_HALF_WIDTH, height, CAR_HALF_LENGTH))
	return out


## The boxes of the buildings of the world.
##
## The city builds its blocks as meshes (a prism per lot, or the block assets of the city unit),
## so the buildings are found by their size: a mass that is taller than four metres and wider
## than eight. A lamp, a tree or a sign is too small.
func _building_boxes() -> Array[AABB]:
	var out := TitleBuildings.boxes_of(Game.world)
	print("[menu] title stage: %d buildings around the title spot" % out.size())
	return out


## True when a point stands inside one of the buildings.
func _inside_a_building(point: Vector3) -> bool:
	return TitleBuildings.inside(point, buildings)


## True when the segment from one point to another crosses one of the buildings.
func _crosses_a_building(from: Vector3, to: Vector3) -> bool:
	return TitleBuildings.crosses(from, to, buildings)


## The points of the lane centrelines of the neighbourhood (the elevated lanes are ignored).
func _nearby_lane_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	var world := Game.world
	if world == null:
		return out
	for lane: LanePath in world.get_lane_paths():
		if lane.elevated or lane.curve == null:
			continue
		for point: Vector3 in lane.curve.get_baked_points():
			if Vector2(point.x - SPOT_REFERENCE.x, point.z - SPOT_REFERENCE.z).length() \
					<= NEARBY_RADIUS:
				out.append(point)
	return out


## The lane points of the rows around a height (the ones further away do not matter).
func _lanes_near(lanes: PackedVector3Array, height: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point: Vector3 in lanes:
		if absf(point.z - height) <= LANE_BAND:
			out.append(point)
	return out


## The distance from a point to the nearest lane centreline.
func _lane_clearance(point: Vector3, lanes: PackedVector3Array) -> float:
	var best := INF
	for lane_point: Vector3 in lanes:
		var distance := Vector2(lane_point.x - point.x, lane_point.z - point.z).length()
		if distance < best:
			best = distance
	return best


## The direction of the road at the reference point: from the closest lane point towards the
## next one that is a few metres away.
func _road_axis(lanes: PackedVector3Array) -> Vector3:
	var closest := Vector3.ZERO
	var best_distance := INF
	for lane_point: Vector3 in lanes:
		var distance := absf(lane_point.z - SPOT_REFERENCE.z)
		if distance < best_distance:
			best_distance = distance
			closest = lane_point
	var next := Vector3.ZERO
	best_distance = INF
	for lane_point: Vector3 in lanes:
		var distance := closest.distance_to(lane_point)
		if distance > 4.0 and distance < best_distance:
			best_distance = distance
			next = lane_point
	var axis := next - closest
	axis.y = 0.0
	return axis.normalized()


## True when there is ground under the point and no static body stands in the way.
func _check_spot(point: Vector3) -> bool:
	var space := _space()
	if space == null:
		return true
	# The ground under the car.
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 20.0,
			point - Vector3.UP * 5.0)
	ray.collision_mask = WORLD_LAYER
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return false
	var position := hit["position"] as Vector3
	if absf(position.y - point.y) > GROUND_TOLERANCE:
		return false
	var exclude: Array[RID] = []
	var collider := hit.get("collider") as Object
	if collider is CollisionObject3D:
		exclude.append((collider as CollisionObject3D).get_rid())
	var player := Game.player
	if player != null:
		exclude.append(player.get_rid())
	# The spot must stand in the open: a car under a roof or inside a block is no use.
	var sky := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0,
			point + Vector3.UP * SKY_HEIGHT)
	sky.collision_mask = WORLD_LAYER
	sky.exclude = exclude
	if not space.intersect_ray(sky).is_empty():
		return false
	# ... and it must have room around it: the camera has to see the car.
	for direction: Vector3 in RAY_DIRECTIONS:
		var from := point + Vector3.UP * OPEN_HEIGHT + direction * 0.3
		var to := from + direction * OPEN_RADIUS
		var open_ray := PhysicsRayQueryParameters3D.create(from, to)
		open_ray.collision_mask = WORLD_LAYER
		open_ray.exclude = exclude
		if not space.intersect_ray(open_ray).is_empty():
			return false
	return true




## The physics space of the world (null when there is none).
func _space() -> PhysicsDirectSpaceState3D:
	if node == null or not node.is_inside_tree():
		return null
	var world := node.get_world_3d()
	if world == null:
		return null
	return world.direct_space_state
