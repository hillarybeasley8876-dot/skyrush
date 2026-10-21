extends RefCounted
## The tyre effects of a car rig: the smoke of the rear wheels, the wet spray of every tyre, the
## water droplets they throw off and the cold vapour of a nitro boost.
##
## The helper owns the emitters, so fx_car_rig.gd only decides *when* they run and how strong
## they are. Every emitter starts switched off: an idle car runs no particle system at all.
## The emitters are children of the rig itself, so the tests (and the probes) still find them
## under the name they know.

const EMITTERS := preload("res://fx/fx_emitters.gd")
const PALETTE := preload("res://fx/fx_palette.gd")
const TUNE := preload("res://fx/fx_tuning.gd")

var vehicle: VehicleBase = null
## The node the emitters are added to (the rig).
var host: Node3D = null
var _quality: float = 1.0
## The budget of the rig (the manager hands it out).
var smoke_granted: bool = true
var spray_granted: bool = true
## The rate scale of the tier of the rig.
var tier_ratio_value: float = 1.0
## Wet road: the tyre smoke turns into the cold mist of the street lights.
var wet: bool = false

var _smoke_left: GPUParticles3D = null
var _smoke_right: GPUParticles3D = null
var _spray_left: GPUParticles3D = null
var _spray_right: GPUParticles3D = null
var _spray_front: GPUParticles3D = null
var _droplets: GPUParticles3D = null
var _vapour: GPUParticles3D = null


## Hands the helper the car, the node the emitters hang on and the quality scale of the preset.
func setup(car: VehicleBase, owner_node: Node3D, quality: float) -> void:
	vehicle = car
	host = owner_node
	_quality = clampf(quality, 0.2, 1.3)


## Builds the emitters of a tier: a REDUCED car gets no front spray, no droplets and no
## vapour trail.
func ensure(full: bool) -> void:
	if _smoke_left == null:
		_smoke_left = EMITTERS.tyre_smoke(_quality)
		_smoke_left.name = "TyreSmokeL"
		host.add_child(_smoke_left)
	if _smoke_right == null:
		_smoke_right = EMITTERS.tyre_smoke(_quality)
		_smoke_right.name = "TyreSmokeR"
		host.add_child(_smoke_right)
	if _spray_left == null:
		_spray_left = EMITTERS.spray_mist(_quality)
		_spray_left.name = "WetSprayL"
		host.add_child(_spray_left)
	if _spray_right == null:
		_spray_right = EMITTERS.spray_mist(_quality)
		_spray_right.name = "WetSprayR"
		host.add_child(_spray_right)
	if not full:
		return
	if _spray_front == null:
		_spray_front = EMITTERS.spray_mist(_quality)
		_spray_front.name = "WetSprayFront"
		host.add_child(_spray_front)
	if _droplets == null:
		_droplets = EMITTERS.droplets(_quality)
		_droplets.name = "Droplets"
		host.add_child(_droplets)
	if _vapour == null:
		_vapour = EMITTERS.vapour(_quality)
		_vapour.name = "NitroVapour"
		host.add_child(_vapour)


## Frees the emitters of a car that went out of range: an idle car runs nothing at all.
func release() -> void:
	for emitter in [_smoke_left, _smoke_right, _spray_left, _spray_right, _spray_front,
			_droplets, _vapour]:
		if emitter != null and is_instance_valid(emitter):
			emitter.queue_free()
	_smoke_left = null
	_smoke_right = null
	_spray_left = null
	_spray_right = null
	_spray_front = null
	_droplets = null
	_vapour = null


## Switches every emitter off.
func stop() -> void:
	for emitter in [_smoke_left, _smoke_right, _spray_left, _spray_right, _spray_front,
			_droplets, _vapour]:
		set_emitting(emitter, false)


## The wet road changes the tint of the tyre smoke: the dry smoke is grey-blue, the wet one is
## the cold mist of the street lights.
func set_wet(value: bool) -> void:
	var color := PALETTE.SPRAY_MIST if value else PALETTE.SMOKE_SCREEN
	for emitter in [_smoke_left, _smoke_right]:
		if emitter == null:
			continue
		var mat := emitter.process_material as ParticleProcessMaterial
		if mat != null:
			mat.color = Color(color.r, color.g, color.b, TUNE.SMOKE_ALPHA)


## The spray comes out of the contact patch of every tyre, not from one box under the axle.
## The smoke of a rear wheel comes out of its own contact patch too: one plume per tyre.
func position(contacts: Array[Dictionary], front_contact: Vector3) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if contacts.is_empty():
		return
	var centre := Vector3.ZERO
	for c: Dictionary in contacts:
		centre += c["point"] as Vector3
	centre /= float(contacts.size())
	var back := vehicle.get_forward().normalized() * TUNE.SPRAY_BACK_OFFSET
	for i in mini(contacts.size(), 2):
		var point: Vector3 = contacts[i]["point"]
		var local := vehicle.to_local(point)
		var smoke := _smoke_left if i == 0 else _smoke_right
		if smoke != null:
			smoke.position = local + Vector3.UP * TUNE.SMOKE_EMIT_HEIGHT
		var spray := _spray_left if i == 0 else _spray_right
		if spray != null:
			spray.position = local - back + Vector3.UP * TUNE.SPRAY_EMIT_HEIGHT
	if _spray_front != null:
		_spray_front.position = vehicle.to_local(front_contact - back * 0.5) \
				+ Vector3.UP * TUNE.SPRAY_EMIT_HEIGHT
	if _vapour != null:
		_vapour.position = vehicle.to_local(centre) - back * 1.6 + Vector3.UP * 0.35


## Tyre smoke, wet spray and the droplets.
##
## The smoke density follows the slip and the speed (lead F-INT2): a slow scrape puffs a little,
## a full drift at speed fills the plume, and a car that is nearly stationary puffs nothing.
##
## The rate of the puffs follows the metres, not the seconds: a drift at 300 km/h needs more
## than 2.5 puffs per metre per tyre, or the plume reads as a dotted line of cotton balls.
func drive(tel: CarTelemetry, sliding: bool, grounded: bool, speed_kmh: float) -> void:
	var speed_mps := speed_kmh / 3.6
	var smoking := sliding and grounded and speed_kmh > TUNE.SMOKE_MIN_SPEED and smoke_granted
	set_emitting(smoke_left(), smoking)
	set_emitting(smoke_right(), smoking)
	set_smoke_ratio(_smoke_ratio(tel, sliding, speed_mps) * tier_ratio())
	var spraying := wet and grounded and speed_kmh > TUNE.SPRAY_MIN_SPEED and spray_granted
	set_emitting(spray_left(), spraying)
	set_emitting(spray_right(), spraying)
	set_emitting(spray_front(), spraying)
	set_emitting(droplets(), spraying)
	var spray_ratio := clampf(speed_kmh / TUNE.SPRAY_FULL_SPEED, 0.0, 1.0) * tier_ratio()
	set_spray_ratio(spray_ratio)
	# The front tyres spray at a third of the strength of the rear ones.
	set_front_ratio(spray_ratio * 0.3)


## How dense the tyre smoke is right now (0..SMOKE_MAX_RATIO).
func _smoke_ratio(tel: CarTelemetry, sliding: bool, speed_mps: float) -> float:
	if not sliding:
		return 0.0
	var slip := clampf((tel.rear_slip - TUNE.SMOKE_SLIP)
			/ maxf(TUNE.SMOKE_FULL_SLIP - TUNE.SMOKE_SLIP, 0.01), 0.0, 1.0)
	if tel.drift_state == &"drift":
		slip = 1.0
	var brake := clampf(tel.brake, 0.0, 1.0) * TUNE.SMOKE_BRAKE_WEIGHT
	var intensity := maxf(slip, brake)
	var factor := clampf(speed_mps / TUNE.SMOKE_FULL_SPEED_MPS, 0.15, 1.0)
	return clampf(intensity * factor, 0.0, TUNE.SMOKE_MAX_RATIO)


## The rate scale of the current tier (OFF runs nothing).
func tier_ratio() -> float:
	return tier_ratio_value


## Scales the rate of every emitter with the tier.
func set_ratio(ratio: float) -> void:
	for emitter in [_smoke_left, _smoke_right, _spray_left, _spray_right, _spray_front,
			_droplets, _vapour]:
		if emitter != null:
			emitter.amount_ratio = ratio


## The rate of the tyre smoke (the smoke of the two rear wheels).
func set_smoke_ratio(ratio: float) -> void:
	for emitter in [_smoke_left, _smoke_right]:
		if emitter != null:
			emitter.amount_ratio = ratio


## The rate of the wet spray.
func set_spray_ratio(ratio: float) -> void:
	for emitter in [_spray_left, _spray_right]:
		if emitter != null:
			emitter.amount_ratio = ratio


## The front tyres spray at a third of the strength of the rear ones.
func set_front_ratio(ratio: float) -> void:
	if _spray_front != null:
		_spray_front.amount_ratio = ratio


## Switches one emitter on or off.
static func set_emitting(p: GPUParticles3D, on: bool) -> void:
	if p != null and p.emitting != on:
		p.emitting = on


## The emitters of the helper (the rig switches them on and off).
func smoke_left() -> GPUParticles3D:
	return _smoke_left


func smoke_right() -> GPUParticles3D:
	return _smoke_right


func spray_left() -> GPUParticles3D:
	return _spray_left


func spray_right() -> GPUParticles3D:
	return _spray_right


func spray_front() -> GPUParticles3D:
	return _spray_front


func droplets() -> GPUParticles3D:
	return _droplets


func vapour() -> GPUParticles3D:
	return _vapour


## Every emitter of the helper.
func emitters() -> Array[GPUParticles3D]:
	return [_smoke_left, _smoke_right, _spray_left, _spray_right, _spray_front, _droplets,
			_vapour]


## The number of particles this helper is currently simulating (budget report).
func billboard_count() -> int:
	var total := 0
	for emitter in emitters():
		if emitter != null and emitter.emitting:
			total += emitter.amount
	return total


## The number of spray emitters that are running right now (the spray is counted apart from the
## smoke / fire emitters, the gameplay DOSSIER §7.7 budget).
func active_spray_count() -> int:
	var count := 0
	for emitter in [_spray_left, _spray_right, _spray_front]:
		if emitter != null and emitter.emitting:
			count += 1
	return count


## The worst case of this helper (every emitter at `ratio` of its full rate).
func worst_case_count(ratio: float = 1.0) -> int:
	var total := 0
	for emitter in emitters():
		if emitter != null:
			total += int(float(emitter.amount) * ratio)
	return total
