class_name RivalBrain
extends RefCounted
## The driving brain of one rival racer (ref/gameplay/DOSSIER.md 6.2): the racing line with a
## speed-scaled look-ahead, the corner speed from the curvature, a PD steering controller, the
## rubber band, the nitro on the straights, the drift, the mistakes, the avoidance of the
## traffic and the pass.
##
## The brain only produces driving inputs. The car that carries it is an ArcadeCar, so the
## rivals use exactly the same physics as the player.
##
## The longitudinal half lives in `rival_speed.gd` and the obstacles and the pass in
## `rival_avoid.gd`.

const LOOKAHEAD_BASE := 18.0        ## m: the look-ahead at a standstill
const LOOKAHEAD_PER_SPEED := 1.25   ## m per m/s: the look-ahead grows with the speed
const LOOKAHEAD_MIN := 10.0         ## m
const LOOKAHEAD_MAX := 120.0        ## m
const STEER_KP := 2.2               ## the PD gain on the heading error (dossier 6.2)
const STEER_KD := 0.25              ## the PD damping on the yaw rate
const STEER_LIMIT := 0.8            ## the AI never asks for more than this much lock
const STANLEY_K := 1.0              ## the cross-track gain (pulls the car back onto the line)
const STANLEY_LIMIT := 0.4          ## rad: the cross-track term never turns the car more
const CROSS_TRACK_MIN_SPEED := 5.0  ## m/s: the cross-track term needs this speed
const STEER_ANGLE := 0.22           ## rad: the steering angle the look-ahead may ask for
const CURVATURE_LOOKAHEAD := 30.0   ## m: the window of the curvature that shortens the look-ahead
const KAPPA_MIN := 0.0002           ## 1/m: the curvature below which a corner counts as straight
const CROSS_AIM_GAIN := 0.7         ## the aim point is pulled this far towards the line
const MISTAKE_LATE_BRAKE := 0.25     ## the brake is only quartered during a late brake
const MISTAKE_WIDE_BIAS := 0.16      ## the sideways error of a wide mistake
const MISTAKE_LATE_TIME := 0.4       ## s: the brake is late for this long
const MISTAKE_WIDE_TIME := 0.6       ## s: the line is wide for this long
const OFF_LINE := 15.0               ## m: the rival is off its line when it is this far from it
const GATE_MISS_MARGIN := 30.0       ## m: the progress past a gate that counts as a missed gate
const DRIFT_KAPPA := 0.006           ## 1/m: the corner that is worth drifting
const DRIFT_LOOKAHEAD := 30.0        ## m: the drift starts this far before the corner
const DRIFT_SPEED := 25.0            ## m/s: the speed a drift needs
const DRIFT_SPEED_MARGIN := 3.0      ## m/s: the car may be this much over the corner speed
const DRIFT_START_LIMIT := 0.8      ## m: the drift only starts when the car is on its line
const DRIFT_STOP_LIMIT := 1.2       ## m: the drift ends when the car slides off its line
const PROJECT_MARGIN := 6.0         ## m: the margin of the projection window
const PROJECT_FACTOR := 2.0         ## the window covers the distance of two ticks
const GATE_APPROACH := 40.0         ## m: the rival aims at the gate from this distance
const GRID_HOLD := 300.0            ## m: the rivals keep their grid column for this distance
const LANE_BLEND := 120.0           ## m: the stretch over which a rival moves onto its own line
const MISTAKE_MIN_SPEED := 15.0     ## m/s: a mistake only happens above this speed
const MISTAKE_CORNER := 0.006       ## 1/m: the corner that is worth a mistake
const MISTAKE_BRAKE := 5.0          ## m/s: the speed the car has to lose to be braking
const MISTAKE_RETRY := 2.0          ## s: the wait before the next attempt at a mistake
const ROAD_HALF_REFRESH := 0.5      ## s: how often the width of the road is measured
const REVERSE_GUARD_SPEED := 0.6    ## m/s: below this speed the brake of the car is its reverse

var line: RivalLine = null
## The lateral offset of the car from the racing line (m): every rival drives its own line.
var lane_offset: float = 0.0
## The column of the grid slot the rival started in (m from the line).
var grid_lane: float = 0.0
## The line the rival drives once the pack has spread out (m from the line).
var spread_lane: float = 0.0
## The longitudinal helper (the speed, the rubber band, the nitro).
var speed_helper: RivalSpeed = RivalSpeed.new()
## The obstacles and the pass.
var avoid: RivalAvoid = RivalAvoid.new()
## The offset of the car on the racing line (m).
var offset: float = 0.0
## The unwrapped offset (m): it keeps counting over the start line.
var travelled: float = 0.0
## The distance the car has driven (m): the watchdog measures it, and not the progress on
## the racing line (the progress jumps when a car drives off the line).
var distance: float = 0.0
## The forward speed of the last tick (m/s).
var speed: float = 0.0
## The last steering command.
var steer: float = 0.0
## The mistake that is running (&"" when the rival is clean).
var mistake: StringName = &""
var mistake_left: float = 0.0
var mistake_timer: float = 30.0
var mistake_bias: float = 0.0
## True while the rival is drifting.
var drifting: bool = false
## The marshal: the watchdog and the rescue of this rival.
var marshal := RivalMarshal.new()
## The road mode: the rival drives on the road of the world when it loses its line.
var road := RivalRoad.new()
## The name of the car (for the warnings).
var car_name: String = ""
## The number of times the marshal had to rescue this rival.
var rescues: int:
	get:
		return marshal.rescues
## The lane graph of the world (the rival drives on the road when it loses its line).
var graph: LaneGraph:
	get:
		return road.graph
	set(value):
		road.graph = value
## True while the rival drives on the road instead of on its racing line.
var on_road: bool:
	get:
		return road.on_road
## The share of the top speed the rival may use (0.6 after the line).
var cruise_factor: float = 1.0:
	get:
		return speed_helper.cruise_factor
	set(value):
		speed_helper.cruise_factor = value
## The gate the rival has to pass next (-1 when it is unknown).
var next_gate: int = -1
## The offset of every gate of the route on the racing line (m).
var gate_offsets: PackedFloat32Array = PackedFloat32Array()
## The position of every gate of the route (the rival aims at the gate when it is close).
var gate_positions: PackedVector3Array = PackedVector3Array()
## The gate the rival drove past without hitting the trigger (-1 when there is none).
var missed_gate: int = -1
## The distance from the car to its next gate (m), set when the gate is set.
var gate_distance: float = INF
## The distance the car had covered when its next gate was set (m).
var gate_watch: float = 0.0
## True when the gate has been measured (the car knows where it is).
var _gate_measured: bool = false

var _projected: bool = false
var _warned_gate: int = -1
var _road_half: float = 6.0
var _road_half_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


## Sets the brain up from a difficulty preset.
func setup(preset: Dictionary, skill_offset: float, factor: float, source_line: RivalLine,
		seed_value: int, lane: float = 0.0) -> void:
	line = source_line
	lane_offset = lane
	offset = lane
	travelled = lane
	_rng.seed = seed_value
	mistake_timer = _rng.randf_range(float(preset.get("mistake_min", 45.0)),
		float(preset.get("mistake_max", 70.0)))
	speed_helper.setup(preset, skill_offset, factor, source_line)


## The grip budget for a car of this spec (the Roadster's mu decides the real limit).
func set_physical_grip(a_physical: float) -> void:
	speed_helper.set_physical_grip(a_physical)


## The rubber band factor for a gap in metres (positive: the rival is ahead of the player).
func rubber_factor(gap: float, race_fraction: float) -> float:
	return speed_helper.rubber_factor(gap, race_fraction)


## Drives the car for one tick.
func tick(delta: float, car: ArcadeCar, ctx: RivalContext) -> void:
	if line == null or line.length < 1.0:
		car.set_controls(0.0, 0.0, 0.0, false)
		return
	_update_position(car, delta)
	var forward := car.get_forward().dot(car.linear_velocity)
	speed = maxf(forward, 0.0)
	distance += speed * delta
	if ctx.on_grid:
		car.set_controls(0.0, 0.0, 0.0, false)
		car.set_drift(false)
		drifting = false
		return
	_update_lane()
	_update_mistake(delta)
	# At the start of a race the rivals keep the column of their grid slot: nobody
	# moves over until the pack has spread out.
	avoid.pass_enabled = travelled >= GRID_HOLD
	avoid.update_blocker(car, ctx, offset, line, lane_offset, speed, delta)
	if _watchdog(delta, car, ctx):
		return
	var on_road := road.update(self, delta, car)
	# The rivals keep the column of their grid slot for the first metres of a race: a
	# rival that may not pass the car in front does not close up on it.
	speed_helper.pass_enabled = avoid.pass_enabled
	speed_helper.update(delta, car, ctx, offset, speed, travelled, avoid.block_speed,
		avoid.block_distance, road.speed_cap(), avoid.pass_speed, avoid.pass_distance)
	var shift := avoid.update(delta, car, ctx, offset, speed, line, lane_offset,
		speed_helper.potential, _road_half_width(delta, car))
	var steer_cmd := road.steering(car) if on_road else _steering(car, shift)
	var throttle := speed_helper.throttle
	var brake := speed_helper.brake
	if avoid.emergency:
		# The rival gave a pass up in front of a car: it brakes at once.
		brake = 1.0
		throttle = 0.0
		avoid.emergency = false
	if mistake == &"late_brake":
		brake *= MISTAKE_LATE_BRAKE
	# The brake of the arcade car is its reverse gear below a walking pace: a rival
	# that brakes to a standstill would drive backwards off the grid. The brake is
	# dropped there: the car coasts to a stop and the throttle takes it forward again.
	if brake > 0.0 and forward < REVERSE_GUARD_SPEED:
		brake = 0.0
	car.set_controls(throttle, brake, steer_cmd, false)
	_update_drift(car)
	speed_helper.update_nitro(delta, car, offset, speed, travelled - ctx.player_travelled)
	if next_gate >= 0 and not _gate_measured:
		_measure_gate()
	_check_gate()


## Tracks the position of the car on the racing line (the offset wraps over the start line).
func _update_position(car: ArcadeCar, delta: float) -> void:
	var pos := car.global_position
	# The window covers the distance of two ticks: a full search of a 100 km line every tick
	# would cost more than the rest of the brain.
	var window := PROJECT_FACTOR * speed * delta + PROJECT_MARGIN
	var new_offset := line.project(offset, pos, window)
	if not _projected:
		new_offset = line.curve.get_closest_offset(pos)
		travelled = new_offset
		offset = new_offset
		_projected = true
		return
	# The car is never looked up on the whole curve: a car that lost its line keeps its
	# place on the line (the marshal puts it back there), so its progress never jumps by
	# half a lap.
	var step := new_offset - offset
	if line.closed:
		if step < -line.length * 0.5:
			step += line.length
		elif step > line.length * 0.5:
			step -= line.length
	travelled += step
	offset = new_offset


## The PD steering command (dossier 6.2) with the cross-track correction on top.
func _steering(car: ArcadeCar, shift: float) -> float:
	var look := _lookahead()
	# The right vector of the aim point: on a curve the lateral offset rotates with the line.
	var aim_right := line.right_at(offset + look)
	var aim := line.point_at(offset + look) + aim_right * (lane_offset + shift)
	# The lane the car drives right now: the personal line and the shift of the pass.
	var lane := lane_offset + shift
	# Near the gate the rival aims at the gate itself: the racing line of a city route does
	# not always run through the checkpoint, and a rival that misses the trigger loses it.
	var to_gate := _distance_to_gate()
	if next_gate >= 0 and next_gate < gate_positions.size() and to_gate < GATE_APPROACH:
		var blend := 1.0 - clampf(to_gate / GATE_APPROACH, 0.0, 1.0)
		# The rival keeps its own column at the gate: only the centre of the gate is pulled
		# in, so the pack does not fold into one line in front of it.
		aim = aim.lerp(gate_positions[next_gate] + aim_right * (lane_offset + shift), blend)
	# The cross-track term: the car is pulled back onto its own line.
	var right_here := line.right_at(offset)
	var here := line.point_at(offset) + right_here * lane
	var cross := (car.global_position - here).dot(right_here)
	# The aim point is pulled towards the line: the pure pursuit cuts the corner, and the
	# aim has to be pulled back with it.
	aim += right_here * (-cross * CROSS_AIM_GAIN)
	var err := -AISteering.heading_error(car.get_forward(), aim - car.global_position)
	err += clampf(-atan(STANLEY_K * cross / maxf(speed, CROSS_TRACK_MIN_SPEED)),
		-STANLEY_LIMIT, STANLEY_LIMIT)
	err += mistake_bias
	steer = clampf(STEER_KP * err + STEER_KD * car.angular_velocity.y, -STEER_LIMIT, STEER_LIMIT)
	return steer


## The look-ahead of the steering: the speed scaled distance of the dossier, shortened in a
## tight corner.
##
## A long look-ahead asks for a lot of steering: on a corner of 80 m radius a look-ahead of
## 50 m needs 30 degrees of lock, and the car cuts the corner when it cannot get them. The
## look-ahead is shortened so that the steering stays inside the lock of the car.
func _lookahead() -> float:
	var look := clampf(LOOKAHEAD_BASE + LOOKAHEAD_PER_SPEED * speed, LOOKAHEAD_MIN, LOOKAHEAD_MAX)
	var kappa := line.max_curvature_ahead(offset, CURVATURE_LOOKAHEAD)
	if kappa <= KAPPA_MIN:
		return look
	return maxf(minf(look, STEER_ANGLE / kappa), LOOKAHEAD_MIN)


## The mistakes (dossier 6.2): a brake 0.4 s late or a line 0.6 s too wide.
func _update_mistake(delta: float) -> void:
	if mistake_left > 0.0:
		mistake_left -= delta
		if mistake_left <= 0.0:
			mistake = &""
			mistake_bias = 0.0
		return
	mistake_timer -= delta
	if mistake_timer <= 0.0:
		if speed < MISTAKE_MIN_SPEED:
			# A car that stands still does not make a mistake: the pack of round 3 logged
			# 26 mistakes at 0 m/s.
			mistake_timer = speed_helper.mistake_min
			return
		if not _in_corner():
			# A mistake only happens in a corner or in a braking zone.
			mistake_timer = MISTAKE_RETRY
			return
		_start_mistake()


## True when the rival is in a corner or on the brakes for one.
func _in_corner() -> bool:
	if line == null:
		return false
	if line.max_curvature_ahead(offset, DRIFT_LOOKAHEAD) > MISTAKE_CORNER:
		return true
	return line.corner_speed(offset + DRIFT_LOOKAHEAD, 14.2) < speed - MISTAKE_BRAKE


## Gives the rival the column of its grid slot and the line it drives once the pack has
## spread out.
func set_lanes(grid: float, spread: float) -> void:
	grid_lane = grid
	spread_lane = spread
	lane_offset = grid


## Moves the rival from the column of its grid slot onto its own line.
##
## The rivals keep their column for the first metres of the race (the pack does not cross
## itself on the grid) and spread out over the stretch that follows it.
func _update_lane() -> void:
	var blend := clampf((travelled - GRID_HOLD) / LANE_BLEND, 0.0, 1.0)
	lane_offset = lerpf(grid_lane, spread_lane, blend)


## The half width of the road the rival drives on (m).
##
## The lane graph of the city is big: the width is measured twice a second, not every tick.
func _road_half_width(delta: float, car: ArcadeCar) -> float:
	_road_half_timer -= delta
	if _road_half_timer <= 0.0:
		_road_half_timer = ROAD_HALF_REFRESH
		_road_half = road.road_half_width(car.global_position)
	return _road_half


## Starts a mistake and schedules the next one.
func _start_mistake() -> void:
	mistake = &"late_brake" if _rng.randf() < 0.5 else &"wide"
	mistake_left = MISTAKE_LATE_TIME if mistake == &"late_brake" else MISTAKE_WIDE_TIME
	mistake_bias = 0.0
	if mistake == &"wide":
		mistake_bias = _rng.randf_range(-MISTAKE_WIDE_BIAS, MISTAKE_WIDE_BIAS)
	mistake_timer = _rng.randf_range(speed_helper.mistake_min, speed_helper.mistake_max)


## The marshal: the watchdog and the rescue of this rival.
func _watchdog(delta: float, car: ArcadeCar, ctx: RivalContext) -> bool:
	return marshal.check(self, delta, car, ctx)


## The signed distance of the car from the line it drives right now (m).
func cross_track(car: ArcadeCar) -> float:
	if line == null:
		return 0.0
	var right := line.right_at(offset)
	var lane := lane_offset + avoid.pass_shift
	return (car.global_position - line.point_at(offset) - right * lane).dot(right)


## Puts the car at a known place on the racing line (the start grid).
func set_line_offset(value: float) -> void:
	offset = value
	travelled = value
	_projected = true


## Tells the brain which gate comes next. The distance is measured on the next tick, when
## the car knows where it is on the line.
func set_next_gate(index: int) -> void:
	next_gate = index
	_gate_measured = false


## Measures the distance to the next gate from where the car is now.
func _measure_gate() -> void:
	gate_watch = travelled
	gate_distance = _distance_to_gate()
	_gate_measured = true


## The distance from the car to its next gate, measured forward along the line.
func _distance_to_gate() -> float:
	if next_gate < 0 or next_gate >= gate_offsets.size() or line == null:
		return INF
	var ahead := gate_offsets[next_gate] - offset
	if line.closed:
		ahead = fposmod(ahead, line.length)
	return ahead


## The safety net for a gate the rival drove past without hitting the trigger.
func _check_gate() -> void:
	if next_gate < 0 or gate_distance == INF:
		return
	if travelled - gate_watch <= gate_distance + GATE_MISS_MARGIN:
		return
	if _warned_gate == next_gate:
		return
	_warned_gate = next_gate
	missed_gate = next_gate
	push_warning("[rivals] %s drove past gate %d without hitting it" % [car_name, next_gate])


## The drift: the rival holds the button from the entry of a corner to its apex.
func _update_drift(car: ArcadeCar) -> void:
	var want := false
	var cross := absf(cross_track(car))
	if speed_helper.may_drift and speed >= DRIFT_SPEED:
		# The drift starts on the entry of the corner and holds to the apex. It only starts
		# when the car is already at the speed of the corner: the drift keeps the speed up,
		# so a car that is still braking would arrive too fast.
		if line.max_curvature_ahead(offset, DRIFT_LOOKAHEAD) > DRIFT_KAPPA \
				and speed <= speed_helper.target + DRIFT_SPEED_MARGIN \
				and cross < DRIFT_START_LIMIT:
			want = true
	if want and cross > DRIFT_STOP_LIMIT:
		# The car slides out of its line: the drift ends, or the car ends up in the lane
		# of its neighbour.
		want = false
	car.set_drift(want)
	drifting = want
