extends RefCounted
## The start grid of a route: two columns on two lanes of the same direction and three rows
## behind the start line. Every slot sits on a lane centre and faces the lane.
##
## The grid is built from the first checkpoint of the route (the one that has been turned
## towards the next checkpoint), so the slots lie behind the start line of the race and not
## behind the heading of the city description (which points the wrong way on three routes).
## When the road of the start has no second lane far enough from the first one, the grid is a
## single file of six slots.

const LanePathFinder := preload("res://world/api/lane_path_finder.gd")
const Heading := preload("res://world/api/heading.gd")
const LaneSpatial := preload("res://world/api/lane_spatial.gd")
const LevelRules := preload("res://world/api/level_rules.gd")

## The distance between two rows of the grid.
const GRID_ROW := 8.0
## The two columns of the grid are at least this far apart.
const GRID_COLUMN := 5.5
## The number of rows of a grid with two columns.
const GRID_ROWS := 3
## The number of slots a grid has at least.
const MIN_SLOTS := 6
## The number of rows that are tried when the road has no room.
const MAX_ROWS := 12
## The height of a slot above the lane.
const GRID_LIFT := 0.6
## How far the lanes around the start line are looked for.
const SEARCH_RADIUS := 30.0
## Two slots of the grid are at least this far apart.
const MIN_SLOT_GAP := 5.0
## The two columns of the grid have to start at the same place (the rows line up).
const ALIGN_WINDOW := 8.0


## The grid of a route: the anchor of the city description is expanded into the slots.
static func build(lanes: Array[LanePath], grid: LaneSpatial, raw: Variant,
		checkpoints: Array[Transform3D]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var anchor: Variant = null
	if not checkpoints.is_empty():
		# The first checkpoint faces the next one, so the grid lies behind the start line.
		anchor = checkpoints[0]
	if anchor == null:
		anchor = _anchor_transform(raw)
	if anchor == null:
		return out
	var finder := LanePathFinder.new()
	var columns := _columns(lanes, grid, anchor)
	if columns.is_empty():
		return [_slot(anchor, Vector3.ZERO)]
	var previous := _previous_lanes(lanes)
	var previous_any := _previous_lanes_any(lanes)
	var rows := GRID_ROWS
	while rows <= MAX_ROWS:
		out = _thin(_slots(lanes, columns, anchor, rows, finder, previous, previous_any))
		if out.size() >= MIN_SLOTS:
			break
		rows += 1
	if out.is_empty():
		out.append(_slot(anchor, Vector3.ZERO))
	return out


## The slots of the grid: the rows behind the anchor on every column.
static func _slots(lanes: Array[LanePath], columns: Array[int], anchor: Transform3D, rows: int,
		finder: LanePathFinder, previous: Dictionary, previous_any: Dictionary) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for row in rows:
		for column in columns:
			var slot: Variant = _slot_on_lane(lanes, column, anchor, row, finder, previous,
				previous_any)
			if slot != null:
				out.append(slot)
	return out


## The slots that are too close to another slot are dropped (a grid slot is a car).
static func _thin(slots: Array[Transform3D]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for slot in slots:
		var clear := true
		for other in out:
			if slot.origin.distance_to(other.origin) < MIN_SLOT_GAP:
				clear = false
				break
		if clear:
			out.append(slot)
	return out


## The anchor of the grid of the city description.
static func _anchor_transform(raw: Variant) -> Variant:
	if not raw is Array:
		return null
	var list := raw as Array
	if list.is_empty():
		return null
	if list[0] is Array:
		var first := list[0] as Array
		if first.size() >= 3:
			return Transform3D(Basis(Vector3.UP, Heading.yaw_from_heading(
				float(first[3]) if first.size() >= 4 else 0.0)),
				Vector3(float(first[0]), float(first[1]), float(first[2])))
		return null
	if list.size() >= 3:
		return Transform3D(Basis(Vector3.UP, Heading.yaw_from_heading(
			float(list[3]) if list.size() >= 4 else 0.0)),
			Vector3(float(list[0]), float(list[1]), float(list[2])))
	return null


## The two lanes of the grid: the ones around the start line that drive the way of the route.
static func _columns(lanes: Array[LanePath], grid: LaneSpatial, anchor: Transform3D) -> Array[int]:
	if grid == null:
		return []
	# The lanes of the level of the anchor only: the start of a route on the deck must not be
	# placed on the frontage street under it.
	var near: Dictionary = grid.query(anchor.origin, SEARCH_RADIUS, anchor.origin.y, LevelRules.LEVEL)
	var forward := -anchor.basis.z
	var candidates: Array[Dictionary] = []
	for index in near.keys():
		var info: Dictionary = grid.detail(int(index), anchor.origin)
		var tangent: Vector3 = info["tangent"]
		if tangent.length_squared() < 0.0001:
			continue
		if forward.length_squared() > 0.0001:
			if tangent.normalized().dot(forward.normalized()) < 0.5:
				continue
		candidates.append({
			"index": int(index),
			# The distance along the lane (the lane that ends at the start line has no room)
			"offset": float(info["offset"]),
			"point": info["point"],
			"tangent": tangent,
		})
	if candidates.is_empty():
		return []
	# The lane that reaches furthest past the start line comes first: it has the most room
	# behind it for the rows of the grid.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["offset"]) > float(b["offset"]))
	var pair := _column_pair(lanes, candidates)
	if pair.size() == 2:
		return pair
	return [int(candidates[0]["index"])]


## The second column of the grid: a lane that runs next to the first one, far enough from it
## to hold a car, and that starts at the same place (so the rows of the two columns line up).
static func _column_pair(lanes: Array[LanePath], candidates: Array[Dictionary]) -> Array[int]:
	if candidates.is_empty():
		return []
	var primary := candidates[0]
	var best: Array[int] = []
	var best_gap := INF
	for i in candidates.size():
		var b := candidates[i]
		if absf(float(b["offset"]) - float(primary["offset"])) > ALIGN_WINDOW:
			continue
		var tangent: Vector3 = primary["tangent"]
		if tangent.normalized().dot((b["tangent"] as Vector3).normalized()) < 0.9:
			continue  # the lanes do not run in the same direction
		var gap := _gap(lanes, primary, b)
		if gap < GRID_COLUMN or gap >= best_gap:
			continue
		best_gap = gap
		best = [int(primary["index"]), int(b["index"])]
	return best


## The distance between two lanes across the road.
static func _gap(lanes: Array[LanePath], a: Dictionary, b: Dictionary) -> float:
	var first := int(a["index"])
	var second := int(b["index"])
	if first < lanes.size() and second < lanes.size():
		if String(lanes[first].road_id) == String(lanes[second].road_id):
			# The same road: the offset of a lane is its distance from the centre line.
			return absf(_offset_of(lanes, first) - _offset_of(lanes, second))
	var tangent: Vector3 = a["tangent"]
	var right := Vector3(-tangent.z, 0.0, tangent.x)
	var between: Vector3 = (b["point"] as Vector3) - (a["point"] as Vector3)
	return absf(between.dot(right))


## The lateral offset of a lane from the centre line of its road.
static func _offset_of(lanes: Array[LanePath], index: int) -> float:
	if index < 0 or index >= lanes.size():
		return 0.0
	return float(lanes[index].get_meta("offset", 0.0))


## One slot of the grid: the point of the road `row` rows behind the anchor. The walk back
## follows the lanes of the road, so the slots are on the road and not on the next lane.
static func _slot_on_lane(lanes: Array[LanePath], index: int, anchor: Transform3D, row: int,
		finder: LanePathFinder, previous: Dictionary, previous_any: Dictionary) -> Variant:
	var lane_index := index
	var offset := finder.closest_offset(lanes[index], anchor.origin)
	var back := GRID_ROW * float(row + 1)
	while back > 0.0:
		if offset - back >= 0.5:
			offset -= back
			back = 0.0
			break
		back -= offset
		var earlier: int = int(previous.get(lane_index, -1))
		if earlier < 0:
			# The lane is the first of its road: the walk back continues on the road the lane
			# comes from (a lane of a junction).
			earlier = int(previous_any.get(lane_index, -1))
		if earlier < 0:
			return null
		lane_index = earlier
		offset = _length(lanes[lane_index])
	if back > 0.0:
		return null
	var lane := lanes[lane_index]
	if lane == null or lane.curve == null:
		return null
	var length := lane.curve.get_baked_length()
	var point := lane.curve.sample_baked(clampf(offset, 0.0, length), true)
	var ahead := lane.curve.sample_baked(minf(offset + 4.0, length - 0.1), true)
	var direction := ahead - point
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	return Transform3D(Basis.looking_at(direction, Vector3.UP), point + Vector3.UP * GRID_LIFT)


## The lane that comes before every lane (the slots of the grid walk back along the road).
static func _previous_lanes(lanes: Array[LanePath]) -> Dictionary:
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


## The lane that comes before every lane, whatever road it belongs to (a lane of a junction
## continues on the road it comes from).
static func _previous_lanes_any(lanes: Array[LanePath]) -> Dictionary:
	var out: Dictionary = {}
	for i in lanes.size():
		for next_index in lanes[i].next_lanes:
			if next_index < 0 or next_index >= lanes.size():
				continue
			if out.has(next_index):
				continue
			out[next_index] = i
	return out


static func _length(lane: LanePath) -> float:
	if lane == null or lane.curve == null:
		return 0.0
	return lane.curve.get_baked_length()


## A slot at the anchor (the fallback when there is no lane).
static func _slot(anchor: Transform3D, offset: Vector3) -> Transform3D:
	return Transform3D(anchor.basis, anchor.origin + offset)
