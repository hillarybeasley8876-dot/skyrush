class_name LaneHash
extends RefCounted
## The cars of a lane, bucketed by lane.
##
## The traffic director fills the hash every tick; the leader and the follower of any car are then
## found without an O(n) scan over every car (dossier 6.1: a car must never pass through its
## leader). Police and rivals can share the same helper.
##
## The index is a flat list of the cars and a linked list per lane. Nothing is allocated while
## the index is filled: the arrays grow once and are then reused for every tick. A lane holds a
## handful of cars, so the list is walked instead of sorted.
##
## The distances are float64 on purpose: a float32 would round the distance of a car down or up,
## and the car would then find ITSELF as its leader and brake to a stop.

## The first car of every lane (-1 when the lane is empty).
var _head: PackedInt32Array = PackedInt32Array()
## The generation of the last fill of every lane (a lane of an older generation is empty).
var _stamp: PackedInt32Array = PackedInt32Array()
## The next car of the same lane.
var _next: PackedInt32Array = PackedInt32Array()
## The distance of every car along its lane.
var _distance: PackedFloat64Array = PackedFloat64Array()
## The car of every entry.
var _object: Array = []
var _generation: int = 0
var _count: int = 0


## Empties the index. The lanes of the last fill are invalidated by the generation.
func clear() -> void:
	_generation += 1
	_count = 0


## Inserts `object` at `s` metres along `lane`.
##
## The cars of a lane are kept sorted by their distance: the leader of a car is then the first
## one that is further along the lane, and the lookup stops there. A lane with thirty cars on
## it (the test road) would otherwise walk the whole list for every car and every tick.
func insert(lane: int, s: float, obj: Object) -> void:
	_ensure_lane(lane)
	if _stamp[lane] != _generation:
		_stamp[lane] = _generation
		_head[lane] = -1
	if _count >= _next.size():
		_next.resize(_count + 64)
		_distance.resize(_count + 64)
		_object.resize(_count + 64)
	var index := _count
	_count += 1
	_distance[index] = s
	_object[index] = obj
	# The place of the car in the sorted list: the cars with the same distance are ordered by
	# their id, so the answer of the lookup is the same every time.
	var id := obj.get_instance_id() if obj != null else 0
	var previous := -1
	var current := _head[lane]
	while current >= 0 and _before(_distance[current], current, s, id):
		previous = current
		current = _next[current]
	_next[index] = current
	if previous < 0:
		_head[lane] = index
	else:
		_next[previous] = index


## True when the car of the list belongs before a car at `s` with the id `id`.
func _before(distance: float, index: int, s: float, id: int) -> bool:
	if distance < s:
		return true
	if distance > s:
		return false
	return _id_of(index) < id


## Number of cars in a lane.
func count(lane: int) -> int:
	var total := 0
	var i := _head_of(lane)
	while i >= 0:
		total += 1
		i = _next[i]
	return total


## The number of cars in the index.
func size() -> int:
	return _count


## The index of the car directly ahead of `s` in `lane` (-1 when the lane is clear ahead).
##
## The caller reads the distance and the car of the entry with `distance_at` and `object_at`,
## so it walks the list of the lane only once.
func leader_index(lane: int, s: float) -> int:
	return _leader_index(lane, s)


## The distance of the entry along the lane.
func distance_at(index: int) -> float:
	return _distance[index]


## The car of the entry.
func object_at(index: int) -> Object:
	return _object[index]


## The bucket entry of the car directly ahead of `s`: [distance along the lane, object].
## Empty when the lane is clear ahead. This allocates an array - the traffic uses the accessors
## below instead.
func leader_entry(lane: int, s: float) -> Array:
	var i := _leader_index(lane, s)
	if i < 0:
		return []
	return [_distance[i], _object[i]]


## The car directly ahead of `s` in `lane` (null when the lane is clear ahead).
func leader(lane: int, s: float) -> Object:
	var i := _leader_index(lane, s)
	return _object[i] if i >= 0 else null


## The car directly behind `s` in `lane` (null when nobody is behind).
func follower(lane: int, s: float) -> Object:
	var i := _follower_index(lane, s)
	return _object[i] if i >= 0 else null


## The distance along the lane to the leader's tail (m). INF when the lane ahead is clear.
##
## `own_length` is the length of the car asking, so the gap is bumper to bumper.
func leader_gap(lane: int, s: float, own_length: float) -> float:
	var distance := leader_distance(lane, s)
	return INF if is_inf(distance) else distance - own_length


## The distance along the lane to the leader (m). INF when the lane ahead is clear.
func leader_distance(lane: int, s: float) -> float:
	var i := _leader_index(lane, s)
	return INF if i < 0 else _distance[i] - s


## The distance along the lane to the car behind (m). INF when nobody is behind.
func follower_distance(lane: int, s: float) -> float:
	var i := _follower_index(lane, s)
	return INF if i < 0 else s - _distance[i]


## The car of the lane that is the closest one ahead of `s` (-1 when the lane is clear ahead).
##
## The cars of a lane are sorted, so the walk stops at the first car that is further along.
func _leader_index(lane: int, s: float) -> int:
	var i := _head_of(lane)
	while i >= 0 and _distance[i] <= s:
		i = _next[i]
	return i


## The car of the lane that is the closest one behind `s` (-1 when nobody is behind).
func _follower_index(lane: int, s: float) -> int:
	var best := -1
	var i := _head_of(lane)
	while i >= 0 and _distance[i] < s:
		best = i
		i = _next[i]
	return best


## True when a car of the lane stands between `from_s` and `to_s` (m along the lane).
##
## The traffic uses it at a junction: a car that merges into a lane that is occupied around the
## entry point has to wait, or the two cars meet in the junction box.
func any_in(lane: int, from_s: float, to_s: float) -> bool:
	var i := _head_of(lane)
	while i >= 0:
		var d := _distance[i]
		if d >= from_s and d <= to_s:
			return true
		i = _next[i]
	return false


## The id of the car of an entry, to break a tie between two cars at the same distance.
func _id_of(index: int) -> int:
	var obj: Object = _object[index]
	if obj == null:
		return 0
	return obj.get_instance_id()


## The first car of the lane (-1 when the lane is empty or was not filled this tick).
func _head_of(lane: int) -> int:
	if lane < 0 or lane >= _head.size():
		return -1
	if _stamp[lane] != _generation:
		return -1
	return _head[lane]


## Makes the arrays big enough for the lane.
func _ensure_lane(lane: int) -> void:
	if lane < 0:
		return
	if lane >= _head.size():
		var old := _head.size()
		_head.resize(lane + 64)
		_stamp.resize(lane + 64)
		# The new lanes are empty: the stamp of an older generation means "no cars".
		for i in range(old, _stamp.size()):
			_stamp[i] = _generation - 1
