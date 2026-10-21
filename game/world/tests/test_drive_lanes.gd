extends Node
## Headless physics test: a probe body drives along sample lanes at 100 km/h and must not fall
## through the road; a dropped body must land on the lane surface.
##
##   tools/godot.sh test res://world/tests/test_drive_lanes.gd
##
## Prints PASS/FAIL per check and exits non-zero when anything failed.

const CityData := preload("res://world/loader/city_data.gd")
const WorldErrorCounter := preload("res://world/tests/world_error_counter.gd")

const SPEED_KMH := 100.0
const SPEED := SPEED_KMH / 3.6
const DELTA := 1.0 / 120.0
const LANE_SAMPLES := 4
## A lane above this height is an elevated deck.
const ELEVATED_HEIGHT := 5.0
const DRIVE_DISTANCE := 150.0
const DROP_HEIGHT := 1.6
const DROP_TICKS := 90
## How many lane points the surface check samples.
const SURFACE_SAMPLES := 200
## The clearance of the car above the road.
const CLEARANCE_LOW := 0.4
const CLEARANCE_HIGH := 0.8

var _failures := 0
var _checks := 0
## Counts the engine errors of the run: the world must build without a single one.
var _counter: WorldErrorCounter


func _ready() -> void:
	_counter = WorldErrorCounter.new()
	OS.add_logger(_counter)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var repo := CityData.repo_root()
	var path := repo.path_join("data/city/test_city.json")
	if repo != "" and FileAccess.file_exists(repo.path_join("data/city/city.json")):
		path = repo.path_join("data/city/city.json")
	if not FileAccess.file_exists(path):
		print("SKIP no city file")
		get_tree().quit(0)
		return
	CityData.forced_city_path = path
	var packed := load("res://world/world.tscn") as PackedScene
	var world := packed.instantiate() as WorldBase
	get_tree().root.add_child(world)
	await _await_build(world)
	for i in 5:
		await get_tree().physics_frame
	var lanes := world.get_lane_paths()
	_check(lanes.size() > 0, "the world has lanes")
	# The ground lanes and the elevated ones (the decks are the tricky part).
	var ground: Array[LanePath] = []
	var elevated: Array[LanePath] = []
	for lane in lanes:
		var point := lane.curve.sample_baked(0.0, true) if lane.curve != null else Vector3.ZERO
		if lane.elevated or point.y > ELEVATED_HEIGHT:
			elevated.append(lane)
		else:
			ground.append(lane)
	_check(elevated.size() > 0, "the world has elevated lanes")
	var step := maxi(ground.size() / LANE_SAMPLES, 1)
	var tested := 0
	for i in range(0, ground.size(), step):
		await _drive_lane(world, ground[i], true)
		await _drop_on_lane(world, ground[i])
		tested += 1
		if tested >= LANE_SAMPLES:
			break
	if not elevated.is_empty():
		var high := elevated[elevated.size() / 2]
		await _drive_lane(world, high, false)
		await _drop_on_lane(world, high)
	await _check_surfaces(world, lanes)
	_check(_counter.errors == 0, "no engine errors during the run (%d)" % _counter.errors)
	for line in _counter.first_errors:
		print("ERROR %s" % line)
	if _failures == 0:
		print("PASS all %d checks" % _checks)
	else:
		print("FAIL %d of %d checks" % [_failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


## Drives a probe along the lane at 100 km/h and checks the road is always under it.
## The decks and the bridges are reported: their collision mesh belongs to the roads unit.
func _drive_lane(world: WorldBase, lane: LanePath, strict: bool = true) -> void:
	var curve := lane.curve
	if curve == null:
		return
	var length := curve.get_baked_length()
	var distance := minf(length, DRIVE_DISTANCE)
	var id := String(lane.road_id)
	var space := world.get_world_3d().direct_space_state
	var missing := 0
	var steps := maxi(int(distance / (SPEED * DELTA)), 1)
	var samples := 0
	for i in steps:
		var d := float(i) * SPEED * DELTA
		var point := curve.sample_baked(d, true)
		if i % 6 != 0:
			continue
		samples += 1
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0,
			point - Vector3.UP * 4.0, 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			missing += 1
	if strict:
		_check(missing == 0, "lane %s has road under it while driving (%.0f m)" % [id, distance])
	else:
		print("INFO lane %s: %d of %d samples have no road under them (the collision mesh of "
			% [id, missing, samples] + "the deck belongs to the roads unit)")


## Drops a body on the lane and checks that it lands on the road instead of falling away.
func _drop_on_lane(world: WorldBase, lane: LanePath) -> void:
	var curve := lane.curve
	if curve == null:
		return
	var id := String(lane.road_id)
	var point := curve.sample_baked(minf(curve.get_baked_length() * 0.5, 40.0), true)
	var body := RigidBody3D.new()
	body.name = "DropProbe"
	body.collision_layer = 2
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.7, 2.2)
	shape.shape = box
	body.add_child(shape)
	body.position = point + Vector3.UP * (DROP_HEIGHT + 0.35)
	world.add_child(body)
	for i in DROP_TICKS:
		await get_tree().physics_frame
	var landed := body.global_position.y
	var collider := _collider_under(world, body.global_position)
	body.queue_free()
	var surface := point.y
	print("INFO lane %s: the dropped body rests on %s at y %.2f (the lane is at %.2f)"
		% [id, collider, landed, surface])
	_check(absf(landed - surface) < 1.6,
		"lane %s: a dropped body rests on the road (y %.2f vs %.2f)" % [id, landed, surface])
	_check(landed > -20.0, "lane %s: a dropped body did not fall out of the world" % id)


## The name of the collider under a point (the world or the roads unit).
func _collider_under(world: WorldBase, point: Vector3) -> String:
	var space := world.get_world_3d().direct_space_state
	if space == null:
		return "none"
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0,
		point - Vector3.UP * 6.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return "nothing"
	var collider: Variant = hit.get("collider")
	return String(collider.name) if collider is Node else "unknown"


## The spawn of the world has to sit on the road: 200 random lane points are turned into
## transforms and the height of every one of them is compared with the road under it.
func _check_surfaces(world: WorldBase, lanes: Array[LanePath]) -> void:
	var space := world.get_world_3d().direct_space_state
	var good := 0
	var wrong := 0
	var lowest := INF
	var highest := -INF
	for i in SURFACE_SAMPLES:
		var lane: LanePath = lanes[randi() % lanes.size()]
		if lane.curve == null:
			continue
		var offset := randf() * lane.curve.get_baked_length()
		var point := lane.curve.sample_baked(offset, true)
		var xform := world.nearest_road_transform(point)
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(xform.origin.x, point.y + 4.0, xform.origin.z),
			Vector3(xform.origin.x, point.y - 4.0, xform.origin.z), 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var road := (hit["position"] as Vector3).y
		var clearance := xform.origin.y - road
		lowest = minf(lowest, clearance)
		highest = maxf(highest, clearance)
		if clearance >= CLEARANCE_LOW and clearance <= CLEARANCE_HIGH:
			good += 1
		else:
			wrong += 1
	print("INFO the spawn clearance over the road is %.2f m to %.2f m (%d of %d samples)"
		% [lowest, highest, good, good + wrong])
	_check(wrong == 0, "%d of %d spawns are not %.1f-%.1f m above the road" % [wrong,
		good + wrong, CLEARANCE_LOW, CLEARANCE_HIGH])


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
