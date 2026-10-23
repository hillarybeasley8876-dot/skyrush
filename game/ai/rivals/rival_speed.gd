class_name RivalSpeed
extends RefCounted
## The longitudinal half of a rival: the speed it aims for, the throttle and the brake, the
## rubber band and the nitro (dossier 6.2).
##
## The corner limit comes from the speed profile of the route (a backward pass), so the lookup
## is O(1) instead of a scan over the braking distance.

const TARGET_MARGIN := 0.5      ## m/s: the target speed the rival is happy with
const THROTTLE_GAIN := 4.0       ## 1/s: the throttle opens with the difference
const THROTTLE_MIN := 0.35       ## the throttle never drops below this while accelerating
const BRAKE_GAIN := 8.0          ## 1/s: the brake opens with the difference
const BRAKE_MIN := 0.15          ## the brake never drops below this while braking
const CORNER_MARGIN := 0.80      ## the corner speed is taken with this margin
const NITRO_STRAIGHT := 250.0    ## m: the nitro needs this much straight ahead
const NITRO_COOLDOWN := 6.0      ## s: the gap between two nitros
const NITRO_LEAD_LIMIT := 150.0  ## m: a rival this far ahead of the player does not boost
const MIN_FOLLOW_SPEED := 2.0    ## m/s: the slowest a rival goes to follow a car
const EMERGENCY_GAP := 10.0       ## m: the gap under which the rival brakes hard
const EMERGENCY_RATE := 3.0       ## m/s per metre: the hard brake of the rival
const FOLLOW_S0 := 2.0           ## m: the bumper to bumper distance a rival keeps
const FOLLOW_T := 0.45           ## s: the time headway of the rival to the car in front
const FOLLOW_A := 11.0           ## m/s^2: the acceleration the rival plans with
const FOLLOW_B := 3.0            ## m/s^2: the comfortable deceleration of the rival
const FOLLOW_V := 4.0            ## the exponent of the free road term of the model
const CAR_LENGTH := 4.3          ## m: the length of a car (the Roadster of the rivals)
const PASS_MARGIN_SPEED := 6.0   ## m/s: the rival may be this much faster than the car it passes
const PASS_GAP := 4.0              ## m: the gap a rival keeps to the car it passes
const TIGHT_CLOSING := 3.0         ## m/s: the speed a rival closes up to the car in front with
const RUBBER_OFF := 0.9          ## the rubber band is off in the last share of the race
const SLIPSTREAM_BONUS := 0.04   ## the share of the top speed a car in the slipstream gets
const SLIPSTREAM_DISTANCE := 25.0  ## m: the car in front that gives the slipstream
const SLIPSTREAM_LATERAL := 1.5   ## m: the lateral distance the car in front may stand at
const TYRE_MU := 1.45            ## the grip of the Roadster's tyres (the Roadster is the hero car)
const GRAVITY := 9.81            ## m/s^2
const GRIP_REFERENCE := 45.0     ## m/s^2: the grip skill of the dossier the presets are built on
const BRAKE_FULL := 2.0          ## the brake is fully open at this difference

var line: RivalLine = null
## The lateral acceleration budget in m/s^2 (the Roadster's tyre limit, scaled by the skill).
var grip: float = TYRE_MU * GRAVITY
## The grip budget as a ratio of the car's own tyre limit.
var grip_ratio: float = 1.0
var rubber_min: float = 0.93
var rubber_max: float = 1.06
## The share of the gap a rival gives back (it leads) or takes (it trails).
var rubber_lead: float = 0.00045
var rubber_trail: float = 0.0004
## The bounds of the grip ratio of the preset.
var grip_min: float = 0.6
var grip_max: float = 1.15
## The speed the nitro needs (m/s) and the fuel it costs (%).
var nitro_speed: float = 30.0
var nitro_fuel: float = 100.0
## The seconds between the mistakes of the rival.
var mistake_min: float = 45.0
var mistake_max: float = 70.0
## True when the rival may drift at all.
var may_drift: bool = true
## The pace of this rival (0.97 .. 1.03): the field must not run as a train.
var top_factor: float = 1.0
## The share of the top speed the rival may use (0.6 after the line).
var cruise_factor: float = 1.0
## The braking the AI plans with (m/s^2).
var brake_accel: float = 11.0
## True while the rival may pass the car in front (the grid hold is over).
var pass_enabled: bool = true
## The speed the rival aims for this tick (m/s).
var target: float = 0.0
## The speed the rival would drive if the way were clear (m/s): the corner limit, its top
## speed and the slipstream, before the car in front caps it.
var potential: float = 0.0
## The rubber band factor of this tick.
var rubber: float = 1.0
## The last throttle and brake.
var throttle: float = 0.0
var brake: float = 0.0

var _n2_cooldown: float = 0.0


## Sets the speed helper up from a difficulty preset.
func setup(preset: Dictionary, skill_offset: float, factor: float, source_line: RivalLine) -> void:
	line = source_line
	rubber_min = float(preset.get("rubber_min", 0.93))
	rubber_max = float(preset.get("rubber_max", 1.06))
	rubber_lead = float(preset.get("rubber_lead", 0.00045))
	rubber_trail = float(preset.get("rubber_trail", 0.0004))
	grip_min = float(preset.get("grip_min", 0.6))
	grip_max = float(preset.get("grip_max", 1.15))
	mistake_min = float(preset.get("mistake_min", 45.0))
	mistake_max = float(preset.get("mistake_max", 70.0))
	may_drift = bool(preset.get("drift", true))
	top_factor = factor
	# The grip skill of the dossier (32/45/57 m/s^2) is 3-6 g, which no road car has, so it is
	# used as a ratio on the Roadster's own tyre limit (mu 1.45 -> 14.2 m/s^2).
	grip_ratio = clampf(float(preset.get("grip", 45.0)) / GRIP_REFERENCE + skill_offset,
		grip_min, grip_max)
	grip = TYRE_MU * GRAVITY * grip_ratio


## The grip budget for a car of this spec (the Roadster's mu decides the real limit).
func set_physical_grip(a_physical: float) -> void:
	grip = a_physical * grip_ratio


## The rubber band of the clone (dossier 6.2): a rival that leads the player is slowed down,
## a rival that trails is sped up. It is off in the last 10 % of the race.
func rubber_factor(gap: float, race_fraction: float) -> float:
	if race_fraction >= RUBBER_OFF:
		return 1.0
	if gap > 0.0:
		return clampf(1.0 - rubber_lead * gap, rubber_min, 1.0)
	return clampf(1.0 + rubber_trail * -gap, 1.0, rubber_max)


## The speed the rival aims for: the corner limit of the route, its own top speed and the car
## in front of it.
func update(delta: float, car: ArcadeCar, ctx: RivalContext, offset: float, speed: float,
		travelled: float, blocked_speed: float, blocked_distance: float,
		speed_cap: float = INF, pass_speed: float = INF, pass_distance: float = INF) -> void:
	rubber = rubber_factor(travelled - ctx.player_travelled, ctx.race_fraction)
	var top := car.spec.top_speed * top_factor * rubber * cruise_factor
	top *= _slipstream(car, ctx, offset)
	var limit := line.speed_limit(offset, grip, brake_accel) * CORNER_MARGIN
	potential = minf(minf(top, limit), speed_cap)
	target = potential
	if pass_distance < INF:
		# The rival is overtaking: it may be a little faster than the car it passes, but
		# it does not drive into its back.
		target = minf(target, pass_speed + PASS_MARGIN_SPEED)
	var gap := INF
	var tight := false
	if blocked_distance < INF:
		# The car in front sets the pace: the rival keeps its distance with the model of
		# the car following, so it does not drive into the back of it.
		gap = maxf(blocked_distance - CAR_LENGTH, 0.1)
		# A rival that is faster than the car in front closes up to it: that is the
		# distance a pass starts from. It closes slowly: a rival that drives into the
		# back of a slow car cannot stop in time.
		# The overtake counts only when the rival may pass: the rivals keep the column
		# of their grid slot for the first metres of a race, and the back rows of the
		# grid may not push the front rows. A rival that may not pass follows the car
		# in front, and the overtake model would ask it for the 39 m of a pass that is
		# not allowed: on the grid the back rows braked to a standstill behind it.
		tight = pass_enabled and potential > blocked_speed
		if tight:
			target = minf(target, blocked_speed + TIGHT_CLOSING)
		# A rival brakes for the car in front only while it is closing on it. A car that
		# falls behind does not need to slow down: braking for a car that pulls away
		# costs the rival the gap it never gets back, and on the grid it was the reason
		# the back rows crawled away behind the row in front.
		var closing := speed - blocked_speed
		if gap < EMERGENCY_GAP and closing > 0.0:
			# The car in front is too close: the rival brakes hard, whatever the model says.
			var pace := blocked_speed - EMERGENCY_RATE * (EMERGENCY_GAP - gap)
			target = minf(target, maxf(pace, MIN_FOLLOW_SPEED))
	# The throttle and the brake follow the target: the target of the overtake and the
	# emergency brake have to be known before the inputs are made, or they are dead.
	_drive_inputs(speed)
	if blocked_distance < INF:
		var accel := _follow_acceleration(speed, blocked_speed, gap, blocked_speed, tight)
		if accel < 0.0:
			brake = maxf(brake, clampf(-accel / BRAKE_GAIN, BRAKE_MIN, 1.0))
			throttle = 0.0


## The share of the top speed the slipstream of the car in front adds.
##
## A car that drives 25 m behind another one in the same line gets a clean wake: it can
## hold 4 % more of its top speed.
func _slipstream(car: ArcadeCar, ctx: RivalContext, offset: float) -> float:
	if line == null:
		return 1.0
	var tangent := line.tangent_at(offset)
	var right := line.right_at(offset)
	var pos := car.global_position
	for node in ctx.rivals:
		if not is_instance_valid(node) or node == car:
			continue
		if _in_wake(node, pos, tangent, right):
			return 1.0 + SLIPSTREAM_BONUS
	if is_instance_valid(ctx.player) and _in_wake(ctx.player, pos, tangent, right):
		return 1.0 + SLIPSTREAM_BONUS
	return 1.0


## True when the node stands in the wake of the car.
##
## The wake of a car on another level is no wake: a car on the street under the deck the
## rival drives on does not give it a slipstream.
func _in_wake(node: Node3D, pos: Vector3, tangent: Vector3, right: Vector3) -> bool:
	if not RivalContext.same_level(pos.y, node.global_position.y):
		return false
	var rel := node.global_position - pos
	var ahead := rel.dot(tangent)
	if ahead <= 0.0 or ahead > SLIPSTREAM_DISTANCE:
		return false
	return absf(rel.dot(right)) <= SLIPSTREAM_LATERAL


## The throttle and the brake for the current speed.
func _drive_inputs(speed: float) -> void:
	throttle = 0.0
	brake = 0.0
	var diff := target - speed
	if diff > TARGET_MARGIN:
		throttle = clampf(diff / THROTTLE_GAIN, THROTTLE_MIN, 1.0)
	elif diff <= -BRAKE_FULL * TARGET_MARGIN:
		brake = clampf(-diff / BRAKE_GAIN, BRAKE_MIN, 1.0)


## The acceleration the rival needs to keep its distance to the car in front (m/s^2).
##
## The model of the car following with the values of a race car: the gap the rival wants
## grows with the speed and with the speed it closes on the car in front.
##
## A rival that is overtaking (tight) does not brake for the car in front: it is changing
## lanes, and the clearance of the pass is the job of the pass logic. Without that the
## model of the car following holds every follower at the speed of the car in front and
## the field never overtakes: it runs as a train for the whole race.
##
## A rival that is not closing on the car in front does not brake for it either: the gap
## grows on its own, and a brake there only makes the rival fall further behind. That is
## what held the back rows of the grid back at the start: they braked for a car that was
## pulling away, crawled off the line and left the field 60 m apart.
func _follow_acceleration(speed: float, leader_speed: float, gap: float, v0: float,
		tight: bool = false) -> float:
	var closing := maxf(speed - leader_speed, 0.0)
	var wanted := FOLLOW_S0 + speed * FOLLOW_T \
			+ speed * closing / (2.0 * sqrt(FOLLOW_A * FOLLOW_B))
	var free := 1.0 - pow(clampf(speed / maxf(v0, 1.0), 0.0, 4.0), FOLLOW_V)
	var interaction := pow(wanted / gap, 2.0)
	if tight or speed <= leader_speed:
		interaction = 0.0
	return FOLLOW_A * (free - interaction)


## The nitro on a long straight (dossier 6.2: straights over 250 m).
##
## The rival does not boost when it is far ahead of the player: the boost would only widen
## the gap the rubber band is meant to close.
func update_nitro(delta: float, car: ArcadeCar, offset: float, speed: float, lead: float) -> void:
	_n2_cooldown = maxf(_n2_cooldown - delta, 0.0)
	if _n2_cooldown > 0.0 or speed < nitro_speed:
		return
	if car.boost.n2 < nitro_fuel:
		return
	if line.straight_ahead(offset) < NITRO_STRAIGHT:
		return
	# A rival that is far ahead of the player does not boost: the rubber band closes the gap.
	if lead > NITRO_LEAD_LIMIT:
		return
	if car.use_nitro():
		_n2_cooldown = NITRO_COOLDOWN
