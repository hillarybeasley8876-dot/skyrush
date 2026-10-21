class_name IDM
extends RefCounted
## The Intelligent Driver Model (Treiber) used for every AI car's longitudinal behaviour, plus the
## MOBIL-lite lane-change test. Values are the SKYRUSH game values (dossier 6.1), not the
## Wikipedia calibrated ones: the game wants crisp reactions, not realistic sluggishness.
##
##   a = a_max * [1 - (v/v0)^4 - (s*/s)^2]
##   s* = s0 + v*T + v*dv / (2*sqrt(a_max*b))
##
## `dv` is the speed difference to the leader (v_self - v_leader), `gap` the bumper-to-bumper
## distance in metres.

const T := 1.2            ## s: safe time headway
const A_MAX := 2.0        ## m/s^2: maximum acceleration
const B_COMF := 3.0       ## m/s^2: comfortable deceleration
const S0 := 2.5           ## m: minimum bumper-to-bumper distance
const EMERGENCY := 8.0    ## m/s^2: hard brake cap
const V_DELTA := 4.0      ## exponent of the free-road term
const GAIN_THRESHOLD := 0.3       ## m/s^2: MOBIL-lite gain needed to change lane
const FOLLOWER_BRAKE_LIMIT := 3.0 ## m/s^2: politeness - never force the follower to brake harder


## The IDM acceleration (m/s^2). Positive = accelerate, negative = brake.
static func acceleration(v: float, v0: float, gap: float, dv: float) -> float:
	if v0 <= 0.1:
		return -EMERGENCY
	if gap <= 0.1:
		return -EMERGENCY
	var s_star := desired_gap(v, dv)
	var free := 1.0 - pow(clampf(v / v0, 0.0, 4.0), V_DELTA)
	var interaction := pow(s_star / gap, 2.0)
	return clampf(A_MAX * (free - interaction), -EMERGENCY, A_MAX)


## The desired bumper-to-bumper distance to the leader (m).
static func desired_gap(v: float, dv: float) -> float:
	return S0 + v * T + v * dv / (2.0 * sqrt(A_MAX * B_COMF))


## MOBIL-lite: is a lane change worth it and safe enough?
##
## `a_current` is the acceleration in the current lane, `a_new` the acceleration after the change,
## `follower_brake` how hard the car behind would have to brake (m/s^2, positive = braking).
static func should_change_lane(a_current: float, a_new: float, follower_brake: float) -> bool:
	if follower_brake > FOLLOWER_BRAKE_LIMIT:
		return false
	return a_new - a_current > GAIN_THRESHOLD


## The braking the car behind would need (m/s^2, positive = it has to brake).
static func required_brake(v: float, v0: float, gap: float, dv: float) -> float:
	return maxf(-acceleration(v, v0, gap, dv), 0.0)


## Distance needed to come to a full stop from `v` at the comfortable deceleration (m).
static func stopping_distance(v: float) -> float:
	return v * v / (2.0 * B_COMF)
