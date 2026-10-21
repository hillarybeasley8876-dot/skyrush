class_name TrafficLamps
extends RefCounted
## The lamps of one traffic car: the head lamps, the tail lamps, the brake lamps and the turn
## indicators, plus the head lamp that lights the road in front of the car.
##
## The car model has real lamp lenses: every lens is a SURFACE of a lamp mesh, so the brake
## state is a per-surface material swap (see TrafficLampMaterials). Nothing is written every
## tick: the materials are only swapped when the state changes, because every swap is a call
## into the renderer and 90 cars x 4 lamps every tick is the most expensive thing the traffic
## could do.

const BLINK_PERIOD := 0.667       ## s: one blink of the indicator (1.5 Hz)
const BRAKE_ON_ACCEL := -0.6      ## m/s^2: below this the brake lamps come on
const BRAKE_OFF_ACCEL := -0.2     ## m/s^2: above this they go off again
const BRAKE_HOLD := 0.3           ## s: how long the brake lamps stay on
const HEAD_LIGHT_RANGE := 35.0    ## m: how far the head lamps reach
const HEAD_LIGHT_ANGLE := 40.0    ## deg: the cone of the head lamps
const HEAD_LIGHT_ON := 46.0       ## m: the head lamps are only lit for the cars this close
const HEAD_LIGHT_ENERGY := 2.4    ## the energy of the head lamp
const HEAD_LIGHT_PITCH := -3.0    ## deg: the lamp points slightly down (a low beam)
const HEAD_LIGHT_COLOR := Color("f4f7ff")


## One lens of the car: the mesh it belongs to and the surface index inside that mesh.
class Lens extends RefCounted:
	var mesh: MeshInstance3D = null
	var index: int = 0


## The spot light of the car. It is only lit for the cars near the player, so the light budget of
## the scene stays small (see ART.md section 4).
var head_light: SpotLight3D = null
## The lens surfaces of the car, grouped by what they are.
var tail_lenses: Array[Lens] = []
var brake_lenses: Array[Lens] = []
var head_lenses: Array[Lens] = []
var reverse_lenses: Array[Lens] = []
## The indicator cards of the car (left, right).
var indicators_l: Array[MeshInstance3D] = []
var indicators_r: Array[MeshInstance3D] = []

var _materials: TrafficLampMaterials.Set = null
var _braking: bool = false
var _applied_brake: bool = false
var _brake_hold: float = 0.0
var _indicator_side: int = 0
var _indicator_on: bool = false
## The phase of the indicator blink, so the cars do not blink in sync.
var _phase: float = 0.0


## Finds the lamps in the visual of the car and builds the head light.
func setup(visual: Node3D, model_id: StringName, car_length: float, parent: Node3D,
		phase: float) -> void:
	_materials = TrafficLampMaterials.set_for(model_id, visual)
	_collect_lenses(visual)
	_collect_indicators(visual)
	_phase = phase
	head_light = _build_head_light(visual, car_length, parent)
	_apply_brake_state()
	_apply_indicator_state()


## Writes the lamp state. `indicator_side` is -1 for left, +1 for right, 0 for off.
##
## `accel` is the acceleration of the car: the brake lamps have a hysteresis, so they do not
## flicker on and off while the car drives at a constant speed.
func update(dt: float, accel: float, indicator_side: int, time: float, near: bool,
		player_distance: float, head_light_allowed: bool) -> void:
	var braking := _braking
	if accel < BRAKE_ON_ACCEL:
		_brake_hold = BRAKE_HOLD
		braking = true
	elif accel > BRAKE_OFF_ACCEL:
		_brake_hold = maxf(_brake_hold - dt, 0.0)
		if _brake_hold <= 0.0:
			braking = false
	if braking != _applied_brake:
		_applied_brake = braking
		_braking = braking
		_apply_brake_state()
	var blink := fmod(time + _phase, BLINK_PERIOD) < BLINK_PERIOD * 0.5
	if blink != _indicator_on or indicator_side != _indicator_side:
		_indicator_on = blink
		_indicator_side = indicator_side
		_apply_indicator_state()
	if head_light != null:
		var lit := near and head_light_allowed and player_distance < HEAD_LIGHT_ON
		if head_light.visible != lit:
			head_light.visible = lit


## Collects the lens surfaces of the car, by the material the model gave them.
func _collect_lenses(visual: Node3D) -> void:
	tail_lenses.clear()
	brake_lenses.clear()
	head_lenses.clear()
	reverse_lenses.clear()
	if visual == null or _materials == null:
		return
	for node in visual.find_children("Lamp_*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if source == null:
				continue
			var lens := Lens.new()
			lens.mesh = mesh
			lens.index = i
			match source.resource_name:
				TrafficLampMaterials.MAT_REAR:
					tail_lenses.append(lens)
				TrafficLampMaterials.MAT_BRAKE:
					brake_lenses.append(lens)
				TrafficLampMaterials.MAT_FRONT:
					if mesh.name == "Lamp_F":
						head_lenses.append(lens)
					else:
						reverse_lenses.append(lens)
	# The head lens and the reversing lens never change: they are set once.
	for lens in head_lenses:
		if _materials.head != null:
			lens.mesh.set_surface_override_material(lens.index, _materials.head)
	for lens in reverse_lenses:
		if _materials.reverse != null:
			lens.mesh.set_surface_override_material(lens.index, _materials.reverse)


## Collects the indicator cards of the car.
func _collect_indicators(visual: Node3D) -> void:
	indicators_l.clear()
	indicators_r.clear()
	if visual == null:
		return
	for node in visual.find_children("Indicator_*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.name.ends_with("L"):
			indicators_l.append(mesh)
		elif mesh.name.ends_with("R"):
			indicators_r.append(mesh)


## The head lamp of the car: a shadowless spot that lights the road in front of it. It sits at
## the `Light_Front` marker of the model, so the pool starts on the road and not under the
## bumper.
func _build_head_light(visual: Node3D, car_length: float, parent: Node3D) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = "HeadLight"
	light.light_color = HEAD_LIGHT_COLOR
	light.light_energy = HEAD_LIGHT_ENERGY
	light.spot_range = HEAD_LIGHT_RANGE
	light.spot_angle = HEAD_LIGHT_ANGLE
	light.spot_angle_attenuation = 1.0
	light.spot_attenuation = 1.4
	light.shadow_enabled = false
	var marker := visual.find_child("Light_Front", true, false) as Node3D
	if marker != null and parent.is_inside_tree():
		light.global_transform = marker.global_transform
	else:
		light.position = Vector3(0.0, 0.6, -(car_length * 0.5 - 0.1))
	light.rotation = Vector3(deg_to_rad(HEAD_LIGHT_PITCH), 0.0, 0.0)
	light.visible = false
	parent.add_child(light)
	return light


## Swaps the brake materials. Only called when the state changes.
func _apply_brake_state() -> void:
	if _materials == null:
		return
	if _braking:
		if _materials.has_brake_lens:
			for lens in brake_lenses:
				lens.mesh.set_surface_override_material(lens.index, _materials.brake_on)
		else:
			for lens in tail_lenses:
				lens.mesh.set_surface_override_material(lens.index, _materials.tail_brake)
	else:
		if _materials.has_brake_lens:
			for lens in brake_lenses:
				lens.mesh.set_surface_override_material(lens.index, _materials.brake_off)
		for lens in tail_lenses:
			lens.mesh.set_surface_override_material(lens.index, _materials.tail)


## Swaps the indicator materials: the amber lens of the side the car is turning to.
func _apply_indicator_state() -> void:
	var on := _indicator_on
	for mesh in indicators_l:
		mesh.material_override = TrafficMaterials.indicator_on() if _indicator_side < 0 and on \
				else TrafficMaterials.indicator_off()
	for mesh in indicators_r:
		mesh.material_override = TrafficMaterials.indicator_on() if _indicator_side > 0 and on \
				else TrafficMaterials.indicator_off()
