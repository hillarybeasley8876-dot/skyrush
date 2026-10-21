extends RefCounted
const LaneSpatial := preload("res://world/api/lane_spatial.gd")
## The shortest lane path between two points, over the `next_lanes` graph of the lanes.
## The search is a Dijkstra over the lanes: the cost of a lane is the distance from its closest
## point to the target, so the path follows the direction of the traffic and never reverses.

const MAX_EXPANSIONS := 20000
## The tangent of the start lane has to agree with the direction of the gate.
const TANGENT_AGREEMENT := 0.7
## How far from the junction the crossing of two lanes is searched.
const JUNCTION_SEARCH := 40.0
## The lanes within this distance of a gate can serve it.
const GATE_RADIUS := 8.0
## The tangent of a lane has to agree with the gate by this much.
const GATE_TANGENT := 0.3
## The lane closest to a point.
func closest_lane(lanes: Array[LanePath], point: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for i in lanes.size():
		var lane := lanes[i]
		if lane.curve == null:
			continue
		var offset := closest_offset(lane, point)
		var closest := lane.curve.sample_baked(offset, true)
		var distance := Vector2(closest.x - point.x, closest.z - point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## The lanes that can serve a gate: the ones within GATE_RADIUS of it whose direction agrees
## with the gate (-Z). The gate of a route is often on the boundary between two lanes, so
## every candidate is a possible start.
func gate_lanes(lanes: Array[LanePath], grid: LaneSpatial, gate: Transform3D,
		radius: float = GATE_RADIUS) -> Array[int]:
	var out: Array[int] = []
	if grid == null:
		return out
	var near: Dictionary = grid.query(gate.origin, radius)
	var forward := -gate.basis.z
	for index in near.keys():
		var info: Dictionary = near[index]
		var tangent: Vector3 = info["tangent"]
		if tangent.length_squared() < 0.0001:
			continue
		if forward.length_squared() > 0.0001:
			if tangent.normalized().dot(forward.normalized()) < GATE_TANGENT:
				continue
		out.append(index)
	out.sort()
	return out


## The point of the lane closest to `point`.
func closest_point(lane: LanePath, point: Vector3) -> Vector3:
	if lane.curve == null:
		return point
	var offset := closest_offset(lane, point)
	return lane.curve.sample_baked(offset, true)


## The offset (metres along the curve) of the point of the lane closest to `point`.
func closest_offset(lane: LanePath, point: Vector3) -> float:
	if lane.curve == null:
		return 0.0
	return lane.curve.get_closest_offset(point)
## The lane sequence from `start` to the lane closest to `target`.
func find(lanes: Array[LanePath], start: int, target: Vector3) -> Array[int]:
	var out: Array[int] = []
	if start < 0 or start >= lanes.size():
		return out
	var dist: Dictionary = {start: 0.0}
	var previous: Dictionary = {}
	var visited: Dictionary = {}
	var expansions := 0
	var current := start
	while current >= 0 and expansions < MAX_EXPANSIONS:
		expansions += 1
		visited[current] = true
		out.append(current)
		if _lane_distance(lanes[current], target) < 25.0:
			break
		var best := -1
		var best_cost := INF
		for next_index in lanes[current].next_lanes:
			if visited.has(next_index) or next_index >= lanes.size():
				continue
			if _goes_backwards(lanes[current], lanes[next_index], target):
				continue
			var cost: float = float(dist[current]) + _step_cost(lanes[current], lanes[next_index], target)
			if not dist.has(next_index) or cost < float(dist[next_index]):
				dist[next_index] = cost
				previous[next_index] = current
			if float(dist[next_index]) < best_cost:
				best_cost = float(dist[next_index])
				best = next_index
		current = best
	return out


## The shortest lane path from any of the sources to any of the targets. A real Dijkstra with
## a heap, so a leg of a route picks the best of the lanes around its gates.
## The lanes are only driven in their own direction: a line that drives against the traffic
## is worse than a leg that is reported.
func find_multi(lanes: Array[LanePath], sources: Array[int], targets: Array[int],
		target_point: Vector3 = Vector3.INF) -> Array[int]:
	if sources.is_empty() or targets.is_empty():
		return []
	# The search does not wander further than the straight way to the target: without the cap
	# every leg of every route walks the whole lane network of the city.
	var limit := INF
	if target_point != Vector3.INF:
		limit = _source_distance(lanes, sources, target_point) * 2.5 + 400.0
	var dist: Dictionary = {}
	var previous: Dictionary = {}
	var done: Dictionary = {}
	for source in sources:
		if not dist.has(source) or 0.0 < float(dist[source]):
			dist[source] = 0.0
	var heap: Array = []
	for source in sources:
		_push(heap, [0.0, source])
	while not heap.is_empty():
		var best := _pop(heap)
		var index: int = best[1]
		if done.has(index):
			continue
		if float(best[0]) > limit:
			break
		done[index] = true
		if targets.has(index):
			return _rebuild(previous, index)

		var lane := lanes[index]
		if lane == null:
			continue
		var cost: float = float(dist.get(index, INF))
		for next_index in lane.next_lanes:
			if done.has(next_index) or next_index >= lanes.size():
				continue
			for neighbour in lanes[index].next_lanes:
				if neighbour >= lanes.size():
					continue
				var step := cost + _link_cost(lanes[index], lanes[neighbour])
				if not dist.has(neighbour) or step < float(dist[neighbour]):
					dist[neighbour] = step
					previous[neighbour] = index
					_push(heap, [step, neighbour])
	return []


## The path from the sources to the lane that comes closest to the target: the fallback of a
## leg whose target cannot be reached on the lane network.
func find_closest(lanes: Array[LanePath], sources: Array[int],
		target_point: Vector3) -> Array[int]:
	if sources.is_empty() or target_point == Vector3.INF:
		return []
	var limit := _source_distance(lanes, sources, target_point) * 2.5 + 400.0
	var dist: Dictionary = {}
	var previous: Dictionary = {}
	var done: Dictionary = {}
	var heap: Array = []
	for source in sources:
		dist[source] = 0.0
		heap.append([0.0, source])
	var closest := -1
	var closest_distance := INF
	while not heap.is_empty():
		var best := _pop(heap)
		var index: int = best[1]
		if done.has(index):
			continue
		done[index] = true
		var distance := _lane_distance(lanes[index], target_point)
		if distance < closest_distance:
			closest_distance = distance
			closest = index
		if float(dist.get(index, INF)) > limit:
			break
		var cost: float = float(dist.get(index, INF))
		for next_index in lanes[index].next_lanes:
			if done.has(next_index) or next_index >= lanes.size():
				continue
			var step := cost + _link_cost(lanes[index], lanes[next_index])
			if not dist.has(next_index) or step < float(dist[next_index]):
				dist[next_index] = step
				previous[next_index] = index
				_push(heap, [step, next_index])
	if closest < 0:
		return []
	return _rebuild(previous, closest)


## The distance from the sources to a point (the straight way).
func _source_distance(lanes: Array[LanePath], sources: Array[int], point: Vector3) -> float:
	var best := INF
	for index in sources:
		best = minf(best, _lane_distance(lanes[index], point))
	return best


## The cost of the step from one lane to the next: the turn plus the length of the lane that is
## entered. Without the length of the lane, a path of many short lanes would look cheaper than
## the straight way, even when it drives around the block.
func _link_cost(from: LanePath, to: LanePath) -> float:
	if from.curve == null or to.curve == null:
		return 1.0
	var a := from.curve.get_point_position(from.curve.get_point_count() - 1)
	var b := to.curve.get_point_position(0)
	var turn := Vector2(a.x - b.x, a.z - b.z).length()
	return maxf(turn, 0.0) + to.curve.get_baked_length()


## The lane sequence that leads to `index`.
func _rebuild(previous: Dictionary, index: int) -> Array[int]:
	var out: Array[int] = []
	var current := index
	var guard := 0
	while current >= 0 and guard < MAX_EXPANSIONS:
		guard += 1
		out.append(current)
		if not previous.has(current):
			break
		current = int(previous[current])
	out.reverse()
	return out


## The cheapest entry of the heap (a binary heap: a linear scan made the routes of the city
## take 20 s).
func _pop(heap: Array) -> Array:
	var entry: Array = heap[0]
	var last: Array = heap[heap.size() - 1]
	heap.remove_at(heap.size() - 1)
	if heap.is_empty():
		return entry
	heap[0] = last
	_sift_down(heap, 0)
	return entry


## Puts an entry into the heap.
func _push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	_sift_up(heap, heap.size() - 1)


## Moves an entry up until its parent is not dearer.
func _sift_up(heap: Array, index: int) -> void:
	var entry: Array = heap[index]
	while index > 0:
		var parent := (index - 1) / 2
		if float((heap[parent] as Array)[0]) <= float(entry[0]):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = entry


## Moves an entry down until both of its children are not cheaper.
func _sift_down(heap: Array, index: int) -> void:
	var size := heap.size()
	var entry: Array = heap[index]
	while true:
		var left := index * 2 + 1
		if left >= size:
			break
		var smallest := left
		var right := left + 1
		if right < size and float((heap[right] as Array)[0]) < float((heap[left] as Array)[0]):
			smallest = right
		if float(entry[0]) <= float((heap[smallest] as Array)[0]):
			break
		heap[index] = heap[smallest]
		index = smallest
	heap[index] = entry


## True when the step from one lane to the next drives away from the target (a U-turn).
func _goes_backwards(from: LanePath, to: LanePath, target: Vector3) -> bool:
	var from_point := _closest_point(from, target)
	var to_point := _closest_point(to, target)
	var step := to_point - from_point
	var goal := target - from_point
	if step.length_squared() < 0.01 or goal.length_squared() < 0.01:
		return false
	return step.normalized().dot(goal.normalized()) < -0.2


## The cost of driving from one lane to the next: the way to the target through both.
func _step_cost(from: LanePath, to: LanePath, target: Vector3) -> float:
	var from_point := _closest_point(from, target)
	var to_point := _closest_point(to, target)
	return from_point.distance_to(to_point)


func _lane_distance(lane: LanePath, target: Vector3) -> float:
	return _closest_point(lane, target).distance_to(target)


func _closest_point(lane: LanePath, target: Vector3) -> Vector3:
	if lane.curve == null:
		return target
	var offset := closest_offset(lane, target)
	return lane.curve.sample_baked(offset, true)
