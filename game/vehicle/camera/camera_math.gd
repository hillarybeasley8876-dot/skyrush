extends RefCounted
## Pure camera math for the chase camera unit (ref/gameplay/DOSSIER.md §2.2-2.3,
## briefs/camera.md). No scene dependencies so the headless tests can check the
## dossier numbers directly. Every constant below is a contract number.

# --- feel numbers (dossier §2.2-2.3) ----------------------------------------------------------
const TOP_SPEED_KMH := 250.0          # V_TOP
const FOV_BASE := 62.0                # vFOV at 0 km/h
const FOV_PER_MPS := 0.10             # +0.10 deg per m/s
const FOV_NITRO := 8.0                # +8 deg in N2
const FOV_MINI := 4.0                 # +4 deg for 小喷
const FOV_MAX := 84.0                 # hard clamp (never exceed 90: nausea)
const FOV_LAMBDA := 4.0               # FOV smoothing rate
const POS_LAMBDA := 14.0              # position follow rate
const YAW_LAMBDA_GRIP := 7.0          # yaw follow rate, gripping
const YAW_LAMBDA_DRIFT := 4.5         # yaw follow rate, drifting
const YAW_LAMBDA_BLEND := 5.0         # how fast the yaw rate fades between grip and drift
const YAW_NOSE_BIAS := 0.35           # yaw target = vel_dir + 0.35 * (heading - vel_dir)
const LOOK_AHEAD := 4.0               # look-at point ahead of the car
const LOOK_HEIGHT := 1.2              # look-at point above the car
const DIST_REST := 6.0                # camera distance at rest
const HEIGHT_REST := 1.9              # camera height at rest
const DIST_TOP_BONUS := 1.2           # extra distance at V_TOP
const FF_LAMBDA := 3.0                # low-pass on the feed-forward velocity (momentum)
const FLIGHT_HEIGHT_BONUS := 2.0      # flight: higher
const FLIGHT_DIST_BONUS := 1.5        # flight: further back
const FLIGHT_POS_LAMBDA := 9.0        # flight: looser follow
const FLIGHT_YAW_LAMBDA := 5.0
const MAX_BANK_DEG := 10.0            # flight: never bank the horizon more than this
const BANK_LAMBDA := 4.0              # how fast the flight bank fades in and out
const DRIFT_SLIP_DEG := 15.0          # |beta| above which the car counts as drifting
const MAX_FEED_FORWARD := 120.0       # m/s, a teleport never throws the camera forward
const VELOCITY_MIN := 0.6             # m/s below which the velocity direction is not used

# --- camera rig ---------------------------------------------------------------------------------
const CAMERA_NEAR := 0.08             # near plane
const CAMERA_FAR := 4000.0            # far plane
const COLLISION_RADIUS := 0.3         # sphere radius of the camera cast
const PULL_OUT_RATE := 10.0           # /s, the camera eases back out to its ideal distance
const CLOSE_SPOT_MIN_DIST := 1.6      # m, below this the camera pops up over the car
const CLOSE_SPOT_EXIT_DIST := 2.0     # m, above this it eases back down (hysteresis)
const CLOSE_SPOT_LAMBDA := 12.0       # /s, the ease between the two spots
const CLOSE_SPOT_HEIGHT := 3.2        # m, the high close spot above the car
const CLOSE_SPOT_BACK := 1.0          # m, the high close spot behind the car
const SELF_FX_LAYER := 19             # visual layer with the player's own FX (hidden in the hood view)
const COLLISION_ANCHOR_HEIGHT := 0.9  # m, the cast starts at the car's roof
const MIN_LOOK_LENGTH := 0.01         # m, below this the look direction is degenerate

# --- shake (dossier §2.3) ----------------------------------------------------------------------
const SHAKE_FREQ := 10.0              # 8-12 Hz low-frequency noise
const SHAKE_MAX_OFFSET := 0.2         # m, the shake can never push the camera through a wall
const SHAKE_PITCH_DEG_PER_M := 6.0    # deg of pitch per metre of amplitude
const NITRO_SHAKE := 0.04             # m, N2 ignition
const NITRO_SHAKE_TIME := 0.2         # s
const LANDING_SHAKE := 0.10           # m per 10 m/s of vertical impact speed
const LANDING_SHAKE_PER_V := 10.0
const LANDING_SHAKE_MAX := 0.25       # m, the landing shake is capped
const LANDING_SHAKE_TIME := 0.3       # s
const WALL_SHAKE_MIN := 0.08          # m, at the smallest wall impact
const WALL_SHAKE_MAX := 0.15          # m, at a hard wall impact
const WALL_SHAKE_MIN_IMPULSE := 8000.0    # N.s, below this a hit does not shake
const WALL_SHAKE_MAX_IMPULSE := 30000.0  # N.s, at this impulse the shake is at its maximum
const WALL_SHAKE_TIME := 0.25         # s
const CAR_HIT_SHAKE_MIN_IMPULSE := 12000.0  # N.s, car-to-car hits shake above this
const CAR_HIT_SHAKE_MAX := 0.12       # m

# --- screen effects -----------------------------------------------------------------------------
const SPEED_LINE_START := 160.0       # km/h where the streaks appear
const SPEED_LINE_FULL := 280.0        # km/h where they are fully opaque
const BLUR_START := 200.0             # km/h where the radial blur starts
const BLUR_FULL := 300.0              # km/h where it reaches its cap
const BLUR_MAX := 0.15                # radial blur cap when cruising
const BLUR_NITRO := 0.25              # radial blur cap in N2
const BLUR_LAMBDA := 6.0              # /s, the blur never jumps
const STREAK_ALPHA := 0.24            # cruising alpha of the speed lines
const STREAK_ALPHA_NITRO := 0.40      # N2 alpha of the speed lines
const STREAK_COLOUR := Color(0.847, 0.957, 1.0, 1.0)      # #D8F4FF
const STREAK_COLOUR_NITRO := Color(0.098, 0.902, 1.0, 1.0)  # ART cyan #19E6FF
const STREAK_COLOUR_LAMBDA := 6.0     # /s, the colour cross-fade
const STREAK_LANES := 110.0           # angular lanes
const STREAK_LIT_RATIO := 0.35        # share of the lanes that are lit
const STREAK_WIDTH_PX := 2.0          # the line core, in pixels at 1080p
const STREAK_DASH_RATIO := 0.16       # the dash cell, as a share of the half diagonal
const STREAK_SCROLL_PX_PER_KMH := 3.0 # scroll speed, pixels per second per km/h
const STREAK_CAR_RADIUS := 0.35       # no streaks within this radius of the car (aspect corrected)
const STREAK_CAR_FEATHER := 0.12      # the soft edge of the car's mask
const STREAK_SKY_FACTOR := 0.18       # alpha above the horizon line (the sky is at infinity)

# --- N2 punch -----------------------------------------------------------------------------------
const PUNCH_KICK := -0.6              # camera punches 0.6 m closer on ignition
const PUNCH_RECOVER := 1.0            # ... then 1.0 m further back
const PUNCH_KICK_TIME := 0.18         # s, the punch in (smoothed, never a pop)
const PUNCH_TIME := 0.45              # s, the whole kick and recovery
const PUNCH_RELEASE_TIME := 1.0       # back to neutral 1.0 s after the boost ends

# --- takedown cam (dossier §3.5) ----------------------------------------------------------------
const TAKEDOWN_DISTANCES: Array[float] = [9.0, 7.0, 5.0, 3.5, 2.5]
const TAKEDOWN_CAM_HEIGHT := 1.0      # m above the road (the first candidate height)
const TAKEDOWN_HEIGHTS: Array[float] = [TAKEDOWN_CAM_HEIGHT, 2.2, 3.5]
const TAKEDOWN_VICTIM_CENTRE := 0.6   # m above the victim's origin
const TAKEDOWN_LOOK_HEIGHT := 0.5     # m above the victim that the camera aims at
const TAKEDOWN_FREE_DIST := 12.0      # m, how far the free-space ray looks
const TAKEDOWN_HITSTOP := 0.06        # s
const TAKEDOWN_HITSTOP_SCALE := 0.05  # Engine.time_scale during the hit-stop
const TAKEDOWN_CUT := 0.06            # s, the side camera cuts in here
const TAKEDOWN_SLOWMO := 0.30         # Engine.time_scale of the shot
const TAKEDOWN_SLOWMO_HOLD := 1.24    # s, until the time scale starts to ease
const TAKEDOWN_EASE_START := 1.30     # s
const TAKEDOWN_EASE_END := 2.40       # s
const TAKEDOWN_TOTAL := 2.70          # s, the hard cut back to the chase camera
const TAKEDOWN_DOLLY := 1.5           # m towards the victim
const TAKEDOWN_DOLLY_END := 1.30      # s
const TAKEDOWN_FOV := 50.0            # vFOV of the shot
const TAKEDOWN_SKIP_AFTER := 0.5      # s, the shot can be skipped after this
const TAKEDOWN_COOLDOWN := 4.0        # s, one slow-mo per 4 s
const TAKEDOWN_FALLBACK_HEIGHT := 6.0 # m, the high fallback shot
const TAKEDOWN_FALLBACK_BACK := 4.0   # m, the high fallback shot
const TAKEDOWN_MIN_DURATION := 0.6    # s, the shortest focus shot
const TAKEDOWN_MIN_LOOK_DIST := 0.2   # m, below this the camera does not re-aim


## The nominal physics step: one tick of unscaled game time. The physics always ticks at
## the project rate, so this is how much real time passes per tick, whatever the slow
## motion does to the delta.
static func physics_step() -> float:
	if _physics_step <= 0.0:
		_physics_step = 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 120))
	return _physics_step


static var _physics_step: float = 0.0


## Smoothstep, used for the eased time scale.
static func smooth01(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


## Frame-rate independent exponential approach.
static func damp(current: float, target: float, lambda: float, dt: float) -> float:
	return current + (target - current) * (1.0 - exp(-lambda * dt))


## The same, for a vector.
static func damp_vec(current: Vector3, target: Vector3, lambda: float, dt: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-lambda * dt))


## Same, for an angle in radians (wraps the short way round).
static func damp_angle(current: float, target: float, lambda: float, dt: float) -> float:
	return current + wrap_angle(target - current) * (1.0 - exp(-lambda * dt))


## Wraps an angle to (-PI, PI].
static func wrap_angle(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


## Yaw of a direction, using the Godot convention (-Z forward, +X right):
## yaw 0 looks down -Z, yaw -PI/2 looks down +X.
static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## Horizontal forward vector of a yaw.
static func forward_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Camera yaw target: look along the velocity, pulled 35 % towards the nose.
static func yaw_target(vel_yaw: float, heading_yaw: float) -> float:
	return vel_yaw + YAW_NOSE_BIAS * wrap_angle(heading_yaw - vel_yaw)


## The horizontal direction the camera follows: the velocity, folded onto the front half of the car. A car that moves
## backwards (it reverses, a hit pushes it back) is followed from behind its nose: the velocity is mirrored across the side
## axis of the car. The raw velocity of a reversing car points at the tail, which put the camera in front of the car, and a
## straight reverse sat on the 180 degree seam of the nose bias: the target jumped from one side of the car to the other
## with every touch of the steering (a swing of 126 degrees, the "camera cuts when I reverse").
static func follow_direction(velocity: Vector3, forward: Vector3) -> Vector3:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var nose := Vector3(forward.x, 0.0, forward.z)
	if nose.length() < 0.001:
		return flat
	nose = nose.normalized()
	var along := flat.dot(nose)
	if along < 0.0:
		flat -= nose * (2.0 * along)
	return flat


## Target vFOV for a speed in m/s and the active boost kinds.
static func fov_target(speed_mps: float, nitro: bool, mini: bool) -> float:
	var fov := FOV_BASE + FOV_PER_MPS * speed_mps
	if nitro:
		fov += FOV_NITRO
	if mini:
		fov += FOV_MINI
	return clampf(fov, FOV_BASE, FOV_MAX)


## Camera distance behind the car: 6.0 m at rest, +1.2 m at V_TOP (linear).
static func distance_for_speed(speed_kmh: float) -> float:
	var t := clampf(speed_kmh / TOP_SPEED_KMH, 0.0, 1.0)
	return DIST_REST + DIST_TOP_BONUS * t


## Look-at point: the car, `height` above it, `ahead` metres along the velocity.
static func look_point(car_pos: Vector3, dir: Vector3, ahead: float, height: float) -> Vector3:
	return car_pos + Vector3.UP * height + dir * ahead


## Speed-line opacity: 0 below 160 km/h, 1 at 280 km/h.
static func speed_line_intensity(speed_kmh: float) -> float:
	var span := SPEED_LINE_FULL - SPEED_LINE_START
	return clampf((speed_kmh - SPEED_LINE_START) / span, 0.0, 1.0)


## The speed ramp of the radial blur: 0 below 200 km/h, 1 at 300 km/h.
static func blur_ramp(speed_kmh: float) -> float:
	var span := BLUR_FULL - BLUR_START
	return clampf((speed_kmh - BLUR_START) / span, 0.0, 1.0)


## Radial blur strength: the speed ramp times the cap (0.25 in N2, else 0.15).
static func blur_strength(speed_kmh: float, nitro: bool) -> float:
	return blur_ramp(speed_kmh) * (BLUR_NITRO if nitro else BLUR_MAX)


## N2 punch offset over time (0 s = ignition): the camera moves 0.6 m towards the car, then
## 1.0 m back out. The move is smoothed, so it never pops (at most 0.05 m per tick).
static func punch_offset(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t < PUNCH_KICK_TIME:
		return PUNCH_KICK * smooth01(t / PUNCH_KICK_TIME)
	if t < PUNCH_TIME:
		var k := (t - PUNCH_KICK_TIME) / (PUNCH_TIME - PUNCH_KICK_TIME)
		return lerpf(PUNCH_KICK, PUNCH_KICK + PUNCH_RECOVER, smooth01(k))
	return PUNCH_KICK + PUNCH_RECOVER


## N2 punch release after the boost ends: back to neutral over 1.0 s.
static func punch_release(t: float) -> float:
	return punch_release_from(PUNCH_KICK + PUNCH_RECOVER, t)


## The same, but from wherever the punch happens to be (the N2 can end mid-kick).
static func punch_release_from(from: float, t: float) -> float:
	if t >= PUNCH_RELEASE_TIME:
		return 0.0
	return lerpf(from, 0.0, t / PUNCH_RELEASE_TIME)


## Shake amplitude for a landing: 0.10 m per 10 m/s of impact, capped.
static func landing_shake(impact_speed: float) -> float:
	return minf(LANDING_SHAKE * (impact_speed / LANDING_SHAKE_PER_V), LANDING_SHAKE_MAX)


## Shake amplitude for any hit: a car hit needs a bigger impulse before it shakes, a wall
## hit scales with the impulse.
static func hit_shake(impulse: float, car_hit: bool) -> float:
	if car_hit:
		return CAR_HIT_SHAKE_MAX if impulse >= CAR_HIT_SHAKE_MIN_IMPULSE else 0.0
	return wall_shake(impulse)


## Shake amplitude for a wall hit, scaled by the impulse.
static func wall_shake(impulse: float) -> float:
	if impulse < WALL_SHAKE_MIN_IMPULSE:
		return 0.0
	var t := clampf((impulse - WALL_SHAKE_MIN_IMPULSE) /
			(WALL_SHAKE_MAX_IMPULSE - WALL_SHAKE_MIN_IMPULSE), 0.0, 1.0)
	return lerpf(WALL_SHAKE_MIN, WALL_SHAKE_MAX, t)
