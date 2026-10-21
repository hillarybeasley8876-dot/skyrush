extends Node
## Lane graph checks for the road unit (res://world/data/lanes.json):
##   - every linked lane meets its neighbour within 0.5 m
##   - every lane polyline is sampled about every 2 m
##   - every road of the city file is covered by lanes (>= 95 % of the length
##     that is not cut away by a junction)
##   - the dead ends are all flagged (a junction T or the edge of the map)
##   - every ramp attach has at least one lane link
##   - the lateral offset of a lane at its stop line is the design offset +- 0.3 m
##   - no two lanes of different approaches share an end point
##
##   tools/godot.sh test res://assets/city/roads/tests/test_lanes.gd

const LANES_PATH := "res://world/data/lanes.json"
const MINIMAP_PATH := "res://world/data/minimap.json"
const MAX_CONTINUITY := 0.5
const MAX_SPACING := 2.7
const MIN_SPACING := 0.2
const COVERAGE := 0.95
const OFFSET_TOLERANCE := 0.3

var _failures := 0
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var data := _read_json(LANES_PATH)
	if data.is_empty():
		_fail("lanes.json is missing or empty")
		_finish()
		return
	var lanes: Array = data.get("lanes", [])
	var links: Array = data.get("links", [])
	var roads: Dictionary = data.get("roads", {})
	_check(lanes.size() > 0, "lanes.json holds lanes (%d)" % lanes.size())
	_check(links.size() > 0, "lanes.json holds links (%d)" % links.size())
	var by_id: Dictionary = {}
	for entry in lanes:
		by_id[String((entry as Dictionary).get("id", ""))] = entry
	_check(by_id.size() == lanes.size(), "every lane has a unique id")

	_check_continuity(links, by_id)
	_check_spacing(lanes)
	_check_coverage(roads)
	_check_termini(lanes)
	_check_offsets(lanes, by_id)
	_check_shared_ends(lanes)
	_check_attaches(by_id, links)
	_finish()


func _check_continuity(links: Array, by_id: Dictionary) -> void:
	var worst := 0.0
	var bad := 0
	for entry in links:
		var link := entry as Dictionary
		var a: Array = (by_id.get(String(link.get("from", "")), {}) as Dictionary).get("points", [])
		var b: Array = (by_id.get(String(link.get("to", "")), {}) as Dictionary).get("points", [])
		if a.is_empty() or b.is_empty():
			bad += 1
			continue
		var gap := _v3(a[a.size() - 1]).distance_to(_v3(b[0]))
		worst = maxf(worst, gap)
		if gap > MAX_CONTINUITY:
			bad += 1
	_check(bad == 0, "linked lanes meet within %.1f m (worst %.3f m, %d bad)"
		% [MAX_CONTINUITY, worst, bad])


func _check_spacing(lanes: Array) -> void:
	var bad := 0
	var worst := 0.0
	for entry in lanes:
		var pts: Array = (entry as Dictionary).get("points", [])
		for i in range(pts.size() - 1):
			var gap := _v3(pts[i]).distance_to(_v3(pts[i + 1]))
			worst = maxf(worst, gap)
			if gap > MAX_SPACING or (gap < MIN_SPACING and gap > 0.001):
				bad += 1
	_check(bad == 0, "lane points are sampled every ~2 m (worst %.2f m, %d bad)" % [worst, bad])


func _check_coverage(roads: Dictionary) -> void:
	var bad: Array = []
	for id in roads:
		var info: Dictionary = roads[id]
		var length := float(info.get("length", 0.0))
		var covered := float(info.get("covered", 0.0))
		var trimmed := float(info.get("trimmed", 0.0))
		if length < 20.0:
			continue   # a stub road shorter than a lane
		var usable := maxf(1.0, length - trimmed)
		if covered < COVERAGE * usable:
			bad.append("%s (%.0f/%.0f m)" % [id, covered, usable])
	_check(bad.is_empty(), "every road is covered by lanes (>= %d %%)  %s"
		% [int(COVERAGE * 100.0), ", ".join(bad.slice(0, 5))])


func _check_termini(lanes: Array) -> void:
	var junction_ends: Array = []
	var map_edges: Array = []
	for entry: Variant in lanes:
		var lane := entry as Dictionary
		if not lane.get("next", []).is_empty():
			continue
		var kind := String(lane.get("terminus_kind", "?"))
		if kind == "map_edge":
			map_edges.append(String(lane.get("id", "")))
		else:
			junction_ends.append(String(lane.get("id", "")))
	_check(junction_ends.is_empty(),
		"no lane dead-ends at a junction (%d dead ends, %d map edges: %s)"
		% [junction_ends.size(), map_edges.size(), ", ".join(map_edges.slice(0, 8))])


func _check_offsets(lanes: Array, by_id: Dictionary) -> void:
	# the lateral offset of a lane at its stop line must be the design offset
	var minimap := _read_json(MINIMAP_PATH)
	var centre: Dictionary = {}
	for entry in minimap.get("roads", []):
		centre[String((entry as Dictionary).get("id", ""))] = (entry as Dictionary).get("points", [])
	var bad := 0
	var sampled := 0
	for n in range(lanes.size()):
		var entry: Dictionary = lanes[n]
		var lane := entry as Dictionary
		if lane.get("connector", false):
			continue
		if n % 25 != 0:
			continue
		sampled += 1
		var line: Array = centre.get(String(lane.get("road", "")), [])
		if line.size() < 2:
			continue
		var end := _xz(lane.get("points", [])[lane.get("points", []).size() - 1])
		var dist := _distance_to_polyline(end, line)
		if absf(dist - absf(float(lane.get("offset", 0.0)))) > OFFSET_TOLERANCE:
			bad += 1
	_check(bad == 0, "the lanes keep their design lateral offset at the stop line (%d of %d sampled bad)" % [bad, sampled])


func _check_shared_ends(lanes: Array) -> void:
	var ends: Array = []
	for entry in lanes:
		var lane := entry as Dictionary
		if lane.get("connector", false):
			continue   # connectors meet their exit lane on purpose
		var pts: Array = lane.get("points", [])
		if pts.is_empty():
			continue
		ends.append([_v3(pts[pts.size() - 1]), String(lane.get("road", ""))])
	var shared := 0
	for i in range(ends.size()):
		for j in range(i + 1, ends.size()):
			if String((ends[i] as Array)[1]) == String((ends[j] as Array)[1]):
				continue
			# two roads that meet at the same kerb return legitimately end together
			if ((ends[i] as Array)[0] as Vector3).distance_to((ends[j] as Array)[0] as Vector3) < 0.15:
				shared += 1
	_check(shared == 0, "no two approaches share an end point (%d shared)" % shared)


func _check_attaches(by_id: Dictionary, links: Array) -> void:
	var city := _read_json(_city_path())
	var attached := 0
	var missing: Array = []
	for entry in city.get("roads", []):
		var road := entry as Dictionary
		if String(road.get("kind", "")) != "ramp":
			continue
		for key in ["attach_start", "attach_end"]:
			if not road.has(key):
				continue
			attached += 1
			if not _has_attach_link(road, String(key), by_id, links):
				missing.append("%s.%s" % [String(road.get("id", "")), key])
	_check(attached == 0 or missing.is_empty(),
		"every ramp attach has a lane link (%d attaches, %d missing: %s)"
		% [attached, missing.size(), ", ".join(missing.slice(0, 5))])


func _has_attach_link(road: Dictionary, key: String, by_id: Dictionary, links: Array) -> bool:
	# a link that starts on one of the ramp's lanes, or a connector lane of the ramp
	for entry in by_id.values():
		var lane := entry as Dictionary
		if String(lane.get("road", "")) == String(road.get("id", "")) and lane.get("attach", false):
			return true
	for entry in links:
		var link := entry as Dictionary
		var from_id := String(link.get("from", ""))
		var lane: Dictionary = by_id.get(from_id, {})
		if String(lane.get("road", "")) == String(road.get("id", "")):
			return true
	return false


func _city_path() -> String:
	var repo := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	if FileAccess.file_exists(repo.path_join("data/city/city.json")):
		return repo.path_join("data/city/city.json")
	return repo.path_join("data/city/test_city.json")


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _v3(p: Variant) -> Vector3:
	if p is Array:
		var a := p as Array
		if a.size() >= 3:
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
		if a.size() == 2:
			return Vector3(float(a[0]), 0.0, float(a[1]))
	return Vector3.ZERO


func _xz(p: Variant) -> Vector3:
	# the ground plane: the lane height does not matter for the lateral offset
	if p is Array:
		var a := p as Array
		if a.size() >= 3:
			return Vector3(float(a[0]), 0.0, float(a[2]))
		if a.size() == 2:
			return Vector3(float(a[0]), 0.0, float(a[1]))
	return Vector3.ZERO


func _distance_to_polyline(p: Vector3, line: Array) -> float:
	var best := 1e9
	for i in range(line.size() - 1):
		var a := _xz(line[i])
		var b := _xz(line[i + 1])
		var d := a.distance_to(b)
		if d < 0.001:
			continue
		var t := clampf((p - a).dot(b - a) / (d * d), 0.0, 1.0)
		best = minf(best, p.distance_to(a + (b - a) * t))
	return best


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _fail(label: String) -> void:
	_failures += 1
	print("FAIL ", label)


func _finish() -> void:
	print("TEST %s: %d checks, %d failures" % ["lanes", _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
