class_name PoliceDriver
extends RefCounted
## The driving helper of a police unit (dossier §6.3).
##
## The police use the same car physics as the player, so the AI only produces a driving input:
## a steering command in [-1, 1] and a throttle / brake pair. The steering is a pure-pursuit
## heading controller; the speed is limited by the corner the unit is taking, so it does not
## understeer off the road.

## The steering gain on the heading error.
const STEER_GAIN := 0.6
## The damping of the yaw rate.
const STEER_DAMP := 0.1
## The lateral acceleration a police car may use (m/s^2). 9.0 is 0.92 g: the arcade car of the
## vehicle unit rolls over above ~0.8 g (see the request in status/police.md). The box of the
## dossier needs the room: the unit has to move three metres to the side while it overtakes.
const MAX_LATERAL := 9.0
## The lateral acceleration of the PIT strike (m/s^2): the grip of the tyres, so the strike
## really reaches the rear quarter of the player.
const STRIKE_LATERAL := 12.0
## The wheelbase of the fleet (m).
const WHEELBASE := 2.9
## The wheel angle of the drive module at rest and at the top speed (degrees).
const STEER_MAX_DEG := 32.0
const STEER_MIN_DEG := 7.0
## The top speed of the car (m/s), the reference of the steering ramp of the drive module.
const TOP_SPEED := 69.44
## The gain of the throttle and the brake on a speed error.
const THROTTLE_GAIN := 0.6
const BRAKE_GAIN := 0.25
## The strongest brake a police car uses (it must not be a wall in front of the player).
const BRAKE_MAX := 0.6
## Below this speed the tyres hold the car at any steer angle (m/s).
const STEER_MIN_SPEED := 8.0
## How much of the top speed a corner takes away (per radian of the heading error).
const CORNER_LOSS := 1.6
## The lowest share of the top speed a sharp corner allows.
const CORNER_MIN_SHARE := 0.22
## The gain of the cross-track term of the steering (a Stanley controller).
const CROSS_TRACK_GAIN := 0.8
## The speed the cross-track term is damped with (m/s).
const CROSS_TRACK_MIN_SPEED := 5.0
## The largest cross-track steering the unit asks for.
const CROSS_TRACK_MAX := 0.45
## The speed limit of a lane when the graph has none (m/s).
const LANE_SPEED_FALLBACK := 25.0


## The largest steering command that keeps the car inside the grip at the given speed.
##
## A police car that corners at the limit rolls onto its bump stops and is thrown into the air,
## so the AI never asks for more than the tyres can hold.
static func grip_steer(speed: float) -> float:
	return _steer_for_lateral(speed, MAX_LATERAL)


## The steering command of the PIT strike: the dossier asks for 25 degrees of wheel angle, but
## only as much as the tyres can hold at the speed of the manoeuvre.
static func strike_steer(speed: float) -> float:
	return minf(PoliceTactics.PIT_STRIKE_STEER, _steer_for_lateral(speed, STRIKE_LATERAL))


## The normalised steering that asks for `lateral` m/s^2 of side force at `speed`.
static func _steer_for_lateral(speed: float, lateral: float) -> float:
	if speed < STEER_MIN_SPEED:
		return 1.0
	var angle := rad_to_deg(atan(lateral * WHEELBASE / (speed * speed)))
	var max_deg := lerpf(STEER_MAX_DEG, STEER_MIN_DEG, clampf(speed / TOP_SPEED, 0.0, 1.0))
	return clampf(angle / max_deg, 0.05, 1.0)


## The steering command that points the car at `target`. `yaw` is the current yaw rate about
## +Y (positive = turning left).
static func steer_command(forward: Vector3, to_target: Vector3, yaw: float, velocity: Vector3,
		gain: float = STEER_GAIN) -> float:
	var error := AISteering.heading_error(forward, to_target)
	return clampf(-error * gain - yaw * STEER_DAMP, -1.0, 1.0)


## The throttle for a speed error. The control is proportional, so a unit can creep in on the
## player instead of arriving in one piece.
static func throttle_for(speed: float, desired: float) -> float:
	return clampf((desired - speed) * THROTTLE_GAIN, 0.0, 1.0)


## The brake for a speed error. The brake is gentle: a police car that brakes hard in front of
## the player is a wall, not a chase.
static func brake_for(speed: float, desired: float) -> float:
	return clampf((speed - desired) * BRAKE_GAIN, 0.0, BRAKE_MAX)


## The speed the unit may carry into a corner of `error` radians (arcade approximation: the
## slower the corner, the lower the cap).
static func corner_limit(error: float, top_speed: float) -> float:
	var e := absf(error)
	if e < 0.02:
		return top_speed
	return top_speed * clampf(1.0 - CORNER_LOSS * e, CORNER_MIN_SHARE, 1.0)


## The driving input of a unit: the throttle, the brake and the steer.
##
## `strike_sign` is the direction of the PIT strike (0 when the unit is not striking).
static func input_for(forward: Vector3, to_target: Vector3, yaw: float, velocity: Vector3,
		speed: float, desired: float, top_speed: float, airborne: bool,
		strike_sign: float) -> Vector3:
	var steer := steer_command(forward, to_target, yaw, velocity)
	var grip := grip_steer(speed)
	if strike_sign != 0.0:
		# The strike: a hard steer into the rear quarter of the player.
		steer = strike_sign * strike_steer(speed)
	else:
		steer = clampf(steer, -grip, grip)
	desired = minf(desired, corner_limit(AISteering.heading_error(forward, to_target), top_speed))
	var throttle := throttle_for(speed, desired)
	var brake := brake_for(speed, desired)
	if airborne:
		# In the air the drive force would only pitch the nose up and dig it into the road.
		throttle = 0.0
		brake = 0.0
	return Vector3(throttle, brake, steer)


## The steering that brings a unit down to a line it is beside of.
##
## The pure pursuit alone converges too slowly when the point it drives at is far away: a unit
## 400 m away would meet the player four metres to the side. The cross-track term adds the
## distance to the line of the player, damped by the speed (a Stanley controller).
static func cross_track_steer(lateral: float, speed: float,
		gain: float = CROSS_TRACK_GAIN) -> float:
	return -clampf(atan(lateral * gain / maxf(speed, CROSS_TRACK_MIN_SPEED)),
			-CROSS_TRACK_MAX, CROSS_TRACK_MAX)


## The driving input of a unit, from the car itself: the target, the wanted speed and the
## direction of the PIT strike (0 when the unit is not striking).
##
## `bias` is added to the steering (the cross-track term of the head-on unit).
static func drive(car: PoliceCar, target: Vector3, desired: float,
		strike_sign: float, bias: float = 0.0) -> float:
	if car == null:
		return 0.0
	var forward := -car.global_transform.basis.z
	var to_target := target - car.global_position
	var current := speed(car)
	var airborne := car.telemetry.grounded_wheels == 0
	var input := input_for(forward, to_target, car.angular_velocity.y, car.linear_velocity,
			current, desired, top_speed(car, car.ctx, car.kind), airborne, strike_sign)
	var steer := clampf(input.z + bias, -1.0, 1.0)
	car.set_controls(input.x, input.y, steer, false)
	return steer


## The top speed of a unit, with the catch-up fairness of §6.3.
static func top_speed(car: RigidBody3D, ctx: DriveContext, kind: StringName) -> float:
	var base := PoliceFleet.top_speed(kind)
	if ctx == null or ctx.player == null:
		return base
	var gap := car.global_position.distance_to(ctx.player.global_position)
	return base * PoliceFleet.catchup_factor(gap)


## The speed of a unit along its own forward axis (m/s).
static func speed(car: RigidBody3D) -> float:
	return maxf(car.linear_velocity.dot(-car.global_transform.basis.z), 0.0)


## The speed limit of the lane a unit is on (m/s).
static func lane_speed_limit(ctx: DriveContext, follower: LaneFollower) -> float:
	if ctx == null or ctx.graph == null or follower == null:
		return LANE_SPEED_FALLBACK
	var index := clampi(follower.lane, 0, ctx.graph.lane_count() - 1)
	return ctx.graph.lanes[index].speed_limit_kmh / 3.6


## Which side of the player a unit is on: +1 = right, -1 = left.
static func side_of_player(car: RigidBody3D, player: VehicleBase) -> float:
	if player == null:
		return 1.0
	var rel := relative_to_player(car, player)
	return 1.0 if rel.x >= 0.0 else -1.0


## The position of the player in its own car frame: x = right, z = behind (the nose is -Z).
static func relative_to_player(car: VehicleBase, player: VehicleBase) -> Vector3:
	if car == null or player == null:
		return Vector3.ZERO
	var basis := player.global_transform.basis
	return basis.inverse() * (car.global_position - player.global_position)
