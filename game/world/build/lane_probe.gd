extends RefCounted
## The lane queries of the world: the nearest lane around a point, the distance to it and
## whether a point stands on a carriageway.
##
## The grid of the lanes answers in microseconds, but the lanes that are near a point are
## measured on their curve: the grid approximates a curve with straight segments, so a tight
## curve can hide a lane from the fast query, and on a steep ramp the segment lies above or
## below the road.

const LaneSpatial := preload("res://world/api/lane_spatial.gd")

## How far the lanes are looked for around a point.
const QUERY_RADIUS := 8.0
## A lane this close to a point is measured on its curve, not on the segments of the grid.
const REFINE_RADIUS := 5.0
## Two lanes are on the same level when their heights are this close.
const LEVEL_TOLERANCE := 2.5

var grid: LaneSpatial
var lanes: Array[LanePath] = []


func setup(lanes: Array[LanePath], grid: LaneSpatial = null) -> void:
	if grid != null:
		self.grid = grid
		if lanes.is_empty():
			lanes = grid.lanes()
	else:
		self.grid = LaneSpatial.new()
		self.grid.build(lanes)
	self.lanes = lanes


## The lanes around a point.
func query(position: Vector3, radius: float = QUERY_RADIUS) -> Dictionary:
	return grid.query_near(position, radius)


## The lane of the query that is closest to the point and on the same level. The lanes of the
## road of a prop come first: a prop that stands on the carriageway of a crossing road would
## be pushed into the road it belongs to.
func nearest_lane(near: Dictionary, position: Vector3, road: String = "") -> int:
	var indices: PackedInt32Array = near["lanes"]
	var best := -1
	var best_distance := INF
	var fallback := -1
	var fallback_distance := INF
	for i in indices.size():
		var index := indices[i]
		var distance := float(near["distances"][i])
		var height := float(near["heights"][i])
		if distance < REFINE_RADIUS:
			var closest := grid.closest_point(index, position)
			height = closest.y
			distance = Vector2(closest.x - position.x, closest.z - position.z).length()
		if absf(height - position.y) > LEVEL_TOLERANCE:
			continue
		if distance < fallback_distance:
			fallback_distance = distance
			fallback = index
		if road != "" and String(lanes[index].road_id) != road:
			continue
		if distance < best_distance:
			best_distance = distance
			best = index
	if best >= 0:
		return best
	return fallback


## The lane of the query that is closest to the point, whatever road it belongs to.
func nearest_any(near: Dictionary, position: Vector3) -> int:
	var indices: PackedInt32Array = near["lanes"]
	var best := -1
	var best_distance := INF
	for i in indices.size():
		var index := indices[i]
		var distance := float(near["distances"][i])
		var height := float(near["heights"][i])
		if distance < REFINE_RADIUS:
			var closest := grid.closest_point(index, position)
			height = closest.y
			distance = Vector2(closest.x - position.x, closest.z - position.z).length()
		if absf(height - position.y) > LEVEL_TOLERANCE:
			continue
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


## The distance of a lane in the result of the fast query, measured on the curve when the
## lane is near the point.
func distance_of(near: Dictionary, lane_index: int, position: Vector3 = Vector3.ZERO) -> float:
	var indices: PackedInt32Array = near["lanes"]
	var distances: PackedFloat32Array = near["distances"]
	for i in indices.size():
		if indices[i] == lane_index:
			if distances[i] >= REFINE_RADIUS:
				return distances[i]
			return grid.closest_distance(lane_index, position)
	return INF


## True when a lane of the same level runs through the point. The margin is the space that
## still counts as carriageway next to the edge of a lane.
## `min_edge` is the smallest distance to a lane centre that still counts as carriageway: a
## narrow lane would otherwise be too close to the road.
func on_carriageway(position: Vector3, near: Dictionary = {}, margin: float = 0.55,
		min_edge: float = 0.0) -> bool:
	if near.is_empty():
		near = query(position)
	var indices: PackedInt32Array = near["lanes"]
	for i in indices.size():
		var index := indices[i]
		var distance := float(near["distances"][i])
		var height := float(near["heights"][i])
		if distance < REFINE_RADIUS:
			var closest := grid.closest_point(index, position)
			height = closest.y
			distance = Vector2(closest.x - position.x, closest.z - position.z).length()
		if absf(height - position.y) > LEVEL_TOLERANCE:
			continue
		if distance < maxf(lanes[index].lane_width * 0.5 + margin, min_edge):
			return true
	return false


## True when no lane runs within `clearance` of the point. The distance is measured on the
## curve of the lane, not on the straight segments of the grid: a tight curve hides a lane
## from the fast query, and a prop that stands on it has to be moved.
func clear_of_lanes(position: Vector3, clearance: float = 2.4) -> bool:
	var near: Dictionary = query(position, QUERY_RADIUS * 2.0)
	var indices: PackedInt32Array = near["lanes"]
	for i in indices.size():
		var index := indices[i]
		var detail: Dictionary = grid.detail(index, position)
		if absf((detail["point"] as Vector3).y - position.y) > LEVEL_TOLERANCE:
			continue
		if float(detail["distance"]) < clearance:
			return false
	return true


## True when the point stands on the median lane of its road and on no other lane of it: the
## median of a road is the gap between its two carriageways.
func on_the_median(near: Dictionary, position: Vector3, lane_index: int) -> bool:
	var indices: PackedInt32Array = near["lanes"]
	for i in indices.size():
		if indices[i] == lane_index:
			continue
		if absf(float(near["heights"][i]) - position.y) > LEVEL_TOLERANCE:
			continue
		if distance_of(near, indices[i], position) < lanes[indices[i]].lane_width * 0.5 + 0.55:
			return false
	return true


## True when a lane of another road runs through the point (a ramp that splits off from the
## median of a road).
func on_another_road(near: Dictionary, position: Vector3, road: String) -> bool:
	var indices: PackedInt32Array = near["lanes"]
	for i in indices.size():
		if absf(float(near["heights"][i]) - position.y) > LEVEL_TOLERANCE:
			continue
		if road != "" and String(lanes[indices[i]].road_id) == road:
			continue
		if distance_of(near, indices[i], position) < lanes[indices[i]].lane_width * 0.5 + 0.55:
			return true
	return false
