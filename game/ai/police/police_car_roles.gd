class_name PoliceCarRoles
extends RefCounted
## The behaviour table of a police unit (ref/gameplay/DOSSIER.md §6.3).
##
## The module owns what a unit does in each of its states: the target it drives at, the speed it
## asks for and the moment it takes its role. The car (PoliceCar) owns the driving, the life
## cycle of the unit and the car following.
##
## The roles that hit the player on purpose (the ram, the PIT and the head-on charge) do not
## brake for the car in front; the others do, so a unit never pushes another police car.

var car: PoliceCar = null

var _pit_side: float = 1.0
## The side of the player the dispatcher gave this unit for the box (-1, 0 or +1).
var _box_side_value: float = 0.0
var _pit_strike_timer: float = 0.0
var _pit_assisted: bool = false
var _strike_sign: float = 0.0
var _head_on_timer: float = 0.0
var _contacted: bool = false


func _init(owned_car: PoliceCar) -> void:
	car = owned_car


## Puts the role state back to its start (the pool reuses the cars).
func reset() -> void:
	_pit_side = 1.0
	_box_side_value = 0.0
	_pit_strike_timer = 0.0
	_pit_assisted = false
	_strike_sign = 0.0
	_head_on_timer = 0.0
	_contacted = false
	car.steer_bias = 0.0


## The tick of the unit: the state table of the dossier.
func tick(dt: float) -> void:
	if car.hold_back:
		_tick_hold_back(dt)
		return
	match car.state:
		PoliceCar.State.PATROL:
			_tick_patrol(dt)
		PoliceCar.State.PURSUE:
			_tick_pursue(dt)
		PoliceCar.State.RAM:
			_tick_ram(dt)
		PoliceCar.State.PIT:
			_tick_pit(dt)
		PoliceCar.State.BOX:
			_tick_box(dt)
		PoliceCar.State.HEAD_ON:
			_tick_head_on(dt)


## The state a role starts in.
func state_for_role(unit_role: PoliceFleet.Role) -> PoliceCar.State:
	match unit_role:
		PoliceFleet.Role.PATROL:
			return PoliceCar.State.PATROL
		PoliceFleet.Role.RAM:
			return PoliceCar.State.RAM
		PoliceFleet.Role.PIT:
			return PoliceCar.State.PIT
		PoliceFleet.Role.BOX_FRONT, PoliceFleet.Role.BOX_SIDE:
			return PoliceCar.State.BOX
		PoliceFleet.Role.HEAD_ON:
			return PoliceCar.State.HEAD_ON
		_:
			return PoliceCar.State.PURSUE


## Switches to a new state and resets its clock.
func enter_state(new_state: PoliceCar.State) -> void:
	if car.state == new_state:
		return
	car.state = new_state
	car.state_time = 0.0
	if new_state == PoliceCar.State.PIT:
		_pit_side = _choose_pit_side()


## PATROL: the unit drives its lane like the traffic. A patrol does not chase: it only reacts
## when the dispatcher starts a pursuit.
func _tick_patrol(dt: float) -> void:
	if car.seen and car.pursuit_active:
		car.engaged = PolicePursuit.ENGAGE_MEMORY
		enter_state(PoliceCar.State.PURSUE)
		return
	if car.follower == null or car.ctx == null or car.ctx.graph == null:
		return
	car.follower.tick(dt)
	if car.follower.advance(PoliceDriver.speed(car) * dt) < 0:
		car.despawn = true
		return
	car.target_point = car.follower.lookahead(PoliceTactics.patrol_lookahead(PoliceDriver.speed(car)))
	car.apply_following(dt, PoliceDriver.lane_speed_limit(car.ctx, car.follower), true)


## The hold-back: the unit keeps the distance to the player instead of taking its role.
func _tick_hold_back(dt: float) -> void:
	if car.ctx == null or car.ctx.player == null:
		return
	car.target_point = car.hold_back_point
	# The unit that holds back keeps its distance with its speed: it must not drive up to the
	# player and wait there.
	car.apply_following(dt, maxf(car.hold_back_speed, 0.0), false)


## PURSUE: the unit aims where the player will be and closes in.
func _tick_pursue(_dt: float) -> void:
	var player := car.ctx.player if car.ctx != null else null
	if player == null:
		return
	var to_player := player.global_position - car.global_position
	var distance := to_player.length()
	var direction := to_player / maxf(distance, 0.001)
	var closing := (car.linear_velocity - player.linear_velocity).dot(direction)
	var lead := PoliceTactics.pursuit_lead(distance, closing)
	car.target_point = player.global_position + player.linear_velocity * lead
	var wanted := PoliceTactics.pursue_speed(player, distance,
			PoliceDriver.top_speed(car, car.ctx, car.kind), car.cached_player_speed())
	car.apply_following(_dt, wanted, _stops_for_player())
	_try_role_state(distance)


## True when the unit brakes for the player that is in front of it.
##
## The roles that hit the player on purpose (the ram, the PIT and the box) do not: they are
## there to touch him.
func _stops_for_player() -> bool:
	match car.role:
		PoliceFleet.Role.RAM, PoliceFleet.Role.PIT, PoliceFleet.Role.BOX_FRONT, \
				PoliceFleet.Role.BOX_SIDE:
			return false
		_:
			return true


## The unit takes its role as soon as the geometry allows it (§6.3).
func _try_role_state(distance: float) -> void:
	if car.role_cooldown > 0.0 or car.state_time < PoliceTactics.ROLE_ENTER_DELAY:
		return
	var player := car.ctx.player
	if player == null:
		return
	var rel := PoliceDriver.relative_to_player(car, player)
	match car.role:
		PoliceFleet.Role.RAM:
			if rel.z > 0.0 and rel.z < PoliceTactics.RAM_DISTANCE \
					and absf(rel.x) < PoliceTactics.RAM_LATERAL:
				enter_state(PoliceCar.State.RAM)
		PoliceFleet.Role.PIT:
			if rel.z > -PoliceTactics.PIT_REAR_CLEARANCE \
					and rel.z < PoliceTactics.PIT_APPROACH \
					and absf(rel.x) < PoliceTactics.PIT_APPROACH_LATERAL:
				enter_state(PoliceCar.State.PIT)
		PoliceFleet.Role.BOX_FRONT, PoliceFleet.Role.BOX_SIDE:
			if distance < PoliceTactics.BOX_ENTER_DISTANCE:
				enter_state(PoliceCar.State.BOX)
		PoliceFleet.Role.HEAD_ON:
			enter_state(PoliceCar.State.HEAD_ON)


## RAM: the unit aims at the rear bumper of the player and pushes past it.
func _tick_ram(_dt: float) -> void:
	var player := car.ctx.player
	if player == null:
		return
	var side := 1.0 if PoliceDriver.side_of_player(car, player) >= 0.0 else -1.0
	car.target_point = PoliceTactics.ram_target(player, side)
	car.desired_speed = PoliceTactics.ram_speed(player, car.state_time < PoliceTactics.RAM_BOOST,
			PoliceDriver.top_speed(car, car.ctx, car.kind))
	if _contacted or car.state_time > PoliceCar.RAM_DURATION:
		car.role_cooldown = PoliceCar.RAM_COOLDOWN
		_contacted = false
		enter_state(PoliceCar.State.PURSUE)


## PIT: the unit sits next to the rear quarter of the player and then steers into it.
func _tick_pit(dt: float) -> void:
	var player := car.ctx.player
	if player == null:
		return
	var rel := PoliceDriver.relative_to_player(car, player)
	# The target: the line beside the player, and then the rear quarter.
	car.target_point = PoliceTactics.pit_target(player, _pit_side, rel)
	car.desired_speed = minf(PoliceTactics.pit_speed(player, rel),
			PoliceDriver.top_speed(car, car.ctx, car.kind))
	if _pit_strike_timer > 0.0:
		_pit_strike_timer -= dt
		if _contacted:
			# The strike hit: the unit goes back to the pursuit and cools down.
			_contacted = false
			car.role_cooldown = PoliceCar.PIT_COOLDOWN
			enter_state(PoliceCar.State.PURSUE)
			return
		if _pit_strike_timer <= 0.0:
			car.role_cooldown = PoliceCar.PIT_COOLDOWN
			enter_state(PoliceCar.State.PURSUE)
		return
	# The strike: the unit is at the rear quarter of the player with a small gap between them.
	var gap := PoliceTactics.pit_gap(rel)
	var distance := player.global_position.distance_to(car.global_position)
	if PoliceTactics.pit_ready(rel, gap, distance):
		_pit_strike_timer = PoliceTactics.PIT_STRIKE_TIME
		_pit_assisted = false
		_strike_sign = -_pit_side


## BOX: the front unit drives ahead of the player, the side units squeeze from both sides.
func _tick_box(dt: float) -> void:
	var player := car.ctx.player
	if player == null:
		return
	var front := car.role == PoliceFleet.Role.BOX_FRONT
	var side := _box_side()
	var rel := PoliceDriver.relative_to_player(car, player)
	car.target_point = PoliceTactics.box_target(player, front, side, rel)
	var wanted := PoliceTactics.box_speed(player, front, side, rel,
			PoliceDriver.top_speed(car, car.ctx, car.kind))
	# The three units of the box drive in a formation: the car in front of them is part of
	# the formation, so it does not make them wait.
	car.apply_following(dt, wanted, false, true)
	if car.state_time > PoliceTactics.BOX_BREAK_TIME:
		enter_state(PoliceCar.State.PURSUE)


## HEAD_ON: the SUV charges the player and turns around when it misses.
func _tick_head_on(dt: float) -> void:
	var player := car.ctx.player
	if player == null:
		return
	if _head_on_timer > 0.0:
		# The U-turn after a miss: the unit turns on the road, it does not swing a 100 m arc.
		_head_on_timer -= dt
		car.target_point = car.global_position - car.get_forward() * PoliceTactics.HEAD_ON_TURN_DISTANCE
		car.desired_speed = PoliceTactics.HEAD_ON_TURN_SPEED
		if _head_on_timer <= 0.0:
			enter_state(PoliceCar.State.PURSUE)
		return
	car.target_point = PoliceTactics.head_on_target(player)
	car.desired_speed = PoliceTactics.HEAD_ON_SPEED
	# The unit comes down to the line of the player: the distance to that line is the
	# cross-track term of the steering.
	var lateral := (car.global_position - player.global_position).dot(player.global_transform.basis.x)
	car.steer_bias = PoliceDriver.cross_track_steer(lateral, PoliceDriver.speed(car))
	var rel := PoliceDriver.relative_to_player(car, player)
	if rel.z > PoliceTactics.HEAD_ON_GIVE_UP_DISTANCE \
			or car.state_time > PoliceTactics.HEAD_ON_GIVE_UP_TIME:
		_head_on_timer = PoliceTactics.HEAD_ON_TURN_TIME


## The side of the player this unit boxes: the dispatcher gives the two side units opposite
## sides, so the box really closes.
func _box_side() -> float:
	if _box_side_value != 0.0:
		return _box_side_value
	var player := car.ctx.player if car.ctx != null else null
	return PoliceDriver.side_of_player(car, player)


## The dispatcher tells the unit which side of the player it boxes.
func set_box_side(side: float) -> void:
	_box_side_value = side


## The side of the player the PIT works on. A unit that is exactly behind the player has no
## side yet, so it takes the right one.
func _choose_pit_side() -> float:
	var player := car.ctx.player if car.ctx != null else null
	if player == null:
		return 1.0
	var rel := PoliceDriver.relative_to_player(car, player)
	if absf(rel.x) < 0.6:
		return 1.0
	return 1.0 if rel.x > 0.0 else -1.0


## The direction of the PIT strike (0 when the unit is not striking).
func strike_sign() -> float:
	return _strike_sign


## The unit touched the player.
func mark_contacted() -> void:
	_contacted = true


## True while the unit is in its PIT strike.
func is_striking() -> bool:
	return _pit_strike_timer > 0.0


## True when the tap of the PIT was already given in this strike.
func pit_assisted() -> bool:
	return _pit_assisted


## The tap of the PIT was given in this strike.
func mark_pit_assisted() -> void:
	_pit_assisted = true
