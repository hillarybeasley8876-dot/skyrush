extends RefCounted
## Works out the continuations of every lane of a lane graph.
##
## The helper is preloaded by LaneGraph, it has no class_name of its own.
##
## The world may name the next lanes of a lane, but the named link is only kept when the two
## lanes actually meet: the entry point on the next lane has to be close to the end of the lane
## (at most 20 m), on the same level (at most 1 m of height difference) and the car must not have
## to turn back on itself (at most 100 degrees). A link that does not fit is dropped and counted,
## so the world can be told about it.
##
## Every link that is kept also gets a connector curve: the car drives it through the junction
## box, from the end of its lane to the entry of the next one, so it turns instead of jumping.

var _graph: LaneGraph = null


## Fills the `next_lanes`, `next_entry`, `straight_next` and `turn_next` arrays of the graph.
func build(graph: LaneGraph) -> void:
	_graph = graph
	_build_all()


func _build_all() -> void:
	var n := _graph.lane_count()
	for i in n:
		var targets := PackedInt32Array()
		var entries := PackedFloat32Array()
		var lengths := PackedFloat32Array()
		for j: int in _graph.lanes[i].next_lanes:
			if j < 0 or j >= n or j == i:
				continue
			# The world builds some roads twice: the traffic drives on the first copy only, so
			# two cars never share the same piece of road.
			if _graph.is_duplicate(j):
				j = _graph.duplicate_of[j]
				if j == i or targets.has(j):
					continue
			var entry := _link_entry(i, j)
			if entry < 0.0:
				_graph.dropped_links += 1
				continue
			var curve := _make_connector(i, j, entry)
			targets.append(j)
			entries.append(entry)
			lengths.append(curve.get_baked_length() if curve != null else 0.0)
			_graph._connectors[LaneGraph.link_key(i, j)] = curve
		if targets.is_empty() and _graph.is_loop[i] == 1:
			targets.append(i)
			entries.append(0.0)
			lengths.append(0.0)
			_graph._connectors[LaneGraph.link_key(i, i)] = _make_connector(i, i, 0.0)
		_graph.next_lanes[i] = targets
		_graph.next_entry[i] = entries
		_graph.next_connector[i] = lengths
		_graph.straight_next.append(_straight_of(i, targets))
		_graph.turn_next.append(_turns_of(i, targets))


## The continuation of the lane that goes straight on: the one with the same heading and the
## smallest lateral offset. -1 when the lane has no straight continuation.
func _straight_of(lane: int, targets: PackedInt32Array) -> int:
	if targets.is_empty():
		return -1
	var end_p := _graph.position_at(lane, _graph.lane_length(lane))
	var right_v := _graph.right_at(lane, _graph.lane_length(lane))
	var best := -1
	var best_off := INF
	for j: int in targets:
		if _graph.tangent_at(lane, _graph.lane_length(lane)).angle_to(_graph.tangent_at(j, 0.0)) \
				> LaneGraph.STRAIGHT_ANGLE:
			continue
		var off := absf((_graph.position_at(j, 0.0) - end_p).dot(right_v))
		if off < best_off:
			best_off = off
			best = j
	if best >= 0:
		return best
	# No straight on: the first continuation is as good as any.
	return targets[0]


## The continuations of the lane that turn (a sharp change of heading).
func _turns_of(lane: int, targets: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	if targets.is_empty():
		return out
	var end_t := _graph.tangent_at(lane, _graph.lane_length(lane))
	for j: int in targets:
		if end_t.angle_to(_graph.tangent_at(j, 0.0)) > LaneGraph.STRAIGHT_ANGLE:
			out.append(j)
	return out


## The point on the lane `to` where a car coming from the lane `from` enters it, or -1 when the
## two lanes do not meet.
func _link_entry(from: int, to: int) -> float:
	var end_p := _graph.position_at(from, _graph.lane_length(from))
	var entry := _graph.closest_offset_near(to, end_p, 0.0, 60.0)
	var entry_p := _graph.position_at(to, entry)
	var horizontal := Vector2(entry_p.x - end_p.x, entry_p.z - end_p.z).length()
	if horizontal > LaneGraph.LINK_MAX_DISTANCE:
		return -1.0
	if absf(entry_p.y - end_p.y) > LaneGraph.LINK_MAX_LEVEL:
		return -1.0
	var end_t := _graph.tangent_at(from, _graph.lane_length(from))
	var entry_t := _graph.tangent_at(to, entry)
	if end_t.angle_to(entry_t) > LaneGraph.LINK_MAX_ANGLE:
		return -1.0
	return entry


## The curve that leads from the end of the lane `from` to the entry of the lane `to`: a cubic
## Hermite that leaves the first lane along its tangent and enters the next one along its own.
func _make_connector(from: int, to: int, entry: float) -> Curve3D:
	var start := _graph.position_at(from, _graph.lane_length(from))
	var end := _graph.position_at(to, entry)
	var distance := start.distance_to(end)
	if distance < LaneGraph.CONNECTOR_MIN_LENGTH:
		# The two lanes meet: there is nothing to turn through.
		return null
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	curve.add_point(start)
	curve.add_point(end)
	var start_t := _graph.tangent_at(from, _graph.lane_length(from))
	var end_t := _graph.tangent_at(to, entry)
	var handle := maxf(distance, 1.0)
	curve.set_point_out(0, start_t * handle)
	curve.set_point_in(1, -end_t * handle)
	return curve
