class_name PoliceTactics
extends RefCounted
## The targets, the speeds and the numbers of the police roles (dossier §6.3).
##
## The module owns every magic number of the behaviour table; the car (PoliceCar) owns the
## driving and the state machine.

## The look-ahead of a patrolling unit (m).
const PATROL_LOOKAHEAD_MIN := 10.0
const PATROL_LOOKAHEAD_PER_SPEED := 0.6
const PATROL_LOOKAHEAD_MAX := 45.0
## The time lead of a pursuit (s).
const PURSUE_LEAD_MAX := 1.5
## The closing speed of a pursuit: this much per metre of the gap (m/s per m).
const PURSUE_CATCH_UP := 0.3
const PURSUE_CATCH_UP_MAX := 8.0
## A pursuing unit that is right behind the player keeps the pressure (m).
const PURSUE_PRESS_DISTANCE := 8.0
## The closing speed below which the unit takes its full time lead (m/s).
const PURSUE_LEAD_MIN_CLOSING := 0.5
## The clearance behind the player the PIT unit needs (m).
const PIT_REAR_CLEARANCE_MIN := -1.0
## The margin under the minimum PIT gap: the strike starts a little before the touch (m).
const PIT_GAP_MARGIN := 0.6
## The lowest speed the front unit of a box keeps when it is ahead of the player (m/s).
const BOX_FRONT_MIN_SPEED := 4.0
## The seconds before a unit takes its role (it settles first).
const ROLE_ENTER_DELAY := 0.3
## The ram: the unit has to be this far behind the player and this close to his centre line.
const RAM_DISTANCE := 12.0
const RAM_LATERAL := 3.0
## The lateral offset of the rear bumper the rammer aims at (m).
const RAM_OFFSET := 0.6
## How far behind the centre of the player the rammer aims (m).
const RAM_REAR := 2.4
## The extra speed of the ram, for RAM_BOOST seconds (m/s).
const RAM_PUSH := 6.0
const RAM_BOOST := 1.0
## The PIT: the line beside the player the unit drives on (m from the centre of the player).
const PIT_OFFSET := 3.4
## The line the unit moves in on for the strike (m from the centre of the player).
const PIT_STRIKE_OFFSET := 2.6
## How far behind the player the unit lines up (m) and where the strike happens (m).
const PIT_BEHIND := 4.0
const PIT_STRIKE_BEHIND := 1.0
## The two half widths of the cars, side by side (m).
const PIT_HALF_WIDTHS := 1.925
## The lateral gap that starts the strike (m).
const PIT_GAP_MIN := 0.6
const PIT_GAP_MAX := 1.6
## The distance at which the PIT unit strikes (m).
const PIT_STRIKE_RANGE := 8.0
## How far behind the player the PIT unit takes its role (m).
const PIT_APPROACH := 25.0
const PIT_APPROACH_LATERAL := 10.0
## The closing speed of the PIT unit: this much per metre of the gap (m/s per m).
const PIT_CATCH_UP := 0.4
const PIT_CATCH_UP_MAX := 6.0
## The clearance the PIT unit keeps in front of the player before it creeps in (m).
const PIT_REAR_CLEARANCE := 2.0
## The steer of the strike: 25 degrees of wheel angle (the dossier §6.3).
const PIT_STRIKE_STEER := 0.78
## The duration of the strike (s).
##
## The strike has to be long enough for the unit to reach the rear quarter of the player: the
## lateral movement of the strike is half of the lateral acceleration times the square of the
## time, and the unit starts a metre and a half beside him.
const PIT_STRIKE_TIME := 0.7
## The box: the front unit drives this far ahead of the player (m).
const BOX_FRONT_AHEAD := 9.0
## The aim point of the merge is that far in front of the gap (m): the pure pursuit needs a
## long baseline, or the unit hunts around the line of the player.
const BOX_MERGE_AIM := 12.0
## The unit starts to merge when it is that far in front of the player (m).
const BOX_MERGE_START := 4.0
## The lateral offset the front unit uses while it overtakes (m).
##
## The front unit passes outside the side units, so the three cars of the box do not fight for
## the same lane.
const BOX_OVERTAKE_OFFSET := 4.6
## How far ahead of the player the front unit aims while it overtakes (m).
##
## The run-up has to be long: the police cars can only pull 7 m/s^2 to the side, so the unit
## needs twenty metres of road to move three metres sideways without touching the player.
const BOX_OVERTAKE_AHEAD := 25.0
## The distance at which the units take their place in the box (m).
const BOX_ENTER_DISTANCE := 22.0
## The lateral offset of the side units (m) and how far behind they drive (m).
const BOX_SIDE_OFFSET := 2.4
const BOX_BACK := 0.0
## The extra speed the front unit uses while it overtakes (m/s).
const BOX_CATCH_UP := 8.0
## The distance behind the player where the front unit slows down to move out of his lane (m).
const BOX_CATCH_UP_DISTANCE := 6.0
## The extra speed of the front unit while it moves out of the lane of the player (m/s).
const BOX_MERGE_SPEED := 2.5
## The front unit slows down this much once it is ahead (m/s).
const BOX_FRONT_SPEED_OFFSET := -3.0
## The extra speed of a side unit, per metre of the gap to its slot (m/s per m).
const BOX_SIDE_GAIN := 0.8
const BOX_SIDE_CATCH_UP_MAX := 8.0
## The distance at which a side unit has reached its slot (m).
const BOX_SLOT_REACHED := 2.0
## The box breaks up after this many seconds.
const BOX_BREAK_TIME := 8.0
## The head-on charge (m/s) and the U-turn after a miss.
const HEAD_ON_SPEED := 25.0
const HEAD_ON_TURN_TIME := 2.0
const HEAD_ON_TURN_SPEED := 8.0
## The head-on unit gives up when it has passed the player (m) or after this many seconds.
const HEAD_ON_GIVE_UP_DISTANCE := 3.0
const HEAD_ON_GIVE_UP_TIME := 20.0
## The distance the head-on unit drives back when it turns around (m).
const HEAD_ON_TURN_DISTANCE := 20.0
## The aim point of the head-on unit is that far in front of the player (m). The unit comes
## from the front, so it drives at the player himself; the cross-track term of the steering
## brings it down to his line.
const HEAD_ON_AIM := 0.0


## The point the head-on unit drives at: the player himself.
##
## The unit merges into the lane of the player and meets him head on. The cross-track term of
## the steering (the distance to the line of the player) brings it down to his lane, the pure
## pursuit alone would let it pass four metres to the side.
static func head_on_target(player: VehicleBase) -> Vector3:
	return player.global_position + player.get_forward() * HEAD_ON_AIM


## The look-ahead point of a patrolling unit (m).
static func patrol_lookahead(speed: float) -> float:
	return clampf(PATROL_LOOKAHEAD_MIN + PATROL_LOOKAHEAD_PER_SPEED * speed,
			PATROL_LOOKAHEAD_MIN, PATROL_LOOKAHEAD_MAX)


## The time lead of a pursuit: the unit aims where the player will be (s).
static func pursuit_lead(distance: float, closing: float) -> float:
	if closing <= PURSUE_LEAD_MIN_CLOSING:
		return PURSUE_LEAD_MAX
	return clampf(distance / closing, 0.0, PURSUE_LEAD_MAX)


## The speed of a pursuing unit: the speed of the player plus a closing speed that shrinks with
## the gap, so the unit does not arrive like a bull.
##
## Inside the press distance the unit never drives faster than the player: the speed of the
## player of the previous tick (the cache of the contacts) is the ceiling, so a player who
## brakes is not shoved down the road by the unit on his bumper.
static func pursue_speed(player: VehicleBase, distance: float, top_speed: float,
		cached_player_speed: float = -1.0) -> float:
	var player_speed := player.get_speed_kmh() / 3.6
	if distance < PURSUE_PRESS_DISTANCE:
		return minf(press_speed(player, cached_player_speed), top_speed)
	var catch_up := clampf(distance * PURSUE_CATCH_UP, 0.0, PURSUE_CATCH_UP_MAX)
	return minf(player_speed + catch_up, top_speed)


## The speed of a unit that is on the bumper of the player: never more than the player.
##
## `cached_player_speed` is the speed of the player of the previous physics tick (the cache of
## the contacts). It is -1 when it is unknown, and then the speed of the player is used.
static func press_speed(player: VehicleBase, cached_player_speed: float) -> float:
	var current := player.get_speed_kmh() / 3.6
	if cached_player_speed < 0.0:
		return current
	return minf(current, cached_player_speed)


## The point the rammer aims at: the rear bumper of the player, a little to one side.
static func ram_target(player: VehicleBase, side: float) -> Vector3:
	return player.global_transform * Vector3(side * RAM_OFFSET, 0.0, RAM_REAR)


## The speed of the rammer.
static func ram_speed(player: VehicleBase, boosted: bool, top_speed: float) -> float:
	var push := RAM_PUSH if boosted else 0.0
	return minf(player.get_speed_kmh() / 3.6 + push, top_speed)


## The point the PIT unit drives at: the line beside the player.
##
## The unit lines up beside the player first (PIT_OFFSET metres to the side, PIT_BEHIND metres
## behind) and moves in on the rear quarter for the strike.
static func pit_target(player: VehicleBase, side: float, rel: Vector3) -> Vector3:
	if rel.z > PIT_BEHIND:
		return player.global_transform * Vector3(side * PIT_OFFSET, 0.0, PIT_BEHIND)
	return player.global_transform * Vector3(side * PIT_STRIKE_OFFSET, 0.0, PIT_STRIKE_BEHIND)


## True when the unit has lined up beside the player and may strike.
static func pit_ready(rel: Vector3, gap: float, distance: float) -> bool:
	if rel.z > PIT_BEHIND or rel.z < PIT_REAR_CLEARANCE_MIN:
		return false
	if gap > PIT_GAP_MAX or gap <= PIT_GAP_MIN - PIT_GAP_MARGIN:
		return false
	return distance < PIT_STRIKE_RANGE


## The speed of the PIT unit: it creeps in and then matches the speed of the player.
static func pit_speed(player: VehicleBase, rel: Vector3) -> float:
	var closing := clampf((rel.z - PIT_REAR_CLEARANCE) * PIT_CATCH_UP, 0.0, PIT_CATCH_UP_MAX)
	return player.get_speed_kmh() / 3.6 + closing


## The gap between the PIT unit and the player (m); zero when they touch.
static func pit_gap(rel: Vector3) -> float:
	return absf(rel.x) - PIT_HALF_WIDTHS


## The point of the box formation.
##
## The front unit overtakes the player in the next lane and merges back when it is nine metres
## ahead; the side units squeeze the player from both sides.
static func box_target(player: VehicleBase, front: bool, side: float, rel: Vector3) -> Vector3:
	if front:
		var lane := player.global_transform.basis.x * side * BOX_OVERTAKE_OFFSET
		if rel.z > -BOX_MERGE_START:
			# The overtake: the unit passes the player in the next lane.
			return player.global_position + player.get_forward() * BOX_OVERTAKE_AHEAD + lane
		# The merge: the unit comes back to the line of the player and holds the gap.
		return player.global_position + player.get_forward() * (BOX_FRONT_AHEAD + BOX_MERGE_AIM)
	return player.global_transform * Vector3(side * BOX_SIDE_OFFSET, 0.0, BOX_BACK)


## The speed of the box: the front unit overtakes first, then it holds nine metres ahead; the
## side units close on their slot and then keep the speed of the player.
static func box_speed(player: VehicleBase, front: bool, side: float, rel: Vector3,
		top_speed: float) -> float:
	var player_speed := player.get_speed_kmh() / 3.6
	if not front:
		var gap := Vector2(rel.x - side * BOX_SIDE_OFFSET, rel.z - BOX_BACK).length()
		if gap <= BOX_SLOT_REACHED:
			return player_speed
		return player_speed + clampf(gap * BOX_SIDE_GAIN, 0.0, BOX_SIDE_CATCH_UP_MAX)
	# The front unit catches up first, then it moves out of the lane of the player slowly (it can
	# only pull 7 m/s^2 to the side) and passes him.
	if rel.z > BOX_CATCH_UP_DISTANCE:
		return minf(player_speed + BOX_CATCH_UP, top_speed)
	if rel.z > -BOX_FRONT_AHEAD:
		return player_speed + BOX_MERGE_SPEED
	return maxf(player_speed + BOX_FRONT_SPEED_OFFSET, BOX_FRONT_MIN_SPEED)
