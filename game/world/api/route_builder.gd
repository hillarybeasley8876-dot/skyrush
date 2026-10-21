extends RefCounted
## Builds the RaceRoute resources (checkpoints, start grid, racing line) from the city.json
## route descriptions. The racing line is the shortest lane path through the lane graph between
## the checkpoints, so the rival AI drives on real lanes and the line never reverses.
##
## A leg whose gates are not on the lane network falls back to a smooth line through its two
## gates; the other legs of the route keep their lane path.

const Spline := preload("res://world/api/spline_util.gd")
const Heading := preload("res://world/api/heading.gd")
const LanePathFinder := preload("res://world/api/lane_path_finder.gd")
const StartGrid := preload("res://world/api/start_grid.gd")
const LaneSpatial := preload("res://world/api/lane_spatial.gd")

## The points of a lane slice are this far apart. The line is a smooth curve, so the points
## have to be close: at a junction the curve cuts the corner, and a cut of more than two metres
## would put the line off the lane.
const SLICE_STEP := 2.0
## The width of a gate.
const GATE_WIDTH := 24.0
## True when the last leg had to look for its lanes further away than GATE_RADIUS.
var _relaxed := false
## True when the last leg could only be driven against the traffic.
var _backwards := false
## True when the last leg could not reach its target on the lanes at all.
var _partial := false
## The legs of the last route that run against the traffic.
var _backwards_legs: Array[int] = []
## How far the lanes of a gate are looked for.
const GATE_RADIUS := 8.0
## The radius that is used when the gates of a leg are not on the lanes (the data of the city
## is then wrong; the leg is reported).
const GATE_RADIUS_FALLBACK := 30.0


func build(routes: Array, lanes: Array[LanePath], grid: LaneSpatial = null) -> Dictionary:
	var out: Dictionary = {}
	for route in routes:
		if route is Dictionary:
			var built := _build_route(route as Dictionary, lanes, grid)
			out[String(built.id)] = built
	return out


func _build_route(spec: Dictionary, lanes: Array[LanePath], grid: LaneSpatial) -> RaceRoute:
	var route := RaceRoute.new()
	route.id = StringName(str(spec.get("id", "route")))
	route.title = str(spec.get("title", ""))
	route.laps = int(spec.get("laps", 1))
	route.checkpoints = _checkpoints(spec.get("checkpoints", []))
	route.set_meta("circuit", _is_circuit(spec))
	_face_the_route(route.checkpoints)
	route.grid = StartGrid.build(lanes, grid, spec.get("grid", []), route.checkpoints)
	route.racing_line = _racing_line(route.checkpoints, lanes, spec, grid)
	route.set_meta("backwards_legs", _backwards_legs)
	if route.checkpoints.size() > 0:
		route.gate_width = GATE_WIDTH
	return route


func _checkpoints(raw: Variant) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 3:
			out.append(_transform(entry as Array))
	return out


## The lane that comes before every lane (the slots of the grid walk back along the road).
func _previous_lanes(lanes: Array[LanePath]) -> Dictionary:
	var out: Dictionary = {}
	for i in lanes.size():
		for next_index in lanes[i].next_lanes:
			if next_index < 0 or next_index >= lanes.size():
				continue
			if out.has(next_index):
				continue
			if lanes[next_index].road_id != lanes[i].road_id:
				continue
			out[next_index] = i
	return out


func _slot(anchor: Transform3D, offset: Vector3) -> Transform3D:
	return Transform3D(anchor.basis, anchor.origin + offset)


func _transform(entry: Array) -> Transform3D:
	var heading := 0.0
	if entry.size() >= 4:
		heading = Heading.yaw_from_heading(float(entry[3]))
	return Transform3D(Basis(Vector3.UP, heading),
		Vector3(float(entry[0]), float(entry[1]), float(entry[2])))


## The racing line: the shortest lane path from checkpoint to checkpoint.
func _racing_line(checkpoints: Array[Transform3D], lanes: Array[LanePath],
		spec: Dictionary, grid: LaneSpatial) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	curve.set_up_vector_enabled(false)
	if checkpoints.size() < 2 or lanes.is_empty():
		return curve
	var finder := LanePathFinder.new()
	var points := PackedVector3Array()
	var unroutable: Array[int] = []
	var relaxed_legs: Array[int] = []
	var backwards_legs: Array[int] = []
	var partial_legs: Array[int] = []
	for i in range(checkpoints.size() - 1):
		_relaxed = false
		_backwards = false
		_partial = false
		var part := _path_between(lanes, checkpoints[i], checkpoints[i + 1], finder, grid)
		if _relaxed:
			relaxed_legs.append(i)
		if _backwards:
			backwards_legs.append(i)
		if _partial:
			partial_legs.append(i)
		if part.is_empty():
			# The gates of this leg are not on one connected lane path: the leg falls back to a
			# smooth line through its two gates; the other legs keep their lane path.
			unroutable.append(i)
			part = _leg_line(checkpoints[i], checkpoints[i + 1])
		points.append_array(part)
	if _is_circuit(spec) and points.size() > 2:
		var closing := _path_between(lanes, checkpoints[checkpoints.size() - 1], checkpoints[0],
			finder, grid)
		if closing.is_empty():
			unroutable.append(checkpoints.size() - 1)
			closing = _leg_line(checkpoints[checkpoints.size() - 1], checkpoints[0])
		points.append_array(closing)
	if not unroutable.is_empty():
		print("[world] route %s: %d legs are not on the lane network (gates %s)" % [
			str(spec.get("id", "route")), unroutable.size(), str(unroutable)])
	if not relaxed_legs.is_empty():
		print("[world] route %s: the gates of the legs %s are more than %d m from the lanes"
			% [str(spec.get("id", "route")), str(relaxed_legs), GATE_RADIUS])
	if not backwards_legs.is_empty():
		print("[world] route %s: the legs %s have no forward path on the lane network"
			% [str(spec.get("id", "route")), str(backwards_legs)])
	if not partial_legs.is_empty():
		print("[world] route %s: the legs %s cannot reach their gate on the lane network"
			% [str(spec.get("id", "route")), str(partial_legs)])
	_backwards_legs = backwards_legs
	return Spline.make_curve(_unique(points))


## The points of a line without the doubles: two identical control points make the curve
## wiggle at the junction between two lanes.
static func _unique(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in points:
		if not out.is_empty() and out[out.size() - 1].distance_to(point) < 1.0:
			continue
		out.append(point)
	return out


## A smooth line through the two gates of a leg (the fallback).
func _leg_line(from: Transform3D, to: Transform3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.append(from.origin)
	points.append(to.origin)
	return Spline.catmull_rom(points, 8)


## Turns the gates that do not face the next checkpoint towards it: 21 of the 55 gates of
## city.json carry a heading that points away from the route (a request to city_layout).
func _face_the_route(checkpoints: Array[Transform3D]) -> void:
	for i in checkpoints.size():
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


## A circuit is a race with more than one lap.
func _is_circuit(spec: Dictionary) -> bool:
	return str(spec.get("kind", "")) == "race" or int(spec.get("laps", 1)) > 1


## The lane path from one checkpoint to the next, sliced into the points of the line.
func _path_between(lanes: Array[LanePath], from: Transform3D, to: Transform3D,
		finder: LanePathFinder, grid: LaneSpatial) -> PackedVector3Array:
	var out := PackedVector3Array()
	var sources := finder.gate_lanes(lanes, grid, from, GATE_RADIUS)
	var targets := finder.gate_lanes(lanes, grid, to, GATE_RADIUS)
	if sources.is_empty() or targets.is_empty():
		# The gates of this leg are not on the lanes: the lanes are looked for further away.
		sources = finder.gate_lanes(lanes, grid, from, GATE_RADIUS_FALLBACK)
		targets = finder.gate_lanes(lanes, grid, to, GATE_RADIUS_FALLBACK)
		if not sources.is_empty() and not targets.is_empty():
			_relaxed = true
	if sources.is_empty() or targets.is_empty():
		return out
	var sequence := finder.find_multi(lanes, sources, targets)
	var partial := false
	if sequence.is_empty():
		# There is no forward path: the leg is reported, not drawn backwards. A line that
		# drives against the traffic is worse than a line that leaves the lanes.
		_backwards = true
		# The line follows the lanes as far as it can and then drives straight to the gate.
		sequence = finder.find_closest(lanes, sources, to.origin)
		partial = not sequence.is_empty()
		_partial = partial
	if sequence.is_empty():
		return out
	var entries := PackedFloat32Array()
	var exits := PackedFloat32Array()
	var forward := PackedByteArray()
	entries.append(_entry_offset(lanes[sequence[0]], from.origin))
	for k in range(1, sequence.size()):
		var goes_forward := lanes[sequence[k - 1]].next_lanes.has(sequence[k])
		forward.append(1 if goes_forward else 0)
		if goes_forward:
			exits.append(_lane_length(lanes[sequence[k - 1]]))
			entries.append(0.0)
		else:
			# The lane is driven backwards: it is entered at its end.
			exits.append(0.0)
			entries.append(_lane_length(lanes[sequence[k]]))
	exits.append(_exit_offset(lanes[sequence[sequence.size() - 1]], to.origin))
	for k in sequence.size():
		var is_forward := k == 0 or forward[k - 1] == 1
		if is_forward:
			if exits[k] < entries[k] - 0.5:
				if k == 0:
					# The gate lies past the end of the lane: the leg starts on the next lane.
					continue
				return PackedVector3Array()  # the path doubles back: not a usable line
			out.append_array(_slice(lanes[sequence[k]], entries[k], exits[k]))
		else:
			out.append_array(_slice_back(lanes[sequence[k]], entries[k], exits[k]))
	if partial:
		# The target cannot be reached on the lane network: the line leaves the lanes for the
		# last stretch (the leg is reported).
		out.append(to.origin)
	return out


## The offset on the lane where the line enters it.
func _entry_offset(lane: LanePath, point: Vector3) -> float:
	return _nearest_offset(lane, point)


## The offset on the lane where the line leaves it (the gate of the next leg).
func _exit_offset(lane: LanePath, point: Vector3) -> float:
	return _nearest_offset(lane, point)


## The offset of the point of the lane closest to `point`, without a full curve search.
func _nearest_offset(lane: LanePath, point: Vector3) -> float:
	if lane.curve == null:
		return 0.0
	var best := 0.0
	var best_distance := INF
	var length := lane.curve.get_baked_length()
	var steps := maxi(int(length / 8.0), 1)
	for s in steps + 1:
		var offset := length * float(s) / float(steps)
		var sample := lane.curve.sample_baked(offset, true)
		var distance := Vector2(sample.x - point.x, sample.z - point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = offset
	return best


func _lane_length(lane: LanePath) -> float:
	if lane.curve == null:
		return 0.0
	return lane.curve.get_baked_length()


## The points of a lane between two offsets, driven backwards.
func _slice_back(lane: LanePath, from: float, to: float) -> PackedVector3Array:
	var points := _slice(lane, to, from)
	var out := PackedVector3Array()
	for i in range(points.size() - 1, -1, -1):
		out.append(points[i])
	return out


## The points of a lane between two offsets (in the direction of the traffic).
func _slice(lane: LanePath, from: float, to: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if lane.curve == null:
		return out
	var length := lane.curve.get_baked_length()
	if length < 0.01:
		return out
	var start := fposmod(from, length)
	var end := fposmod(to, length)
	var spans: Array[Vector2] = []
	if end >= start:
		spans.append(Vector2(start, end))
	else:
		spans.append(Vector2(start, length))
		spans.append(Vector2(0.0, end))
	for span in spans:
		var steps := maxi(int((span.y - span.x) / SLICE_STEP), 1)
		for s in steps + 1:
			out.append(lane.curve.sample_baked(span.x + (span.y - span.x) * float(s) / float(steps), true))
	return out
