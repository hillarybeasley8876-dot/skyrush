extends RefCounted
const LaneSpatial := preload("res://world/api/lane_spatial.gd")
const LaneGraphBuilder := preload("res://world/api/lane_graph.gd")
## Links the lanes into a drivable graph. Priority: the explicit `next` lists in the roads
## unit's lanes.json; otherwise links are derived from the city.json junctions (roads that meet)
## and from lanes whose ends come close to another road.

const JUNCTION_RADIUS := 45.0
const PROXIMITY := 30.0
## How close a lane has to be to a junction to take part in a turn.
const TURN_RADIUS := 30.0
## The biggest turn a connector may make (no U-turns).
const MAX_TURN := 135.0


## The index of every lane id (the lookup of a declared link used to scan the whole list).
var _index_of: Dictionary = {}


## The links already set on the lanes (the straight continuation inside a road) are kept; the
## declared links of the roads unit and the junction links are added on top of them.
func link(lanes: Array[LanePath], graph: LaneGraphBuilder, junctions: Array, grid: LaneSpatial = null) -> void:
	_index_of.clear()
	for i in graph.ids.size():
		_index_of[graph.ids[i]] = i
	_link_declared(lanes, graph)
	_link_junctions(lanes, graph, junctions, grid)
	_link_turns(lanes, graph, junctions, grid)
	_link_proximity(lanes, grid)


## The turn connectors of every junction of the city description: from every lane that ends
## at the junction to every lane of another road that starts there. The roads unit's lanes.json
## has no links for some of the turns (the turn of the Bund into the Nanjing Rd), and without
## them the racing line can only be driven backwards.
func _link_turns(lanes: Array[LanePath], graph: LaneGraphBuilder, junctions: Array,
		grid: LaneSpatial) -> void:
	for junction in junctions:
		if not junction is Dictionary:
			continue
		var data := junction as Dictionary
		var point := Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("z", 0.0)))
		var road_ids: Array = data.get("roads", [])
		var incoming: Array[Dictionary] = []
		var outgoing: Array[Dictionary] = []
		for road_id in road_ids:
			for index in _lanes_of_road(graph, String(road_id)):
				if index < 0 or index >= lanes.size():
					continue
				var lane := lanes[index]
				if lane.curve == null:
					continue
				var end_point := lane.curve.get_point_position(lane.curve.get_point_count() - 1)
				if Vector2(end_point.x - point.x, end_point.z - point.z).length() <= TURN_RADIUS:
					incoming.append({"index": index, "road": String(road_id),
						"point": end_point, "heading": _heading_at(lane, 1.0)})
				var start_point := lane.curve.get_point_position(0)
				if Vector2(start_point.x - point.x, start_point.z - point.z).length() <= TURN_RADIUS:
					outgoing.append({"index": index, "road": String(road_id),
						"point": start_point, "heading": _heading_at(lane, 0.0)})
		for a in incoming:
			for b in outgoing:
				if a["index"] == b["index"]:
					continue
				if a["road"] == b["road"]:
					continue
				var turn: float = _angle_between(a["heading"], b["heading"])
				if turn > MAX_TURN:
					continue  # a U-turn is not a turn
				_add(lanes[int(a["index"])], int(b["index"]))


## The direction of a lane at its start (0.0) or at its end (1.0).
static func _heading_at(lane: LanePath, at: float) -> Vector3:
	if lane.curve == null:
		return Vector3.FORWARD
	var length := lane.curve.get_baked_length()
	if length < 0.1:
		return Vector3.FORWARD
	var offset := length * at
	var ahead := lane.curve.sample_baked(minf(offset + 3.0, length), true)
	var behind := lane.curve.sample_baked(maxf(offset - 3.0, 0.0), true)
	var heading := ahead - behind
	heading.y = 0.0
	if heading.length_squared() < 0.0001:
		return Vector3.FORWARD
	return heading.normalized()


## The angle between two directions, in degrees (0 to 180).
static func _angle_between(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


func _link_declared(lanes: Array[LanePath], graph: LaneGraphBuilder) -> bool:
	var found := false
	for id in graph.declared_next.keys():
		var next_ids: Array = graph.declared_next[id]
		if next_ids.is_empty():
			continue
		found = true
		var index := _index_of_id(graph, String(id))
		if index < 0:
			continue
		for other in next_ids:
			var other_index := _index_of_id(graph, String(other))
			if other_index >= 0:
				_add(lanes[index], other_index)
	return found


func _link_junctions(lanes: Array[LanePath], graph: LaneGraphBuilder, junctions: Array, grid: LaneSpatial) -> void:
	for junction in junctions:
		if not junction is Dictionary:
			continue
		var jd := junction as Dictionary
		var point := Vector3(float(jd.get("x", 0.0)), 0.0, float(jd.get("z", 0.0)))
		var road_ids: Array = jd.get("roads", [])
		var near: Array[Dictionary] = []
		var around: Dictionary = grid.query(point, JUNCTION_RADIUS) if grid != null else {}
		for road_id in road_ids:
			for index in _lanes_of_road(graph, String(road_id)):
				if grid != null:
					if not around.has(index):
						continue
				elif _distance_to(lanes[index], point) > JUNCTION_RADIUS:
					continue
				near.append({"index": index, "state": _junction_state(lanes[index], point)})
		for a in near:
			# Only a lane that drives into the junction can turn into another road.
			if String(a["state"]) != "incoming":
				continue
			for b in near:
				if a["index"] == b["index"]:
					continue
				if _same_road(lanes, int(a["index"]), int(b["index"])):
					continue
				var state := String(b["state"])
				if state != "outgoing" and state != "through":
					continue
				_add(lanes[int(a["index"])], int(b["index"]))


## Where the junction sits on the lane: "incoming" (the lane drives into it), "outgoing" (the
## lane starts there) or "through" (the lane passes it in the middle).
static func _junction_state(lane: LanePath, point: Vector3) -> String:
	if lane.curve == null:
		return "none"
	var length := lane.curve.get_baked_length()
	if length < 1.0:
		return "none"
	var offset := lane.curve.get_closest_offset(point)
	var t := offset / length
	if t < 0.4:
		return "outgoing"
	if t > 0.6:
		return "incoming"
	return "through"


## Lanes that end next to the end of another lane are linked, so a route can turn where the
## roads meet even when the junction is not in the city description.
func _link_proximity(lanes: Array[LanePath], grid: LaneSpatial) -> void:
	if grid == null:
		return
	for i in lanes.size():
		var lane := lanes[i]
		if lane.curve == null:
			continue
		var end_point := lane.curve.get_point_position(lane.curve.get_point_count() - 1)
		for other in grid.query(end_point, PROXIMITY).keys():
			if other == i:
				continue
			if _same_road(lanes, i, other):
				continue
			if lanes[i].next_lanes.has(other):
				continue
			_add(lane, other)


# --- helpers ---------------------------------------------------------------------------------------

static func _add(lane: LanePath, index: int) -> void:
	if not lane.next_lanes.has(index):
		lane.next_lanes.append(index)


static func _same_road(lanes: Array[LanePath], a: int, b: int) -> bool:
	return lanes[a].road_id == lanes[b].road_id


static func _lanes_of_road(graph: LaneGraphBuilder, road_id: String) -> Array:
	var list: Array = graph.by_road.get(road_id, [])
	return list


func _index_of_id(graph: LaneGraphBuilder, id: String) -> int:
	return int(_index_of.get(id, -1))


## Distance from a point to the closest point on a lane curve.
static func _distance_to(lane: LanePath, point: Vector3) -> float:
	if lane.curve == null:
		return INF
	var offset := lane.curve.get_closest_offset(point)
	var closest := lane.curve.sample_baked(offset, true)
	return closest.distance_to(point)


