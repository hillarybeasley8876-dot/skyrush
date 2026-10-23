class_name DriveContext
extends RefCounted
## The state every AI car needs for one tick: the lane graph of the world, the shared per-lane
## car index, the player, the world itself and a clock.
##
## The traffic director owns one of these and hands it to the cars it spawns, so the car and the
## director never have to reference each other (no cyclic preload, no null checks per tick).

var graph: LaneGraph = null
## Cars of every AI unit, bucketed per lane. The director refills it at the start of each tick.
var hash: LaneHash = LaneHash.new()
## The player car (may be null in a headless test).
var player: VehicleBase = null
## The world the traffic drives in.
var world: WorldBase = null
## Shared random source, seeded per run.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Seconds since the context was created.
var time: float = 0.0
## Set by the unit when a race or pursuit is running (traffic density is scaled down).
var density_scale: float = 1.0
## The junction id of every lane of the world (empty when the lane has no junction).
var junctions: PackedStringArray = PackedStringArray()
## The cars that have a body (the near cars and the wrecks) by the cell of the plan they stand in: key = cell_key(x, z). The lane
## hash knows the cars of a LANE, so two cars of lanes that cross, merge or lie over each other never saw each other; this index
## is what they look at. The director refills it with the lane hash.
var cells: Dictionary = {}
const CELL := 12.0


func _init() -> void:
	rng.randomize()


## The traffic light state for the approach of `road_id` into `junction_id`
## (0 red, 1 amber, 2 green). Worlds without signals report green.
func signal_state(junction_id: StringName, road_id: StringName) -> int:
	if world == null:
		return 2
	return world.signal_state(junction_id, road_id)


## The speed of the car ahead, along the lane.
##
## A traffic car that is far away is frozen and moved by setting its transform, so its body
## reports a speed of zero. Its real speed is the one it drives with on its lane.
func speed_of(leader: VehicleBase, tangent: Vector3) -> float:
	if leader == null:
		return 0.0
	if leader is TrafficCar:
		return (leader as TrafficCar).speed
	return maxf(leader.linear_velocity.dot(tangent), 0.0)


## True when the lane ends at a traffic light.
func lane_has_signal(lane: int) -> bool:
	return lane >= 0 and lane < junctions.size() and junctions[lane] != ""


## The junction id of a lane, or an empty name when the lane does not end at a junction.
func junction_of(lane: int) -> StringName:
	if lane < 0 or lane >= junctions.size():
		return &""
	return StringName(junctions[lane])


## The key of the cell of the plan that contains (x, z).
static func cell_key(x: float, z: float) -> int:
	return (int(floor(x / CELL)) + 100000) * 200000 + (int(floor(z / CELL)) + 100000)


## The cars with a body in the 3 x 3 cells around (x, z).
func cars_around(x: float, z: float) -> Array:
	var out: Array = []
	var cx := int(floor(x / CELL))
	var cz := int(floor(z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := (cx + dx + 100000) * 200000 + (cz + dz + 100000)
			if cells.has(key):
				out.append_array(cells[key])
	return out
