extends Node
## The toll plaza of the real city (申城西收费站 on the G50): it stands across its road, its lanes on the lanes of the road,
## and it lets the cars through the way the dossier says.
##
##   python tools/gd.py test res://world/tests/test_toll_road.gd -- --timeout=400
##
## The plaza stood turned by 90 degrees along the G50 with its 20 booths in one lane (a car hit them at 100 km/h), its
## signals were red over the green arrows and every eastbound car counted as a toll dodger. Checks: six lanes within
## 0.3 m of the six lane centres of the road, the inner lane of each direction is the ETC lane (green, its arm up), every
## closed lane has its arm; a car that runs a closed lane at 100 km/h is a toll dodger and breaks the arm, a car that
## creeps through one pays (the arm lifts, no infraction), the ETC lane lets a car through at 100 km/h.

const CityData := preload("res://world/loader/city_data.gd")
const WORLD := "res://world/world.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const ROAD := "g50_west"
const LANE_TOLERANCE := 0.3

var _failures := 0
var _infractions: Array[StringName] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := (load(WORLD) as PackedScene).instantiate() as WorldBase
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate() as ArcadeCar
	car.player_controlled = false
	add_child(car)
	Game.player = car
	await Game.world_ready()
	car.queue_free()
	Events.infraction.connect(func(_v: VehicleBase, kind: StringName) -> void: _infractions.append(kind))
	var plaza := world.find_child("TollPlaza_toll_west", true, false) as Node3D
	_expect(plaza != null, "the toll plaza of the G50 is built")
	if plaza == null:
		_finish()
		return
	var lane_z: Array = plaza.get("_lane_z")
	var lane_open: Array = plaza.get("_lane_open")
	var arm_lanes: Array = plaza.get("_arm_lanes")
	_expect(lane_z.size() == 6, "the plaza has six lanes (%d)" % lane_z.size())
	# the lanes of the plaza on the lane centres of the road
	var centres := _road_lane_offsets(plaza)
	var worst := 0.0
	for z in lane_z:
		var best := INF
		for c in centres:
			best = minf(best, absf(float(z) - c))
		worst = maxf(worst, best)
	_expect(worst <= LANE_TOLERANCE, "every lane of the plaza lies on a lane centre of the road (worst %.2f m)" % worst)
	var etc := 0
	for i in lane_z.size():
		if bool(lane_open[i]):
			etc += 1
			_expect(absf(float(lane_z[i])) < 4.0, "the ETC lane %d is the inner lane (z %.2f)" % [i, float(lane_z[i])])
		else:
			_expect(arm_lanes.count(i) == 1, "the closed lane %d has one arm (%d)" % [i, arm_lanes.count(i)])
	_expect(etc == 2, "one ETC lane each way (%d)" % etc)
	# the passes: eastbound lanes have z > 0 and run along +x of the plaza
	var closed := -1
	var slow := -1
	var open := -1
	for i in lane_z.size():
		if float(lane_z[i]) <= 0.0:
			continue
		if bool(lane_open[i]):
			open = i
		elif closed < 0:
			closed = i
		else:
			slow = i
	_infractions.clear()
	await _drive(world, plaza, float(lane_z[open]), 28.0)
	_expect(not _infractions.has(&"toll_evaded"), "the ETC lane lets a car through at 100 km/h")
	_infractions.clear()
	await _drive(world, plaza, float(lane_z[closed]), 28.0)
	_expect(_infractions.has(&"toll_evaded"), "a car that runs a closed lane at 100 km/h dodges the toll")
	var broken: Array = plaza.get("_broken")
	var arms: Array = plaza.get("_arm_lanes")
	_expect(broken[arms.find(closed)], "the arm of the lane that was run is broken off")
	_infractions.clear()
	var lifted := await _drive(world, plaza, float(lane_z[slow]), 5.0, slow)
	_expect(not _infractions.has(&"toll_evaded"), "a car that creeps through a closed lane pays")
	_expect(lifted, "the arm of the paid lane is up when the car reaches it")
	_finish()


## The lateral offsets (the plaza's local z) of the lane centres of the road at the plaza.
func _road_lane_offsets(plaza: Node3D) -> Array[float]:
	var out: Array[float] = []
	var data: Variant = CityData._read_json(CityData.repo_root().path_join("data/city/city.json"))
	if not data is Dictionary:
		return out
	for road in (data as Dictionary).get("roads", []):
		if str(road.get("id", "")) != ROAD:
			continue
		var median := float(road.get("median", 0.0))
		var width := float(road.get("lane_width", 3.75))
		for side in [-1.0, 1.0]:
			for i in int(road.get("lanes_fwd", 3)):
				out.append(side * (median * 0.5 + width * (float(i) + 0.5)))
	return out


## A probe car driven along +x of the plaza through a lane (local z) at a speed (m/s), from 45 m before it. Returns
## whether the lane `lane` was open while the car passed its arm.
func _drive(world: Node, plaza: Node3D, z: float, speed: float, lane: int = -1) -> bool:
	var car := VehicleBase.new()
	car.name = "TollProbe"
	car.team = VehicleBase.Team.PLAYER
	car.collision_layer = 2
	car.collision_mask = 0
	car.gravity_scale = 0.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 0.75, 4.4)
	shape.shape = box
	shape.position = Vector3(0.0, 0.72, 0.0)
	car.add_child(shape)
	world.add_child(car)
	var along := plaza.global_transform.basis.x.normalized()
	var across := plaza.global_transform.basis.z.normalized()
	car.global_transform = Transform3D(Basis.looking_at(along, Vector3.UP),
		plaza.global_position - along * 45.0 + across * z + Vector3.UP * 0.05)
	var open_at_arm := false
	var ticks := int((90.0 / speed) * Engine.physics_ticks_per_second)
	for i in ticks:
		car.linear_velocity = along * speed
		await get_tree().physics_frame
		var x := (car.global_position - plaza.global_position).dot(along)
		if lane >= 0 and x > 0.0 and x < 6.0 and bool(plaza.call("lane_is_open", lane)):
			open_at_arm = true
	car.queue_free()
	await get_tree().physics_frame
	return open_at_arm


func _expect(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _finish() -> void:
	print("TOLL ROAD TESTS %s (%d failures)" % ["OK" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
