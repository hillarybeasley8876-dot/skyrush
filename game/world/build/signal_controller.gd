extends Node
## Per-junction traffic signal cycle and the traffic-light masts.
## Cycle: 30 s per junction, split evenly between the roads it joins; the last 3 s of a road's
## slot is amber. Roads that are not part of the junction report green.
##
## The masts are drawn as four MultiMesh batches (the bodies and the three lenses), so the
## whole city costs four draw calls instead of one per mast part. The lens state travels in
## the instance custom data; only the masts whose state changed are updated.

const MastBatch := preload("res://world/build/mast_batch.gd")
const Spline := preload("res://world/api/spline_util.gd")
const LaneProbe := preload("res://world/build/lane_probe.gd")
const LaneSpatial := preload("res://world/api/lane_spatial.gd")
const PropCollision := preload("res://world/build/prop_collision.gd")

## Two lanes are on the same level when their heights are this close.
const LEVEL_TOLERANCE := 2.5

const CYCLE := 30.0
const AMBER := 3.0
const BACK_OFFSET := 9.0
## How far behind the kerb a mast stands.
const KERB_GAP := 0.5
## The smallest distance between a mast and the centre of a lane.
## The space between the pole of a mast and the edge of a lane. The kerb of a road is about
## 2.9 m from the centre of its outer lane, so a bigger margin would push every mast of a
## junction off the corner.
const MAST_CLEARANCE := 1.0
## The smallest distance to the centre of a lane that still counts as carriageway.
const MIN_CARRIAGEWAY := 2.4
## The step of the search around the middle of a junction (the corners).
const CORNER_STEP := 15
## Two junctions closer than this are one junction (the city description has two signalised
## junctions 15 m apart at the Bund, and their cycles fought each other).
const MERGE_DISTANCE := 20.0
## The rate at which the lenses are updated.
const LENS_HZ := 10.0
## The height of a mast.
const MAST_HEIGHT := 6.4


var _junctions: Dictionary = {}  # junction id -> {"roads": Array, "point": Vector3}
## The lane queries (a mast may not stand in a carriageway).
var _probe: LaneProbe = null
var _roads_by_id: Dictionary = {}
## The masts in the order of the batch: {"junction": String, "road": String}.
var _masts: Array[Dictionary] = []
var _batch: MastBatch
## Seconds since the world started; the junction phase cycle runs on this.
var elapsed := 0.0
## The clock of the lens updates (the heads are updated at 10 Hz).
var _lens_clock := 0.0
var _last_state: Dictionary = {}


## `entries` are the traffic-light props of the roads unit's road_furniture.json; when they are
## missing the light positions are derived from the road centre lines.
func setup(junctions: Array, roads: Array, parent: Node3D,
		entries: Array[Dictionary] = [], lanes: Array[LanePath] = [], grid = null) -> void:
	for road in roads:
		if road is Dictionary:
			var id := str((road as Dictionary).get("id", ""))
			_roads_by_id[id] = road
	# The junctions that stand closer than MERGE_DISTANCE are one junction: they have one
	# cycle and one set of masts, so two heads never show two different states at the same
	# approach.
	var merged := _merge_junctions(junctions)
	var placements: Array[Dictionary] = []
	var known: Dictionary = {}
	for junction in merged:
		var data := junction as Dictionary
		var id := str(data.get("id", ""))
		_junctions[id] = {"roads": data.get("roads", []),
			"point": Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("z", 0.0)))}
		known[id] = true
		if not bool(data.get("signals", true)) or not _at_grade(data.get("roads", [])):
			continue
		placements.append_array(_place_masts(id, data, entries))
	# The traffic lights of the roads unit that name a junction the city description does not
	# have are placed as well: the mast stands where the roads unit put it, and the junction
	# reports green (the ids of the two data sets do not agree).
	for entry in entries:
		var junction_id := str(entry.get("junction", ""))
		if junction_id == "" or known.has(junction_id):
			continue
		var xform: Transform3D = entry.get("transform", Transform3D.IDENTITY)
		placements.append({"transform": xform, "junction": junction_id,
			"road": str(entry.get("road", ""))})
	_masts = _dedupe(placements)
	var dropped := 0
	if grid != null and not lanes.is_empty():
		_probe = LaneProbe.new()
		_probe.setup(lanes, grid)
		var kept: Array[Dictionary] = []
		for mast in _masts:
			var moved := _on_the_kerb(mast["transform"], lanes, grid,
				str(mast.get("junction", "")), str(mast.get("road", "")))
			if not _clear_of_lanes(moved.origin):
				# A mast that cannot stand clear of the lanes is not placed: a traffic light in
				# the middle of the road is worse than no traffic light.
				dropped += 1
				continue
			mast["transform"] = moved
			kept.append(mast)
		_masts = kept
		print("[world] signals: %d masts, %d without a place on the kerb" % [
			_masts.size(), dropped])
	_batch = MastBatch.new()
	if not _batch.load_meshes():
		_batch = null
		return
	_batch.build(parent, _masts)
	_build_collision(parent)


## The collision of the masts: the car must not drive through a pole.
func _build_collision(parent: Node3D) -> void:
	var entries: Array[Dictionary] = []
	for mast in _masts:
		entries.append({"type": "traffic_light", "transform": mast["transform"],
			"height_m": MAST_HEIGHT})
	PropCollision.new().build(parent, entries)


## The junctions of the city, with the ones that stand close together merged into one.
func _merge_junctions(junctions: Array) -> Array[Dictionary]:
	var groups: Array = []
	for junction in junctions:
		if not junction is Dictionary:
			continue
		var data := junction as Dictionary
		var point := Vector3(float(data.get("x", 0.0)), 0.0, float(data.get("z", 0.0)))
		var found := -1
		for i in groups.size():
			if (groups[i][0] as Vector3).distance_to(point) <= MERGE_DISTANCE:
				found = i
				break
		if found < 0:
			groups.append([point, [data]])
		else:
			var group: Array = groups[found]
			var count := float((group[1] as Array).size())
			group[0] = ((group[0] as Vector3) * count + point) / (count + 1.0)
			(group[1] as Array).append(data)
	var out: Array[Dictionary] = []
	for group in groups:
		var members: Array = group[1]
		var roads: Array = []
		var signals := false
		for member in members:
			var d := member as Dictionary
			signals = signals or bool(d.get("signals", true))
			for road in d.get("roads", []):
				if not roads.has(road):
					roads.append(road)
		out.append({
			"id": str((members[0] as Dictionary).get("id", "")),
			"x": (group[0] as Vector3).x,
			"z": (group[0] as Vector3).z,
			"roads": roads,
			"signals": signals,
		})
	return out


## One mast per approach: two masts of the same junction and the same road that stand close
## together are one mast.
func _dedupe(placements: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mast in placements:
		var key := "%s_%s" % [mast.get("junction", ""), mast.get("road", "")]
		var origin: Vector3 = (mast["transform"] as Transform3D).origin
		var duplicate := false
		for kept in out:
			if "%s_%s" % [kept.get("junction", ""), kept.get("road", "")] != key:
				continue
			if (kept["transform"] as Transform3D).origin.distance_to(origin) <= MERGE_DISTANCE:
				duplicate = true
				break
		if not duplicate:
			out.append(mast)
	return out


## A junction on a bridge has no traffic lights.
func _at_grade(road_ids: Variant) -> bool:
	if not road_ids is Array:
		return true
	for road_id in road_ids as Array:
		var road: Variant = _roads_by_id.get(String(road_id))
		if road is Dictionary:
			var kind := str((road as Dictionary).get("kind", "surface"))
			if kind == "elevated" or kind == "bridge":
				return false
	return true


## The masts of a junction: the ones the roads unit listed, or two per road from the centrelines.
func _place_masts(junction_id: String, junction: Dictionary,
		entries: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var road_ids: Array = junction.get("roads", [])
	for entry in entries:
		if str(entry.get("junction", "")) != junction_id:
			continue
		var xform: Transform3D = entry.get("transform", Transform3D.IDENTITY)
		out.append({"transform": xform, "junction": junction_id,
			"road": str(entry.get("road", ""))})
	if not out.is_empty():
		return out
	var point := Vector3(float(junction.get("x", 0.0)), 0.0, float(junction.get("z", 0.0)))
	for road_id in road_ids:
		for xform in _derive_masts(String(road_id), point):
			out.append({"transform": xform, "junction": junction_id, "road": String(road_id)})
	return out


## One mast on each side of the road, a few metres before the junction. The mast stands
## behind the kerb of the whole road (both carriageways), never between the lanes.
func _derive_masts(road_id: String, junction: Vector3) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var road: Variant = _roads_by_id.get(road_id)
	if not road is Dictionary:
		return out
	var line := Spline.road_line(road as Dictionary)
	if line.size() < 2:
		return out
	var index := _closest_index(line, junction)
	var tangent := _tangent_at(line, index)
	var width := _kerb_distance(road as Dictionary)
	for side in [1.0, -1.0]:
		var direction := tangent if side > 0.0 else -tangent
		var normal := Vector3(direction.z, 0.0, -direction.x).normalized()
		var position := line[index] - direction * BACK_OFFSET + normal * width
		position.y = line[index].y
		out.append(Transform3D(Basis.IDENTITY, position).looking_at(position - direction, Vector3.UP))
	return out


## The distance from the centre line of a road to the kerb (the half width of the road plus
## its shoulder) plus the margin behind the kerb.
func _kerb_distance(road: Dictionary) -> float:
	var lanes := float(road.get("lanes_fwd", 2))
	var width := float(road.get("lane_width", 3.75))
	var median := float(road.get("median", 1.0))
	var shoulder := float(road.get("shoulder", 0.5))
	return median * 0.5 + lanes * width + shoulder + KERB_GAP


## Moves a mast that stands in the carriageway to a place where no lane runs: the kerb of its
## road, or the corner of the junction when the kerb is still in the way of another road.
func _on_the_kerb(xform: Transform3D, lanes: Array[LanePath], grid: LaneSpatial, junction_id: String,
		road_id: String) -> Transform3D:
	var moved := _to_the_kerb(xform, lanes, grid)
	if _clear_of_lanes(moved.origin):
		return moved
	# The corners of the junction first: the ring around the middle of the junction at the
	# distance of the kerb of the road. A corner is the place where the kerb of one road
	# meets the kerb of the next one.
	var road: Variant = _roads_by_id.get(road_id, {})
	var junction: Variant = _junction_point(junction_id)
	if road is Dictionary and junction != null:
		var kerb := _kerb_distance(road as Dictionary)
		var centre: Vector3 = junction
		for angle in range(0, 360, CORNER_STEP):
			var offset := Vector3(cos(deg_to_rad(float(angle))), 0.0,
				sin(deg_to_rad(float(angle)))) * kerb
			var candidate: Vector3 = centre + offset
			candidate.y = moved.origin.y
			if _clear_of_lanes(candidate):
				return Transform3D(moved.basis, candidate)
	# Then the places around the kerb of the road.
	for distance: float in [2.0, 3.5, 5.0, 7.0, 9.0, 12.0, 16.0, 20.0]:
		for angle in range(0, 360, 45):
			var offset := Vector3(cos(deg_to_rad(float(angle))), 0.0,
				sin(deg_to_rad(float(angle)))) * distance
			var candidate: Vector3 = moved.origin + offset
			if _clear_of_lanes(candidate):
				return Transform3D(moved.basis, candidate)
	return moved


## The middle of the junction a mast belongs to.
func _junction_point(junction_id: String) -> Variant:
	if not _junctions.has(junction_id):
		return null
	var junction: Dictionary = _junctions[junction_id]
	return junction.get("point", null)


## True when no lane of the same level runs through the point. The distance is measured on the
## curve of the lane, so a lane that curves past the point is found as well.
func _clear_of_lanes(position: Vector3) -> bool:
	if _probe == null:
		return true
	return _probe.clear_of_lanes(position, MIN_CARRIAGEWAY)


## Moves a mast that stands in the carriageway out to the kerb of its road.
func _to_the_kerb(xform: Transform3D, lanes: Array[LanePath], grid: LaneSpatial) -> Transform3D:
	var near: Dictionary = grid.query_near(xform.origin, 16.0)
	var indices: PackedInt32Array = near["lanes"]
	var distances: PackedFloat32Array = near["distances"]
	var heights: PackedFloat32Array = near["heights"]
	var best := -1
	var best_distance := INF
	for i in indices.size():
		if absf(heights[i] - xform.origin.y) > LEVEL_TOLERANCE:
			continue
		if distances[i] < best_distance:
			best_distance = distances[i]
			best = indices[i]
	if best < 0:
		return xform
	var lane := lanes[best]
	if best_distance >= lane.lane_width * 0.5 + MAST_CLEARANCE:
		return xform  # the mast is already clear of the lanes
	var road: Variant = _roads_by_id.get(String(lane.road_id), {})
	if not road is Dictionary:
		return xform
	var info2: Dictionary = grid.detail(best, xform.origin)
	var tangent: Vector3 = info2["tangent"]
	if tangent.length_squared() < 0.0001:
		return xform
	var right := Vector3(-tangent.z, 0.0, tangent.x)
	var offset := float(lane.get_meta("offset", 0.0))
	var dir_sign := float(lane.get_meta("dir", 1))
	# The road centre line is at the offset 0 of the road, so the outward direction is the
	# sign of the offset of the lane (the lane travels backwards on the other side).
	var outward := signf(offset) * dir_sign
	if absf(outward) < 0.01:
		outward = signf((xform.origin - (info2["point"] as Vector3)).dot(right))
	if absf(outward) < 0.01:
		return xform
	var kerb := _kerb_distance(road as Dictionary)
	var target := maxf(kerb - absf(offset), lane.lane_width * 0.5 + MAST_CLEARANCE)
	var position: Vector3 = (info2["point"] as Vector3) + right * (outward * target)
	position.y = xform.origin.y
	return Transform3D(xform.basis, position)


## The positions of the masts (the tests read them).
func mast_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for mast in _masts:
		out.append((mast["transform"] as Transform3D).origin)
	return out


## 0 red, 1 amber, 2 green for a road at a junction.
func signal_state(junction_id: StringName, road_id: StringName) -> int:
	if not _junctions.has(String(junction_id)):
		return 2
	var junction: Dictionary = _junctions[String(junction_id)]
	var road_ids: Array = junction["roads"]
	if not road_ids.has(String(road_id)):
		return 2
	var index := road_ids.find(String(road_id))
	var slot := CYCLE / maxf(float(road_ids.size()), 1.0)
	var position := fmod(elapsed, CYCLE)
	var active := int(floor(position / maxf(slot, 0.01))) % road_ids.size()
	if active != index:
		return 0
	var into := position - float(active) * slot
	var amber := minf(AMBER, slot * 0.4)
	if into >= slot - amber:
		return 1
	return 2


func _process(delta: float) -> void:
	elapsed = fmod(elapsed + delta, CYCLE)
	# The lenses are updated at 10 Hz: the state of a head only changes every few seconds, and
	# the city has more than a thousand masts.
	_lens_clock += delta
	if _lens_clock < 1.0 / LENS_HZ:
		return
	_lens_clock = 0.0
	_update_lenses()


## Updates the lens of the masts whose state changed.
func _update_lenses() -> void:
	if _batch == null:
		return
	for i in _masts.size():
		var mast := _masts[i]
		var key := "%s_%s" % [mast["junction"], mast["road"]]
		var state := signal_state(StringName(mast["junction"]), StringName(mast["road"]))
		if int(_last_state.get(key, -1)) == state:
			continue
		_last_state[key] = state
		_batch.set_state(i, state)


static func _closest_index(line: PackedVector3Array, point: Vector3) -> int:
	var best := 0
	var best_distance := INF
	for i in line.size():
		var d := line[i].distance_squared_to(point)
		if d < best_distance:
			best_distance = d
			best = i
	return best


static func _tangent_at(line: PackedVector3Array, index: int) -> Vector3:
	var tangent := Vector3.FORWARD
	if index < line.size() - 1:
		tangent = line[index + 1] - line[index]
	elif index > 0:
		tangent = line[index] - line[index - 1]
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		return Vector3.FORWARD
	return tangent.normalized()
