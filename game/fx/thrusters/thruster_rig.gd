extends Node3D
## Per-vehicle thruster rig: resolves the ten nozzles of one car, drives their plumes from
## telemetry, owns the two "lit throat" lights and the ground clouds.
##
## The rig never reaches into the vehicle: it reads `vehicle.telemetry.thrusters` and the marker
## transforms that CONTRACTS §5 defines.

const NozzleTable := preload("res://fx/thrusters/lib/nozzle_table.gd")
const NozzleFX := preload("res://fx/thrusters/nozzle_fx.gd")
const GroundCloud := preload("res://fx/thrusters/ground_cloud.gd")
const LandingPuff := preload("res://fx/thrusters/landing_puff.gd")

## A down-plume reaches the road from 5-7 m up (dossier §6.1), so the reach is 6 m.
const GROUND_REACH := 6.0
## The lift raycast only counts when the jets point downwards: a car on its side fires them
## sideways, and the cloud would land under the car.
const DOWNWARD_DIR_Y := -0.5
## The rear launch cloud only exists while the rear nozzles are just above the road.
const REAR_CLOUD_MAX_HEIGHT := 1.2
## A marker must point this closely at the dossier direction to be trusted.
const MARKER_DIR_DOT := 0.5
## The ground raycast starts this far in front of the nozzle.
const NOZZLE_AHEAD := 0.25
## Tier ids: 0 = full plume, 1 = core + reduced vapour, 2 = core only.
const TIER_FULL := 0
const TIER_REDUCED := 1
const TIER_CORE_ONLY := 2
## The height used when there is no road under the plume: the column does not fade.
const GROUND_UNKNOWN := -1000.0
## The vapour has to stop at the road instead of falling through it.
const GROUND_COLLISION_SIZE := Vector3(8.0, 0.5, 8.0)
const LIGHT_RANGE := 2.0
const LIGHT_COLOUR := Color(0.812, 0.890, 1.0)
## The lit throat fakes the reflected scene light: energy 0.5-1 while firing (dossier §6.3).
const LIGHT_ENERGY_MIN := 0.5
const LIGHT_ENERGY_MAX := 1.0

var vehicle: VehicleBase = null
var quality: float = 1.0
## 0 = full plume, 1 = core + reduced vapour, 2 = core only.
var tier: int = 0

var _nozzles: Dictionary[String, NozzleFX] = {}
var _anchors: Dictionary[String, Node3D] = {}
var _lights: Dictionary[String, OmniLight3D] = {}
var _clouds: GroundCloud = null
var _ground_collision: GPUParticlesCollisionBox3D = null
## Fallback anchors live under the car (CONTRACTS: the fallback is parented to the car), so the
## rig has to clean them up when it goes away.
var _fallback_anchors: Array[Node3D] = []
## The plumes live under the car's markers, so the rig has to clean them up as well.
var _nozzle_nodes: Array[NozzleFX] = []
var _puff_serial: int = 0
var _lift_hit: Vector3 = Vector3(INF, INF, INF)
var _rear_hit: Vector3 = Vector3(INF, INF, INF)
var _rear_exit: Vector3 = Vector3.INF
var _rear_dir: Vector3 = Vector3.BACK


## Builds the plumes for `veh`.
func setup(veh: VehicleBase, particle_quality: float) -> void:
	vehicle = veh
	quality = clampf(particle_quality, 0.0, 1.0)
	for nozzle_name in NozzleTable.NAMES:
		_build_nozzle(nozzle_name)
	_clouds = GroundCloud.new()
	_clouds.name = "GroundClouds"
	add_child(_clouds)
	_build_ground_collision()
	_build_lights()


func _build_nozzle(nozzle_name: String) -> void:
	var cfg: Dictionary = NozzleTable.get_nozzle(nozzle_name)
	if cfg.is_empty():
		return
	var anchor := _resolve_anchor(nozzle_name, cfg)
	var fx := NozzleFX.new()
	fx.name = "Fx" + nozzle_name
	anchor.add_child(fx)
	fx.setup(cfg, quality)
	_nozzles[nozzle_name] = fx
	_anchors[nozzle_name] = anchor
	_nozzle_nodes.append(fx)


## Finds the car marker for a nozzle, or falls back to the dossier layout.
##
## The glTF contract says the marker's -Z is the jet direction. If a marker is found but points
## somewhere else, the dossier direction is used instead and only the position is taken from the
## marker, so a mis-oriented marker can never fire a plume the wrong way.
func _resolve_anchor(nozzle_name: String, cfg: Dictionary) -> Node3D:
	var marker: Node3D = vehicle.get_marker(StringName(nozzle_name))
	var expected: Vector3 = cfg["dir"]
	if marker != null:
		var world_dir: Vector3 = -(marker.global_transform.basis.z)
		var car_dir: Vector3 = vehicle.global_transform.basis.inverse() * world_dir
		if car_dir.normalized().dot(expected) > MARKER_DIR_DOT:
			return marker
		var local_pos: Vector3 = vehicle.global_transform.affine_inverse() * marker.global_position
		return _fallback_anchor(local_pos, expected)
	return _fallback_anchor(cfg["pos"], expected)


## Fallback nozzle anchor. It is parented to the car so the plume follows the car, exactly like
## a real marker does.
func _fallback_anchor(local_pos: Vector3, dir: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = "NozzleFallback"
	var parent: Node = vehicle.get_visual_root()
	if parent == null:
		parent = vehicle
	parent.add_child(node)
	node.position = local_pos
	var up: Vector3 = Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	node.transform.basis = Basis.looking_at(dir.normalized(), up)
	_fallback_anchors.append(node)
	return node


## The plumes and the fallback anchors hang off the car, so they have to go when the rig does.
func _exit_tree() -> void:
	for fx in _nozzle_nodes:
		if is_instance_valid(fx):
			fx.queue_free()
	_nozzle_nodes.clear()
	for anchor in _fallback_anchors:
		if is_instance_valid(anchor):
			anchor.queue_free()
	_fallback_anchors.clear()


## A collision box on the road, so the plume lands on it and spreads instead of sinking.
func _build_ground_collision() -> void:
	_ground_collision = GPUParticlesCollisionBox3D.new()
	_ground_collision.name = "GroundCollision"
	_ground_collision.size = GROUND_COLLISION_SIZE
	add_child(_ground_collision)


func _build_lights() -> void:
	for group in [NozzleTable.REAR, NozzleTable.LIFT]:
		var light := OmniLight3D.new()
		light.name = "Light" + group
		light.light_color = LIGHT_COLOUR
		light.light_energy = 0.0
		light.omni_range = LIGHT_RANGE
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights[group] = light


## Drives every plume from the telemetry snapshot.
func update_from_telemetry(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	var thrusters: Dictionary = vehicle.telemetry.thrusters
	for nozzle_name in _nozzles:
		var fx: NozzleFX = _nozzles[nozzle_name]
		fx.set_target(float(thrusters.get(nozzle_name, 0.0)))
	_update_lights()
	_update_clouds(delta)


func _update_lights() -> void:
	for group in _lights:
		var light: OmniLight3D = _lights[group]
		var best: float = 0.0
		var centre := Vector3.ZERO
		var count: int = 0
		for nozzle_name in NozzleTable.names_in_group(group):
			var fx: NozzleFX = _nozzles[nozzle_name]
			var v: float = fx.get_value()
			if v <= 0.0:
				continue
			best = maxf(best, v)
			centre += _anchors[nozzle_name].global_position
			count += 1
		if count == 0:
			light.visible = false
			light.light_energy = 0.0
			continue
		light.visible = true
		light.global_position = centre / float(count)
		light.light_energy = lerpf(LIGHT_ENERGY_MIN, LIGHT_ENERGY_MAX, best)


## Raycasts happen in the physics step; the clouds consume the results in the render step.
func _physics_process(_delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	_lift_hit = _lift_ground_hit()
	_rear_hit = _ground_hit(_group_centre(NozzleTable.REAR, 0.0), Vector3.DOWN)
	_update_rear_exit()
	_update_ground_collision()
	_update_ground_heights()


## The road under the lift jets. The cast follows the mean jet direction, so a car that is
## rolled or upside down does not throw its cloud under itself (review SHOULD-FIX 2).
func _lift_ground_hit() -> Vector3:
	var jet := _group_jet(NozzleTable.LIFT, 0.0)
	if jet.is_empty():
		return Vector3.INF
	var dir: Vector3 = jet["dir"]
	if dir.y > DOWNWARD_DIR_Y:
		return Vector3.INF
	return _ground_hit(jet["pos"], dir)


## Feeds the height of the road to the vapour columns, so they dissolve into it.
func _update_ground_heights() -> void:
	for nozzle_name in NozzleTable.names_in_group(NozzleTable.LIFT):
		_nozzles[nozzle_name].set_ground_height(_ground_y(_lift_hit))
	for nozzle_name in NozzleTable.names_in_group(NozzleTable.REAR):
		_nozzles[nozzle_name].set_ground_height(_ground_y(_rear_hit))


## The height of a ground hit, or a very low value when there is no ground.
func _ground_y(hit: Vector3) -> float:
	return hit.y if hit.is_finite() else GROUND_UNKNOWN


## Keeps the collision box on the road under the plume: its top face is the road itself.
func _update_ground_collision() -> void:
	if not _lift_hit.is_finite():
		_ground_collision.process_mode = Node.PROCESS_MODE_DISABLED
		return
	_ground_collision.process_mode = Node.PROCESS_MODE_INHERIT
	_ground_collision.global_position = _lift_hit - Vector3(0.0, GROUND_COLLISION_SIZE.y * 0.5, 0.0)


## The rear launch cloud starts at the nozzle exit and trails backwards, never under the car.
func _update_rear_exit() -> void:
	var exit_pos := Vector3.ZERO
	var dir := Vector3.ZERO
	var count: int = 0
	for nozzle_name in NozzleTable.names_in_group(NozzleTable.REAR):
		var fx: NozzleFX = _nozzles[nozzle_name]
		if fx.get_value() <= 0.05:
			continue
		var anchor: Node3D = _anchors[nozzle_name]
		var jet_dir: Vector3 = -(anchor.global_transform.basis.z)
		exit_pos += anchor.global_position + jet_dir * NOZZLE_AHEAD
		dir += jet_dir
		count += 1
	if count == 0:
		_rear_exit = Vector3.INF
		_rear_dir = Vector3.BACK
		return
	_rear_exit = exit_pos / float(count)
	_rear_dir = dir.normalized()


func _update_clouds(delta: float) -> void:
	if tier > TIER_FULL:
		# A demoted rig must not keep throwing up vapour (review SHOULD-FIX 1).
		_clouds.stop()
		return
	# The rear cloud only exists when the rear nozzles are just above the road.
	var rear_low: bool = _rear_hit.is_finite() and _rear_exit.is_finite() \
			and _rear_exit.y - _rear_hit.y <= REAR_CLOUD_MAX_HEIGHT
	_clouds.update_clouds(delta, _lift_hit, _group_value(NozzleTable.LIFT), rear_low, _rear_exit,
			_rear_dir, vehicle.global_transform.basis)


## Changes the particle budget of the whole rig (used when the tier changes).
func set_particle_quality(particle_quality: float) -> void:
	quality = clampf(particle_quality, 0.0, 1.0)
	for nozzle_name in _nozzles:
		_nozzles[nozzle_name].set_particle_quality(quality)


## The particles alive for this car: the sum of every emitter's amount.
func particle_capacity() -> int:
	var total: int = 0
	for nozzle_name in _nozzles:
		total += _nozzles[nozzle_name].particle_capacity()
	if tier == TIER_FULL:
		total += _clouds.particle_capacity()
	return total


## The plume node of one nozzle (null when the nozzle is unknown).
func get_nozzle(nozzle_name: StringName) -> NozzleFX:
	return _nozzles.get(nozzle_name)


## Average world position of the firing nozzles of a group, pushed `ahead` metres along the jet.
func _group_centre(group: String, ahead: float) -> Vector3:
	var jet := _group_jet(group, ahead)
	if jet.is_empty():
		return Vector3.INF
	return jet["pos"]


## The strongest throttle in a group.
func _group_value(group: String) -> float:
	var best: float = 0.0
	for nozzle_name in NozzleTable.names_in_group(group):
		best = maxf(best, _nozzles[nozzle_name].get_value())
	return best


## The mean jet of the firing nozzles of a group: {pos, dir}. Empty when the group is not firing.
func _group_jet(group: String, ahead: float) -> Dictionary:
	var centre := Vector3.ZERO
	var dir := Vector3.ZERO
	var count: int = 0
	for nozzle_name in NozzleTable.names_in_group(group):
		var fx: NozzleFX = _nozzles[nozzle_name]
		if fx.get_value() <= 0.05:
			continue
		var anchor: Node3D = _anchors[nozzle_name]
		var jet_dir: Vector3 = -(anchor.global_transform.basis.z)
		centre += anchor.global_position + jet_dir * ahead
		dir += jet_dir
		count += 1
	if count == 0:
		return {}
	return {"pos": centre / float(count), "dir": dir.normalized()}


## First world layer below `origin`, or Vector3.INF when there is no ground within reach.
func _ground_hit(origin: Vector3, dir: Vector3) -> Vector3:
	if not origin.is_finite():
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * GROUND_REACH, 1)
	if vehicle != null and is_instance_valid(vehicle):
		params.exclude = [vehicle.get_rid()]
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"]


## Ring of vapour at wheel height plus the faint ground ring (gameplay dossier §5.5).
func spawn_landing_puff() -> void:
	var origin: Vector3 = vehicle.global_position + Vector3(0.0, 0.25, 0.0)
	var point: Vector3 = _ground_hit(origin, Vector3.DOWN)
	if not point.is_finite():
		point = vehicle.global_position
	_puff_serial += 1
	var puff := LandingPuff.new()
	# A unique name: Godot renames a child whose name clashes with a sibling.
	puff.name = "LandingPuff%d" % _puff_serial
	add_child(puff)
	puff.trigger(point, vehicle.global_transform.basis)
