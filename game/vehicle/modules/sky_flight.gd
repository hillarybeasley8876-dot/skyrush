extends RefCounted
## The sky lane flight (dossier 5.6). The car flies on rails inside a tube: the player only
## steers inside it. The world unit builds the lane (the SkyLane contract); this module moves
## the car.
##
## The take-off blends into the lane over 0.4 s (the lift jets fire, the gravity goes to 0 and
## the car aligns to the lane), the soft edge pushes the car back into the tube and the exit
## descends the car at 3 m/s until the ground.

const DriveTuning := preload("res://vehicle/tuning/drive_tuning.gd")
const LaneTuning := preload("res://vehicle/tuning/lane_tuning.gd")

## True while the car is in the tube.
var flying: bool = false
## The lane the car is flying in.
var lane: SkyLane = null
## Metres travelled along the lane (negative while the car is still before the curve).
var offset: float = 0.0
## Offset from the lane centre: x = lateral, y = vertical.
var lateral: float = 0.0
var vertical: float = 0.0
## Speed along the lane in m/s.
var speed: float = 0.0
## Lateral and vertical speed in m/s (the player's input).
var lateral_speed: float = 0.0
var vertical_speed: float = 0.0
## True while the car leaves the tube.
var exiting: bool = false
## True while the car glides down with an empty tank.
var gliding: bool = false
## True on the tick the car touches the ground at the end of the flight.
var landed: bool = false
## True on the tick an N2 ring was collected.
var ring_collected: bool = false
## True while the take-off blends into the lane.
var transitioning: bool = false
## True while the P1-P4 cushion holds the glide down (the early exit).
var cushioning: bool = false

var _transition: float = 0.0
var _takeoff: Transform3D = Transform3D.IDENTITY
var _next_ring: int = 0
var _exit_time: float = 0.0
var _ground_y: float = 0.0
## The lateral speed the player commands (the bank follows it).
var _lateral_command: float = 0.0


## True when the car may take off: fast enough and with enough N2.
func can_enter(lane_ref: SkyLane, speed_kmh: float, n2: float) -> bool:
	if lane_ref == null:
		return false
	return speed_kmh >= lane_ref.min_entry_kmh and n2 >= lane_ref.min_n2


## Starts the flight. takeoff is the transform of the car at the take-off.
func enter(lane_ref: SkyLane, speed_mps: float, speed_cap: float, takeoff: Transform3D) -> void:
	lane = lane_ref
	flying = true
	exiting = false
	gliding = false
	landed = false
	lateral_speed = 0.0
	vertical_speed = 0.0
	_takeoff = takeoff
	_transition = LaneTuning.LANE_TRANSITION_TIME
	transitioning = true
	_next_ring = 0
	_exit_time = 0.0
	ring_collected = false
	# The flight starts where the car is: the curve may begin behind the take-off, so the offset
	# is negative at the start (the frame is extrapolated along the tangent). The lateral and
	# vertical offsets keep the car where it is, so the take-off never snaps it into the tube.
	offset = _entry_offset(takeoff.origin)
	var start: Transform3D = lane.frame_at(0.0)
	var delta: Vector3 = takeoff.origin - start.origin
	lateral = delta.dot(start.basis.x)
	vertical = delta.dot(start.basis.y)
	var cruise: float = lane_ref.cruise_kmh / DriveTuning.KMH
	speed = clampf(maxf(speed_mps, cruise), 0.0, speed_cap)


## Where the car enters the curve: negative when it is still before the start of the lane.
## The lane frame looks down the curve, so its forward axis is -basis.z.
func _entry_offset(position: Vector3) -> float:
	if lane == null:
		return 0.0
	var start: Transform3D = lane.frame_at(0.0)
	return (position - start.origin).dot(-start.basis.z)


## Advances the flight. ground_y is the height of the ground under the car.
func update(dt: float, steer: float, throttle: float, brake: float, n2: float,
		boost_kind: StringName, ground_y: float) -> void:
	if not flying or lane == null:
		return
	ring_collected = false
	_ground_y = ground_y
	# The N2 boost raises the lane speed to 300 km/h (dossier 5.6).
	var cruise: float = lane.cruise_kmh / DriveTuning.KMH
	var target: float = maxf(speed, cruise)
	if boost_kind == &"nitro" or boost_kind == &"launch":
		target = maxf(target, LaneTuning.LANE_BOOST_SPEED)
	speed = move_toward(speed, target, LaneTuning.LANE_SPEED_ACCEL * dt)
	offset += speed * dt
	# The take-off blend.
	if _transition > 0.0:
		_transition = maxf(_transition - dt, 0.0)
		transitioning = true
	else:
		transitioning = false
	# The player steers inside the tube. Near the edge the steering fades, so the soft spring
	# pushes the car back before the hard clamp (the car must not ride the clamp).
	var half_w: float = lane.tube_half_width
	var over: float = maxf(absf(lateral) - half_w, 0.0)
	var steer_scale: float = clampf(1.0 - over / LaneTuning.LANE_EDGE_MARGIN, 0.0, 1.0)
	var commanded: float = clampf(steer, -1.0, 1.0) * LaneTuning.LANE_LATERAL_SPEED
	_lateral_command = commanded
	var target_lat: float = commanded * steer_scale
	var target_vert: float = clampf(throttle - brake, -1.0, 1.0) * LaneTuning.LANE_VERTICAL_SPEED
	lateral_speed = lerpf(lateral_speed, target_lat, clampf(LaneTuning.LANE_RESPONSE * dt, 0.0, 1.0))
	vertical_speed = lerpf(vertical_speed, target_vert, clampf(LaneTuning.LANE_RESPONSE * dt, 0.0, 1.0))
	lateral += lateral_speed * dt
	vertical += vertical_speed * dt
	# The soft edge: a spring back into the tube, then the hard limit.
	var limit: float = half_w + LaneTuning.LANE_EDGE_MARGIN
	if over > 0.0:
		# The speed against the wall fades, so the car cannot build it up, and the spring
		# pushes it back into the tube before it reaches the hard clamp.
		lateral_speed *= steer_scale
		lateral_speed -= signf(lateral) * LaneTuning.LANE_EDGE_ACCEL * over * dt
		lateral_speed = clampf(lateral_speed, -LaneTuning.LANE_LATERAL_SPEED, LaneTuning.LANE_LATERAL_SPEED)
	if absf(lateral) > limit:
		lateral = signf(lateral) * limit
		lateral_speed = 0.0
	if vertical > lane.tube_up:
		vertical = lane.tube_up
		vertical_speed = minf(vertical_speed, 0.0)
	if vertical < -lane.tube_down:
		vertical = -lane.tube_down
		vertical_speed = maxf(vertical_speed, 0.0)
	# The N2 rings.
	var rings: PackedFloat32Array = lane.n2_ring_offsets
	while _next_ring < rings.size() and offset >= rings[_next_ring]:
		_next_ring += 1
		ring_collected = true
	# The exit: the end of the lane descends on the rails, an empty tank leaves them.
	if n2 <= 0.0 and not gliding and not exiting:
		gliding = true
	if offset >= lane.length() and not gliding:
		exiting = true
	if exiting and not gliding:
		_exit_time += dt
		# The car descends at 3 m/s until the ground is under it.
		var frame: Transform3D = _frame_at(offset)
		var target_vertical: float = _ground_y - frame.origin.y
		vertical = maxf(vertical - LaneTuning.LANE_EXIT_DESCENT * dt, target_vertical)
		vertical_speed = 0.0
		if vertical <= target_vertical + LaneTuning.LANE_EXIT_EPS:
			# The car is on the ground: the flight ends and the wheels touch down.
			landed = true


## Leaves the tube early (the flight key): the car glides down outside the rails (dossier 5.6).
func exit_early() -> void:
	if gliding or landed:
		return
	gliding = true
	exiting = true


## The world transform of the car inside the tube.
func pose() -> Transform3D:
	if lane == null:
		return Transform3D.IDENTITY
	var frame: Transform3D = _frame_at(offset)
	var basis: Basis = frame.basis
	# The bank and the pitch (dossier 5.6). A positive bank rolls the right side down, so the
	# car leans into the move; a positive pitch lifts the nose.
	# The bank follows the lateral speed the player asks for: the car leans into the move it
	# commands, also when it is already sliding along the wall of the tube.
	var bank: float = clampf(_lateral_command * LaneTuning.LANE_BANK_DEG,
			-LaneTuning.LANE_BANK_MAX_DEG, LaneTuning.LANE_BANK_MAX_DEG)
	var pitch: float = clampf(vertical_speed * LaneTuning.LANE_PITCH_DEG,
			-LaneTuning.LANE_BANK_MAX_DEG, LaneTuning.LANE_BANK_MAX_DEG)
	var origin: Vector3 = frame.origin + basis.x * lateral + basis.y * vertical
	# The bank is about the car's forward axis, the pitch about its right axis.
	var oriented: Basis = basis * Basis(Vector3.FORWARD, deg_to_rad(bank)) \
			* Basis(Vector3.RIGHT, deg_to_rad(pitch))
	if _transition > 0.0:
		# The take-off blend: the car turns towards the lane and rises to its height, but it
		# already follows the line, so the flight never teleports.
		var t: float = 1.0 - _transition / LaneTuning.LANE_TRANSITION_TIME
		var eased: float = smoothstep(0.0, 1.0, t)
		oriented = _takeoff.basis.slerp(oriented, eased).orthonormalized()
		origin.y = lerpf(_takeoff.origin.y, origin.y, eased)
	return Transform3D(oriented, origin)


## The lane frame at an offset; before the start of the curve the tangent is extrapolated.
func _frame_at(at: float) -> Transform3D:
	if lane == null:
		return Transform3D.IDENTITY
	if at >= 0.0:
		return lane.frame_at(minf(at, lane.length()))
	var start: Transform3D = lane.frame_at(0.0)
	return Transform3D(start.basis, start.origin - start.basis.z * at)


## The velocity the car should have while flying.
func velocity() -> Vector3:
	if lane == null:
		return Vector3.ZERO
	var frame: Transform3D = _frame_at(offset)
	var basis: Basis = frame.basis
	return -basis.z * speed + basis.x * lateral_speed + basis.y * vertical_speed


## Progress along the lane, 0..1.
func progress() -> float:
	if lane == null or lane.length() <= 0.0:
		return 0.0
	return clampf(offset / lane.length(), 0.0, 1.0)


## Clears the flight (a respawn).
func reset() -> void:
	flying = false
	exiting = false
	gliding = false
	landed = false
	transitioning = false
	cushioning = false
	lane = null
	offset = 0.0
	lateral = 0.0
	vertical = 0.0
	_transition = 0.0
