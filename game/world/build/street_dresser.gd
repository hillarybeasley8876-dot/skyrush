extends RefCounted
## Dresses the streets of the city: the bins, the bollards, the bike racks, the hydrants, the
## planters, the metro entrances and the neon blade signs. Without them a street is a road with
## a few lamps on it; with them it reads as a place (ART §6, the scale cues).
##
## The props are placed on the sidewalk of their road, at a fixed rate per metre of kerb, so
## the dressing is the same on every street of the city.

const Spline := preload("res://world/api/spline_util.gd")
const LaneProbe := preload("res://world/build/lane_probe.gd")

## The number of bins per 100 m of kerb.
const BINS_PER_100M := 2.0
## The number of bike racks per 150 m of kerb.
const BIKES_PER_150M := 1.0
## The number of hydrants per 120 m of kerb.
const HYDRANTS_PER_120M := 1.0
## The distance between two planters on a promenade.
const PLANTER_GAP := 11.0
## The distance between two neon blade signs on a shop street.
const BLADE_MIN := 25.0
const BLADE_MAX := 40.0
## The distance between two shop name boards.
const SHOP_SIGN_GAP := 120.0
## A road needs a sidewalk of at least this width to be dressed.
const SIDEWALK_MIN := 2.5
## The distance from the kerb the props stand at.
const KERB_GAP := 1.1
## The roads that get planters (the promenade of the Bund and the shopping street).
const PLANTER_ROADS: Array[String] = ["bund_zhongshan_e1", "bund_north", "st_nanjing_e_rd"]
## The prefix of the shopping streets (they get the neon blade signs).
const SHOP_PREFIX := "st_"
## The names of the shops (Chinese parody names, ART §7).
const SHOP_NAMES: Array[String] = [
	"申城便利", "老周面馆", "赛博茶饮", "修车铺", "照相馆", "电子城", "夜宵摊", "小杨生煎",
]
## The number of bollards at every corner of a junction.
const BOLLARDS_PER_CORNER := 3
## The number of metro entrances.
const METRO_ENTRANCES := 4
## The space outside a lane that still counts as carriageway.
const LANE_CLEARANCE := 0.6
## The chance that a bin stands at its place on the kerb.
const BIN_CHANCE := 0.75
## The chance that a bike rack stands at its place on the kerb.
const BIKE_CHANCE := 0.7
## The chance that a place on the kerb gets a bike rack and not a scooter.
const E_SCOOTER_CHANCE := 0.6
## The distance between two bollards of a corner.
const BOLLARD_SPACING := 2.2
## The steps along the road that are tried when a prop does not fit on the kerb.
const KERB_SLIDES: Array[float] = [3.0, -3.0, 6.0, -6.0, 9.0, -9.0, 13.0, -13.0]

var _random := RandomNumberGenerator.new()
## The index of the next shop name.
var _shop_index := 0
var _entries: Array[Dictionary] = []
var _counts: Dictionary = {}
## The centre line of every road (the resampling of a road is done once, not once per prop).
var _lines: Dictionary = {}
## The half width of the carriageway of every road, from the lanes of the roads unit.
var _half_widths: Dictionary = {}
## The lane queries (a prop may not stand in the carriageway of a crossing road).
var _probe: LaneProbe = null


## The dressed streets of the city.
func build(roads: Array, junctions: Array, pois: Array,
		half_widths: Dictionary = {}, grid = null) -> Array[Dictionary]:
	_entries.clear()
	_counts.clear()
	_lines.clear()
	_half_widths = half_widths
	_probe = LaneProbe.new()
	_probe.setup([], grid)
	_random.seed = 20240517
	for road in roads:
		if road is Dictionary:
			_dress_road(road as Dictionary)
	_dress_junctions(junctions, roads)
	_dress_metro(pois, roads)
	return _entries


## The number of props per type.
func counts() -> Dictionary:
	return _counts


func _add(type: String, xform: Transform3D, text: String = "") -> void:
	if _probe != null and not _clear_of_lanes(xform.origin):
		return  # the prop would stand in the carriageway of a crossing road
	_entries.append({
		"type": type,
		"transform": xform,
		"scale": 1.0,
		"scale_vector": Vector3.ONE,
		"light": false,
		"height_m": 0.0,
		"road": "",
		"text": text,
		"style": "shop" if type == "shop_sign" else "",
		"dressed": true,
	})
	_counts[type] = int(_counts.get(type, 0)) + 1


## True when no lane runs through the point.
func _clear_of_lanes(position: Vector3) -> bool:
	return not _probe.on_carriageway(position, {}, LANE_CLEARANCE)


## The kerb line of a road: the centre line of the road, offset to the edge of the pavement.
func _kerb(road: Dictionary, distance: float, side: float) -> Transform3D:
	var line := _line(road)
	if line.size() < 2:
		return Transform3D.IDENTITY
	var point := Spline.point_at(line, distance)
	var tangent := Spline.tangent_at(line, distance)
	var normal := Vector3(-tangent.z, 0.0, tangent.x)
	var half := _half_width(road)
	var position := point + normal * (half + KERB_GAP) * side
	return Transform3D(Basis.looking_at(tangent, Vector3.UP), position)


func _line(road: Dictionary) -> PackedVector3Array:
	var id := str(road.get("id", ""))
	if _lines.has(id):
		return _lines[id]
	var points := PackedVector3Array()
	var raw: Variant = road.get("points", [])
	if not raw is Array:
		return points
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 3:
			points.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
	var line := Spline.resample(Spline.sample_centerline(points, str(road.get("spline", "catmull"))), 4.0)
	_lines[id] = line
	return line


## The half width of the pavement of a road: the lanes of the roads unit are the truth, the
## description of the city is the fallback.
func _half_width(road: Dictionary) -> float:
	var id := str(road.get("id", ""))
	if _half_widths.has(id) and float(_half_widths[id]) > 0.0:
		return float(_half_widths[id])
	var lanes := int(road.get("lanes_fwd", 2))
	var width := float(road.get("lane_width", 3.75))
	var median := float(road.get("median", 1.0))
	return median * 0.5 + float(lanes) * width


## The kerb dressing of one road.
func _dress_road(road: Dictionary) -> void:
	if str(road.get("kind", "surface")) != "surface":
		return
	var sidewalk := float(road.get("sidewalk", 0.0))
	if sidewalk < SIDEWALK_MIN:
		return
	var line := _line(road)
	var length := Spline.total_length(line)
	if length < 20.0:
		return
	var id := str(road.get("id", ""))
	var bin_step := 100.0 / BINS_PER_100M
	var bike_step := 150.0 / BIKES_PER_150M
	var hydrant_step := 120.0 / HYDRANTS_PER_120M
	var distance := 0.0
	for side in [1.0, -1.0]:
		distance = bin_step * 0.5
		while distance < length:
			if _random.randf() < BIN_CHANCE:
				_add("bin", _kerb_at(road, distance, side))
			distance += bin_step
		distance = bike_step * 0.5
		while distance < length:
			if _random.randf() < BIKE_CHANCE:
				_add("bike_share" if _random.randf() < E_SCOOTER_CHANCE else "e_scooter",
					_kerb_at(road, distance, side))
			distance += bike_step
		distance = hydrant_step * 0.5
		while distance < length:
			_add("hydrant", _kerb_at(road, distance, side))
			distance += hydrant_step
	if id in PLANTER_ROADS:
		distance = PLANTER_GAP * 0.5
		while distance < length:
			var pot := "planter_pot_bougainvillea" if _random.randf() < 0.5 else "planter_pot_privet"
			_add(pot, _kerb_at(road, distance, 1.0))
			distance += PLANTER_GAP
	if id.begins_with(SHOP_PREFIX):
		distance = BLADE_MIN
		while distance < length:
			_add("neon_blade_frame", _kerb_at(road, distance, 1.0))
			distance += _random.randf_range(BLADE_MIN, BLADE_MAX)
		distance = SHOP_SIGN_GAP * 0.5
		while distance < length:
			_add("shop_sign", _kerb_at(road, distance, 1.0),
				SHOP_NAMES[_shop_index % SHOP_NAMES.size()])
			_shop_index += 1
			distance += SHOP_SIGN_GAP


## The bollards at the corners of the junctions.
func _dress_junctions(junctions: Array, roads: Array) -> void:
	var by_id: Dictionary = {}
	for road in roads:
		if road is Dictionary:
			by_id[str((road as Dictionary).get("id", ""))] = road as Dictionary
	for junction in junctions:
		if not junction is Dictionary:
			continue
		var jd := junction as Dictionary
		var point := Vector3(float(jd.get("x", 0.0)), float(jd.get("y", 0.0)), float(jd.get("z", 0.0)))
		var road_ids: Array = jd.get("roads", [])
		if road_ids.is_empty():
			continue
		var road: Dictionary = by_id.get(String(road_ids[0]), {})
		if road.is_empty():
			continue
		var line := _line(road)
		if line.size() < 2:
			continue
		var distance := _closest_distance(line, point)
		for side in [1.0, -1.0]:
			for k in BOLLARDS_PER_CORNER:
				var along := float(k - 1) * BOLLARD_SPACING
				_add("bollard", _kerb_at(road, distance + along, side))


## The point of a polyline that is closest to a point.
func _closest_distance(line: PackedVector3Array, point: Vector3) -> float:
	var best := 0.0
	var best_distance := INF
	var travelled := 0.0
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var segment := a.distance_to(b)
		if segment < 0.001:
			continue
		var t := clampf((point - a).dot(b - a) / (segment * segment), 0.0, 1.0)
		var closest := a.lerp(b, t)
		var distance := Vector2(closest.x - point.x, closest.z - point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = travelled + segment * t
		travelled += segment
	return best


## The kerb at a distance along the road, moved along the road until no lane runs through it.
func _kerb_at(road: Dictionary, distance: float, side: float) -> Transform3D:
	var xform := _kerb(road, distance, side)
	if _probe == null or _clear_of_lanes(xform.origin):
		return xform
	for step in KERB_SLIDES:
		var candidate := _kerb(road, distance + step, side)
		if _clear_of_lanes(candidate.origin):
			return candidate
	return xform


## The metro entrances near the points of interest.
func _dress_metro(pois: Array, roads: Array) -> void:
	var placed := 0
	for poi in pois:
		if placed >= METRO_ENTRANCES:
			break
		if not poi is Dictionary:
			continue
		var p := poi as Dictionary
		var kind := str(p.get("kind", ""))
		if kind not in ["charge", "hiding_spot", "police_station"]:
			continue
		var point := Vector3(float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0)))
		var road := _nearest_road(roads, point)
		if road.is_empty():
			continue
		var xform := Transform3D(Basis(Vector3.UP, _random.randf_range(0.0, TAU)),
			point + Vector3(6.0, 0.0, 4.0))
		_add("metro_entrance", xform)
		placed += 1


## The road whose centre line is closest to a point.
func _nearest_road(roads: Array, point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for road in roads:
		if not road is Dictionary:
			continue
		var d := road as Dictionary
		if str(d.get("kind", "surface")) != "surface":
			continue
		var line := _line(d)
		if line.size() < 2:
			continue
		var distance := INF
		for p in line:
			distance = minf(distance, Vector2(p.x - point.x, p.z - point.z).length())
		if distance < best_distance:
			best_distance = distance
			best = d
	return best
