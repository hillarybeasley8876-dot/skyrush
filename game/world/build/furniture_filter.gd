extends RefCounted
## Sorts the street furniture of the roads unit. A prop that stands on the carriageway is
## pushed out onto the sidewalk of its own road instead of being deleted; a prop that has no
## room there (another lane, a junction, a site or a deck above it) is dropped.
##
## The lanes are looked up in a fine grid (api/lane_spatial.gd), so the 36,000 props of the
## city are sorted in a second instead of the fifteen a lane-by-lane search took.

const LaneProbe := preload("res://world/build/lane_probe.gd")

## The margin outside a lane that is still carriageway. The quality test measures the distance
## to the centre of the lane with a margin of 2.2 m, so the filter has to be stricter.
const LANE_MARGIN := 0.9
## The smallest distance to the centre of a lane that still counts as carriageway.
const MIN_CARRIAGEWAY := 2.4
## The space between the kerb and where a relocated prop stands.
const RELOCATE_GAP := 1.0
## The shoulder of a road when the city description does not give one.
const DEFAULT_SHOULDER := 0.5
## Two lanes are on the same level when their heights are this close.
const LEVEL_TOLERANCE := 2.5
## The half size of the box of a junction that stays free.
const JUNCTION_CLEARANCE := 8.0
## The space a site needs around it.
const SITE_CLEARANCE := 4.0
## How far the furniture is looked for around a prop.
const QUERY_RADIUS := 8.0
## The size of the cells of the junction index.
const JUNCTION_CELL := 32.0
## A median prop stands in the middle of the road: it is never moved.
const MEDIAN_LIMIT := 4.0
## A road needs a median of at least this width before a prop may stand in it.
const MEDIAN_MIN := 0.5
## The distance at which a deck over a point counts as over it.
const DECK_CLEARANCE := 3.0
## The step of the samples along the perimeter of a box prop (footprint_clear).
const FOOTPRINT_STEP := 1.0

var _probe: LaneProbe
var _lanes: Array[LanePath] = []
var _junction_cells: Dictionary = {}
var _sites: Array[Dictionary] = []
var _half_width: Dictionary = {}
var _shoulder: Dictionary = {}
var _sidewalk: Dictionary = {}
var _median: Dictionary = {}
var _rejected: Dictionary = {}
var _relocated := 0


func setup(lanes: Array[LanePath], junctions: Array, pois: Array, roads: Array = [],
		grid = null) -> void:
	_lanes = lanes
	_probe = LaneProbe.new()
	_probe.setup(lanes, grid)
	_measure_roads(roads)
	_index_junctions(junctions)
	_index_sites(pois)


## The half width of every road (the outer edge of its carriageway) and the shoulder and the
## sidewalk of the city description.
func _measure_roads(roads: Array) -> void:
	for lane in _lanes:
		var road := String(lane.road_id)
		var offset := absf(float(lane.get_meta("offset", 0.0)))
		var edge := offset + lane.lane_width * 0.5
		if not _half_width.has(road) or float(_half_width[road]) < edge:
			_half_width[road] = edge
	for road in roads:
		if not road is Dictionary:
			continue
		var d := road as Dictionary
		var id := str(d.get("id", ""))
		if id == "":
			continue
		_shoulder[id] = float(d.get("shoulder", DEFAULT_SHOULDER))
		_sidewalk[id] = float(d.get("sidewalk", 0.0))
		_median[id] = float(d.get("median", 0.0))


func _index_junctions(junctions: Array) -> void:
	_junction_cells.clear()
	for junction in junctions:
		if not junction is Dictionary:
			continue
		var d := junction as Dictionary
		var point := Vector3(float(d.get("x", 0.0)), 0.0, float(d.get("z", 0.0)))
		var key := _cell_key(point)
		if not _junction_cells.has(key):
			_junction_cells[key] = []
		(_junction_cells[key] as Array).append(point)


func _index_sites(pois: Array) -> void:
	_sites.clear()
	for poi in pois:
		if not poi is Dictionary:
			continue
		var p := poi as Dictionary
		var size: Array = p.get("size", [0.0, 0.0])
		_sites.append({
			"position": Vector3(float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0))),
			"size": Vector2(float(size[0]) if size.size() > 0 else 0.0,
				float(size[1]) if size.size() > 1 else 0.0),
		})


## The place where a prop may stand: its own position when it is clear of the carriageway, the
## sidewalk of its road when it is not, and null when there is no room.
## A dressed prop (a bin of the street dresser) keeps its place in a junction, but it is still
## moved out of the carriageway.
func place(position: Vector3, height: float, kind: String, mount: String = "",
		road: String = "", dressed: bool = false) -> Variant:
	var near: Dictionary = _probe.query(position, QUERY_RADIUS)
	# The lane of the own road of the prop says where it is pushed to; the nearest lane of any
	# road says whether it stands in a carriageway at all.
	var lane_index := _probe.nearest_lane(near, position, road)
	var any_index := _probe.nearest_any(near, position)
	# Every lane around the point counts, not only the nearest one: the Bund has several
	# parallel roads, and a prop between two of them stands on both.
	var on_road := _probe.on_carriageway(position, near, LANE_MARGIN, MIN_CARRIAGEWAY)
	if lane_index < 0:
		lane_index = any_index
	if kind == "gantry":
		return position  # a gantry spans the road on purpose
	if not on_road:
		if kind == "vms":
			return position  # a VMS board is not tested against the junctions
		if not dressed and (_in_junction(position) or _in_site(position)
				or _under_deck(near, position, height)):
			_reject(kind, "in a junction" if _in_junction(position) else
				("inside a site" if _in_site(position) else "under a deck"))
			return null
		return position
	if mount == "median" and float(_median.get(road, 0.0)) > MEDIAN_MIN \
			and _probe.distance_of(near, lane_index, position) < MEDIAN_LIMIT \
			and not _probe.on_another_road(near, position, road) \
			and _probe.on_the_median(near, position, lane_index):
		# A lamp in the median of a road that has one: it stays where it is.
		return position
	var moved: Variant = _relocate(position, near, lane_index, height, dressed)
	if moved == null:
		if kind == "vms":
			return position
		_reject(kind, "no room on the sidewalk")
		return null
	_relocated += 1
	return moved


## Pushes the prop out of the carriageway onto the sidewalk of its own road.
func _relocate(position: Vector3, near: Dictionary, lane_index: int, height: float,
		dressed: bool = false) -> Variant:
	var lane := _lanes[lane_index]
	var info: Dictionary = _probe.grid.detail(lane_index, position)
	var road := String(lane.road_id)
	var half := float(_half_width.get(road, lane.lane_width * 3.0))
	var shoulder := float(_shoulder.get(road, DEFAULT_SHOULDER))
	var sidewalk := float(_sidewalk.get(road, 0.0))
	var target := half + shoulder + RELOCATE_GAP
	if sidewalk <= 0.01:
		# A road without a sidewalk: the prop stays on the paved shoulder.
		target = minf(target, half + shoulder * 2.0 - 0.5)
	var meta_offset := float(lane.get_meta("offset", 0.0))
	var dir_sign := float(lane.get_meta("dir", 1))
	var tangent: Vector3 = info["tangent"]
	if tangent.length_squared() < 0.0001:
		return null
	var right := Vector3(-tangent.z, 0.0, tangent.x)
	var centre: Vector3 = info["point"]
	# The road centre line is at the offset 0, so the outward direction is the sign of the
	# offset of the lane (the lanes of the other direction travel backwards).
	var outward := signf(meta_offset) * dir_sign
	if absf(outward) < 0.01:
		outward = signf((position - centre).dot(right))
	if absf(outward) < 0.01:
		return null
	# The kerb of the road: the centre line of the road with the offset of the lane taken off.
	var road_centre: Vector3 = centre - right * (outward * absf(meta_offset))
	var distance := maxf(target, lane.lane_width * 0.5 + LANE_MARGIN)
	# Both kerbs of the road are tried, and the prop slides along the road when the kerb is
	# taken: a prop is only dropped when there is really no room for it.
	for side in [outward, -outward]:
		for slide in [0.0, 2.0, -2.0, 4.5, -4.5, 7.0, -7.0, 11.0, -11.0]:
			var candidate: Vector3 = road_centre + right * (side * distance) + tangent * slide
			candidate.y = position.y
			if _is_free(candidate, height, dressed):
				return candidate
	return null


## True when a prop may stand at the point: not on a carriageway, not in a junction, not inside
## a site and not under a deck.
func _is_free(position: Vector3, height: float, dressed: bool = false) -> bool:
	if not dressed:
		if _in_junction(position):
			return false
		if _in_site(position):
			return false
	var near: Dictionary = _probe.query(position, QUERY_RADIUS)
	if _probe.on_carriageway(position, near, LANE_MARGIN, MIN_CARRIAGEWAY):
		return false
	if _under_deck(near, position, height):
		return false
	return true


## True when a deck runs over the point (the prop would grow through it).
func _under_deck(near: Dictionary, position: Vector3, height: float) -> bool:
	if height <= 0.0:
		return false
	var indices: PackedInt32Array = near["lanes"]
	var distances: PackedFloat32Array = near["distances"]
	var heights: PackedFloat32Array = near["heights"]
	for i in indices.size():
		if heights[i] <= position.y + LEVEL_TOLERANCE:
			continue
		if heights[i] > position.y + height:
			continue
		if distances[i] < DECK_CLEARANCE:
			return true
	return false


func _in_junction(position: Vector3) -> bool:
	var cx := int(floor(position.x / JUNCTION_CELL))
	var cz := int(floor(position.z / JUNCTION_CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := "%d_%d" % [cx + dx, cz + dz]
			if not _junction_cells.has(key):
				continue
			for point in _junction_cells[key] as Array:
				if Vector2(point.x - position.x, point.z - position.z).length() < JUNCTION_CLEARANCE:
					return true
	return false


func _in_site(position: Vector3) -> bool:
	for site in _sites:
		var centre: Vector3 = site["position"]
		var size: Vector2 = site["size"]
		var half := size * 0.5 + Vector2(SITE_CLEARANCE, SITE_CLEARANCE)
		if absf(position.x - centre.x) <= half.x and absf(position.z - centre.z) <= half.y:
			return true
	return false


## True when the point stands on a lane of the same level (the gantry posts).
func on_lane(position: Vector3) -> bool:
	return _probe.on_carriageway(position)


## The direction of the road at a point (the props slide along it when the kerb is taken).
func tangent_at(position: Vector3, road: String = "") -> Vector3:
	if _probe == null:
		return Vector3.FORWARD
	var near: Dictionary = _probe.query(position, QUERY_RADIUS)
	var index := _probe.nearest_lane(near, position, road)
	if index < 0:
		index = _probe.nearest_any(near, position)
	if index < 0:
		return Vector3.FORWARD
	var info: Dictionary = _probe.grid.detail(index, position)
	var tangent: Vector3 = info["tangent"]
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		return Vector3.FORWARD
	return tangent.normalized()


## The horizontal unit vector from a point to the nearest lane of `road` (the side of the road the point is on), or ZERO.
func road_side(position: Vector3, road: String = "") -> Vector3:
	if _probe == null:
		return Vector3.ZERO
	var near: Dictionary = _probe.query(position, QUERY_RADIUS * 2.0)
	var index := _probe.nearest_lane(near, position, road)
	if index < 0:
		index = _probe.nearest_any(near, position)
	if index < 0:
		return Vector3.ZERO
	var info: Dictionary = _probe.grid.detail(index, position)
	var toward: Vector3 = (info["point"] as Vector3) - position
	toward.y = 0.0
	if toward.length_squared() < 0.0001:
		return Vector3.ZERO
	return toward.normalized()


## True when no lane runs within `clearance` of the footprint of a box prop: the perimeter of the box (size = x, y, z of the
## box, turned with the yaw of `xform`) is sampled every FOOTPRINT_STEP metres. A box is as long as 8 m (a shelter) or 30 m (a
## noise wall): the origin that stands clear of the lanes does not say that the ends do.
func footprint_clear(xform: Transform3D, size: Vector3, clearance: float) -> bool:
	if _probe == null:
		return true
	var turn := Basis(Vector3.UP, atan2(-xform.basis.x.z, xform.basis.x.x))
	var half := Vector2(size.x, size.z) * 0.5
	var steps_x := maxi(int(ceil(size.x / FOOTPRINT_STEP)), 1)
	var steps_z := maxi(int(ceil(size.z / FOOTPRINT_STEP)), 1)
	for i in steps_x + 1:
		var x := -half.x + size.x * float(i) / float(steps_x)
		for z in [-half.y, half.y]:
			if not _probe.clear_of_lanes(xform.origin + turn * Vector3(x, 0.0, z), clearance):
				return false
	for j in range(1, steps_z):
		var z := -half.y + size.z * float(j) / float(steps_z)
		for x in [-half.x, half.x]:
			if not _probe.clear_of_lanes(xform.origin + turn * Vector3(x, 0.0, z), clearance):
				return false
	return true


## True when the point stands on a carriageway.
func on_carriageway(position: Vector3) -> bool:
	return _probe.on_carriageway(position, {}, LANE_MARGIN, MIN_CARRIAGEWAY)


## True when no lane runs within `clearance` of the point.
func clear_of_lanes(position: Vector3, clearance: float = MIN_CARRIAGEWAY) -> bool:
	if _probe == null:
		return true
	return _probe.clear_of_lanes(position, clearance)


## The half width of the carriageway of a road (from the lanes of the roads unit).
func half_width(road: String) -> float:
	return float(_half_width.get(road, 0.0))


## The roads that have lanes.
func half_widths() -> Array:
	return _half_width.keys()


## The number of props rejected per kind and per reason.
func rejected() -> Dictionary:
	return _rejected


## The number of props that were pushed out of the carriageway.
func relocated() -> int:
	return _relocated


func _reject(kind: String, reason: String) -> void:
	var key := "%s (%s)" % [kind, reason]
	_rejected[key] = int(_rejected.get(key, 0)) + 1


static func _cell_key(point: Vector3) -> String:
	return "%d_%d" % [int(floor(point.x / JUNCTION_CELL)), int(floor(point.z / JUNCTION_CELL))]
