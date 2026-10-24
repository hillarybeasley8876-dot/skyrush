class_name PoliceDirector
extends Node3D
## The dispatcher of the police pursuit (ref/gameplay/DOSSIER.md §3.1-3.4 and §6.3).
##
## The director owns the units, the drones and the roadblocks and hands the rules to its
## helpers: PolicePursuit (the heat, the sight, the evade bar, the busted meter), PoliceOffences
## (the four offences of §3.4), PoliceEvents (the bus), PoliceSpawner (where the units come
## from), PoliceBlockade (the roadblocks), PoliceAir (the drones), PoliceSquad (the units on the
## road), PolicePool (the objects), PoliceWorldSetup (the world) and PoliceAftermath (the end).
##
## The heat follows the table of §3.4 (units 3/5/7/9/12, backup 60/50/45/40/35 s, cooldown
## 20/35/50/70/90 s).

const GROUP := &"police_director" ## the group the HUD finds the meters in
## The dispatcher runs after the cars, so the debuffs it writes are not overwritten by the
## boost module of the player.
const PRIORITY := 10

## The heat of the pursuit (0 = free roam).
var heat: int:
	get: return pursuit.heat
## The state of the pursuit: &"none", &"chase", &"search", &"cooldown", &"escaped", &"busted".
var pursuit_state: StringName:
	get: return pursuit.state
## The evade bar (0..1).
var evade: float:
	get: return pursuit.evade
## The busted meter (0..1).
var busted: float:
	get: return pursuit.busted
## The police units on the road.
var units: Array[PoliceCar]:
	get: return squad.units
## The player of the moment.
var player: VehicleBase:
	get: return _player
## The lane of the player and his distance along it.
var lane: int:
	get: return watch.lane
var lane_offset: float:
	get: return watch.lane_offset
## The drones in the air.
var drones: Array[PoliceDrone]:
	get: return air.drones
## The spike strips on the road.
var strips: Array[PoliceSpikeStrip] = []
## The last tick of the dispatcher (ms) and the slowest tick since the start (ms).
var tick_ms: float = 0.0
var tick_peak_ms: float = 0.0
## False switches the spawning of units off (the tests).
var spawn_enabled: bool = true
## The number of PIT taps the police gave.
var pit_assists: int:
	get: return events.pit_assists

## The rules of the pursuit: the heat, the line of sight, the evade bar, the busted meter.
var pursuit: PolicePursuit = PolicePursuit.new()
## The offences of §3.4, the grace and the events of the bus.
var events: PoliceEvents = PoliceEvents.new()
## The four offences of §3.4 and the grace after the player appears.
var offences: PoliceOffences = PoliceOffences.new()
## Where the units come from and what role they play.
var spawner: PoliceSpawner = PoliceSpawner.new()
## The roadblocks on the road.
var blockade: PoliceBlockade = PoliceBlockade.new()
## The drones in the air and the strips they drop.
var air: PoliceAir = PoliceAir.new()
## The debuffs of the player (the punctures, the EMP).
var debuff: PoliceDebuff = PoliceDebuff.new()
## The units on the road: their tick, their removal and the hold-back.
var squad: PoliceSquad = PoliceSquad.new()
## The pool of the police objects: nothing is instantiated during the chase.
var pool: PolicePool = PolicePool.new()
## The velocity cache of the contacts (who hit whom).
var contact: PoliceContact = PoliceContact.new()
## The test hooks of the dispatcher.
var hooks: PoliceTestHooks = PoliceTestHooks.new()
## The aftermath of a bust or an escape: the end state, then the reset to "none".
var aftermath: PoliceAftermath = PoliceAftermath.new()
## What the dispatcher watches: the lane of the player, the sight, the offences.
var watch: PoliceWatch = PoliceWatch.new()

var _world: WorldBase = null
var _player: VehicleBase = null
var _rng := RandomNumberGenerator.new()
## The fingerprint of the last role assignment (the roles are not given out every frame).
var _roles_token: String = ""
## The milliseconds the last tick needed in every part of the dispatcher (the tests read it).
var module_ms: Dictionary = {}


## The dispatcher starts with the world of the game and listens to the bus.
func _ready() -> void:
	# --seed=N: the same police every run (tools/frame_probe.gd compares two runs)
	if Game.has_option("seed"):
		_rng.seed = int(Game.option("seed")) + 1
	else:
		_rng.randomize()
	add_to_group(GROUP)
	process_physics_priority = PRIORITY
	hooks.director = self
	events.pursuit = pursuit
	events.offences = offences
	events.contact = contact
	watch.pursuit = pursuit
	watch.offences = offences
	watch.events = events
	watch.contact = contact
	Events.infraction.connect(_on_infraction)
	Events.vehicle_collided.connect(_on_vehicle_collided)
	Events.flight_changed.connect(_on_flight_changed)
	Events.charge_finished.connect(_on_charge_finished)
	Events.player_respawned.connect(_on_player_respawned)
	_refresh_world()
	build_pool()


## The director follows `Game.world`, so it survives a change of world (menu -> city).
func _refresh_world() -> void:
	var world_setup := PoliceWorldSetup.new(self)
	if world_setup.refresh():
		_world = world_setup.world
		_player = world_setup.player


## A random number of the dispatcher (the helpers seed their own source with it).
func random_seed() -> int:
	return _rng.randi()


## Builds the pool of the police objects, so the chase never instantiates anything.
func build_pool() -> void:
	if pool.is_built() or spawner.ctx.graph == null:
		return
	spawner.pool = pool
	blockade.pool = pool
	air.pool = pool
	squad.pool = pool
	pool.build(self, spawner.ctx, spawner.grid)
	for unit in pool.units:
		unit.wrecked.connect(_on_unit_wrecked.bind(unit))
		unit.contact = contact
	for drone in pool.drones:
		drone.spike_requested.connect(_on_drone_spike)


## The tick of the dispatcher.
func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	PoliceRadio.tick(delta)
	if spawner.ctx.graph == null or spawner.ctx.graph.lane_count() == 0:
		if _world != Game.world or spawner.ctx.graph == null:
			_refresh_world()
		return
	if _player != Game.player:
		_on_player_changed()
	if _world != Game.world:
		_clear_all()
		_refresh_world()
		return
	if _player == null:
		return
	var mark := Time.get_ticks_usec()
	watch.cache_contacts(_player, units)
	watch.track(_player)
	_mark("watch", mark)
	mark = Time.get_ticks_usec()
	pursuit.update_heat(delta)
	watch.update_sight(delta, get_world_3d().direct_space_state, _player, units, drones)
	watch.check_offences(delta, _player)
	_mark("sight", mark)
	mark = Time.get_ticks_usec()
	if pursuit.update_state(delta, _player):
		_end_pursuit(&"escaped")
	if pursuit.update_busted(delta, _player, units):
		_end_pursuit(&"busted")
	if aftermath.update(delta, pursuit.state):
		pursuit.reset()
	_mark("pursuit", mark)
	mark = Time.get_ticks_usec()
	_update_spawning(delta)
	_mark("spawning", mark)
	mark = Time.get_ticks_usec()
	squad.update(delta, _player, get_viewport().get_camera_3d(),
			watch.hold_back_point(delta), blockade.block_cars)
	pursuit.disabled += squad.newly_disabled
	_mark("squad", mark)
	mark = Time.get_ticks_usec()
	_update_drones(delta)
	_update_blockade(delta)
	for strip in strips:
		strip.tick(delta)
	debuff.tick(delta, _player)
	_mark("road", mark)
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	tick_ms = elapsed
	tick_peak_ms = maxf(tick_peak_ms, elapsed)


## Writes the milliseconds a part of the dispatcher needed (the tests print the top five).
func _mark(name: String, started: int) -> void:
	module_ms[name] = float(Time.get_ticks_usec() - started) / 1000.0


## A new player car: the grace starts again and the debuffs of the old car are dropped.
func _on_player_changed() -> void:
	_player = Game.player
	spawner.ctx.player = _player
	blockade.ctx.player = _player
	events.on_player_changed(_player)
	offences.on_player_appeared()
	debuff.on_player_changed(_player)


## The player respawned: the grace starts again.
func _on_player_respawned() -> void:
	offences.on_player_appeared()


## The pursuit is over: the heat goes back to zero and the units leave the road.
func _end_pursuit(state: StringName) -> void:
	pursuit.end(state)
	debuff.clear()
	remove_all_units()
	spawner.end_pursuit()
	_roles_token = ""


## The spawning of the units: the budget of the heat, the backup timer and the roles.
func _update_spawning(delta: float) -> void:
	if pursuit.state == &"escaped" or pursuit.state == &"busted":
		return
	spawner.spawn_enabled = spawn_enabled
	if spawn_enabled:
		var unit := spawner.update(delta, pursuit.heat, _player, units, watch.lane, watch.lane_offset)
		if unit != null:
			unit.pursuit_active = pursuit.is_active()
			squad.add(unit)
	_assign_roles()


## Hands out the roles of the units, but only when the set of units or the heat changes.
##
## A role is a decision of the dispatcher, not of every frame: the same list of roles for the
## same units is the same decision.
func _assign_roles() -> void:
	var token := "%s:%d:%d" % [spawner.roles_token(pursuit.heat), units.size(), _unit_token()]
	if token == _roles_token:
		return
	_roles_token = token
	spawner.assign_roles(units, pursuit.heat)


## A cheap fingerprint of the units on the road (so a replaced unit is a new set).
func _unit_token() -> int:
	var token := 0
	for unit in units:
		token ^= unit.get_instance_id()
	return token


## The drones: one from heat 4, two from heat 5.
func _update_drones(delta: float) -> void:
	air.update(delta, pursuit.heat, _player)


## The drone drops a spike strip on the route ahead of the player.
func _on_drone_spike() -> void:
	blockade.drop_strip(_player, watch.lane, watch.lane_offset, PoliceDrone.SPIKE_AHEAD)


## The roadblocks on the road.
func _update_blockade(delta: float) -> void:
	blockade.update(delta, pursuit.heat, _player, watch.lane, watch.lane_offset)


## An offence was reported on the bus.
func _on_infraction(vehicle: VehicleBase, kind: StringName) -> void:
	events.on_infraction(vehicle, kind)


## A collision with a police car or with the traffic.
func _on_vehicle_collided(vehicle: VehicleBase, other: Node3D, impulse: float, point: Vector3,
		_normal: Vector3) -> void:
	events.on_collision(vehicle, other, point, impulse)
	for block in blockade.blocks:
		block.on_collision(vehicle, other, contact.closing_speed(vehicle, other))


## The player enters a sky lane.
func _on_flight_changed(vehicle: VehicleBase, active: bool, _lane: SkyLane) -> void:
	events.on_flight_changed(vehicle, active)


## The player flash-charges.
func _on_charge_finished(vehicle: VehicleBase, _station: Area3D, _amount: float) -> void:
	events.on_charge_finished(vehicle)


## A police car was wrecked: it counts as disabled.
func _on_unit_wrecked(source: Node3D, unit: PoliceCar) -> void:
	unit.state = PoliceCar.State.WRECK
	unit.wreck_time = 0.0
	unit.linear_damp = PoliceCar.WRECK_DAMP
	unit.angular_damp = PoliceCar.WRECK_DAMP
	if unit.counted_disabled:
		return
	unit.counted_disabled = true
	unit.disabled = true
	pursuit.disabled += 1


## Removes every unit, drone and roadblock from the road.
func remove_all_units() -> void:
	for unit in units:
		unit.pursuit_active = false
	squad.clear()
	for drone in air.drones:
		pool.release_drone(drone)
	air.drones.clear()
	blockade.clear_blocks()
	for strip in strips:
		pool.release_strip(strip)
	strips.clear()


## The world changed: everything leaves the road.
func _clear_all() -> void:
	remove_all_units()
	pursuit.reset()
	debuff.clear()


## Starts a pursuit at a given heat. The mode "pursuit" uses this (heat 2 or 3); the grace of
## the spawn does not apply to a pursuit the game starts itself.
func start_pursuit(level: int) -> void:
	pursuit.start(level)
	for unit in units:
		unit.pursuit_active = true
	spawner.begin_pursuit(pursuit.heat)
	_roles_token = ""


## Sets the heat of the pursuit (the mode "pursuit" calls this).
func set_heat(level: int) -> void:
	pursuit.set_heat(level)


## The number of units that are on the player (the HUD shows it).
func engaged_units() -> int:
	return squad.engaged_count()


## The seconds until the backup unit arrives (the HUD shows it).
func backup_seconds_left() -> float:
	return spawner.backup_timer


## Removes a unit from the road (the tests and the modes use it).
func despawn_unit(unit: PoliceCar) -> void:
	squad.remove_unit(unit)


## Puts a unit on the road at a given place, with a given role (the test hook).
func place_unit(xform: Transform3D, role: PoliceFleet.Role) -> PoliceCar:
	var kind := PoliceFleet.kind_for_role(role, pursuit.heat)
	var car := spawner.take_unit(kind)
	if car == null:
		return null
	PoliceFleet.place_unit(car, role, spawner.ctx, xform, _rng.randi(), spawner.grid)
	car.pursuit_active = pursuit.is_active()
	squad.add(car)
	return car


## The test hook: ends the pursuit without a reward.
func clear_pursuit() -> void:
	hooks.clear_pursuit()


## The test hook: every unit gets this role (-1 = the roles of the heat table).
func force_role(role: int) -> void:
	hooks.force_role(role)


## The test hook: the units get these roles in order.
func force_roles(roles: Array) -> void:
	hooks.force_roles(roles)


## The test hook: the heat of the pursuit, without a pursuit.
func force_heat(level: int) -> void:
	hooks.force_heat(level)


## The test hook: a unit at a given place, with a given role.
func spawn_unit_at(xform: Transform3D, role: PoliceFleet.Role) -> PoliceCar:
	return hooks.spawn_unit_at(xform, role)


## The test hook: sets up a roadblock right now.
func spawn_roadblock_now() -> bool:
	return hooks.spawn_roadblock_now()
