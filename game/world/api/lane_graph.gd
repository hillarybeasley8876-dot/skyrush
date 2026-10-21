extends RefCounted
## Builds the drivable lane graph (LanePath resources) that the traffic, police and rival AI
## drive on. Uses the roads unit's lanes.json when it exists; otherwise the lanes are derived
## from the city.json road descriptions (same lane widths, offsets and directions).

const Spline := preload("res://world/api/spline_util.gd")

## The bake interval of the lanes of the city (metres).
const LANE_BAKE := 4.0

var ids: PackedStringArray = PackedStringArray()
var declared_next: Dictionary = {}  # lane id -> Array[String] of next lane ids
var by_road: Dictionary = {}  # road id -> Array[int] lane indices
var _covered: Dictionary = {}  # road id -> true when lanes.json already provides its lanes


## The lanes of the roads unit are used for the roads they cover; every other road of the city
## gets its lanes derived from the city description, so a partly regenerated lanes.json never
## leaves the world without lanes.
func build(lane_dicts: Array[Dictionary], roads: Array,
		links: Array[Dictionary] = []) -> Array[LanePath]:
	var lanes: Array[LanePath] = []
	if not lane_dicts.is_empty():
		var usable := _usable_entries(lane_dicts, roads)
		lanes = _from_lanes_json(usable)
		_merge_links(links)
	lanes.append_array(_from_city_roads(roads))
	return lanes


## Keeps the lanes of the roads unit that belong to a road of this city and sit on it: a
## lanes.json that was generated for another map must not leak into the world.
func _usable_entries(lane_dicts: Array[Dictionary], roads: Array) -> Array[Dictionary]:
	var by_id: Dictionary = {}
	for road in roads:
		if road is Dictionary:
			by_id[str((road as Dictionary).get("id", ""))] = road as Dictionary
	var out: Array[Dictionary] = []
	for entry in lane_dicts:
		var road_id := str(entry.get("road", ""))
		if not by_id.has(road_id):
			continue
		if not _on_road(entry, by_id[road_id]):
			continue
		out.append(entry)
	return out


## True when the lane of lanes.json lies on the road of the city description.
func _on_road(entry: Dictionary, road: Dictionary) -> bool:
	var lane_points := _points(entry.get("points", []))
	if lane_points.is_empty():
		return false
	var road_points := _points(road.get("points", []))
	if road_points.size() < 2:
		return false
	var best := INF
	for p in lane_points:
		for r in road_points:
			best = minf(best, Vector2(p.x - r.x, p.z - r.z).length())
			if best < 25.0:
				return true
	return best < 25.0


# --- lanes.json -----------------------------------------------------------------------------------

func _from_lanes_json(entries: Array[Dictionary]) -> Array[LanePath]:
	var lanes: Array[LanePath] = []
	for entry in entries:
		var pts := _points(entry.get("points", []))
		if pts.size() < 2:
			continue
		var lane := LanePath.new()
		var road := str(entry.get("road", ""))
		lane.road_id = StringName(road)
		lane.lane_width = float(entry.get("width", 3.5))
		lane.speed_limit_kmh = float(entry.get("speed_kmh", 80.0))
		lane.elevated = bool(entry.get("elevated", false))
		# The lateral offset of the lane from the centre line of its road and the sign of its
		# travel direction: the furniture filter needs them to move a prop off the carriageway.
		lane.set_meta("offset", float(entry.get("offset", 0.0)))
		lane.set_meta("dir", int(entry.get("dir", 1)))
		lane.curve = Spline.make_curve(pts, LANE_BAKE)
		var id := String(entry.get("id", "lane_%d" % lanes.size()))
		ids.append(id)
		_register(id, road, lanes.size())
		_covered[road] = true
		var nxt: Array = []
		var raw_next: Variant = entry.get("next", [])
		if raw_next is Array:
			for n in raw_next as Array:
				nxt.append(String(n))
		declared_next[id] = nxt
		lanes.append(lane)
	return lanes


# --- derived from city.json -----------------------------------------------------------------------

func _from_city_roads(roads: Array) -> Array[LanePath]:
	var lanes: Array[LanePath] = []
	for road in roads:
		if not road is Dictionary:
			continue
		var d := road as Dictionary
		if _covered.has(str(d.get("id", ""))):
			continue
		var road_lanes := _road_lanes(d)
		var base := lanes.size()
		for lane in road_lanes:
			var index := lanes.size()
			lanes.append(lane)
			var id := String(lane.get_meta("id", ""))
			ids.append(id)
			_register(id, String(lane.road_id), index)
		_chain_road(lanes, base, road_lanes.size(), int(d.get("lanes_fwd", 2)))
	return lanes


## The lanes of one road continue into each other: the forward lanes in order, the backward
## lanes in the opposite order (the same convention the roads unit uses).
func _chain_road(lanes: Array[LanePath], base: int, count: int, fwd: int) -> void:
	for k in range(fwd - 1):
		_link(lanes, base + k, base + k + 1)
	for k in range(count - fwd - 1):
		_link(lanes, base + fwd + k + 1, base + fwd + k)


func _link(lanes: Array[LanePath], from_index: int, to_index: int) -> void:
	if from_index < 0 or to_index < 0 or from_index >= lanes.size() or to_index >= lanes.size():
		return
	var next_lanes := lanes[from_index].next_lanes
	if not next_lanes.has(to_index):
		next_lanes.append(to_index)


func _road_lanes(road: Dictionary) -> Array[LanePath]:
	var out: Array[LanePath] = []
	var pts := _points(road.get("points", []))
	if pts.size() < 2:
		return out
	var line := Spline.resample(Spline.sample_centerline(pts, str(road.get("spline", "catmull"))), 4.0)
	var w := float(road.get("lane_width", 3.75))
	var median := float(road.get("median", 1.0))
	var speed := float(road.get("speed_kmh", 80.0))
	var elevated := str(road.get("kind", "surface")) in ["elevated", "bridge"]
	var road_id := str(road.get("id", "road"))
	var fwd := int(road.get("lanes_fwd", 2))
	var back := int(road.get("lanes_back", 2))
	for k in fwd:
		# Right-hand traffic: the forward carriageway is right of the travel direction.
		var offset := median * 0.5 + float(k) * w + w * 0.5
		out.append(_make_lane(road_id, k, 1, line, offset, w, speed, elevated))
	for k in back:
		var offset2 := median * 0.5 + float(k) * w + w * 0.5
		out.append(_make_lane(road_id, k, -1, line, -offset2, w, speed, elevated))
	return out


## `offset` is the lateral distance of the lane from the centre line of the road, measured to
## the right of the travel direction of the forward lanes (the convention of lanes.json).
func _make_lane(road_id: String, index: int, dir: int, line: PackedVector3Array, offset: float,
		width: float, speed: float, elevated: bool) -> LanePath:
	var shifted := Spline.offset_polyline(line, offset)
	if dir < 0:
		shifted = _reversed(shifted)
	var lane := LanePath.new()
	lane.road_id = StringName(road_id)
	lane.lane_width = width
	lane.speed_limit_kmh = speed
	lane.elevated = elevated
	lane.set_meta("offset", offset)
	lane.set_meta("dir", dir)
	lane.curve = Spline.make_curve(shifted)
	var id := "%s_%s_%d" % [road_id, "f" if dir > 0 else "b", index]
	lane.set_meta("id", id)
	return lane


## Adds the explicit link list of the roads unit to the per-lane next lists.
func _merge_links(links: Array[Dictionary]) -> void:
	for link in links:
		var from_id := str(link.get("from", ""))
		var to_id := str(link.get("to", ""))
		if from_id == "" or to_id == "":
			continue
		if not declared_next.has(from_id):
			declared_next[from_id] = [] as Array
		var list: Array = declared_next[from_id]
		if not list.has(to_id):
			list.append(to_id)


func _register(id: String, road: String, index: int) -> void:
	if not by_road.has(road):
		by_road[road] = []
	var list: Array = by_road[road]
	list.append(index)


static func _reversed(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(points.size() - 1, -1, -1):
		out.append(points[i])
	return out


static func _points(raw: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 3:
			out.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
		elif entry is Array and (entry as Array).size() == 2:
			out.append(Vector3(float(entry[0]), 0.0, float(entry[1])))
	return out
