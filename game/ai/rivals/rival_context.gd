class_name RivalContext
extends RefCounted
## The state every rival needs for one tick, filled by the rival director.
##
## The brain never looks for other cars itself: the director collects the traffic, the rivals
## and the player once per tick, so six rivals do not scan the scene six times.

## The player car (may be null in a headless test).
var player: VehicleBase = null
## The player's position on the racing line (unwrapped, in metres).
var player_travelled: float = 0.0
## The player's offset on the racing line (m).
var player_offset: float = 0.0
## The distance every car has covered on the racing line (m), keyed by the instance id.
##
## The cars of the field share one line, so the distance they have covered orders them: a car
## that is ahead on the line is ahead of the other one. The distance is measured on the line
## and not along the tangent of a car, or two cars that stand side by side would each see the
## other as the car in front (a deadlock that no car can get out of).
var travelled: Dictionary = {}
## How much of the race is over (0..1). The rubber band is off in the last 10 %.
var race_fraction: float = 0.0
## The traffic cars of the world.
var traffic: Array[VehicleBase] = []
## The other rivals.
var rivals: Array[VehicleBase] = []
## True while the cars wait on the start grid.
var on_grid: bool = true
## The seconds since the race started.
var elapsed: float = 0.0
## The cars every rival has to keep clear of, keyed by the instance id of the rival.
## The list is rebuilt at 10 Hz by the director.
var near: Dictionary = {}


## The cars near one rival (the rivals and the traffic within the range of the director).
func near_of(car: Node3D) -> Array[Node3D]:
	if car == null:
		return [] as Array[Node3D]
	return near.get(car.get_instance_id(), [] as Array[Node3D]) as Array[Node3D]


## The distance a car has covered on the racing line (m).
##
## The traffic of the city does not drive on the racing line: it gets the distance of the
## leader of the line, and the frame of the tangent of the rival is used for it instead.
func travelled_of(node: Node3D) -> float:
	if node == null:
		return 0.0
	return float(travelled.get(node.get_instance_id(), 0.0))
