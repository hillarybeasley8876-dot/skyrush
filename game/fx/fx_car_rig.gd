extends Node3D
## Per-car effect rig. Every emitter starts switched off: the rig only switches one on when its
## effect is actually wanted, so an idle car runs no particle system at all.
##
## Tiers (set by the director): FULL = the player and the three nearest cars, REDUCED = the rest
## inside 150 m, OFF = beyond that (nothing is simulated).
##
## The rig itself drives the tyre effects (smoke, wet spray, skid marks) and the wheel arch
## glow. The tyre emitters live in fx_rig_tyres.gd, the collision effects in fx_rig_collision.gd
## and the wreck visuals in fx_wreck_fx.gd.

const PALETTE := preload("res://fx/fx_palette.gd")
const TUNE := preload("res://fx/fx_tuning.gd")
const ARCH := preload("res://fx/fx_arch_glow.gd")
const WRECK := preload("res://fx/fx_wreck_fx.gd")
const GROUND := preload("res://fx/fx_ground.gd")
const TYRES := preload("res://fx/fx_rig_tyres.gd")
const COLLISION := preload("res://fx/fx_rig_collision.gd")
const SKID_RIBBON := preload("res://fx/fx_skid_ribbon.gd")
const SPARK_POOL := preload("res://fx/fx_spark_pool.gd")
const DEBRIS_POOL := preload("res://fx/fx_debris_pool.gd")
const LIGHT_POOL := preload("res://fx/fx_light_pool.gd")
const Dev := preload("res://fx/fx_dev.gd")

enum Tier { FULL, REDUCED, OFF }

const REDUCED_RATIO := 0.3
## A REDUCED car probes its wheels every this many physics ticks.
const REDUCED_PROBE_TICKS := 4
## The rear wheels of the car.
const REAR_MARKERS: Array[StringName] = [&"Wheel_RL", &"Wheel_RR"]
## The front wheels of the car.
const FRONT_MARKERS: Array[StringName] = [&"Wheel_FL", &"Wheel_FR"]

var vehicle: VehicleBase
var tier: int = -1  ## -1 = never tiered yet
var wet: bool = false
var wrecked: bool = false

var _skid: SKID_RIBBON = null
var _spark: SPARK_POOL = null
var _debris: DEBRIS_POOL = null
var _lights: LIGHT_POOL = null
var _quality: float = 1.0

var _tyres: TYRES = null
var _collision: COLLISION = null
var _arch: Node3D = null
var _wreck_fx: Node3D = null

var _arch_glow: float = 0.0
var _airborne_frames: int = 0
## The dev switches of the unit (--fx-no-*).
var _dev: Dev = null
## The emitter budget, handed out by the manager (gameplay DOSSIER §7.7).
var _smoke_granted: bool = true
var _wreck_granted: bool = true
var _spray_granted: bool = true
var _fire_granted: bool = true
## The speed of a car that does not write its own telemetry (the traffic cars): it is measured
## from the movement of the car between two physics ticks.
var _velocity: Vector3 = Vector3.ZERO
## The time since the car last moved (s), and how long a car may not move before it stands still.
var _since_move: float = 0.0
const MOVE_WAIT := 0.1
var _last_position: Vector3 = Vector3.ZERO
var _has_position: bool = false
## The contact patches of the rear wheels, probed in the physics step.
var _contacts: Array[Dictionary] = []
## The contacts were probed since the emitters were last put on them.
var _contacts_fresh: bool = false
## The tick of the wheel probe of a REDUCED car (0..REDUCED_PROBE_TICKS-1, at random: the cars are spread over the ticks).
var _probe_phase: int = randi() % REDUCED_PROBE_TICKS
## The contact patches of the front wheels, probed in the physics step.
var _front_contacts: Array[Dictionary] = []


## Builds the rig for `car`.
func setup(car: VehicleBase, skid: SKID_RIBBON, spark: SPARK_POOL, debris: DEBRIS_POOL,
		lights: LIGHT_POOL, quality: float) -> void:
	vehicle = car
	_skid = skid
	_spark = spark
	_debris = debris
	_lights = lights
	_quality = clampf(quality, 0.2, 1.3)
	if _tyres == null:
		_tyres = TYRES.new()
		_tyres.setup(car, self, _quality)
	if _collision == null:
		_collision = COLLISION.new()
		_collision.name = "Collision"
		add_child(_collision)
		_collision.setup(car, spark, debris, lights)
	# A pooled car can be re-added: the signal is connected only once.
	if not car.tree_exiting.is_connected(_on_vehicle_exiting):
		car.tree_exiting.connect(_on_vehicle_exiting)
	# The rig is built in code and added to a car that is already in the tree: the scene tree
	# only registers the physics callback of a node that joins the tree with its script. Without
	# this, the ground probe (and with it the skid marks and the contact patches) never runs.
	set_physics_process(false)
	set_physics_process(true)


## The dev switches of the unit (--fx-no-smoke, --fx-no-spray, --fx-no-skid).
func set_dev(value: Dev) -> void:
	_dev = value


## True when the dev switches ask for the tyre smoke to be off.
func _smoke_off() -> bool:
	return _dev != null and _dev.no_smoke


## True when the dev switches ask for the wet spray to be off.
func _spray_off() -> bool:
	return _dev != null and _dev.no_spray


## The manager hands out the emitter budget: a rig that may not run its smoke stays quiet.
func set_grants(smoke_granted: bool, wreck_granted: bool, spray_granted: bool,
		fire_granted: bool = true) -> void:
	_smoke_granted = smoke_granted
	_wreck_granted = wreck_granted
	_spray_granted = spray_granted
	_fire_granted = fire_granted
	_tyres.smoke_granted = smoke_granted
	_tyres.spray_granted = spray_granted
	if not smoke_granted:
		_tyres.set_emitting(_tyres.smoke_left(), false)
		_tyres.set_emitting(_tyres.smoke_right(), false)
	if not spray_granted:
		for emitter in [_tyres.spray_left(), _tyres.spray_right(), _tyres.spray_front(),
				_tyres.droplets()]:
			_tyres.set_emitting(emitter, false)


## True when the car is wrecked (the manager gives the wrecked cars the first claim on the
## emitter budget).
func is_wrecked() -> bool:
	return wrecked


## How many emitters of the budget this rig uses: a car burns one for its tyre smoke, a wrecked
## car burns one for its column and one more for its fire.
func emitter_cost() -> int:
	if not wrecked:
		return 1
	return 1 if _electric() else 2


## The current tier (test hook): Tier.FULL, Tier.REDUCED or Tier.OFF.
func get_tier() -> int:
	return tier


## Distance tier. OFF runs nothing at all.
func set_tier(value: int) -> void:
	if value == tier:
		return
	tier = value
	_apply_tier()


func _apply_tier() -> void:
	match tier:
		Tier.FULL:
			_tyres.ensure(true)
			_tyres.tier_ratio_value = 1.0
			_tyres.set_ratio(1.0)
		Tier.REDUCED:
			_tyres.ensure(false)
			_tyres.tier_ratio_value = REDUCED_RATIO
			_tyres.set_ratio(REDUCED_RATIO)
		_:
			_stop_all()
			_tyres.release()


## ---------------------------------------------------------------------------------------------
## Per frame
## ---------------------------------------------------------------------------------------------

## The road is probed in the physics step: a raycast outside of it is not safe.
##
## A FULL car (the player, the nearest cars) probes its four wheels every tick: its skid marks need a point every tick. A REDUCED
## car probes them every REDUCED_PROBE_TICKS ticks: four rays at 120 Hz for every car within 150 m cost the traffic 0.5 ms a tick,
## for smoke that follows the car anyway (the emitters are children of the car, they are put on the wheels after a probe).
func _physics_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if tier == Tier.OFF:
		# nothing reads the velocity of a car that is out of range: the tracking starts again when it comes back
		_has_position = false
		return
	_track_velocity(delta)
	# the REDUCED cars are spread over the ticks (the pool builds them all at once)
	var probe_tick := (Engine.get_physics_frames() + _probe_phase) % REDUCED_PROBE_TICKS == 0
	if tier == Tier.FULL or _contacts.is_empty() or probe_tick:
		_contacts = GROUND.wheel_contacts(vehicle, REAR_MARKERS)
		_front_contacts = GROUND.wheel_contacts(vehicle, FRONT_MARKERS)
		_contacts_fresh = true
	_update_skids()


## The skid marks: only the player and the FULL cars leave a mark.
##
## The points are added in the physics step (120 Hz), so the ribbon has a quad every 0.9 m even
## at 280 km/h. The strip is only cut when the wheels really leave the road (with a grace
## period, so a single bouncing frame does not cut the ribbon); the end of a drift just stops
## the ribbon.
func _update_skids() -> void:
	if _skid == null or not is_instance_valid(_skid):
		return
	if _dev != null and _dev.no_skid:
		return
	var tel := vehicle.telemetry
	var grounded := tel.grounded_wheels >= 2 and not tel.airborne
	if tier != Tier.FULL or _contacts.size() < 2 or not grounded:
		_airborne_frames += 1
		if _airborne_frames > TUNE.SKID_AIRBORNE_GRACE:
			for i in 2:
				_skid.break_strip(i)
		return
	_airborne_frames = 0
	if not _is_sliding(tel):
		return
	# The gap grows with the speed: a fast car moves more than 3 m between two physics ticks.
	var speed_mps := _velocity.length()
	var max_gap := maxf(TUNE.SKID_MAX_GAP,
			speed_mps * TUNE.SKID_GAP_SECONDS / float(Engine.physics_ticks_per_second))
	var right := vehicle.global_transform.basis.x
	for i in _contacts.size():
		var c: Dictionary = _contacts[i]
		_skid.add_point(i, c["point"], c["normal"], right, max_gap, _now())


## The effects are driven in the idle frame: the telemetry of the car is written in the physics
## step, so the newest values are the ones of the idle frame.
func _process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if tier == Tier.OFF:
		return
	var tel := vehicle.telemetry
	var grounded := tel.grounded_wheels >= 2 and not tel.airborne
	var sliding := _is_sliding(tel)
	if _contacts_fresh:
		_contacts_fresh = false
		_tyres.position(_contacts, _front_contact())
	_tyres.drive(tel, sliding, grounded, _speed_kmh(tel))
	_boost(delta, tel)
	_wreck(delta)


## Wet road (skyrush_wetness > 0.5): the tyre smoke turns into the cold mist of the street
## lights (the spray itself is a separate effect).
func set_wet(value: bool) -> void:
	if value == wet:
		return
	wet = value
	_tyres.wet = value
	_tyres.set_wet(value)


## The contact patch of the front axle (the middle between the two front wheels).
func _front_contact() -> Vector3:
	if _front_contacts.is_empty():
		return vehicle.global_position
	var centre := Vector3.ZERO
	for c: Dictionary in _front_contacts:
		centre += c["point"] as Vector3
	return centre / float(_front_contacts.size())


## The speed of the car: the telemetry of the car, or the movement of the car for the cars that
## do not write their own telemetry (the traffic cars are kinematic).
func _speed_kmh(tel: CarTelemetry) -> float:
	if tel.speed_kmh > 1.0:
		return tel.speed_kmh
	return _velocity.length() * 3.6


## The velocity of the car, measured from its movement between two moves. A far traffic car moves every second tick (the traffic
## thinks at 60 Hz): measured per tick its speed went 0, double, 0, double, and the spray of the wet road blinked. A car that has
## not moved for MOVE_WAIT seconds stands still.
func _track_velocity(delta: float) -> void:
	var position := vehicle.global_position
	if not _has_position or delta <= 0.0:
		_last_position = position
		_since_move = 0.0
		_has_position = true
		return
	_since_move += delta
	if position != _last_position or _since_move > MOVE_WAIT:
		_velocity = (position - _last_position) / _since_move
		_last_position = position
		_since_move = 0.0


## Is the car sliding? Reversing is not braking: the forward speed has to be positive.
func _is_sliding(tel: CarTelemetry) -> bool:
	if tel.rear_slip > TUNE.SMOKE_SLIP or tel.drift_state == &"drift":
		return true
	return tel.brake > 0.5 and tel.forward_speed_kmh > TUNE.SKID_BRAKE_SPEED


## The rate scale of the current tier (OFF runs nothing).
func _tier_ratio() -> float:
	match tier:
		Tier.FULL:
			return 1.0
		Tier.REDUCED:
			return REDUCED_RATIO
		_:
			return 0.0


## N2 boost: the wheel arches glow and a cold vapour trail follows the car.
func _boost(delta: float, tel: CarTelemetry) -> void:
	var active := tel.boost_kind == &"nitro" or tel.boost_kind == &"launch"
	var target := 1.0 if active else 0.0
	_arch_glow = move_toward(_arch_glow, target, TUNE.ARCH_FADE_SPEED * delta)
	if _arch != null:
		_arch.set_glow(_arch_glow)
	_tyres.set_emitting(_tyres.vapour(), active)


## Wrecked cars keep smoking; EVs get white-blue arcs, ICE cars get fire licks.
func _wreck(_delta: float) -> void:
	if not wrecked or _wreck_fx == null:
		return
	_wreck_fx.update(_delta, _wreck_granted, _fire_granted, vehicle)


## ---------------------------------------------------------------------------------------------
## Events
## ---------------------------------------------------------------------------------------------

## Called by the director for every `Events.vehicle_collided` of this car.
func on_collision(impulse: float, point: Vector3, normal: Vector3, other: Node3D) -> void:
	if tier == Tier.OFF or _collision == null:
		return
	_collision.on_collision(impulse, point, normal, other)


## The car is wrecked: smoke column, fire licks (ICE) or electrical arcs (EV).
func set_wrecked() -> void:
	if wrecked:
		return
	wrecked = true
	if _wreck_fx == null:
		_wreck_fx = WRECK.new()
		_wreck_fx.name = "WreckFx"
		add_child(_wreck_fx)
	_wreck_fx.setup(vehicle, _electric(), _quality)


## Traffic passed within 1.2 m at speed: a ribbon of displaced air along the passing car.
func near_miss(other: Node3D) -> void:
	if tier == Tier.OFF or _collision == null:
		return
	_collision.near_miss(other)


func _electric() -> bool:
	if vehicle == null:
		return false
	if vehicle.has_meta(&"is_ev"):
		return bool(vehicle.get_meta(&"is_ev"))
	return vehicle == Game.player


func _on_vehicle_exiting() -> void:
	_stop_all()


static func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _stop_all() -> void:
	_tyres.stop()
	_arch_glow = 0.0
	if _arch != null:
		_arch.set_glow(0.0)
	if _wreck_fx != null:
		_wreck_fx.stop()


## The number of particles this rig is currently simulating (budget report).
func billboard_count() -> int:
	var total := _tyres.billboard_count()
	if _wreck_fx != null:
		total += _wreck_fx.billboard_count()
	return total


## The number of smoke / fire emitters that are running right now.
func active_emitter_count() -> int:
	var count := 0
	for emitter in [_tyres.smoke_left(), _tyres.smoke_right()]:
		if emitter != null and emitter.emitting:
			count += 1
	if _wreck_fx != null:
		count += _wreck_fx.active_emitter_count()
	return count


## The number of spray emitters that are running right now (they are counted apart from the
## smoke / fire emitters, the gameplay DOSSIER §7.7 budget).
func active_spray_count() -> int:
	return _tyres.active_spray_count()


## The worst case of this rig (every emitter at `ratio` of its full rate).
func worst_case_count(ratio: float = 1.0) -> int:
	var total := _tyres.worst_case_count(ratio)
	if _wreck_fx != null:
		total += _wreck_fx.worst_case_count()
	return total
