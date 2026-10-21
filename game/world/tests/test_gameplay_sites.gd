extends Node
## Headless test of the gameplay sites: builds a small synthetic city with every kind of POI
## (charge bay, gas station, toll plaza, police station, hiding spot, roadblock site) and checks
## that the world builds the sites, that the signals cycle green / amber / red and that the toll
## plaza raises the toll_evaded infraction and the charge bay starts a charge.
##
##   tools/godot.sh test res://world/tests/test_gameplay_sites.gd
##
## Prints PASS/FAIL per check and exits non-zero when anything failed.
const Layers := preload("res://world/api/layers.gd")

const CityData := preload("res://world/loader/city_data.gd")
const WorldErrorCounter := preload("res://world/tests/world_error_counter.gd")

var _failures := 0
var _checks := 0
## Counts the engine errors of the run: the world must build without a single one.
var _counter: WorldErrorCounter
var _infractions: Array[Dictionary] = []
var _charges := 0
## The stunt events of the run (the breaker has to raise one).
var _stunts: Array[Dictionary] = []


func _ready() -> void:
	_counter = WorldErrorCounter.new()
	OS.add_logger(_counter)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var path := "user://world_gameplay_fixture.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("FAIL cannot write the fixture")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(_fixture()))
	file.close()
	CityData.forced_city_path = path
	Events.infraction.connect(_on_infraction)
	Events.charge_started.connect(_on_charge_started)
	Events.stunt.connect(_on_stunt)
	var packed := load("res://world/world.tscn") as PackedScene
	var world := packed.instantiate() as WorldBase
	get_tree().root.add_child(world)
	await _await_build(world)
	for i in 5:
		await get_tree().physics_frame
	_check_sites(world)
	_check_signals(world)
	await _check_toll(world)
	await _check_charge(world)
	await _check_breaker(world)
	_check(_counter.errors == 0, "no engine errors during the run (%d)" % _counter.errors)
	for line in _counter.first_errors:
		print("ERROR %s" % line)
	if _failures == 0:
		print("PASS all %d checks" % _checks)
	else:
		print("FAIL %d of %d checks" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _fixture() -> Dictionary:
	return {
		"version": 1,
		"name": "fixture",
		"window": {"x_min": -300, "x_max": 300, "z_min": -300, "z_max": 300},
		"roads": [
			{"id": "main_ew", "name": "测试大道", "kind": "surface", "spline": "linear",
				"points": [[-200, 0, 0], [0, 0, 0], [200, 0, 0]], "lanes_fwd": 2, "lanes_back": 2,
				"lane_width": 3.75, "median": 2.0, "shoulder": 0.5, "sidewalk": 3.0, "speed_kmh": 60,
				"style": {"parapet": "none", "lamps": "side", "trees": "plane"}},
		],
		"junctions": [
			{"id": "j_mid", "x": 0, "z": 0, "roads": ["main_ew"], "signals": true},
		],
		"water": [],
		"blocks": [],
		"pois": [
			{"id": "charge", "kind": "charge", "x": -120, "y": 0, "z": 20, "heading_deg": 90,
				"size": [24, 10], "label": "申城闪充", "asset": "charging_station"},
			{"id": "gas", "kind": "gas", "x": 60, "y": 0, "z": 30, "heading_deg": 90,
				"size": [80, 70], "label": "中石华", "asset": "gas_station"},
			{"id": "toll", "kind": "toll", "x": 180, "y": 0, "z": 0, "heading_deg": 90,
				"size": [160, 110], "label": "申城西收费站", "asset": "toll_plaza"},
			{"id": "police", "kind": "police_station", "x": -40, "y": 0, "z": 60,
				"heading_deg": 0, "label": "公安分局"},
			{"id": "hide", "kind": "hiding_spot", "x": -200, "y": 0, "z": 60, "heading_deg": 0,
				"label": "车库"},
			{"id": "block", "kind": "roadblock_site", "x": 0, "y": 0, "z": 0, "heading_deg": 90,
				"label": "路障点"},
		],
		"sky_lanes": [
			{"id": "lane", "label": "测试航道", "points": [[-150, 4, -120], [0, 20, -120], [150, 4, -120]],
				"pad": {"x": -170, "y": 0, "z": -120, "heading_deg": 90}, "n2_rings_m": [120]},
		],
		"routes": [
			{"id": "loop", "title": "测试环线", "laps": 1, "kind": "race",
				"checkpoints": [[-100, 0, 0, 90], [100, 0, 0, 90]], "grid": [[-120, 0, 0, 90]]},
		],
		"spawns": {"player": [-150, 0, -4, 90], "police": [[150, 0, 4, 270]], "traffic_density": 1.0},
	}


# --- checks -----------------------------------------------------------------------------------------

func _check_sites(world: WorldBase) -> void:
	_check(world.find_child("ChargeStation_charge", true, false) != null, "charge station built")
	_check(world.find_child("GasStation_gas", true, false) != null, "gas station built")
	_check(world.find_child("TollPlaza_toll", true, false) != null, "toll plaza built")
	_check(world.find_child("HidingSpot_hide", true, false) != null, "hiding spot built")
	_check(world.find_child("PoliceStation_police", true, false) != null, "police station built")
	_check(world.find_child("Breaker", true, false) != null, "pursuit breaker built")
	_check(world.find_child("StuntGate_fly_over_gas", true, false) != null, "gas stunt gate built")
	_check(world.find_child("StuntGate_fly_over_toll", true, false) != null, "toll stunt gate built")
	_check(world.find_child("LaunchPad", true, false) != null, "sky lane launch pad built")
	_check(world.get_roadblock_sites().size() == 1, "roadblock site registered")
	var kinds: Array[StringName] = []
	for poi in world.get_points_of_interest():
		kinds.append(poi["kind"])
	_check(kinds.has(&"charge") and kinds.has(&"gas") and kinds.has(&"toll"), "POI kinds listed")
	_check(kinds.has(&"sky_lane"), "sky lane listed as a POI")


func _check_signals(world: WorldBase) -> void:
	var signals := world.find_child("Signals", true, false)
	if signals == null:
		_fail("signal controller missing")
		return
	signals.elapsed = 1.0
	_check(world.signal_state(&"j_mid", &"main_ew") == 2, "signal is green in its own slot")
	signals.elapsed = 28.0
	_check(world.signal_state(&"j_mid", &"main_ew") == 1, "signal is amber at the end of its slot")
	signals.elapsed = 5.0
	_check(world.signal_state(&"j_mid", &"other") == 2, "unknown roads report green")


## A car that drives through a closed toll lane raises the toll_evaded infraction. Two passes
## six seconds apart have to raise two of them.
func _check_toll(world: WorldBase) -> void:
	_infractions.clear()
	for run in 2:
		var car := _make_car(world, Vector3(180.0, 1.0, 0.0))
		for i in 10:
			await get_tree().physics_frame
		car.queue_free()
		if run == 0:
			for i in 360:
				await get_tree().physics_frame
	var found := 0
	for entry in _infractions:
		if StringName(entry["kind"]) == &"toll_evaded":
			found += 1
	_check(found == 2, "%d toll_evaded infractions in two passes (expected 2)" % found)
	await _check_broken_arm(world)


## A broken barrier arm becomes debris on the layer 5 and comes to rest above the ground.
func _check_broken_arm(world: WorldBase) -> void:
	var plaza := world.find_child("TollPlaza_toll", true, false)
	if plaza == null:
		_fail("the toll plaza is missing")
		return
	var arms: Array = plaza.get("_arms")
	var lanes: Array = plaza.get("_arm_lanes")
	if arms.is_empty():
		_fail("the toll plaza has no barrier arms")
		return
	var body := arms[0] as RigidBody3D
	plaza.call("break_arm", int(lanes[0]), Vector3(0.0, 0.0, -20.0))
	for i in 240:
		await get_tree().physics_frame
	_check(body.collision_layer == Layers.DEBRIS, "the broken arm is on the debris layer (%d)" % body.collision_layer)
	_check(body.global_position.y >= 0.0,
		"the broken arm rests at y %.2f" % body.global_position.y)


## A car that hits a Support_* node of a breaker at 70 km/h collapses the structure in 1.2 s,
## wrecks the police behind it and raises the breaker stunt.
func _check_breaker(world: WorldBase) -> void:
	_stunts.clear()
	var supports := world.find_children("Support_*", "Node3D", true, false)
	if supports.is_empty():
		_fail("the world has no Support_* node to hit")
		return
	var support := supports[0] as Node3D
	var structure := support.get_parent()
	if structure == null:
		_fail("the breaker has no structure")
		return
	# The police car in the zone behind the breaker.
	var police := _make_car(world, structure.global_position + Vector3(0.0, 1.0, -12.5))
	police.team = VehicleBase.Team.POLICE
	police.add_to_group(&"police")
	# The car that drives into the support at 70 km/h.
	var car := _make_car(world, support.global_position + Vector3(0.0, 0.8, -6.0))
	car.collision_mask = 0
	var hit_at := -1
	var touch_at := -1
	for i in 300:
		car.linear_velocity = Vector3(0.0, 0.0, 19.4)
		await get_tree().physics_frame
		if touch_at < 0 and Vector2(car.global_position.x - support.global_position.x,
				car.global_position.z - support.global_position.z).length() < 2.5:
			touch_at = i
		if not _stunts.is_empty():
			hit_at = i
			break
	car.queue_free()
	_check(hit_at >= 0, "driving into a Support_* node at 70 km/h raises a breaker stunt")
	# The collapse takes 1.2 s from the moment the car touches the support.
	var frames := hit_at - touch_at if hit_at >= 0 and touch_at >= 0 else -1
	_check(frames >= 0 and frames <= 150,
		"the breaker collapsed within 1.2 s of the hit (%d frames)" % frames)
	_check(police.is_wrecked, "the police car in the zone behind the breaker is wrecked")
	var breaker := false
	for entry in _stunts:
		if StringName(entry["kind"]) == &"breaker":
			breaker = true
	_check(breaker, "the breaker raises the breaker stunt")
	police.queue_free()


## A car that drives through the charge bay at speed starts a charge.
func _check_charge(world: WorldBase) -> void:
	_charges = 0
	var car := _make_car(world, Vector3(-120.0, 1.0, 20.0))
	car.linear_velocity = Vector3(20.0, 0.0, 0.0)
	for i in 10:
		await get_tree().physics_frame
	car.queue_free()
	_check(_charges > 0, "driving through the charge bay starts a charge")


func _make_car(world: WorldBase, position: Vector3) -> VehicleBase:
	var car := VehicleBase.new()
	car.name = "Probe"
	car.team = VehicleBase.Team.PLAYER
	car.collision_layer = 2
	car.collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.3, 4.2)
	shape.shape = box
	car.add_child(shape)
	world.add_child(car)
	car.global_position = position
	return car


func _on_infraction(vehicle: VehicleBase, kind: StringName) -> void:
	_infractions.append({"vehicle": vehicle, "kind": kind})


func _on_charge_started(vehicle: VehicleBase, station: Area3D) -> void:
	_charges += 1


func _on_stunt(kind: StringName, points: int, label: String) -> void:
	_stunts.append({"kind": kind, "points": points, "label": label})


# --- reporting --------------------------------------------------------------------------------------

## Waits until the world has built itself (the builder works in phases and yields a frame).
func _await_build(world: WorldBase) -> void:
	for i in 400:
		await get_tree().process_frame
		if float(world.get("loading_fraction")) >= 1.0:
			return


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)


func _fail(label: String) -> void:
	_checks += 1
	_failures += 1
	print("FAIL %s" % label)
