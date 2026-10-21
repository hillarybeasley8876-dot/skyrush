extends Node
## Unit tests for the fx_thrusters plume system.
## Run: tools/godot.sh test res://fx/thrusters/tests/test_thrusters.gd
##
## Follows the project convention: a Node script loaded at runtime by tools/test_host.gd, so the
## autoloads (Events, Game, Settings) and the VehicleBase contract are available.

const NozzleTable := preload("res://fx/thrusters/lib/nozzle_table.gd")
const JetMesh := preload("res://fx/thrusters/lib/jet_mesh.gd")
const ThrusterSystem := preload("res://fx/thrusters/thruster_system.gd")
const ThrusterRig := preload("res://fx/thrusters/thruster_rig.gd")
const NozzleFX := preload("res://fx/thrusters/nozzle_fx.gd")
const GroundCloud := preload("res://fx/thrusters/ground_cloud.gd")
const LandingPuff := preload("res://fx/thrusters/landing_puff.gd")
const DemoCar := preload("res://fx/thrusters/demo/demo_car.gd")
const ErrorCounter := preload("res://tools/error_counter.gd")
const STUB_CAR := "res://core/stubs/stub_car.tscn"

const FRAME_TIMEOUT := 400
## The car the fallback anchors are checked against.
const FALLBACK_POS := Vector3(10.0, 5.0, -3.0)
const FALLBACK_YAW := 90.0
## The lift cloud exists between these heights above the road.
const CLOUD_LOW_HEIGHT := 5.0
const CLOUD_HIGH_HEIGHT := 9.0
## The rear cloud only exists just above the road.
const REAR_CLOUD_HEIGHT := 2.5

var _fails: int = 0
var _frame: int = 0
var _system: ThrusterSystem
var _car: VehicleBase
var _npcs: Array[VehicleBase] = []
## The player car: it always gets a full-tier plume.
var _player: VehicleBase = null
## A car with real nozzle markers, for the detach test.
var _marker_car: DemoCar = null
var _counter: ErrorCounter = null


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS ", label)
	else:
		_fails += 1
		print("FAIL ", label, " ", detail)


func _ready() -> void:
	_test_table()
	_test_mesh()
	_build_ground()
	_system = ThrusterSystem.new()
	_system.name = "ThrusterSystem"
	add_child(_system)
	_car = _make_stub_car("Roadster")
	_system.attach(_car)


## A flat road, so the ground raycasts have something to hit.
func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)
	add_child(ground)


func _make_stub_car(node_name: String) -> VehicleBase:
	var car := (load(STUB_CAR) as PackedScene).instantiate() as VehicleBase
	car.name = node_name
	car.freeze = true
	add_child(car)
	return car


func _test_table() -> void:
	_check("table has ten nozzles", NozzleTable.NAMES.size() == 10)
	var ok_dir := true
	for name in NozzleTable.NAMES:
		var cfg: Dictionary = NozzleTable.get_nozzle(name)
		if cfg.is_empty() or not (cfg["dir"] as Vector3).is_normalized():
			ok_dir = false
	_check("every nozzle has a unit direction", ok_dir)
	var r1: Dictionary = NozzleTable.get_nozzle(&"Nozzle_R1")
	_check("rear nozzle points backwards", (r1["dir"] as Vector3) == Vector3(0, 0, 1))
	var p1: Dictionary = NozzleTable.get_nozzle(&"Nozzle_P1")
	_check("lift nozzle points down", (p1["dir"] as Vector3) == Vector3(0, -1, 0))
	_check("rear nozzles are grouped", NozzleTable.names_in_group(NozzleTable.REAR).size() == 4)
	_check("lift nozzles are grouped", NozzleTable.names_in_group(NozzleTable.LIFT).size() == 4)
	_check("yaw nozzles are grouped", NozzleTable.names_in_group(NozzleTable.YAW).size() == 2)
	_check("lift nozzles are down-firing", NozzleTable.is_down_firing(&"Nozzle_P3"))
	_check("rear nozzles are not down-firing", not NozzleTable.is_down_firing(&"Nozzle_R1"))


func _test_mesh() -> void:
	var mesh := JetMesh.mesh()
	_check("jet mesh has one surface", mesh.get_surface_count() == 1)
	var aabb := mesh.get_aabb()
	_check("jet mesh has a usable aabb", aabb.size.length() > 0.5, str(aabb))
	_check("jet mesh spans one unit along y", aabb.size.y > 0.9, str(aabb))
	_check("jet mesh widens towards the tip", aabb.size.x > 0.1, str(aabb))


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame > FRAME_TIMEOUT:
		_check("test finished", false, "timed out")
		_finish()
		return
	match _frame:
		1:
			_car.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(FALLBACK_YAW)),
					FALLBACK_POS)
		3:
			_test_fallback_anchors()
			_test_tiers()
		4:
			_counter = ErrorCounter.new()
			OS.add_logger(_counter)
		5:
			_test_reattach()
		6:
			OS.remove_logger(_counter)
			_check("attach after detach raises no engine error", _counter.errors == 0,
					"%d errors: %s" % [_counter.errors, str(_counter.first_errors)])
			_counter = null
		8:
			_player.global_position = Vector3(FALLBACK_POS.x, CLOUD_LOW_HEIGHT, FALLBACK_POS.z)
			_fire_lift(_player, 1.0)
		10:
			_check("lift cloud is on 5 m above the road", _lift_cloud().emitting)
			_player.global_position = Vector3(FALLBACK_POS.x, CLOUD_HIGH_HEIGHT, FALLBACK_POS.z)
		12:
			_check("lift cloud is off 9 m above the road", not _lift_cloud().emitting)
			_player.global_position = Vector3(FALLBACK_POS.x, REAR_CLOUD_HEIGHT, FALLBACK_POS.z)
			_fire_rear(_player, 1.0)
		14:
			_check("rear cloud is off 2.5 m above the road", not _rear_cloud().emitting)
			_player.global_position = Vector3(FALLBACK_POS.x, 0.0, FALLBACK_POS.z)
			_fire_rear(_player, 1.0)
		17:
			_test_rear_cloud()
		19:
			_test_landing_events()
		21:
			_test_materials()
		23:
			_test_particle_budget()
		25:
			_test_detach_attach()
		27:
			_check("detach frees the plumes", _count_plumes(_marker_car) == 0,
					"%d plumes left" % _count_plumes(_marker_car))
			_system.attach(_marker_car)
		29:
			_check("re-attach gives one plume per marker", _count_plumes(_marker_car) == 10,
					"%d plumes" % _count_plumes(_marker_car))
			var marker: Node = _marker_car.get_visual_root().get_node(^"Nozzle_R1")
			var under_marker := 0
			for child in marker.get_children():
				if String(child.name).begins_with("Fx"):
					under_marker += 1
			_check("no duplicate plume under a marker", under_marker == 1, "%d plumes" % under_marker)
			_finish()


## The stub car has no nozzle markers, so the rig falls back to the dossier layout - and those
## anchors have to be parented to the car, not to the world.
func _test_fallback_anchors() -> void:
	var bad_pos := 0
	var bad_dir := 0
	for nozzle_name in NozzleTable.NAMES:
		var fx: NozzleFX = _rig().get_nozzle(StringName(nozzle_name))
		if fx == null:
			bad_pos += 1
			continue
		var local_pos: Vector3 = _car.global_transform.affine_inverse() * fx.global_position
		var expected: Dictionary = NozzleTable.get_nozzle(nozzle_name)
		if local_pos.distance_to(expected["pos"]) > 0.01:
			bad_pos += 1
		var car_dir: Vector3 = _car.global_transform.basis.inverse() \
				* (-(fx.global_transform.basis.z))
		if car_dir.normalized().dot(expected["dir"]) < 0.99:
			bad_dir += 1
	_check("fallback nozzles sit at the dossier positions on the car", bad_pos == 0,
			"%d wrong" % bad_pos)
	_check("fallback nozzles point along the dossier directions", bad_dir == 0, "%d wrong" % bad_dir)


## At most two cars get the full plume, and the player is always one of them. The player car is
## attached last, so the tiers have to be recomputed on every attach.
func _test_tiers() -> void:
	for i in 3:
		var npc := _make_stub_car("Npc%d" % i)
		_npcs.append(npc)
		_system.attach(npc)
	var player_car := _make_stub_car("PlayerCar")
	Game.player = player_car
	_player = player_car
	_system.attach(player_car)
	var full := 0
	var player_full := false
	for car in _npcs:
		if _system.tier_of(car) == 0:
			full += 1
	if _system.tier_of(player_car) == 0:
		full += 1
		player_full = true
	if _system.tier_of(_car) == 0:
		full += 1
	_check("exactly two cars get the full plume", full == 2, "%d full" % full)
	_check("the player gets a full plume", player_full)


## attach -> detach -> attach must not raise.
func _test_reattach() -> void:
	_system.detach(_car)
	_system.attach(_car)
	_check("attach after detach works", _system.attached_count() == 5,
			"count=%d" % _system.attached_count())
	_check("the re-attached car is still tracked", _system.is_attached(_car))


## The rear launch cloud: it has to emit, and it has to emit backwards.
func _test_rear_cloud() -> void:
	_check("rear cloud is on at ground level", _rear_cloud().emitting)
	var emitter: GPUParticles3D = _rear_cloud()
	var jet_dir: Vector3 = -(emitter.global_transform.basis.z)
	var car_back: Vector3 = _player.global_transform.basis.z
	_check("the rear cloud emits backwards", jet_dir.dot(car_back) > 0.9,
			"dot=%.2f" % jet_dir.dot(car_back))


## A crash must not throw up vapour, a clean landing must, and so must leaving a sky lane.
func _test_landing_events() -> void:
	_car.global_position = Vector3(FALLBACK_POS.x, 0.1, FALLBACK_POS.z)
	var before: int = _puff_count()
	Events.landed.emit(_car, 0.4, 9.0, &"crash")
	_check("a crash landing spawns no puff", _puff_count() == before)
	Events.landed.emit(_car, 1.2, 9.0, &"clean")
	_check("a clean landing spawns a puff", _puff_count() == before + 1)
	var before_lane: int = _puff_count()
	# A SkyLane is a node, so it has to be freed again or it leaks at exit.
	var lane := SkyLane.new()
	Events.flight_changed.emit(_car, true, lane)
	Events.flight_changed.emit(_car, false, lane)
	lane.free()
	_check("leaving a sky lane spawns a puff", _puff_count() == before_lane + 1,
			"count=%d" % _puff_count())


## Every emitter takes one random sprite frame and never animates it, and every emitter collides
## with the road.
func _test_materials() -> void:
	var fx: NozzleFX = _rig().get_nozzle(&"Nozzle_R1")
	var vapour: GPUParticles3D = fx.get_node(^"JetVapour") as GPUParticles3D
	var vpm: ParticleProcessMaterial = vapour.process_material as ParticleProcessMaterial
	_check("the vapour takes a random sprite frame",
			vpm.anim_offset_max >= 0.99 and vpm.anim_speed_max == 0.0)
	_check("the vapour collides with the road",
			vpm.collision_mode != ParticleProcessMaterial.COLLISION_DISABLED)
	var lpm: ParticleProcessMaterial = _lift_cloud().process_material as ParticleProcessMaterial
	_check("the lift cloud takes a random sprite frame", lpm.anim_offset_max >= 0.99)
	_check("the lift cloud collides with the road",
			lpm.collision_mode != ParticleProcessMaterial.COLLISION_DISABLED)
	var rpm: ParticleProcessMaterial = _rear_cloud().process_material as ParticleProcessMaterial
	_check("the rear cloud takes a random sprite frame", rpm.anim_offset_max >= 0.99)
	_check("the rear cloud collides with the road",
			rpm.collision_mode != ParticleProcessMaterial.COLLISION_DISABLED)
	var puff: LandingPuff = _rig().get_node(^"LandingPuff1") as LandingPuff
	var pm: ParticleProcessMaterial = puff.get_node(^"Puff").process_material \
			as ParticleProcessMaterial
	_check("the landing puff takes a random sprite frame", pm.anim_offset_max >= 0.99)
	_check("the landing ring lies flat on the road", pm.emission_ring_axis == Vector3.UP)
	_check("the landing puff collides with the road",
			pm.collision_mode != ParticleProcessMaterial.COLLISION_DISABLED)


## The particle budget has to stay inside the whole-game budget.
func _test_particle_budget() -> void:
	var capacity: int = _system.particle_capacity(Game.player)
	_check("a full car stays under 6000 particles", capacity <= 6000, "capacity=%d" % capacity)
	var preset: float = minf(1.0, float(Settings.feature("particles")))
	var expected: int = _expected_vapour(preset) \
			+ GroundCloud.CLOUD_AMOUNT + GroundCloud.REAR_AMOUNT
	_check("the budget scales with the quality preset", capacity == expected,
			"capacity=%d expected=%d" % [capacity, expected])
	var reduced: int = _system.particle_capacity(_npcs[2])
	_check("a reduced car has no ground cloud", reduced <= 500, "capacity=%d" % reduced)


## The vapour particles of a full car, scaled by the quality preset.
func _expected_vapour(preset: float) -> int:
	var total: int = 0
	for nozzle_name in NozzleTable.NAMES:
		var cfg: Dictionary = NozzleTable.get_nozzle(nozzle_name)
		var group: String = String(cfg["group"])
		total += int(round(float(NozzleFX.VAPOUR_AMOUNT[group]) * preset))
	return total


## Detaching a car with real markers must take its plumes with it.
func _test_detach_attach() -> void:
	_marker_car = DemoCar.new()
	_marker_car.name = "MarkerCar"
	add_child(_marker_car)
	_system.attach(_marker_car)
	_fire_rear(_marker_car, 1.0)
	_check("the marker car got its plumes", _count_plumes(_marker_car) == 10,
			"%d plumes" % _count_plumes(_marker_car))
	_system.detach(_marker_car)


## The number of plume nodes under a car.
func _count_plumes(car: Node) -> int:
	var count := 0
	for node in car.find_children("Fx*", "Node3D", true, false):
		count += 1
	return count


## The rig of the test car (it changes when the car is re-attached).
func _rig() -> ThrusterRig:
	return _system.rig_for(_car)


## The rig of the player car (the full-tier one).
func _player_rig() -> ThrusterRig:
	return _system.rig_for(Game.player)


func _lift_cloud() -> GPUParticles3D:
	return _player_rig().get_node(^"GroundClouds/LiftCloud") as GPUParticles3D


func _rear_cloud() -> GPUParticles3D:
	return _player_rig().get_node(^"GroundClouds/RearCloud") as GPUParticles3D


func _puff_count() -> int:
	var count := 0
	for child in _rig().get_children():
		if String(child.name).begins_with("LandingPuff"):
			count += 1
	return count


func _fire_lift(car: VehicleBase, value: float) -> void:
	for nozzle_name in NozzleTable.names_in_group(NozzleTable.LIFT):
		car.telemetry.thrusters[nozzle_name] = value


func _fire_rear(car: VehicleBase, value: float) -> void:
	for nozzle_name in NozzleTable.names_in_group(NozzleTable.REAR):
		car.telemetry.thrusters[nozzle_name] = value


func _finish() -> void:
	# Everything is detached and freed, so the run does not leak objects.
	if _marker_car != null:
		_system.detach(_marker_car)
		_marker_car.queue_free()
	for npc in _npcs:
		_system.detach(npc)
		npc.queue_free()
	_system.detach(_car)
	_system.detach(Game.player)
	_car.queue_free()
	if Game.player != null:
		Game.player.queue_free()
		Game.player = null
	_system.queue_free()
	# The queue_free above is deferred: the nodes have to leave the tree before the engine
	# counts the objects, and the shared meshes and materials have to be released as well.
	await get_tree().process_frame
	await get_tree().process_frame
	ThrusterSystem.release_assets()
	await get_tree().process_frame
	print("TESTS %s" % ("PASS" if _fails == 0 else "FAIL %d" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)
