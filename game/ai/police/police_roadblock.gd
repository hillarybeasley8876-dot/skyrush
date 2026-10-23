class_name PoliceRoadblock
extends Node3D
## A stationary roadblock (ref/gameplay/DOSSIER.md §6.3).
##
## The cars stand broadside across the carriageway of the player, kerb to kerb, alternating
## +/-12 degrees like a real 设卡. Up to heat 3 the block has exactly one body-to-body gap of
## three metres to thread; from heat 4 the block is closed and a full-width spike strip lies
## seven metres in front of it.
##
## The local frame of the block: the X axis is across the road, the -Z axis is the direction of
## the traffic. So everything the driver meets BEFORE the cars (the cone taper, the sign board,
## the strip of the closed block) stands at a positive z.
##
## The parked cars are frozen while they wait, but a real hit of at least 3 m/s shoves them off
## the road: they are cars, not walls. A shoved car stays a prop (it does not drive away) and
## leaves with the block.


## The length and the width of a blocked car (m).
const CAR_LENGTH := 4.79
const CAR_WIDTH := 2.08
## The cars stand broadside across the road, with a small alternating tilt (degrees).
const YAW := 90.0
const YAW_ALT := 12.0
## The body-to-body gap of the block up to heat 3 (m).
const GAP := 3.1
## The number of cars a pooled block holds.
const CAR_COUNT := 4
## The least number of cars a block stands on: the block needs two cars and the gap (m).
const MIN_BLOCK_CARS := 2
## The space between two cars of a closed block (m): they touch, but they do not overlap.
const CAR_PITCH_MARGIN := 0.1
## The strip in front of the closed block (m).
const STRIP_AHEAD := 7.0
## A parked car is shoved off the road when it is hit this hard (m/s).
const SHOVE_SPEED := 3.0
## The block is removed this long after the player passed it (s).
const PASSED_TIMEOUT := 20.0
## The distance at which the player counts as passed (m).
const PASSED_DISTANCE := 25.0
## The depth under the road where the cars that the block does not need wait (m).
const PARKED_DEPTH := 30.0

## The cars of the block.
var cars: Array[PoliceCar] = []
## The strip in front of the closed block.
var strips: Array[PoliceSpikeStrip] = []
## True once the player has driven past the block on the level of the block.
var passed: bool = false
## The width of the carriageway the block was built for (m).
var width: float = 0.0

## The seconds since the player went past the block (the block leaves the road then).
var _passed_time: float = 0.0
## The closest the player came to the block (m).
var _closest: float = INF
## The closest the player came to the block on the level of the block (m).
var _level_closest: float = INF
var _car_used: Array[bool] = []
## The dressing of the block (the barriers, the cones and the sign board).
var props: PoliceRoadblockProps = PoliceRoadblockProps.new()


## Builds the block once: the cars, the barriers, the cones, the sign and the strip.
##
## The block is pooled, so everything is built here and only moved in setup().
func build_pool(ctx: DriveContext, grid: LaneGrid) -> void:
	for i in CAR_COUNT:
		var car := PoliceFleet.build_unit(self, &"patrol", PoliceFleet.Role.PATROL, ctx,
				Transform3D.IDENTITY, i, grid)
		if car == null:
			continue
		car.parked = true
		car.freeze = true
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.set_lights_enabled(false)
		cars.append(car)
	props.build(self)
	var strip := PoliceSpikeStrip.new()
	strip.name = "BlockStrip"
	add_child(strip)
	strip.setup(Vector3.RIGHT)
	strips.append(strip)
	set_active(false)


## Switches the block on and off: a block that waits in the pool must not cost a frame.
##
## A block that is not in use has no collider either: a car without a collider is an invisible
## wall on the road, and the block leaves the road when it is over.
func set_active(active: bool) -> void:
	visible = active
	for i in cars.size():
		var car := cars[i]
		var used := active and i < _car_used.size() and _car_used[i]
		car.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		car.visible = used
		car.collision_layer = 2 if used else 0
		# Only the cars that stand on the road are police cars: the ones that wait in the
		# block or under the road are not in the groups.
		if used:
			car.add_to_group("police")
			car.add_to_group("vehicles")
		else:
			car.remove_from_group("police")
			car.remove_from_group("vehicles")


## Sets the block up on the road: the cars across the carriageway, the barriers to the kerbs,
## the cone taper, the sign board and (from heat 4) the strip.
func setup(xform: Transform3D, _across: Vector3, carriageway: float, heat: int,
		seed_value: int) -> void:
	global_transform = xform
	var gap := GAP if heat < 4 else 0.0
	# The block stands on the whole carriageway, but it is never narrower than its cars and
	# the gap: a block without a gap is a wall, and a gap of less than a car is no gap.
	width = maxf(carriageway, float(MIN_BLOCK_CARS) * car_span() + gap)
	var slots := _car_slots(carriageway, gap)
	_place_cars(slots, gap)
	props.place(carriageway, slots, gap, car_span())
	_place_strips(heat)
	set_active(true)
	passed = false
	_passed_time = 0.0
	_closest = INF
	_level_closest = INF


## The lateral positions of the cars: they fill the carriageway, with one gap up to heat 3.
##
## A closed block has as many cars as fit in the road: the rest of the width is closed with
## barriers. The cars never overlap: the pitch is the span of a car plus a margin.
func _car_slots(carriageway: float, gap: float) -> Array[float]:
	var out: Array[float] = []
	var span := car_span()
	if gap <= 0.0:
		# The block is closed: the cars stand from kerb to kerb.
		var closed := clampi(int(floor(carriageway / span)), 1, CAR_COUNT)
		var pitch := span + CAR_PITCH_MARGIN
		var start := -float(closed) * pitch * 0.5
		for i in closed:
			out.append(start + (float(i) + 0.5) * pitch)
		return out
	var count := clampi(int(floor((carriageway - gap) / span)), 1, CAR_COUNT)
	# The gap sits between two cars, never at the end of the block.
	var gap_index := maxi(count - 1, 0) / 2
	var x := -carriageway * 0.5
	for i in count:
		out.append(x + span * 0.5)
		x += span
		if i == gap_index:
			x += gap
	return out


## The space a broadside car takes across the road (m).
func car_span() -> float:
	var tilt := deg_to_rad(YAW_ALT)
	return CAR_LENGTH * absf(cos(tilt)) + CAR_WIDTH * absf(sin(tilt))


## Puts the cars on their slots, broadside, and hides the cars the block does not need.
func _place_cars(slots: Array[float], gap: float) -> void:
	_car_used.clear()
	for i in cars.size():
		var car := cars[i]
		var used := i < slots.size()
		_car_used.append(used)
		if not used:
			# The car that the block does not need waits under the road: it must not stand in
			# the way of the cars of the block, or the contacts of the physics are mixed up.
			car.transform = Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, -PARKED_DEPTH, 0.0))
			car.freeze = true
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			continue
		car.freeze = true
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		var yaw := deg_to_rad(YAW + (YAW_ALT if i % 2 == 0 else -YAW_ALT))
		car.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(slots[i], 0.0, 0.0))


## The full-width spike strip in front of the closed block.
func _place_strips(heat: int) -> void:
	for strip in strips:
		strip.visible = heat >= 4
		if heat < 4:
			continue
		strip.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, STRIP_AHEAD))
		strip.reset_strip()


## The cars of the block that are in use (the block holds more than it needs).
func active_cars() -> Array[PoliceCar]:
	var out: Array[PoliceCar] = []
	for i in cars.size():
		if i < _car_used.size() and _car_used[i]:
			out.append(cars[i])
	return out


## The cones of the block (the tests read them).
func cones() -> Array[Node3D]:
	return props.cones


## The barriers of the block (the tests read them).
func barriers() -> Array[Node3D]:
	return props.barriers


## The strips of the block that are in use.
func active_strips() -> Array[PoliceSpikeStrip]:
	var out: Array[PoliceSpikeStrip] = []
	for strip in strips:
		if strip.visible:
			out.append(strip)
	return out


## The tick of the block: the cars flash, the strip unrolls and the block leaves when it is done.
##
## Only a player on the level of the block meets it: a player who drives over the block on the
## deck above it has not passed the block on the street.
func tick(dt: float, player: VehicleBase) -> void:
	for car in cars:
		car.tick(dt)
	for strip in strips:
		strip.tick(dt)
	if player == null:
		return
	var distance := global_position.distance_to(player.global_position)
	_closest = minf(_closest, distance)
	# The player meets the block on its level: the distance of the meeting is only a meeting
	# when the player is not ten metres above or below the block.
	var on_level := absf(player.global_position.y - global_position.y) <= PolicePursuit.LEVEL
	if on_level:
		_level_closest = minf(_level_closest, distance)
	if not passed and _level_closest < PASSED_DISTANCE and distance > PASSED_DISTANCE * 1.6:
		passed = true
	# The block leaves the road when the player has gone past it: a block on the street must
	# not stay there when the player drove over it on the deck.
	if _closest < PASSED_DISTANCE and distance > PASSED_DISTANCE * 1.6:
		_passed_time += dt


## A real contact with one of the parked cars: a hard hit shoves it off the road.
##
## The car stays a prop (it does not drive away) and it leaves with the block.
func on_collision(vehicle: VehicleBase, other: Node3D, closing: float) -> void:
	if vehicle == null or other == null:
		return
	var car := other as PoliceCar
	if car == null or not cars.has(car):
		return
	if not car.freeze or closing < SHOVE_SPEED:
		return
	car.freeze = false
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.set_controls(0.0, 1.0, 0.0, true)


## True when the block may be removed.
##
## The block leaves the road when the player has gone past it (the flag `passed` says whether
## he met it on its level).
func is_expired() -> bool:
	return _passed_time > PASSED_TIMEOUT
