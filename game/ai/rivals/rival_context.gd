class_name RivalContext
extends RefCounted
## The state every rival needs for one tick, filled by the rival director.
##
## The brain never looks for other cars itself: the director collects the traffic, the rivals
## and the player once per tick, so six rivals do not scan the scene six times.

const LEVEL := 4.0   ## m: the height difference under which two cars are on the same level

## The empty list of a rival without near cars (it is shared: it is never written to).
static var _empty: Array[Node3D] = [] as Array[Node3D]

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
## The frame of the line at the place of every car that drives on it (the point of the
## line and its right vector).
##
## The frame of a place on the line does not change while the line is the same: it is
## measured again only when the car drives on. Every rival of the field measures the side
## of the other cars from it, and the side of a car is the same for all of them.
var _frames: Dictionary = {}
## The frames of the line (7 numbers per car: the offset, the point and the right vector).
var _frame_data: PackedFloat64Array = PackedFloat64Array()


## The side of a car that drives on the racing line (m, positive = to the right).
##
## The side is measured from the line at the place of the car: the cars of the field are
## compared on the same ribbon. The frame of the place is kept: it is the same for every
## rival of the field, and it is measured again only when the car drives on.
func lateral_of(node: Node3D, line: RivalLine, offset: float) -> float:
	var id := node.get_instance_id()
	var slot: int = int(_frames.get(id, -1))
	if slot < 0:
		# The car has no frame yet: it gets a slot of its own.
		slot = _frame_data.size() / 7
		_frame_data.resize((slot + 1) * 7)
		_frames[id] = slot
	var base := slot * 7
	if _frame_data[base] != offset:
		# The car drove on: the frame of its place on the line is measured again.
		_frame_data[base] = offset
		var point := line.point_at(offset)
		var right := line.right_at(offset)
		_frame_data[base + 1] = point.x
		_frame_data[base + 2] = point.y
		_frame_data[base + 3] = point.z
		_frame_data[base + 4] = right.x
		_frame_data[base + 5] = right.y
		_frame_data[base + 6] = right.z
	var here := Vector3(_frame_data[base + 1], _frame_data[base + 2], _frame_data[base + 3])
	var right := Vector3(_frame_data[base + 4], _frame_data[base + 5], _frame_data[base + 6])
	return (node.global_position - here).dot(right)


## The cars near one rival (the rivals and the traffic within the range of the director).
func near_of(car: Node3D) -> Array[Node3D]:
	if car == null:
		return _empty
	return near.get(car.get_instance_id(), _empty) as Array[Node3D]


## The distance a car has covered on the racing line (m).
##
## The traffic of the city does not drive on the racing line: it gets the distance of the
## leader of the line, and the frame of the tangent of the rival is used for it instead.
func travelled_of(node: Node3D) -> float:
	if node == null:
		return 0.0
	return float(travelled.get(node.get_instance_id(), 0.0))


## True when two heights are on the same level.
##
## The map is not flat: the Yan'an street runs under the Yan'an deck, 10 m apart in height,
## and a car on the street below is not a car in front of a rival that drives on the deck.
static func same_level(y: float, other_y: float) -> bool:
	return absf(y - other_y) <= LEVEL


## True when two cars drive on the same level.
static func on_my_level(a: Node3D, b: Node3D) -> bool:
	return same_level(a.global_position.y, b.global_position.y)
