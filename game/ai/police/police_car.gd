class_name PoliceCar
extends ArcadeCar
## One police unit of the pursuit (ref/gameplay/DOSSIER.md §3.4, §6.3, §7.3).
##
## The unit drives the same physics as the player (an ArcadeCar with a CarSpec of the fleet), so
## a ram or a PIT is a real collision and not a scripted animation.
##
##   PATROL   - the lane path, like the traffic; a patrol stays on its round until the
##              dispatcher starts a pursuit
##   PURSUE   - the player, with a time lead
##   RAM      - the rear bumper of the player
##   PIT      - the rear quarter of the player, then a hard steer into it
##   BOX      - the front unit drives ahead, the side units squeeze from both sides
##   HEAD_ON  - the SUV that comes the other way
##
## The behaviour table lives in PoliceCarRoles; this class owns the driving, the life cycle of
## the unit and the car following. The dispatcher (police_director.gd) hands out the role, the
## line of sight and the contacts.

enum State { PATROL, PURSUE, RAM, PIT, BOX, HEAD_ON, WRECK }

const WRECK_LIFETIME := 10.0  ## s: how long a wreck stays on the road
const RAM_DURATION := 2.5     ## s: the longest a ram lasts
const RAM_COOLDOWN := 3.0     ## s: the pause before the same unit may ram again
const PIT_COOLDOWN := 6.0     ## s: the pause before the same unit may PIT again
## A unit that is upside down counts as disabled (dossier §6.3).
const FLIP_DOT := 0.3
## A unit that stands still while it is engaged counts as disabled (dossier §6.3).
const STUCK_SPEED := 2.0
## The damping of a wreck (it must not slide any more).
const WRECK_DAMP := 2.0
## The distance the unit gives up on the player when it holds back (m).
const HOLD_BACK_DISTANCE := 38.0
## The seconds a ghost unit waits between two moves (a body update costs a physics step).
const GHOST_STEP := 0.1
## The tick clock of the unit (s): the gameplay timing does not run on the wall clock.
const CLOCK_START := 0.0
## The difference between the speed of the car and the speed of the following at which the
## model takes the real speed back (m/s). It is a large one on purpose: a corner that limits
## the speed of the car is not a reason to throw the model away.
const FOLLOW_RESYNC := 8.0

var ctx: DriveContext = null
var follower: LaneFollower = null
## The unit kind of the fleet (&"patrol", &"interceptor", &"heavy_suv").
var kind: StringName = &"patrol"
## The role the dispatcher gave this unit.
var role: PoliceFleet.Role = PoliceFleet.Role.PATROL
var state: State = State.PATROL
## The seconds the unit has been in its state.
var state_time: float = 0.0
## The seconds before this unit may use its role again (the 3 s / 6 s cooldowns).
var role_cooldown: float = 0.0
## True while the dispatcher sees the player from this unit.
var seen: bool = false
## Seconds of memory: how long the unit still chases after it lost the player.
var engaged: float = 0.0
## Set when the unit must be removed.
var despawn: bool = false
## The time of the last contact with the player (the tick clock of the unit).
var player_contact: float = -99.0
## True when the car is a parked roadblock unit: it only flashes its light bar.
var parked: bool = false
## True when the unit is disabled (wrecked, flipped or stuck).
var disabled: bool = false
## The seconds the unit has been a wreck.
var wreck_time: float = 0.0
## True once the unit has been counted as disabled.
var counted_disabled: bool = false
## True while the unit keeps its distance from the player (the hold-back of §6.3).
var hold_back: bool = false
## True while a pursuit is running: only then the units react to the player.
var pursuit_active: bool = false
## The seconds the unit has been out of sight of the camera.
var off_screen_time: float = 0.0
## True while the unit drives as a ghost (the dispatcher holds its body).
var ghost: bool = false
## The point the unit drives at.
var target_point: Vector3 = Vector3.ZERO
## The speed the unit aims for (m/s).
var desired_speed: float = 0.0
## The last driving input of the unit (the debug overlay and the tests read it).
var steer_command: float = 0.0
## True when the unit drives with the full car physics; a far unit drives as a ghost instead.
var full_physics: bool = true
## The point the hold-back unit keeps (the director puts it on the lane of the player).
var hold_back_point: Vector3 = Vector3.ZERO
## The speed the hold-back unit keeps (m/s).
var hold_back_speed: float = 0.0
## The velocity cache of the contacts (the speed of the player of the previous tick).
var contact: PoliceContact = null
## The tick clock of the unit (s).
var clock: float = CLOCK_START

var light_bar: PoliceLightBar = PoliceLightBar.new()
var sleep_state: PoliceSleep = PoliceSleep.new()
## The behaviour table of the roles (PoliceCarRoles).
var roles: PoliceCarRoles = null

## The extra steering of the unit (the cross-track term of the head-on unit).
var steer_bias: float = 0.0
## The time a ghost unit has waited for its next move.
var _ghost_timer: float = 0.0
## The speed the car following integrates (m/s): the IDM has a speed of its own.
var _follow_speed: float = 0.0
## The gap to the car in front (m): the debug overlay and the tests read it.
var follow_gap: float = INF


## Builds the unit: the fleet preset, the lane state and the light bar.
##
## The unit starts its lane state at the place it is put, so a unit that is spawned 300 m away
## stays there instead of being snapped onto the player.
func configure(context: DriveContext, unit_kind: StringName, unit_role: PoliceFleet.Role,
		lane: int, offset: float, seed_value: int) -> void:
	ctx = context
	kind = unit_kind
	follower = LaneFollower.new()
	follower.setup(context.graph, lane, offset, seed_value)
	roles = PoliceCarRoles.new(self)
	# The role and the state always agree: a unit that is placed with the role PURSUE pursues
	# from the first tick, not from the moment the dispatcher assigns it a new role.
	set_role(unit_role)
	light_bar.phase = float(seed_value % 1000) / 1000.0 * PoliceLights.LOOP
	desired_speed = PoliceDriver.lane_speed_limit(ctx, follower)
	_follow_speed = desired_speed


## The scene tree is ready: the visual of the car is built, so the light bar can be found.
func _ready() -> void:
	super._ready()
	light_bar.build(self, get_visual_root())


## One tick of the unit. The dispatcher calls it for every unit, in a fixed order.
func tick(dt: float) -> void:
	if parked:
		light_bar.update(dt)
		return
	clock += dt
	state_time += dt
	role_cooldown = maxf(role_cooldown - dt, 0.0)
	engaged = maxf(engaged - dt, 0.0)
	roles.tick(dt)
	if full_physics:
		if ghost:
			# The unit drives for real now.
			ghost = false
			freeze = false
			process_mode = Node.PROCESS_MODE_INHERIT
		_drive(dt)
	else:
		if not ghost:
			# A far unit does not cost a physics step: it drives as a ghost.
			ghost = true
			process_mode = Node.PROCESS_MODE_DISABLED
		_drive_ghost(dt)
	light_bar.update(dt)


## Puts the unit back into its initial state (the pool reuses the cars).
func reset_for_spawn() -> void:
	state = State.PATROL
	state_time = 0.0
	role_cooldown = 0.0
	seen = false
	engaged = 0.0
	despawn = false
	player_contact = -99.0
	parked = false
	disabled = false
	wreck_time = 0.0
	counted_disabled = false
	hold_back = false
	pursuit_active = false
	off_screen_time = 0.0
	target_point = Vector3.ZERO
	desired_speed = 0.0
	steer_command = 0.0
	full_physics = true
	hold_back_point = Vector3.ZERO
	hold_back_speed = 0.0
	steer_bias = 0.0
	clock = CLOCK_START
	_follow_speed = 0.0
	ghost = false
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	set_controls(0.0, 0.0, 0.0, true)
	repair()
	if roles != null:
		roles.reset()


## The dispatcher hands out a new role.
##
## The state always follows the role while the unit is neutral (PATROL or PURSUE), so a unit
## that is placed with a role really plays that role. A unit that is cooling down after its
## role keeps the state it has: the pause of the role is a real pause.
func set_role(new_role: PoliceFleet.Role) -> void:
	var changed := new_role != role
	role = new_role
	if state != State.PATROL and state != State.PURSUE:
		return
	if not changed and role_cooldown > 0.0:
		return
	roles.enter_state(roles.state_for_role(new_role))


## Puts the unit to sleep (frozen on its lane) or wakes it up.
func put_to_sleep(asleep: bool) -> void:
	sleep_state.put_to_sleep(self, asleep)


## The dispatcher gives the omni lights of the light bar to the three nearest units only.
func set_lights_enabled(enabled: bool) -> void:
	light_bar.set_enabled(enabled)


## The car following: the unit keeps the gap to the car in front (the IDM of the traffic unit).
##
## A unit never pushes another car: the car in front sets the speed. The player is the one
## exception the police car brakes for, and there it stops right behind him (a small minimum
## gap), so a standing player is busted and not shoved down the road.
##
## `stops_for_player` is false for the roles that hit the player on purpose (the ram, the PIT
## and the box: the box squeezes him, it does not stop for him).
##
## `formation` is true for the box: the three units of the box drive in a formation, so the
## police car in front of them and the player himself do not set their speed. Only the traffic
## does.
##
## The IDM has a speed of its own (`_follow_speed`): the model integrates the acceleration, and
## the car asks for that speed. With the real speed of the car as the input of the model the
## acceleration is a step above the speed, and the throttle of the car is always zero.
func apply_following(dt: float, wanted: float, stops_for_player: bool,
		formation: bool = false) -> void:
	var space := get_world_3d().direct_space_state
	var lead := PoliceFollow.leader(space, self)
	var leader := lead["body"] as Node3D
	var is_player := leader == ctx.player if ctx != null else false
	if formation and (leader is PoliceCar or is_player):
		# The formation sets the speed: the unit drives where the formation puts it.
		desired_speed = wanted
		_follow_speed = wanted
		return
	if leader != null and is_player and (not stops_for_player or _player_is_beside()):
		# The player is beside the unit, not in front of it: he does not block the way.
		desired_speed = wanted
		_follow_speed = wanted
		return
	follow_gap = float(lead["gap"])
	var s0 := PoliceFollow.PLAYER_S0 if is_player else IDM.S0
	# The model of the following has a speed of its own. When the car and the model drift apart
	# (a spawn, a crash, a shove) the model takes the real speed back.
	var actual := PoliceDriver.speed(self)
	if absf(_follow_speed - actual) > FOLLOW_RESYNC:
		_follow_speed = actual
	var dv := _follow_speed - float(lead["speed"])
	var accel := PoliceFollow.acceleration(_follow_speed, maxf(wanted, PoliceFollow.MIN_TARGET),
			float(lead["gap"]), dv, s0)
	_follow_speed = maxf(_follow_speed + accel * dt, 0.0)
	desired_speed = _follow_speed


## True when the player is beside the unit and not in front of it.
##
## The side units of the box drive next to the player: the player does not stand in their way.
func _player_is_beside() -> bool:
	if ctx == null or ctx.player == null:
		return false
	var rel := PoliceDriver.relative_to_player(self, ctx.player)
	return absf(rel.x) > PoliceFollow.PLAYER_BESIDE


## The speed of the player of the previous physics tick (m/s), from the contact cache.
func cached_player_speed() -> float:
	if contact == null or ctx == null or ctx.player == null:
		return -1.0
	return contact.cached_speed(ctx.player)


## The dispatcher tells the unit which side of the player it boxes.
func set_box_side(side: float) -> void:
	roles.set_box_side(side)


## Turns the target into a driving input and hands it to the car.
func _drive(dt: float) -> void:
	var strike := 0.0
	if roles != null:
		strike = roles.strike_sign()
	steer_command = PoliceDriver.drive(self, target_point, desired_speed, strike, steer_bias)


## The unit is far away: it drives its target as a ghost, so it does not push the world around.
##
## A ghost moves in steps: a body that changes its transform costs a physics step, and a dozen of
## them would cost more than the chase.
func _drive_ghost(dt: float) -> void:
	_ghost_step(dt)


## The ghost moves one step along its lane (the body is frozen and placed on the lane graph).
func _ghost_step(dt: float) -> void:
	_ghost_timer += dt
	if _ghost_timer < GHOST_STEP:
		return
	var step := _ghost_timer
	_ghost_timer = 0.0
	sleep_state.roll_lane(self, follower, desired_speed, step)


## The dispatcher tells the unit that it touched the player.
func notify_contact() -> void:
	roles.mark_contacted()
	player_contact = clock


## True while the unit is in its PIT strike (the tap of the PIT is only allowed then).
func is_striking() -> bool:
	return roles.is_striking()


## True when the tap of the PIT was already given in this strike.
func pit_assisted() -> bool:
	return roles.pit_assisted()


## The tap of the PIT was given in this strike.
func mark_pit_assisted() -> void:
	roles.mark_pit_assisted()


## True when the unit lies on its roof.
func is_flipped() -> bool:
	return global_transform.basis.y.dot(Vector3.UP) < FLIP_DOT


## True when the unit stands still while it is engaged with the player.
func is_stuck() -> bool:
	return PoliceDriver.speed(self) < STUCK_SPEED and engaged > 0.0
