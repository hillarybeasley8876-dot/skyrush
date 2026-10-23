extends RefCounted
## The gates of a route: which way they face.
##
## A gate of a route is driven through, so it has to face the way the route goes: along the
## racing line, and not back at the way to the next gate. The headings of city.json are the
## headings of the lanes, so a gate that lies on a lane of its own level keeps its heading: a
## hairpin (the Pudong loop turns the road by 180 degrees between two gates) must not turn a
## gate around.

const LaneSpatial := preload("res://world/api/lane_spatial.gd")
const LevelRules := preload("res://world/api/level_rules.gd")

## How far the lanes of a gate are looked for.
const GATE_RADIUS := 8.0
## A gate that lies on a lane of its own level keeps its heading when the lane runs within this
## angle of it.
const GATE_ALIGN := 0.819  # cos(35 degrees)
## The line points (about 2 m apart) in which the next gate is looked for.
const GATE_WINDOW := 1500
## A gate the line does not come within this many metres of is not on the line.
const GATE_MISS := 40.0
## A gate that faces further back than this along the way to the next gate is turned towards it.
const GATE_BACK := -0.9


## Turns the gates that do not face the next checkpoint towards it: 21 of the 55 gates of
## city.json carry a heading that points away from the route. A gate that lies on a lane of its
## own level keeps its heading.
static func face_the_route(checkpoints: Array[Transform3D], lanes: Array[LanePath],
		grid: LaneSpatial) -> void:
	for i in checkpoints.size():
		if on_a_lane(checkpoints[i], lanes, grid):
			continue
		var next := i + 1
		if next >= checkpoints.size():
			if checkpoints.size() < 2:
				continue
			next = 0
		var forward := -checkpoints[i].basis.z
		var to_next := checkpoints[next].origin - checkpoints[i].origin
		if forward.dot(to_next) > 0.0:
			continue
		var basis := Basis.looking_at(to_next, Vector3.UP)
		checkpoints[i] = Transform3D(basis, checkpoints[i].origin)


## True when a lane of the level of the gate runs within GATE_RADIUS of it in the direction of
## the gate: such a gate faces along the road and keeps its heading.
static func on_a_lane(gate: Transform3D, lanes: Array[LanePath], grid: LaneSpatial) -> bool:
	if grid == null:
		return false
	var forward := -gate.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return false
	var near: Dictionary = grid.query(gate.origin, GATE_RADIUS, gate.origin.y, LevelRules.LEVEL)
	for index in near.keys():
		var lane := lanes[int(index)]
		if lane == null or lane.curve == null:
			continue
		var closest := lane.curve.sample_baked(lane.curve.get_closest_offset(gate.origin), true)
		if absf(closest.y - gate.origin.y) > LevelRules.LEVEL:
			continue  # the lane is on another level here
		var tangent := _tangent_at(lane, gate.origin)
		if tangent.length_squared() < 0.0001:
			continue
		if tangent.normalized().dot(forward.normalized()) >= GATE_ALIGN:
			return true
	return false


## The direction of a lane at the point of the lane that is closest to the point.
static func _tangent_at(lane: LanePath, point: Vector3) -> Vector3:
	var offset := lane.curve.get_closest_offset(point)
	var closest := lane.curve.sample_baked(offset, true)
	var ahead := lane.curve.sample_baked(
		minf(offset + 4.0, lane.curve.get_baked_length()), true)
	var tangent := ahead - closest
	tangent.y = 0.0
	return tangent


## Turns the gates that do not face along the racing line towards it: the line cuts the corner
## of a sharp turn, so a gate that keeps the heading of the lane there would face across the
## line.
static func face_the_line(checkpoints: Array[Transform3D], line: Curve3D) -> void:
	if line == null or line.get_point_count() < 2:
		return
	var points := line.get_baked_points()
	if points.size() < 8:
		return
	var cursor := 0
	for i in checkpoints.size():
		# The gate is looked for in the part of the line that follows the previous gate.
		var best := INF
		var at := -1
		for p in range(cursor, mini(points.size(), cursor + GATE_WINDOW)):
			var distance := points[p].distance_to(checkpoints[i].origin)
			if distance < best:
				best = distance
				at = p
		if at < 0 or best > GATE_MISS:
			continue
		cursor = at
		var before := points[at] - points[maxi(at - 3, 0)]
		var after := points[mini(at + 3, points.size() - 1)] - points[at]
		var tangent := points[mini(at + 3, points.size() - 1)] - points[maxi(at - 3, 0)]
		# The line doubles back at the gate (the route turns round there): the chord across the
		# gate is then short and says nothing, so the gate faces the way the route leaves it.
		if tangent.length() < 0.5 * (before.length() + after.length()):
			tangent = after
		tangent.y = 0.0
		if tangent.length_squared() < 0.01:
			continue
		tangent = tangent.normalized()
		var forward := -checkpoints[i].basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.01:
			continue
		if forward.normalized().dot(tangent) >= GATE_ALIGN:
			continue
		checkpoints[i] = Transform3D(Basis.looking_at(tangent, Vector3.UP), checkpoints[i].origin)


## Turns the gates that would face back along the way to the next gate towards it. The route
## turns round at such a gate (the gate at the end of the straight road of the test city), and a
## gate that faces back at the route is a trap for the driver.
static func face_ahead(checkpoints: Array[Transform3D]) -> void:
	for i in checkpoints.size() - 1:
		var forward := -checkpoints[i].basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			continue
		var to_next := checkpoints[i + 1].origin - checkpoints[i].origin
		if to_next.length_squared() < 0.01:
			continue
		if forward.normalized().dot(to_next.normalized()) > GATE_BACK:
			continue
		var basis := Basis.looking_at(to_next, Vector3.UP)
		checkpoints[i] = Transform3D(basis, checkpoints[i].origin)
