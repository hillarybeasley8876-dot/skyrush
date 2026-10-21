class_name AISteering
extends RefCounted
## Steering helpers shared by traffic, police and rivals: heading errors, yaw rates and the
## lateral correction that pulls a car back onto its lane.
##
## Sign convention: a positive heading error means "turn left" (a positive yaw rate about +Y).

const DEFAULT_YAW_GAIN := 2.2    ## 1/s: PD gain on the heading error
const DEFAULT_MAX_YAW := 2.5     ## rad/s: cap on the yaw rate
const LATERAL_GAIN := 2.0        ## 1/s: how hard a car pulls back onto its lane centre
const LATERAL_MAX := 4.0         ## m/s: cap on the sideways correction


## Signed heading error (rad) between the car's forward axis and the desired direction.
## Positive = turn left, negative = turn right.
static func heading_error(forward: Vector3, desired: Vector3) -> float:
	var f := forward
	var d := desired
	f.y = 0.0
	d.y = 0.0
	if f.length_squared() < 0.00001 or d.length_squared() < 0.00001:
		return 0.0
	return f.normalized().signed_angle_to(d.normalized(), Vector3.UP)


## The yaw rate (rad/s) that turns the car towards `desired`.
static func yaw_rate(forward: Vector3, desired: Vector3, gain: float = DEFAULT_YAW_GAIN,
		max_rate: float = DEFAULT_MAX_YAW) -> float:
	return clampf(heading_error(forward, desired) * gain, -max_rate, max_rate)


## The sideways velocity (m/s) that cancels a lateral error; negative pulls the car back left.
static func lateral_correction(lateral_error: float, gain: float = LATERAL_GAIN,
		max_speed: float = LATERAL_MAX) -> float:
	return clampf(-lateral_error * gain, -max_speed, max_speed)


## Steers towards a look-ahead point: returns the normalised lateral command in [-1, 1]
## (positive = right). `lookahead` is the distance to the target in metres.
static func steer_to_target(forward: Vector3, to_target: Vector3, gain: float = 1.0) -> float:
	var err := heading_error(forward, to_target)
	return clampf(-err * gain, -1.0, 1.0)


## Blends two directions (used to keep a car pointing along its lane while it is still
## aligning after a lane change).
static func blend_direction(a: Vector3, b: Vector3, weight: float) -> Vector3:
	var t := clampf(weight, 0.0, 1.0)
	var out := a.lerp(b, t)
	out.y = 0.0
	if out.length_squared() < 0.00001:
		return b
	return out.normalized()
