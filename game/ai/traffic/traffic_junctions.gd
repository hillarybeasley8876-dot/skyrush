class_name TrafficJunctions
extends RefCounted
## The traffic light junction of every lane of the world.
##
## The world does not name the junction of a lane yet (the request with the exact signature is
## in status/traffic.md), so the junctions are read from the city data: a junction is a point
## with a list of roads, and it belongs to a lane when the lane ends on one of those roads close
## to the junction. When the world grows a `get_lane_junction(lane)` the world wins.
##
## Only a street has a traffic light. A lane of an elevated deck, of a ramp or of a bridge is
## not slowed down by a light - the light of a junction in the plan view is somewhere else in
## the city, and a red light in the middle of a deck looks broken. So a lane gets a junction
## only when its road is a surface street at ground level and it ends close to a junction that
## really has signals.

const JUNCTION_RADIUS := 20.0   ## m: how far from the end of a lane a signalled junction can be
const MAX_END_HEIGHT := 2.0     ## m: only a street at ground level has a traffic light
const SURFACE_ROAD := "surface" ## the kind of a road that has traffic lights
const CITY_PATH := "../data/city/city.json"
const CITY_KEY := "junctions"

## The number of lanes that end at a junction.
var resolved: int = 0

var _junctions_by_road: Dictionary = {}
var _road_kind: Dictionary = {}


## Works out the junction of every lane. Returns the junction id of each lane ("" when the lane
## does not end at a junction).
func resolve(world: WorldBase, graph: LaneGraph) -> PackedStringArray:
	var out := PackedStringArray()
	resolved = 0
	_load_city()
	var from_world := _world_junctions(world, graph)
	for i in graph.lane_count():
		var id := from_world[i] if i < from_world.size() else ""
		if id == "":
			id = _junction_of_lane(graph, i)
		out.append(id)
		if id != "":
			resolved += 1
	return out


## The junctions the world itself names (empty when the world cannot be asked).
func _world_junctions(world: WorldBase, graph: LaneGraph) -> PackedStringArray:
	var out := PackedStringArray()
	if world == null or not world.has_method(&"get_lane_junction"):
		return out
	for i in graph.lane_count():
		out.append(String(world.call(&"get_lane_junction", i)))
	return out


## The junction of a lane: the closest signalled junction of the road the lane is on.
##
## A lane of a ramp or of a deck has no traffic light, and a lane that ends in the air (the
## ramps of the elevated roads) has none either.
func _junction_of_lane(graph: LaneGraph, lane: int) -> String:
	if lane < 0 or lane >= graph.lanes.size():
		return ""
	var path := graph.lanes[lane]
	if path == null or path.elevated:
		return ""
	var road_id := String(path.road_id)
	if String(_road_kind.get(road_id, "")) != SURFACE_ROAD:
		return ""
	var end := graph.position_at(lane, graph.lane_length(lane))
	if end.y > MAX_END_HEIGHT:
		return ""
	var best := ""
	var best_d := JUNCTION_RADIUS
	for entry in _junctions_by_road.get(road_id, []) as Array:
		if not bool((entry as Dictionary).get("signals", false)):
			continue
		var point := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
		var d := Vector2(point.x - end.x, point.z - end.z).length()
		if d < best_d:
			best_d = d
			best = String(entry["id"])
	return best


## Reads the junctions and the roads of the city data and groups the junctions by road.
func _load_city() -> void:
	_junctions_by_road.clear()
	_road_kind.clear()
	var path := ProjectSettings.globalize_path("res://") + CITY_PATH
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		return
	var city := data as Dictionary
	for road in city.get("roads", []) as Array:
		if not (road is Dictionary):
			continue
		var entry := road as Dictionary
		_road_kind[String(entry.get("id", ""))] = String(entry.get("kind", ""))
	var junctions: Variant = city.get(CITY_KEY, [])
	if not (junctions is Array):
		return
	for entry in junctions as Array:
		if not (entry is Dictionary):
			continue
		var junction := entry as Dictionary
		for road in junction.get("roads", []) as Array:
			var key := String(road)
			if not _junctions_by_road.has(key):
				_junctions_by_road[key] = [] as Array
			(_junctions_by_road[key] as Array).append(junction)
