class_name PoliceSpawner
extends RefCounted
## Where the police units come from (ref/gameplay/DOSSIER.md §3.4 and §6.3).
##
## The spawner owns the ring (150-320 m, never in the view of the player, never more than three
## units within thirty metres), the police stations of the world, the roles of the heat table and
## the backup timer. It hands the dispatcher the cars; it does not drive them.
##
## The spawn mix prefers the units that come towards the player: the units that appear in front
## of him have to make a U-turn, the ones that come from the oncoming lanes do not.

const SPAWN_MIN := 150.0      ## m: the inner edge of the spawn ring
const SPAWN_MAX := 320.0      ## m: the outer edge of the spawn ring
const CLOSE_LIMIT := 3        ## never more than three units within CLOSE_RADIUS
const CLOSE_RADIUS := 30.0    ## m
const PATROL_COUNT := 2       ## the patrols on the road when there is no pursuit
const SPAWN_INTERVAL := 2.5   ## s: the time between two units of the same pursuit
const FIRST_SPAWN := 1.2      ## s: the delay of the first unit
## The time between two attempts after a place was not free (s).
const SPAWN_RETRY := 1.0
## The guard of the walk to the next lane (the tries of a place).
const SPOT_GUARD := 6

## The shared AI context (the lane graph of the world).
var ctx: DriveContext = DriveContext.new()
## The world of the game.
var world: WorldBase = null
## The node the units are added to.
var host: Node3D = null
## The shared random source.
var rng := RandomNumberGenerator.new()
## The pool of the police objects: a spawn is a placement, not an instantiation.
var pool: PolicePool = null
## The velocity cache of the contacts (the speed of the player of the previous tick).
var contact: PoliceContact = null
## The roadblocks of the dispatcher: a unit does not spawn inside a block.
var blockade: PoliceBlockade = null
## The lane grid of the world: the fast "which lane is near this point" search.
var grid: LaneGrid = LaneGrid.new()
## The places the units appear (the spawner keeps the timers and the roles).
var spots: PoliceSpawnSpots = PoliceSpawnSpots.new()
## The role every unit gets (-1 = the roles of the heat table). A test hook.
var forced_role: int = -1
## The roles the units get in order (a test hook; empty = the roles of the heat table).
var forced_roles: Array = []
## The time until the next unit.
var spawn_timer: float = 0.0
## The time until the backup arrives when a running pursuit lost all its units.
var backup_timer: float = 0.0
## False switches the spawning of units off, the backup included (the tests).
var spawn_enabled: bool = true
## True while a pursuit is running: the backup timer only runs then.
var _pursuit_running: bool = false


## Prepares the spawner for a world.
func setup(context: DriveContext, world_node: WorldBase, host_node: Node3D) -> void:
	ctx = context
	world = world_node
	host = host_node
	spawn_timer = FIRST_SPAWN
	grid.build(ctx.graph)
	spots.ctx = ctx
	spots.world = world_node
	spots.host = host_node
	spots.rng = rng
	spots.grid = grid
	spots.blockade = blockade


## The tick of the spawning: the budget of the heat, the backup timer and the out-of-view rule.
##
## Returns the unit that was spawned (null when nothing was).
func update(delta: float, heat: int, player: VehicleBase, units: Array[PoliceCar],
		lane: int, lane_s: float) -> PoliceCar:
	if not spawn_enabled:
		return null
	var live := live_units(units)
	var budget := PoliceHeat.units_max(heat)
	if heat == 0:
		# Without a pursuit the road still has patrols, so an offence can be spotted.
		budget = PATROL_COUNT
	if live.is_empty():
		# The road is empty: the patrols come back, or the backup of a lost pursuit comes.
		if _pursuit_running:
			backup_timer -= delta
			if backup_timer > 0.0:
				return null
			backup_timer = PoliceHeat.backup_time(maxi(heat, 1))
		else:
			spawn_timer -= delta
			if spawn_timer > 0.0:
				return null
		return _try_spawn(wanted_role(heat, 0), heat, player, units, lane, lane_s)
	_pursuit_running = true
	backup_timer = PoliceHeat.backup_time(maxi(heat, 1))
	spawn_timer -= delta
	if spawn_timer > 0.0 or live.size() >= budget:
		return null
	spawn_timer = SPAWN_INTERVAL
	return _try_spawn(wanted_role(heat, live.size()), heat, player, units, lane, lane_s)


## A pursuit starts: the first unit comes within FIRST_SPAWN seconds.
func begin_pursuit(heat: int) -> void:
	_pursuit_running = true
	spawn_timer = FIRST_SPAWN
	backup_timer = FIRST_SPAWN


## The pursuit is over: the patrols fill the road again.
func end_pursuit() -> void:
	_pursuit_running = false
	spawn_timer = FIRST_SPAWN


## Spawns a unit; when no place was free the next attempt comes in SPAWN_RETRY seconds.
func _try_spawn(role: PoliceFleet.Role, heat: int, player: VehicleBase,
		units: Array[PoliceCar], lane: int, lane_s: float) -> PoliceCar:
	var unit := spawn(role, heat, player, units, lane, lane_s)
	if unit == null:
		# The place was not free: try again in a second, not in a whole backup time.
		spawn_timer = SPAWN_RETRY
		backup_timer = SPAWN_RETRY
	return unit


## The units that are still driving.
func live_units(units: Array[PoliceCar]) -> Array[PoliceCar]:
	var out: Array[PoliceCar] = []
	for unit in units:
		if not unit.is_wrecked and not unit.parked:
			out.append(unit)
	return out


## The role of the next unit: the wanted roles in the order of the table of §3.4.
func wanted_role(heat: int, index: int) -> PoliceFleet.Role:
	var wanted := wanted_roles(heat)
	if wanted.is_empty():
		return PoliceFleet.Role.PATROL
	return wanted[mini(index, wanted.size() - 1)]


## The roles the heat asks for.
func wanted_roles(heat: int) -> Array:
	if heat == 0:
		var patrol: Array = []
		for i in PATROL_COUNT:
			patrol.append(PoliceFleet.Role.PATROL)
		return patrol
	var out: Array = [PoliceFleet.Role.PURSUE]
	if heat >= 1:
		out.append(PoliceFleet.Role.RAM)
	if heat >= 2:
		out.append(PoliceFleet.Role.BOX_FRONT)
		out.append(PoliceFleet.Role.BOX_SIDE)
		out.append(PoliceFleet.Role.BOX_SIDE)
	if heat >= 3:
		out.append(PoliceFleet.Role.PIT)
	if heat >= 4:
		out.append(PoliceFleet.Role.HEAD_ON)
	while out.size() < PoliceHeat.units_max(heat):
		out.append(PoliceFleet.Role.PURSUE)
	return out


## A fingerprint of the roles the spawner hands out (so the dispatcher knows when to do it).
##
## The forced roles of the tests are part of it: a test that changes them expects the change at
## once.
func roles_token(heat: int) -> String:
	var token := "%d:%d" % [heat, forced_role]
	for role: int in forced_roles:
		token += ":%d" % role
	return token


## Gives every unit the role it should play. The two side units of the box get opposite sides.
##
## The roles are only handed out when the set of units or the heat changes: a role is a
## decision of the dispatcher, not of every frame.
func assign_roles(units: Array[PoliceCar], heat: int) -> void:
	var live := live_units(units)
	if live.is_empty():
		return
	var wanted := wanted_roles(heat)
	var side := 0
	for i in live.size():
		var role: PoliceFleet.Role = PoliceFleet.Role.PURSUE
		if forced_role >= 0:
			role = forced_role as PoliceFleet.Role
		elif not forced_roles.is_empty():
			role = forced_roles[mini(i, forced_roles.size() - 1)] as PoliceFleet.Role
		elif i < wanted.size():
			role = wanted[i]
		live[i].set_role(role)
		if role == PoliceFleet.Role.BOX_SIDE:
			# The first side unit takes the right of the player, the second the left.
			live[i].set_box_side(-1.0 if side == 0 else 1.0)
			side += 1
		elif role == PoliceFleet.Role.BOX_FRONT:
			# The front unit overtakes in the next lane: it takes the left of the player.
			live[i].set_box_side(1.0)
		else:
			live[i].set_box_side(0.0)


## Spawns one unit at a free place. Returns null when there is no room.
func spawn(role: PoliceFleet.Role, heat: int, player: VehicleBase, units: Array[PoliceCar],
		lane: int, lane_s: float) -> PoliceCar:
	if host == null or player == null:
		return null
	if close_units(units, player) >= CLOSE_LIMIT:
		return null
	var spot := spots.spawn_spot(role, player, lane, lane_s)
	if spot.is_empty():
		return null
	var kind := PoliceFleet.kind_for_role(role, heat)
	var unit := take_unit(kind)
	if unit == null:
		return null
	PoliceFleet.place_unit(unit, role, ctx, spot["transform"], rng.randi(), spots.grid)
	return unit


## Takes a unit out of the pool (or builds one when there is no pool).
func take_unit(kind: StringName) -> PoliceCar:
	if pool != null:
		var car := pool.take_unit(kind)
		if car != null:
			car.contact = contact
		return car
	if host == null:
		# The world is not ready yet, so there is nowhere to put the unit.
		return null
	var built := PoliceFleet.build_unit(host, kind, PoliceFleet.Role.PURSUE, ctx,
			Transform3D.IDENTITY, rng.randi(), spots.grid)
	if built != null:
		built.contact = contact
	return built


## The number of units within CLOSE_RADIUS of the player.
##
## Only the units that are on the road count: a car that waits in the pool is not on the road.
func close_units(units: Array[PoliceCar], player: VehicleBase) -> int:
	var count := 0
	for unit in units:
		if unit.is_wrecked or unit.parked:
			continue
		if unit.global_position.distance_to(player.global_position) <= CLOSE_RADIUS:
			count += 1
	return count
