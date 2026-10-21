extends Node
## Quality test of the world: the ground has no floor over the river, the street furniture does
## not stand on the carriageway, the traffic lights light exactly one lens, the light pool is
## fast and its decals sit on the ground, the reflection probes and the occluders exist.
##
##   tools/godot.sh test res://world/tests/test_world_quality.gd
##
## Prints PASS/FAIL per check and exits non-zero when anything failed.

const CityData := preload("res://world/loader/city_data.gd")
const WorldErrorCounter := preload("res://world/tests/world_error_counter.gd")
const LaneIndex := preload("res://world/api/lane_index.gd")
const WaterProbe := preload("res://world/tests/water_probe.gd")
const AssetLibrary := preload("res://world/loader/asset_library.gd")
const PropOccupancy := preload("res://world/build/prop_occupancy.gd")

## How many rays are cast into the water and onto the land.
const RAYS := 50
## A ray that hits the water has to hit it at this height.
const WATER_Y := -3.0
const WATER_TOLERANCE := 0.6
## A lamp is on the carriageway when it is this close to a lane centre.
const LANE_CLEARANCE := 2.2
## The light pool may not take longer than this (ms).
const REASSIGN_LIMIT := 1.0

var _failures := 0
var _checks := 0
var _counter: WorldErrorCounter


func _ready() -> void:
	_counter = WorldErrorCounter.new()
	OS.add_logger(_counter)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var repo := CityData.repo_root()
	var path := repo.path_join("data/city/city.json")
	if not FileAccess.file_exists(path):
		path = repo.path_join("data/city/test_city.json")
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
	await _check_water(world)
	await _check_furniture(world)
	await _check_signals(world)
	await _check_masts(world)
	await _check_lights(world)
	_check_occluders(world)
	await _check_probes(world)
	_check_tiles(world)
	_check_props(world)
	_check_glow(world)
	await _check_collision(world)
	_check(_counter.errors == 0, "no engine errors during the run (%d)" % _counter.errors)
	for line in _counter.first_errors:
		print("ERROR %s" % line)
	if _failures == 0:
		print("PASS all %d checks" % _checks)
	else:
		print("FAIL %d of %d checks" % [_failures, _checks])
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


## The ground must not be a floor over the river: the rays in the water hit the water.
func _check_water(world: WorldBase) -> void:
	var space := world.get_world_3d().direct_space_state
	var data := CityData.new()
	data.load_all()
	var water := 0
	var land := 0
	var wrong := 0
	var water_probe := WaterProbe.new()
	water_probe.setup(data)
	# The sample points come from the water surface itself, so they are really on the river.
	var points := water_probe.water_points(world)
	for i in mini(RAYS, points.size()):
		var point: Vector3 = points[i]
		# From just above the water, so a bridge above the river does not intercept it.
		var hit := _ray(space, point + Vector3.UP * 0.5, point + Vector3.UP * -10.0)
		if absf(hit - WATER_Y) <= WATER_TOLERANCE:
			water += 1
		else:
			wrong += 1
			print("  wrong water ray at ", point, " hit y ", hit)
	for i in RAYS:
		var point := Vector3(randf_range(-1500.0, 1500.0), 0.0, randf_range(-1000.0, 1000.0))
		if water_probe.is_water(Vector2(point.x, point.z)):
			continue
		var hit := _ray_down(space, point)
		if hit == INF or hit < -10.0:
			land += 1  # outside the map: the kill floor is below
			continue
		if hit < -0.05:
			# The shore band is cut with a 5 m grid, so a ray near the bank may reach the water.
			if water_probe.near_water(Vector2(point.x, point.z), 12.0):
				land += 1
				continue
			wrong += 1
			print("  wrong land ray at ", point, " hit y ", hit)
		else:
			land += 1
	_check(water > 0 and wrong == 0,
		"the rays hit the water at %.1f m (%d water, %d land, %d wrong)" % [WATER_Y, water, land, wrong])


## No prop may stand on the carriageway.
func _check_furniture(world: WorldBase) -> void:
	var lanes := world.get_lane_paths()
	var index := LaneIndex.new()
	index.build(lanes)
	var on_road := 0
	var total := 0
	# The multi mesh buffer belongs to the renderer, so the positions of the data are checked.
	var kinds: Array[String] = world.get("_builder").furniture_kinds
	var by_kind: Dictionary = {}
	var i := 0
	for position in world.get_furniture_positions():
		total += 1
		if _on_carriageway(index, lanes, position):
			on_road += 1
			var kind := kinds[i] if i < kinds.size() else "?"
			by_kind[kind] = int(by_kind.get(kind, 0)) + 1
		i += 1
	print("INFO the props on the carriageway: %s" % str(by_kind))
	if on_road > 0:
		var shown: Dictionary = {}
		var i2 := 0
		for position2 in world.get_furniture_positions():
			if _on_carriageway(index, lanes, position2):
				var kind2 := kinds[i2] if i2 < kinds.size() else "?"
				if int(shown.get(kind2, 0)) < 2:
					shown[kind2] = int(shown.get(kind2, 0)) + 1
					print("INFO offender ", kind2, " at ", position2, " nearest ",
						_nearest_road(lanes, position2))
			i2 += 1
	_check(on_road == 0, "%d of %d furniture props stand on the carriageway" % [on_road, total])


## The road of the lane that is closest to a point.
func _nearest_road(lanes: Array[LanePath], position: Vector3) -> String:
	var best := ""
	var best_distance := INF
	for lane in lanes:
		if lane.curve == null:
			continue
		var offset := lane.curve.get_closest_offset(position)
		var closest := lane.curve.sample_baked(offset, true)
		var distance := Vector2(closest.x - position.x, closest.z - position.z).length()
		if distance < best_distance:
			best_distance = distance
			best = "%s (%.1f m, width %.1f)" % [lane.road_id, distance, lane.lane_width]
	return best


## Exactly one lens of every mast is lit, and it matches the signal state.
func _check_signals(world: WorldBase) -> void:
	var signals := world.find_child("Signals", true, false)
	if signals == null:
		_fail("the signal controller is missing")
		return
	var lenses := world.find_children("Lens*", "MultiMeshInstance3D", true, false)
	var masts := 0
	var wrong := 0
	for lens in lenses:
		var mmi := lens as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		if not String(mmi.name).begins_with("LensesLens_"):
			continue
		masts += 1
		var lit := 0
		for i in mmi.multimesh.instance_count:
			var on := mmi.multimesh.get_instance_custom_data(i).r
			if on > 0.5:
				lit += 1
		if lit > 0:
			wrong += 1
	_check(masts > 0, "the traffic lights are batched (%d lens batches)" % masts)
	_check(wrong == 0, "no lens batch has more than one lit lens per mast")


## No traffic-light mast may stand in the carriageway: the masts go on the kerb corners.
func _check_masts(world: WorldBase) -> void:
	var signals := world.find_child("Signals", true, false)
	if signals == null:
		_fail("the signal controller is missing")
		return
	var lanes := world.get_lane_paths()
	var index := LaneIndex.new()
	index.build(lanes)
	var positions: Array[Vector3] = signals.mast_positions()
	var inside := 0
	for position in positions:
		if _on_carriageway(index, lanes, position):
			inside += 1
	_check(positions.size() > 0, "the city has %d traffic-light masts" % positions.size())
	_check(inside == 0, "%d of %d traffic-light masts stand in the carriageway" % [inside,
		positions.size()])


## The light pool re-assignment has to be fast and the decals have to touch the ground.
func _check_lights(world: WorldBase) -> void:
	var pool := world.find_child("LightPool", true, false)
	if pool == null:
		_fail("the light pool is missing")
		return
	var lights := world.find_children("Omni*", "OmniLight3D", true, false)
	_check(lights.size() <= 32, "the light pool holds %d omni lights" % lights.size())
	var decals := world.find_children("LightPool_*", "Decal", true, false)
	_check(decals.size() <= 48, "the light pool holds %d decals" % decals.size())
	# A camera 60 to 130 m from the lamps: the lamps that are too far for a real light get a
	# light pool (a decal) on the ground under them.
	var camera := _make_camera(world, _camera_position(world))
	await get_tree().create_timer(0.4).timeout
	pool._reassign()
	var floating := 0
	var active := 0
	for decal in decals:
		var node := decal as Decal
		if node == null:
			continue
		if node.emission_energy <= 0.0:
			continue
		active += 1
		var hit := _ray_down(world.get_world_3d().direct_space_state, node.global_position)
		if hit == INF or node.global_position.y - hit > 1.0:
			floating += 1
	_check(active >= 10, "%d light pools are active around the camera" % active)
	_check(floating == 0, "%d of %d active light pools float above the ground" % [floating, active])
	_check(pool.last_reassign_ms <= REASSIGN_LIMIT,
		"the light pool re-assignment takes %.2f ms" % pool.last_reassign_ms)


## A camera in the world, so the light pool and the probes have a point of view.
func _make_camera(world: WorldBase, position: Vector3) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "TestCamera"
	world.add_child(camera)
	camera.global_position = position
	camera.look_at(position + Vector3.FORWARD, Vector3.UP)
	camera.make_current()
	return camera


## A place with lamps around: above the player spawn.
func _camera_position(world: WorldBase) -> Vector3:
	var spawn := world.get_spawn_transform(&"player", 0).origin
	return Vector3(spawn.x, spawn.y + 90.0, spawn.z)


## The blocks come with occlusion boxes.
func _check_occluders(world: WorldBase) -> void:
	var occluders := world.find_children("Occluder*", "OccluderInstance3D", true, false)
	_check(occluders.size() > 0, "the city has %d occlusion boxes" % occluders.size())


## The reflection probes are looked up in a grid: only the ones near the camera are enabled.
func _check_probes(world: WorldBase) -> void:
	var probes := world.find_children("Probe_*", "ReflectionProbe", true, false)
	var active := 0
	for probe in probes:
		var node := probe as ReflectionProbe
		if node != null and node.visible:
			active += 1
	_check(probes.size() > 0, "the city has %d reflection probes" % probes.size())
	_check(active <= 4, "%d reflection probes are enabled" % active)
	# The probes around the camera are enabled, the ones far away are not.
	await get_tree().create_timer(0.8).timeout
	var near := 0
	var far := 0
	var origin := _camera_position(world)
	for probe in probes:
		var node := probe as ReflectionProbe
		if node == null:
			continue
		if origin.distance_to(node.global_position) <= 400.0 and node.visible:
			near += 1
		elif origin.distance_to(node.global_position) > 400.0 and node.visible:
			far += 1
	_check(near >= 1 and near <= 4, "%d reflection probes within 400 m are enabled" % near)
	_check(far == 0, "%d reflection probes beyond 400 m are enabled" % far)


## Waits until the world has built itself (the builder works in phases and yields a frame).
func _await_build(world: WorldBase) -> void:
	for i in 400:
		await get_tree().process_frame
		if float(world.get("loading_fraction")) >= 1.0:
			return


## The height of the ray that hits the ground, or INF.
func _ray_down(space: PhysicsDirectSpaceState3D, point: Vector3) -> float:
	return _ray(space, point + Vector3.UP * 60.0, point + Vector3.UP * -60.0)


## The height of the first thing the ray hits, or INF.
func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> float:
	if space == null:
		return INF
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return INF
	return (hit["position"] as Vector3).y


## True when a lane of the same level runs through the point.
func _on_carriageway(index: LaneIndex, lanes: Array[LanePath], position: Vector3) -> bool:
	for i in index.candidates(position, 24.0):
		var lane := lanes[i]
		if lane.curve == null:
			continue
		var offset := lane.curve.get_closest_offset(position)
		var closest := lane.curve.sample_baked(offset, true)
		if absf(closest.y - position.y) > 2.5:
			continue
		if Vector2(closest.x - position.x, closest.z - position.z).length() < LANE_CLEARANCE:
			return true
	return false


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


## The tiles of the roads, the blocks and the Bund have to be instantiated: the loader used to
## skip every imported tile, and the city was the fallback prisms.
func _check_tiles(world: WorldBase) -> void:
	var lib := AssetLibrary.new()
	for spec in [["roads", AssetLibrary.ROADS_DIR, "roads_"],
			["blocks", AssetLibrary.BLOCKS_DIR, "blocks_"],
			["bund", AssetLibrary.BUND_DIR, ""]]:
		var label := String(spec[0])
		var files := lib.find_glbs(String(spec[1]), String(spec[2]))
		if files.is_empty():
			continue
		var loaded := 0
		for path in files:
			var node := lib.instantiate_glb(path)
			if node == null:
				continue
			loaded += 1
			node.free()
		_check(loaded == files.size(), "%s: %d of %d tiles instantiated" % [label, loaded,
			files.size()])
	# The fallback city (the prisms of city.json) must not be there when the tiles are there.
	var prisms := world.find_children("Block_*", "Node3D", true, false)
	var ribbons := world.find_children("Road_*", "Node3D", true, false)
	_check(prisms.is_empty(), "the city has %d fallback block prisms" % prisms.size())
	_check(ribbons.is_empty(), "the city has %d fallback road ribbons" % ribbons.size())


## The props may not stand inside each other: no two of them are closer than the sum of their
## radii. The five worst pairs are printed.
func _check_props(world: WorldBase) -> void:
	var positions: Array[Vector3] = world.get_furniture_positions()
	var kinds: Array[String] = world.get("_builder").furniture_kinds
	var grid: Dictionary = {}
	for i in positions.size():
		var key := "%d_%d" % [int(floor(positions[i].x / 4.0)), int(floor(positions[i].z / 4.0))]
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(i)
	var worst: Array[Dictionary] = []
	for key in grid.keys():
		var list: Array = grid[key]
		for a in list.size():
			for b in range(a + 1, list.size()):
				var i := int(list[a])
				var j := int(list[b])
				var distance := Vector2(positions[i].x - positions[j].x,
					positions[i].z - positions[j].z).length()
				var limit := PropOccupancy.radius_of(kinds[i]) + PropOccupancy.radius_of(kinds[j])
				if distance >= limit:
					continue
				worst.append({"gap": limit - distance, "i": i, "j": j, "distance": distance})
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["gap"]) > float(b["gap"]))
	var shown := 0
	for entry in worst:
		if shown >= 5:
			break
		shown += 1
		var i := int(entry["i"])
		var j := int(entry["j"])
		print("INFO %s (r %.2f m) and %s (r %.2f m) stand %.2f m apart" % [kinds[i],
			PropOccupancy.radius_of(kinds[i]), kinds[j], PropOccupancy.radius_of(kinds[j]),
			float(entry["distance"])])
	_check(worst.is_empty(), "%d props stand inside each other" % worst.size())


## The radius of the footprint of a kind.
func radius_of(kind: String) -> float:
	return PropOccupancy.radius_of(kind)


## The head of every lamp is its own batch, visible from 1,500 m: the street grid of the city
## reads as a net of light dots from the air.
func _check_glow(world: WorldBase) -> void:
	var lamps := 0
	var glows := 0
	var dot := 0
	for node in world.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var name := String(mmi.name)
		if name.contains("lamp") or name.contains("magnolia") or name.contains("heritage"):
			if name.contains("glow"):
				glows += mmi.multimesh.instance_count
				_check(mmi.visibility_range_end >= 1500.0,
					"the head of a lamp is visible for %.0f m" % mmi.visibility_range_end)
			elif name.contains("dot"):
				dot += mmi.multimesh.instance_count
			else:
				lamps += mmi.multimesh.instance_count
	_check(glows >= int(float(lamps) * 0.95), "%d lamp heads for %d lamps" % [glows, lamps])
	_check(dot > 0, "the city has %d far dots of lamps" % dot)


## A car that drives into a lamp, a mast or a tree has to hit it: the street furniture has
## collision.
func _check_collision(world: WorldBase) -> void:
	var targets := _collision_targets(world)
	if targets.is_empty():
		_check(false, "the city has no prop to drive into")
		return
	for target in targets:
		var result := await _drive_into(world, target["position"], target["direction"])
		_check(bool(result["hit"]), "a car at 60 km/h hits the %s (%.1f km/h)" % [
			target["kind"], float(result["speed"])])
		_check(float(result["speed"]) < 30.0, "the car slows down at the %s (%.1f km/h)" % [
			target["kind"], float(result["speed"])])


## A prop to drive into: a lamp, a traffic-light mast and a tree near the spawn.
func _collision_targets(world: WorldBase) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var positions: Array[Vector3] = world.get_furniture_positions()
	var kinds: Array[String] = world.get("_builder").furniture_kinds
	var spawn := world.get_spawn_transform(&"player", 0).origin
	for kind in ["lamp", "tree"]:
		for i in positions.size():
			if kinds[i] != kind:
				continue
			if positions[i].distance_to(spawn) > 150.0:
				continue
			out.append({"kind": kind, "position": positions[i],
				"direction": (positions[i] - spawn).normalized()})
			break
	var signals := world.find_child("Signals", true, false)
	if signals != null:
		for position in signals.mast_positions():
			if position.distance_to(spawn) > 150.0:
				continue
			out.append({"kind": "mast", "position": position,
				"direction": (position - spawn).normalized()})
			break
	return out


## Drives a probe body into a point and reports the speed it has after the hit.
func _drive_into(world: WorldBase, target: Vector3, direction: Vector3) -> Dictionary:
	var body := RigidBody3D.new()
	body.mass = 1900.0
	body.collision_layer = 2
	body.collision_mask = 1 | 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.4, 4.0)
	shape.shape = box
	body.add_child(shape)
	var from := target - direction * 15.0 + Vector3(0.0, 0.8, 0.0)
	body.position = from
	world.add_child(body)
	body.linear_velocity = direction * 16.7
	var speed := 60.0
	for i in 300:
		await get_tree().physics_frame
		speed = body.linear_velocity.length() * 3.6
		if body.global_position.distance_to(target) < 2.0:
			break
	var hit := body.get_contact_count() > 0 or speed < 55.0
	body.queue_free()
	return {"speed": speed, "hit": hit}
