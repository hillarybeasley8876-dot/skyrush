extends RefCounted
## The contacts of the unit (dossier §7.2): the pairs of cars that have met.
##
## Both cars report the same contact (the vehicle unit and the traffic unit), so a pair
## is only resolved once: a report that lands in the same physics step (or the one after
## it) is the same contact. A car that leaves the world takes its contacts with it.

## How many physics frames two reports of the same contact may be apart.
const DEDUPE_FRAMES := 1
## How long a contact of a pair is remembered (the pairs that are long gone are dropped).
const PAIR_MEMORY := 1.0


## One resolved contact of a pair of cars: the frame it happened in, the time and the two
## cars.
class Pair:
	extends RefCounted
	var frame: int = -100
	var time: float = 0.0
	var a: int = 0
	var b: int = 0

	func _init(p_frame: int = -100, p_time: float = 0.0, p_a: int = 0, p_b: int = 0) -> void:
		frame = p_frame
		time = p_time
		a = p_a
		b = p_b

	func holds(id: int) -> bool:
		return a == id or b == id


## The contacts, by the key of the pair.
var _pairs: Dictionary = {}


## Starts a contact of two cars. It returns the time since the last contact of the pair
## (the grind against a wall is counted once per step) and -1.0 when the pair has already
## been resolved in this frame: the same contact must not be counted twice.
func begin(a: Node3D, b: Node3D, frame: int, now: float) -> float:
	var key := key_of(a, b)
	var last := _pairs.get(key, null) as Pair
	if last != null and frame - last.frame <= DEDUPE_FRAMES:
		return -1.0
	var elapsed := now - (last.time if last != null else now)
	_pairs[key] = Pair.new(frame, now, a.get_instance_id(), b.get_instance_id())
	return elapsed


## The contacts of the pairs that are long gone (the state must not leak).
func prune(now: float) -> void:
	for key: String in _pairs.keys():
		var entry := _pairs.get(key, null) as Pair
		if entry != null and now - entry.time > PAIR_MEMORY:
			_pairs.erase(key)


## The contacts of a car that left the world.
func forget(id: int) -> void:
	for key: String in _pairs.keys():
		var entry := _pairs.get(key, null) as Pair
		if entry != null and entry.holds(id):
			_pairs.erase(key)


## The number of the contacts (for the leak test).
func count() -> int:
	return _pairs.size()


## The key of a pair of cars.
func key_of(a: Node3D, b: Node3D) -> String:
	var ia := a.get_instance_id()
	var ib := b.get_instance_id()
	return "%d|%d" % [mini(ia, ib), maxi(ia, ib)]
