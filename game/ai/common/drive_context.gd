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
