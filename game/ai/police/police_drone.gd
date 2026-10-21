class_name PoliceDrone
extends Node3D
## The police drone (ref/gameplay/DOSSIER.md §3.4 and §6.3).
##
## The air unit that replaces the helicopter: it hovers 30-40 m above the player, 20 m behind,
## with a search light on a gimbal that aims at the car. The body stays level (it pitches a
## little into the direction of the flight and banks a little in the turns) and only the gimbal
## aims at the player. It keeps the line of sight even when the player flies a sky lane, drops a
## spike strip 120 m ahead every 25 s and, from heat 5 on, locks the player for two seconds and
## fires an EMP pulse (30 % less speed, no N2 for three seconds).

## The model of the npc_cars unit.
const SCENE := preload("res://assets/cars/npc/police_drone.glb")
## The shader of the beam of the search light.
const BEAM_SHADER := preload("res://ai/police/police_beam.gdshader")

const HOVER_HEIGHT := 35.0    ## m: the altitude over the player
const HOVER_BACK := 20.0       ## m: the distance behind the player
const MOVE_RATE := 1.6         ## 1/s: how fast the drone catches its hover position
## The search light: a 15 degree cone that reads brighter than the street.
const SPOT_ANGLE := 15.0
const SPOT_RANGE := 140.0
const SPOT_ENERGY := 18.0
const SPOT_ATTENUATION := 1.0
const SPOT_COLOR := Color("d9e8ff")
## The volumetric fog of the search light (only when the world has it).
const SPOT_FOG_ENERGY := 2.0
## The soft beam cone that makes the pool readable without volumetric fog.
const BEAM_ALPHA := 0.05
const BEAM_RADIUS := 9.0
const LAMP_RADIUS := 0.12
## The length the beam mesh has (m): the node is scaled to the real length.
const BEAM_MESH_LENGTH := 1.0
## The length the beam radius is measured for (m).
const BEAM_REFERENCE_LENGTH := 40.0
## The smallest scale of the radius of the beam.
const BEAM_MIN_SCALE := 0.3
## The largest scale of the radius of the beam.
const BEAM_MAX_SCALE := 1.2
## The camera is not inside the beam: the shaft fades out within this distance (m).
const BEAM_CAMERA_FADE := 8.0
## The distance at which the beam is fully visible again (m).
const BEAM_CAMERA_FULL := 22.0
## The height of the gimbal when the model has no "Spot" empty (m).
const GIMBAL_FALLBACK := 0.35
## The physics layer of the world (the ground the beam ends on).
const WORLD_LAYER := 1
## The EMP: the lock-on and the pulse.
const EMP_COLOR := Color("ff2030")
const EMP_PULSE := 4.0         ## Hz: the blink of the lock-on
const EMP_LOCK := 2.0          ## s: the lock-on time before the pulse
const EMP_INTERVAL := 20.0     ## s: the time between two pulses
## The body of the drone stays level.
const BODY_PITCH := 12.0       ## degrees
const BODY_BANK := 15.0        ## degrees
## The rotors of the drone.
const ROTOR_SPEED := 40.0      ## rad/s
## The gain of the pitch and the bank of the body (per m/s of the drift).
const BODY_GAIN := 0.02
## The blink of the EMP: the bright and the dim part of the pulse.
const EMP_BRIGHT := 1.4
const EMP_DIM := 0.2
const EMP_BLINK_ON := 0.5
const SPIKE_INTERVAL := 25.0   ## s: the time between two spike drops
const SPIKE_AHEAD := 120.0     ## m: how far ahead of the player the strip lands

## The drone asks the dispatcher to drop a spike strip.
signal spike_requested

## True while the drone has the line of sight to the player (the dispatcher writes it).
var seen: bool = false

var _model: Node3D = null
var _gimbal: Node3D = null
var _spot: SpotLight3D = null
var _beam: MeshInstance3D = null
var _beam_material: ShaderMaterial = null
var _rotors: Array[Node3D] = []
var _bar: PoliceLightBar = PoliceLightBar.new()
var _spike_timer: float = SPIKE_INTERVAL
var _emp_timer: float = EMP_INTERVAL
var _emp_lock: float = 0.0
## The clock of the blink of the EMP (s).
var _emp_blink: float = 0.0
## The clock of the dust of the beam (s).
var _dust_time: float = 0.0
var _height: float = HOVER_HEIGHT


## Builds the drone: the model, the gimbal, the search light and the rotors.
func setup() -> void:
	_model = SCENE.instantiate() as Node3D
	if _model == null:
		return
	_model.name = "Model"
	add_child(_model)
	MaterialLibrary.apply(_model)
	_rotors = _find_rotors(_model)
	_bar.build(self, _model, "Strobe_", false)
	_build_gimbal()
	_build_spot()
	_build_beam()


## The four rotor nodes of the model.
func _find_rotors(model: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for name in ["Rotor_FL", "Rotor_FR", "Rotor_RL", "Rotor_RR"]:
		var rotor := model.find_child(name, true, false) as Node3D
		if rotor != null:
			out.append(rotor)
	return out


## The gimbal: a node of its own at the "Spot" empty of the model, so the light aims with the
## gimbal and not with the body of the drone.
func _build_gimbal() -> void:
	_gimbal = Node3D.new()
	_gimbal.name = "Gimbal"
	add_child(_gimbal)
	var spot := _model.find_child("Spot", true, false) as Node3D
	if spot == null:
		_gimbal.position = Vector3(0.0, -GIMBAL_FALLBACK, 0.0)
		return
	_gimbal.position = _offset_in_model(spot)


## The place of a node of the model, in the frame of the model.
func _offset_in_model(node: Node3D) -> Vector3:
	var local := node.transform
	var parent := node.get_parent()
	while parent != null and parent != _model:
		local = parent.transform * local
		parent = parent.get_parent()
	return local.origin


## The search light: it hangs under the gimbal, so it aims with the gimbal and not with the body.
func _build_spot() -> void:
	_spot = SpotLight3D.new()
	_spot.name = "SearchLight"
	_spot.spot_angle = SPOT_ANGLE
	_spot.spot_range = SPOT_RANGE
	_spot.spot_attenuation = SPOT_ATTENUATION
	_spot.light_energy = SPOT_ENERGY
	_spot.light_color = SPOT_COLOR
	_spot.shadow_enabled = false
	# With volumetric fog the light itself makes a shaft, so the mesh is only a soft hint.
	if _has_volumetric_fog():
		_spot.light_volumetric_fog_energy = SPOT_FOG_ENERGY
	_gimbal.add_child(_spot)
	_spot.position = Vector3.ZERO


## True when the world has volumetric fog (the settings of the quality preset).
func _has_volumetric_fog() -> bool:
	return bool(Settings.feature("volumetric_fog"))


## The soft beam cone under the light: it runs along the -Z axis of the light, so the cone and
## the pool of the light are the same.
##
## The cone is a shader: a plain mesh with a hard rim covers the whole screen with a grey veil
## when the camera is under the drone.
func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = BEAM_RADIUS
	cone.bottom_radius = LAMP_RADIUS
	cone.height = BEAM_MESH_LENGTH
	cone.radial_segments = 32
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = BEAM_SHADER
	# With volumetric fog the light makes its own shaft, so the mesh is only a soft hint.
	var alpha := BEAM_ALPHA * (0.5 if _has_volumetric_fog() else 1.0)
	_beam_material.set_shader_parameter("beam_alpha", alpha)
	_beam.material_override = _beam_material
	_gimbal.add_child(_beam)
	_beam.rotation.x = -PI * 0.5


## One tick of the drone.
func tick(dt: float, player: VehicleBase, heat: int) -> void:
	_update_flight(dt, player)
	_update_aim(dt, player)
	_update_rotors(dt)
	_bar.update(dt)
	_update_beam(dt, player)
	if heat < 4:
		return
	_spike_timer -= dt
	if _spike_timer <= 0.0:
		_spike_timer = SPIKE_INTERVAL
		_request_spike(player)
	if heat < 5:
		return
	_emp_timer -= dt
	if _emp_lock > 0.0:
		_emp_lock -= dt
		if _emp_lock <= 0.0:
			_fire_emp(player)
	elif _emp_timer <= 0.0:
		_emp_timer = EMP_INTERVAL
		_emp_lock = EMP_LOCK
		PoliceRadio.say(&"emp")


## The hover: above the player and behind it, in the direction it came from.
##
## The point of the hover leads the player: the drone catches up with a lag of 1 / MOVE_RATE
## seconds, so the point is put that much further ahead (dossier §6.3: 20 m behind, not 35).
func _update_flight(dt: float, player: VehicleBase) -> void:
	if player == null:
		return
	var back := -player.get_forward()
	var wanted := player.global_position + back * HOVER_BACK + Vector3.UP * _height
	wanted += player.linear_velocity / MOVE_RATE
	global_position = global_position.lerp(wanted, clampf(MOVE_RATE * dt, 0.0, 1.0))
	# The body stays level: it pitches a little into the flight and banks a little in the turns.
	var velocity := (wanted - global_position)
	var pitch := clampf(-velocity.y * BODY_GAIN, -1.0, 1.0) * deg_to_rad(BODY_PITCH)
	var bank := clampf(velocity.dot(player.get_forward().cross(Vector3.UP)) * BODY_GAIN,
			-1.0, 1.0) * deg_to_rad(BODY_BANK)
	if _model != null:
		_model.rotation = Vector3(pitch, 0.0, bank)


## The gimbal aims at the player; the body does not move. While the EMP locks on, the light
## turns red and pulses four times a second.
func _update_aim(dt: float, player: VehicleBase) -> void:
	if player == null or _gimbal == null:
		return
	_gimbal.look_at(player.global_position, Vector3.UP)
	if _spot == null:
		return
	_emp_blink += dt
	if _emp_lock > 0.0:
		var blink := fmod(_emp_blink * EMP_PULSE, 1.0) < EMP_BLINK_ON
		_spot.light_color = EMP_COLOR
		_spot.light_energy = SPOT_ENERGY * (EMP_BRIGHT if blink else EMP_DIM)
	else:
		_spot.light_color = SPOT_COLOR
		_spot.light_energy = SPOT_ENERGY


## The rotors spin about their own axis (the plane of the disc stays level).
func _update_rotors(dt: float) -> void:
	for i in _rotors.size():
		# The rotors on the left turn one way, the ones on the right the other.
		var sign := 1.0 if i % 2 == 0 else -1.0
		_rotors[i].rotate_y(ROTOR_SPEED * dt * sign)


## The beam cone reaches down to the road: it runs along the -Z axis of the light, so the cone
## and the pool of the light are the same.
##
## The length is the ray from the gimbal to the ground, not the distance to the player: the
## beam of a light ends where the light ends.
func _update_beam(dt: float, player: VehicleBase) -> void:
	if _beam == null or _gimbal == null:
		return
	_dust_time += dt
	var length := _beam_length()
	var scale := clampf(length / BEAM_REFERENCE_LENGTH, BEAM_MIN_SCALE, BEAM_MAX_SCALE)
	_beam.scale = Vector3(scale, length, scale)
	_beam.position = Vector3(0.0, 0.0, -length * 0.5)
	if _beam_material == null:
		return
	_beam_material.set_shader_parameter("beam_length", length)
	_beam_material.set_shader_parameter("dust_time", _dust_time)
	_beam_material.set_shader_parameter("camera_fade", _camera_fade(player))


## The distance from the gimbal to the ground along the beam (m).
func _beam_length() -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return BEAM_REFERENCE_LENGTH
	var from := _gimbal.global_position
	var to := from - _gimbal.global_transform.basis.z * BEAM_REFERENCE_LENGTH * 2.0
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return BEAM_REFERENCE_LENGTH
	return maxf(from.distance_to(hit["position"] as Vector3), 1.0)


## How much of the beam the camera sees: it is nothing when the camera is under the drone.
func _camera_fade(player: VehicleBase) -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 1.0
	var axis := _gimbal.global_transform.basis.z
	var to_camera := camera.global_position - _gimbal.global_position
	var along := to_camera.dot(axis)
	var distance := (to_camera - axis * along).length()
	return clampf((distance - BEAM_CAMERA_FADE) / (BEAM_CAMERA_FULL - BEAM_CAMERA_FADE), 0.0, 1.0)


## The drone drops a spike strip on the road ahead of the player.
func _request_spike(player: VehicleBase) -> void:
	if player == null:
		return
	spike_requested.emit()
	PoliceRadio.say(&"spikes")


## The EMP: the light turns red and pulses while it locks on, then the pulse hits.
func _fire_emp(player: VehicleBase) -> void:
	if player == null:
		return
	var director := get_tree().get_first_node_in_group(&"police_director") as PoliceDirector
	if director != null:
		director.debuff.emp(player)
	PoliceRadio.say(&"emp_pulse")


## The test hook: drops a spike strip right now.
func force_spike_drop() -> void:
	_spike_timer = 0.0


## The test hook: fires the EMP pulse right now.
func force_emp() -> void:
	_emp_lock = EMP_LOCK
