extends Node3D
## Entry point: res://fx/thrusters/thruster_system.tscn
##
## The fx director instances this once and calls `attach(vehicle)` for every car that has nozzle
## markers. The system reads `vehicle.telemetry.thrusters` every frame and never touches anything
## else on the vehicle, so it works with the stub car and with the real glTF alike.

const ThrusterRig := preload("res://fx/thrusters/thruster_rig.gd")
const JetMesh := preload("res://fx/thrusters/lib/jet_mesh.gd")
const JetColumn := preload("res://fx/thrusters/lib/jet_column.gd")
const PlumeAssets := preload("res://fx/thrusters/lib/plume_assets.gd")

## At most this many cars get the full plume: the player and one more.
const MAX_FULL_FX := 2
## Tier ids (see thruster_rig.gd): full plume, core + reduced vapour, core only.
const TIER_FULL := 0
const TIER_REDUCED := 1
const TIER_CORE_ONLY := 2
## Vapour fraction of a reduced car.
const VAPOUR_REDUCED := 0.25
## Landings softer than this do not throw up a cloud (gameplay dossier §5.5).
const PUFF_MIN_IMPACT := 4.0

var _rigs: Dictionary[int, ThrusterRig] = {}
var _order: Array[int] = []
var _vehicles: Dictionary[int, VehicleBase] = {}
var _exit_callbacks: Dictionary[int, Callable] = {}
var _was_flying: Dictionary[int, bool] = {}


## Starts the plumes for a vehicle. Safe to call twice for the same car.
func attach(vehicle: VehicleBase) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var key: int = vehicle.get_instance_id()
	if _rigs.has(key):
		return
	var rig := ThrusterRig.new()
	rig.name = "Rig" + str(key)
	add_child(rig)
	rig.setup(vehicle, _particle_quality(TIER_FULL))
	_rigs[key] = rig
	_order.append(key)
	_vehicles[key] = vehicle
	var callback := _on_vehicle_gone.bind(key)
	_exit_callbacks[key] = callback
	if not vehicle.tree_exiting.is_connected(callback):
		vehicle.tree_exiting.connect(callback)
	_recompute_tiers()


## Stops the plumes for a vehicle and frees its rig.
func detach(vehicle: VehicleBase) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	_remove_rig(vehicle.get_instance_id())


## True when the vehicle currently has a rig.
func is_attached(vehicle: VehicleBase) -> bool:
	return vehicle != null and _rigs.has(vehicle.get_instance_id())


## Number of vehicles currently driven by the system.
func attached_count() -> int:
	return _rigs.size()


## The rig of a vehicle (null when it is not attached).
func rig_for(vehicle: VehicleBase) -> ThrusterRig:
	return _rigs.get(vehicle.get_instance_id())


## The tier of a vehicle (0 = full plume, 1 = reduced, 2 = core only), or -1 when it is not attached.
func tier_of(vehicle: VehicleBase) -> int:
	var rig: ThrusterRig = _rigs.get(vehicle.get_instance_id())
	return -1 if rig == null else rig.tier


## The particles alive for a vehicle: the sum of every emitter's amount.
func particle_capacity(vehicle: VehicleBase) -> int:
	var rig: ThrusterRig = _rigs.get(vehicle.get_instance_id())
	if rig == null:
		return 0
	return rig.particle_capacity()


## The player always gets a full slot; the cars attached after it share the remaining ones.
func _recompute_tiers() -> void:
	var keys: Array[int] = []
	var player_key: int = 0
	for key in _order:
		var rig: ThrusterRig = _rigs[key]
		if rig != null and rig.vehicle == Game.player:
			player_key = key
	if player_key != 0 and _rigs.has(player_key):
		keys.append(player_key)
	for key in _order:
		if key != player_key:
			keys.append(key)
	for i in keys.size():
		var tier: int = TIER_CORE_ONLY
		if i < MAX_FULL_FX:
			tier = TIER_FULL
		elif i == MAX_FULL_FX:
			tier = TIER_REDUCED
		_set_tier(keys[i], tier)


func _set_tier(key: int, tier: int) -> void:
	var rig: ThrusterRig = _rigs.get(key)
	if rig == null:
		return
	rig.tier = tier
	rig.set_particle_quality(_particle_quality(tier))


func _particle_quality(tier: int) -> float:
	var preset: float = clampf(float(Settings.feature("particles")), 0.0, 1.0)
	match tier:
		TIER_FULL:
			return preset
		TIER_REDUCED:
			return preset * VAPOUR_REDUCED
		_:
			return 0.0


func _process(delta: float) -> void:
	# The stale rigs are collected first: the dictionary must not change while it is iterated.
	var stale: Array[int] = []
	for key in _rigs:
		var rig: ThrusterRig = _rigs[key]
		if not is_instance_valid(rig):
			stale.append(key)
			continue
		rig.update_from_telemetry(delta)
	for key in stale:
		_remove_rig(key)


func _on_vehicle_gone(key: int) -> void:
	_remove_rig(key)


func _remove_rig(key: int) -> void:
	var vehicle: VehicleBase = _vehicles.get(key)
	var callback: Callable = _exit_callbacks.get(key)
	# The signal is on the vehicle, not on the system that owns the bound method.
	if vehicle != null and is_instance_valid(vehicle) and callback.is_valid():
		if vehicle.tree_exiting.is_connected(callback):
			vehicle.tree_exiting.disconnect(callback)
	_vehicles.erase(key)
	_exit_callbacks.erase(key)
	var rig: ThrusterRig = _rigs.get(key)
	if rig != null and is_instance_valid(rig):
		rig.queue_free()
	_rigs.erase(key)
	_order.erase(key)
	_was_flying.erase(key)
	_recompute_tiers()
	if _rigs.is_empty():
		release_assets()


## Drops the shared meshes and materials. The engine's leak detector counts them at exit, so
## they are released once the last rig is gone.
static func release_assets() -> void:
	JetMesh.release()
	JetColumn.release()
	PlumeAssets.release()


func _ready() -> void:
	Events.landed.connect(_on_landed)
	Events.flight_changed.connect(_on_flight_changed)
	Events.player_respawned.connect(_recompute_tiers)


## A clean or wobbly landing that was not gentle throws up a ring of vapour.
func _on_landed(vehicle: VehicleBase, _airtime: float, impact_speed: float, quality: StringName) -> void:
	if quality != &"clean" and quality != &"wobble":
		return
	if impact_speed <= PUFF_MIN_IMPACT:
		return
	_puff(vehicle)


## Leaving a sky lane ends in a puff as well.
func _on_flight_changed(vehicle: VehicleBase, active: bool, _lane: SkyLane) -> void:
	var key: int = vehicle.get_instance_id()
	var was: bool = bool(_was_flying.get(key, false))
	_was_flying[key] = active
	if was and not active:
		_puff(vehicle)


func _puff(vehicle: VehicleBase) -> void:
	var rig: ThrusterRig = _rigs.get(vehicle.get_instance_id())
	if rig != null and is_instance_valid(rig):
		rig.spawn_landing_puff()
