extends RefCounted
## The obstacles of the sky lanes (飞行航道): drones, neon billboards and crane arms
## (ref/gameplay/DOSSIER.md §5.6). A hit costs 15 HP and 30 % of the speed, never a wreck: the
## vehicle unit does that in `ArcadeCar.flight_hit()`, the world unit only places the obstacles and
## the trigger that calls it.
##
## The obstacles of a lane are seeded with the name of the lane, so the same lane always gets the
## same obstacles (the city is built again on every game start). The meshes and the materials are
## shared by all the obstacles: a lane is a few dozen nodes, not a few thousand draw calls.

const ProcMeshes := preload("res://world/loader/proc_meshes.gd")

## The kinds of obstacle, in the order they repeat along a lane.
const KINDS := ["drone", "billboard", "crane"]

const FIRST_OFFSET := 200.0        # the first obstacle is 200 m after the start of the curve
const GAP_MIN := 180.0             # the next ones are 180 to 260 m further
const GAP_MAX := 260.0
const END_MARGIN := 120.0           # no obstacle in the last 120 m of the curve
const SHORT_LANE := 400.0          # a lane under 400 m gets a single obstacle in its middle
const LATERAL_LIMIT := 4.5          # the centre of an obstacle, sideways from the lane centre
const HEIGHT_MIN := -1.5           # the centre of an obstacle, over the lane centre
const HEIGHT_MAX := 3.0
const TUBE_HALF_WIDTH := 7.0        # the tube of a lane is 14 m wide
const TUBE_UP := 5.0                # and 8 m high
const CRANE_LENGTH := 10.0          # the arm of the crane reaches into the tube from one side
const HIT_LAYER := 1 << 3           # the trigger layer
const VEHICLE_MASK := 1 << 1        # the vehicles

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}


## One obstacle: the meshes and the trigger that hits a flying car.
class SkyObstacle extends Node3D:
	## Only a car that flies in a lane is hit: a car on the ground under the lane is not.
	func on_body_entered(body: Node3D) -> void:
		var vehicle := body as VehicleBase
		if vehicle == null:
			return
		if not vehicle.has_method("flight_hit"):
			return
		if not vehicle.telemetry.flying:
			return
		vehicle.call("flight_hit")


## Fills a lane with obstacles. Returns how many it made.
func build(lane: SkyLane) -> int:
	if lane == null or lane.curve == null:
		return 0
	var length := lane.length()
	if length <= 0.0:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(lane.name))
	var offsets := _offsets(length, rng)
	var made := 0
	for i in offsets.size():
		var obstacle := _make(lane, offsets[i], i, rng)
		if obstacle == null:
			continue
		lane.add_child(obstacle)
		made += 1
	return made


## The offsets of the obstacles of a lane along its curve.
func _offsets(length: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if length < SHORT_LANE:
		# A short lane gets a single obstacle in its middle, far enough from both ends.
		out.append(clampf(length * 0.5, 150.0, maxf(length - 100.0, 150.0)))
		return out
	var offset := FIRST_OFFSET
	var limit := length - END_MARGIN
	while offset <= limit:
		out.append(offset)
		offset += rng.randf_range(GAP_MIN, GAP_MAX)
	return out


## One obstacle of a lane: where it is, and what it looks like.
func _make(lane: SkyLane, offset: float, index: int, rng: RandomNumberGenerator) -> SkyObstacle:
	var kind := String(KINDS[index % KINDS.size()])
	var frame := lane.frame_at(offset)
	var side := 1.0
	var lateral := 0.0
	if kind == "crane":
		side = 1.0 if rng.randf() < 0.5 else -1.0
		lateral = _crane_lateral(side, rng)
	else:
		lateral = rng.randf_range(-LATERAL_LIMIT, LATERAL_LIMIT)
	var height := rng.randf_range(HEIGHT_MIN, HEIGHT_MAX)
	var obstacle := SkyObstacle.new()
	obstacle.name = "SkyObstacle_%s_%d" % [_lane_id(lane), index]
	obstacle.set_meta("kind", kind)
	obstacle.add_to_group("sky_obstacle")
	# The frame of the lane at this offset: x is sideways, y is up, -z is along the lane.
	var origin := frame.origin + frame.basis.x * lateral + frame.basis.y * height
	obstacle.transform = Transform3D(frame.basis, origin)
	match kind:
		"drone":
			_build_drone(obstacle)
		"billboard":
			_build_billboard(obstacle, height)
		"crane":
			_build_crane(obstacle, lateral, side)
	return obstacle


## The lateral offset of the centre of a crane: it lies on the arm, which reaches 10 m in from
## the wall of the tube.
func _crane_lateral(side: float, rng: RandomNumberGenerator) -> float:
	var root := side * TUBE_HALF_WIDTH
	var tip := root - side * CRANE_LENGTH
	var low := maxf(-LATERAL_LIMIT, minf(root, tip))
	var high := minf(LATERAL_LIMIT, maxf(root, tip))
	return rng.randf_range(low, high)


## A drone: a flat glowing body with a ring light around it.
func _build_drone(obstacle: SkyObstacle) -> void:
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _mesh("drone_body")
	body.material_override = _material("drone", Color("ff2bd6"), 2.2)
	obstacle.add_child(body)
	var ring := MeshInstance3D.new()
	ring.name = "RingLight"
	ring.mesh = _mesh("drone_ring")
	ring.material_override = _material("drone", Color("ff2bd6"), 2.2)
	obstacle.add_child(ring)
	_add_hit(obstacle, Vector3(2.2, 0.7, 2.2), Vector3.ZERO)


## A neon billboard: a panel on two thin poles that hang it from the roof of the tube.
func _build_billboard(obstacle: SkyObstacle, height: float) -> void:
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	panel.mesh = _mesh("billboard_panel")
	panel.material_override = _material("billboard", Color("00e5ff"), 1.8)
	obstacle.add_child(panel)
	var pole_length := maxf(0.5, TUBE_UP - height - 1.2)
	for side in [-1.0, 1.0]:
		var pole := MeshInstance3D.new()
		pole.name = "Pole_L" if side < 0.0 else "Pole_R"
		pole.mesh = _mesh("billboard_pole")
		pole.material_override = ProcMeshes.material("metal")
		pole.scale = Vector3(1.0, pole_length, 1.0)
		pole.position = Vector3(side * 1.8, 1.2 + pole_length * 0.5, 0.0)
		obstacle.add_child(pole)
	_add_hit(obstacle, Vector3(4.4, 2.6, 0.5), Vector3.ZERO)
	_add_hit(obstacle, Vector3(3.9, pole_length, 0.4), Vector3(0.0, 1.2 + pole_length * 0.5, 0.0))


## A crane arm: a thin boom that reaches 10 m into the tube from one side, with a red warning
## light at its tip. The tube stays open: the arm is thin and leaves a line past it.
func _build_crane(obstacle: SkyObstacle, lateral: float, side: float) -> void:
	var root := side * TUBE_HALF_WIDTH
	var tip := root - side * CRANE_LENGTH
	var centre := root - side * CRANE_LENGTH * 0.5 - lateral
	var arm := MeshInstance3D.new()
	arm.name = "Arm"
	arm.mesh = _mesh("crane_arm")
	arm.material_override = _material("crane", Color("ffb020"), 1.4)
	arm.position = Vector3(centre, 0.0, 0.0)
	obstacle.add_child(arm)
	var mount := MeshInstance3D.new()
	mount.name = "Mount"
	mount.mesh = _mesh("crane_mount")
	mount.material_override = _material("crane", Color("ffb020"), 1.4)
	mount.position = Vector3(root - lateral, 0.0, 0.0)
	obstacle.add_child(mount)
	var light := MeshInstance3D.new()
	light.name = "WarningLight"
	light.mesh = _mesh("crane_light")
	light.material_override = _material("crane_light", Color("ff2a2a"), 3.0)
	light.position = Vector3(tip - lateral, 0.0, 0.0)
	obstacle.add_child(light)
	_add_hit(obstacle, Vector3(CRANE_LENGTH + 0.2, 0.6, 0.6), Vector3(centre, 0.0, 0.0))


## The trigger of an obstacle: a box around the meshes, on the trigger layer.
func _add_hit(obstacle: SkyObstacle, size: Vector3, offset: Vector3) -> void:
	var area := Area3D.new()
	area.name = "Hit"
	area.collision_layer = HIT_LAYER
	area.collision_mask = VEHICLE_MASK
	area.monitoring = true
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	area.add_child(shape)
	area.body_entered.connect(obstacle.on_body_entered)
	obstacle.add_child(area)


## The id of a lane, without the "SkyLane_" prefix of its node name.
func _lane_id(lane: SkyLane) -> String:
	var lane_name := str(lane.name)
	var prefix := "SkyLane_"
	if lane_name.begins_with(prefix):
		return lane_name.substr(prefix.length())
	return lane_name


## A shared mesh: one mesh for all the obstacles of a kind.
func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key] as Mesh
	var mesh := _make_mesh(key)
	_meshes[key] = mesh
	return mesh


## A shared material: one material for all the obstacles of a kind.
func _material(key: String, color: Color, energy: float) -> Material:
	if _materials.has(key):
		return _materials[key] as Material
	var material := ProcMeshes.glow(color, energy)
	_materials[key] = material
	return material


func _make_mesh(key: String) -> Mesh:
	match key:
		"drone_body":
			return ProcMeshes.box(Vector3(1.6, 0.35, 1.6))
		"drone_ring":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.85
			torus.outer_radius = 1.05
			torus.rings = 16
			torus.ring_segments = 8
			return torus
		"billboard_panel":
			return ProcMeshes.box(Vector3(4.2, 2.4, 0.3))
		"billboard_pole":
			return ProcMeshes.box(Vector3(0.16, 1.0, 0.16))
		"crane_arm":
			return ProcMeshes.box(Vector3(CRANE_LENGTH, 0.3, 0.3))
		"crane_mount":
			return ProcMeshes.box(Vector3(0.7, 0.9, 0.7))
		"crane_light":
			return ProcMeshes.sphere(0.22)
	return ProcMeshes.box(Vector3(0.2, 0.2, 0.2))
