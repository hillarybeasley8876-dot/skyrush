class_name PoliceDemoFreeze
extends RefCounted
## The moment the capture of the police demo shows (the tactic is there).
##
## The demo freezes the game tree as soon as the tactic of the scenario is on the road, so the
## capture at any later time shows that moment.

## The distance the player keeps to the block before the capture (m).
const BLOCK_DISTANCE := 25.0
## The distance the player keeps to the spike strip before the capture (m).
const STRIP_DISTANCE := 2.5
## The distance the head-on unit keeps to the player before the capture (m).
const HEAD_ON_DISTANCE := 80.0
## The seconds between the PIT contact and the capture.
const PIT_LAG := 0.5
## The seconds the chase, the drone and the toll closure need before the capture.
const CHASE_LAG := 4.0
const DRONE_LAG := 6.0
const TOLL_LAG := 6.0
## The side of the player the units of the box take (m).
const BOX_SIDE_MIN := 1.8
const BOX_SIDE_MAX := 3.6

var _pit_contact: float = -1.0


## True when the tactic of the scenario is on the road and the scene may be frozen.
func ready(scenario: StringName, director: PoliceDirector, player: VehicleBase,
		clock: float) -> bool:
	match scenario:
		&"pit":
			return _pit_ready(director, player, clock)
		&"box":
			return _box_formed(director, player)
		&"roadblock3", &"roadblock4":
			return _in_range(_block_distance(director, player), BLOCK_DISTANCE)
		&"spikes":
			return _in_range(_strip_distance(director, player), STRIP_DISTANCE)
		&"head_on":
			return _in_range(_head_on_distance(director, player), HEAD_ON_DISTANCE)
		&"drone":
			return clock > DRONE_LAG
		&"toll5":
			return clock > TOLL_LAG and not director.blockade.blocks.is_empty()
		&"chase":
			return clock > CHASE_LAG
	return false


## True when the distance is in the window of the capture.
func _in_range(distance: float, window: float) -> bool:
	return distance > 0.0 and distance <= window


## The PIT: the capture is made half a second after the unit touched the player.
func _pit_ready(director: PoliceDirector, player: VehicleBase, clock: float) -> bool:
	if _pit_contact < 0.0:
		if _units_touched(director, player) > 0:
			_pit_contact = clock
		return false
	return clock - _pit_contact >= PIT_LAG


## The number of units that touched the player.
func _units_touched(director: PoliceDirector, _player: VehicleBase) -> int:
	var count := 0
	for unit in director.units:
		if unit.player_contact > -50.0:
			count += 1
	return count


## True when the three units form the box around the player.
func _box_formed(director: PoliceDirector, player: VehicleBase) -> bool:
	var front := 0
	var sides := 0
	for unit in director.units:
		var rel := _relative(unit, player)
		if unit.role == PoliceFleet.Role.BOX_FRONT and rel.z < -5.0 and absf(rel.x) < 1.6:
			front += 1
		if unit.role == PoliceFleet.Role.BOX_SIDE and absf(rel.x) > BOX_SIDE_MIN \
				and absf(rel.x) < BOX_SIDE_MAX:
			sides += 1
	return front >= 1 and sides >= 2


## The position of a unit in the frame of the player (x = right, z = behind).
func _relative(unit: PoliceCar, player: VehicleBase) -> Vector3:
	var basis := player.global_transform.basis
	return basis.inverse() * (unit.global_position - player.global_position)


## The distance to the roadblock in front of the player (m).
func _block_distance(director: PoliceDirector, player: VehicleBase) -> float:
	if director.blockade.blocks.is_empty():
		return -1.0
	var block: PoliceRoadblock = director.blockade.blocks[0]
	return block.global_position.distance_to(player.global_position)


## The distance to the spike strip in front of the player (m).
func _strip_distance(director: PoliceDirector, player: VehicleBase) -> float:
	var best := -1.0
	for strip in director.strips:
		var distance := strip.global_position.distance_to(player.global_position)
		if best < 0.0 or distance < best:
			best = distance
	return best


## The distance to the head-on unit (m).
func _head_on_distance(director: PoliceDirector, player: VehicleBase) -> float:
	var best := -1.0
	for unit in director.units:
		if unit.role != PoliceFleet.Role.HEAD_ON:
			continue
		var distance := unit.global_position.distance_to(player.global_position)
		if best < 0.0 or distance < best:
			best = distance
	return best
