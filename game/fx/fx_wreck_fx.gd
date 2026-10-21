extends Node3D
## The visuals of a wrecked car (brief §7): a dark smoke column, fire licks for an ICE car and
## cold white-blue arcs for an EV.
##
## The column and the fire run as long as the rig is allowed to use the emitter budget, the
## arcs only for an EV and only while the car is nearly dead (below ARC_HEALTH_LIMIT).
##
## The smoke and the fire emitters are top level, so the column always rises straight up, even
## when the car is flipped. The arcs stay in the local space of the car: they run on the shell
## of the bodywork.

const EMITTERS := preload("res://fx/fx_emitters.gd")
const ARCS := preload("res://fx/fx_arcs.gd")
const PALETTE := preload("res://fx/fx_palette.gd")
const TUNE := preload("res://fx/fx_tuning.gd")

const ARC_INTERVAL_MIN := 0.08
const ARC_INTERVAL_MAX := 0.2
## The height of the engine bay above the road.
const ENGINE_HEIGHT := 0.5

var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _arcs: Node3D
var _fire_light: OmniLight3D
var _arc_timer: float = 0.0
var _flicker: float = 0.0
var _electric: bool = false
var _vehicle: VehicleBase = null
var _flicker_noise := FastNoiseLite.new()


## Builds the wreck effects. `electric` picks the EV look (white smoke + arcs).
func setup(vehicle: VehicleBase, electric: bool, quality: float) -> void:
	_vehicle = vehicle
	_electric = electric
	if _smoke == null:
		_smoke = EMITTERS.wreck_smoke(quality,
				PALETTE.WRECK_SMOKE_EV if electric else PALETTE.WRECK_SMOKE, not electric)
		_smoke.name = "WreckSmoke"
		# The column rises in the world, not with the car.
		_smoke.top_level = true
		add_child(_smoke)
	if electric:
		if _arcs == null:
			_arcs = ARCS.new()
			_arcs.name = "WreckArcs"
			add_child(_arcs)
			_arcs.setup(PALETTE.ARC, 5.0, 4)
			_arcs.set_surface(vehicle)
			_arcs.play()
	else:
		if _fire == null:
			_fire = EMITTERS.wreck_fire(quality)
			_fire.name = "WreckFire"
			_fire.top_level = true
			add_child(_fire)
		if _fire_light == null:
			_fire_light = OmniLight3D.new()
			_fire_light.name = "WreckFireLight"
			_fire_light.light_color = PALETTE.FIRE_LIGHT
			_fire_light.omni_range = TUNE.WRECK_LIGHT_RANGE
			_fire_light.shadow_enabled = false
			_fire_light.top_level = true
			add_child(_fire_light)
	_flicker_noise.seed = 4711
	_flicker_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_flicker_noise.frequency = 9.0
	_smoke.emitting = true


## Runs the wreck effects. `granted` is false when the rig may not run any emitter (the budget
## of the director): the column and the fire stay off then.
func update(delta: float, granted: bool, fire_granted: bool, car: VehicleBase) -> void:
	if _smoke == null:
		return
	if car != null and is_instance_valid(car):
		_vehicle = car
	var origin := _vehicle.global_position if _vehicle != null else global_position
	_smoke.emitting = granted
	_smoke.global_position = origin + Vector3.UP * ENGINE_HEIGHT
	if _fire != null:
		# A wreck that is still sliding does not show its fire: the licks would be left behind
		# as a trail of cards on the road.
		_fire.emitting = granted and fire_granted and not _sliding()
		_fire.global_position = origin + Vector3.UP * ENGINE_HEIGHT
	if _fire_light != null:
		_fire_light.global_position = origin + Vector3.UP * TUNE.WRECK_LIGHT_HEIGHT
		_flicker = fmod(_flicker + delta * 11.0, 1000.0)
		# The light flickers with noise, not with a sine: a sine reads as a lamp.
		var noise := _flicker_noise.get_noise_1d(_flicker) * 0.5 + 0.5
		_fire_light.light_energy = lerpf(TUNE.WRECK_LIGHT_MIN, TUNE.WRECK_LIGHT_MAX, noise)
	if not _electric or _arcs == null:
		return
	if not _nearly_dead():
		_arcs.stop()
		return
	_arc_timer -= delta
	if _arc_timer <= 0.0:
		_arc_timer = randf_range(ARC_INTERVAL_MIN, ARC_INTERVAL_MAX)
		if _arcs.is_running():
			_arcs.regenerate()
		else:
			_arcs.play()


## True while the car is so damaged that its electrics arc over the bodywork.
func _nearly_dead() -> bool:
	if _vehicle == null or not is_instance_valid(_vehicle):
		return false
	return _vehicle.telemetry.health_norm < TUNE.ARC_HEALTH_LIMIT


## True while the wreck is still sliding along the road.
func _sliding() -> bool:
	if _vehicle == null or not is_instance_valid(_vehicle):
		return false
	return _vehicle.linear_velocity.length() > TUNE.WRECK_FIRE_MAX_SLIDE


## Stops every wreck effect (the car left the full range or was freed).
func stop() -> void:
	if _smoke != null:
		_smoke.emitting = false
	if _fire != null:
		_fire.emitting = false
	if _fire_light != null:
		_fire_light.light_energy = 0.0
	if _arcs != null:
		_arcs.stop()


## True while the electrical arcs of the wreck are running (the test hook).
func arcs_running() -> bool:
	return _arcs != null and _arcs.is_running()


## The particles this node simulates right now.
func billboard_count() -> int:
	var total := 0
	for emitter in [_smoke, _fire]:
		if emitter != null and emitter.emitting:
			total += emitter.amount
	return total


## The number of smoke / fire emitters that are running right now.
func active_emitter_count() -> int:
	var count := 0
	for emitter in [_smoke, _fire]:
		if emitter != null and emitter.emitting:
			count += 1
	return count


## The worst case of this node (every emitter at full rate).
func worst_case_count() -> int:
	var total := 0
	for emitter in [_smoke, _fire]:
		if emitter != null:
			total += emitter.amount
	return total
