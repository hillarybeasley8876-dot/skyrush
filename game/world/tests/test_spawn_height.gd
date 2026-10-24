extends Node
## A car that the world puts on a lane stands on the road of that lane, and a respawn has a clear road.
##
## The spawn placer (world/api/spawn_placer.gd) finds the height of the road with a ray down. The ray started 4 m above the lane
## and took the first surface it met: 334 of 68,000 lane points put the car on top of something over the lane (the roof of a
## toll booth, the Bund promenade, the deck of an elevated road, the ground over a tunnel, the deck of the Waibaidu bridge), and a
## wreck respawned the player there, in the air. The respawn took the nearest lane point as it was and sent the car off at
## 60 km/h: 10 of 58 respawns hit a tree, a lamp or a wall within 4 s, one with its roof in an elevated road.
## Run: python tools/gd.py test res://world/tests/test_spawn_height.gd -- --timeout=290 --stub=audio,menu,hud,rivals,traffic,police

const MAIN := "res://main.tscn"
const SpawnPlacer := preload("res://world/api/spawn_placer.gd")
## The step between two samples of a lane (m).
const STEP := 10.0
## A spawn this far above its lane is on top of something.
const RISE := 0.8
## Places where the old ray put the car on top of something: a lane of the west toll plaza (a booth roof), a lane next to the
## Bund promenade, a lane under the Waibaidu bridge deck, a lane in a tunnel under the ground.
const OLD_BAD: Array[Vector3] = [Vector3(-2070.0, 0.0, 734.6), Vector3(-48.5, 0.0, -175.8), Vector3(-140.1, 0.0, -978.3),
	Vector3(624.1, -4.0, -447.8)]
## The respawns that are checked for a clear spot: every n-th lane.
const RESPAWN_EVERY := 97

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String = "") -> void:
	if ok:
		print("PASS ", label, "  ", detail)
	else:
		_failures += 1
		print("FAIL ", label, "  ", detail)


func _run() -> void:
	var main := (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	await Game.world_ready()
	await get_tree().physics_frame
	var lanes: Array = Game.world.get_lane_paths()
	var placer := SpawnPlacer.new()
	var samples := 0
	var high: Array[String] = []
	for lane: LanePath in lanes:
		if lane.curve == null:
			continue
		var length := lane.curve.get_baked_length()
		var d := 0.0
		while d < length:
			var point := lane.curve.sample_baked(d, true)
			d += STEP
			samples += 1
			var rise := placer.surface_y(Game.world, point) - SpawnPlacer.LANE_LIFT - point.y
			if rise > RISE:
				high.append("(%.0f, %.1f, %.0f) +%.1f m" % [point.x, point.y, point.z, rise])
	_check(samples > 50000, "the lanes of the city are sampled", "(%d points)" % samples)
	_check(high.is_empty(), "no spawn is on top of something over its lane",
			"(%d: %s)" % [high.size(), ", ".join(high.slice(0, 5))])
	# the places of the old bug: the respawn there stands on the road of the lane
	for place in OLD_BAD:
		var xform := Game.world.respawn_transform(place, Vector3.FORWARD)
		var lane_y := _lane_y_near(lanes, xform.origin)
		_check(absf(xform.origin.y - SpawnPlacer.LANE_LIFT - lane_y) < RISE,
				"the respawn near (%.0f, %.0f) is on its road" % [place.x, place.z],
				"(spawn y %.2f, lane y %.2f)" % [xform.origin.y, lane_y])
	# a respawn has its own spot and 30 m ahead clear of the world and the props
	var space := get_viewport().get_world_3d().direct_space_state
	var blocked: Array[String] = []
	var tried := 0
	for i in range(0, lanes.size(), RESPAWN_EVERY):
		var lane := lanes[i] as LanePath
		if lane.curve == null or lane.curve.get_baked_length() < 20.0:
			continue
		var point := lane.curve.sample_baked(lane.curve.get_baked_length() * 0.5, true)
		var xform := Game.world.respawn_transform(point, Vector3.RIGHT)
		tried += 1
		if not _box_clear(space, xform) or not _corridor_clear(space, xform):
			blocked.append("(%.0f, %.1f, %.0f)" % [xform.origin.x, xform.origin.y, xform.origin.z])
	# a respawn may find no clear spot within 120 m of a cluttered lane and keep the first: a few, not many
	_check(tried > 80 and blocked.size() * 20 <= tried, "a respawn has its own spot and the 30 m ahead clear",
			"(%d of %d blocked: %s)" % [blocked.size(), tried, ", ".join(blocked.slice(0, 5))])
	print("SPAWN HEIGHT TESTS %s (%d failures)" % ["OK" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## The height of the lane point nearest to a point.
func _lane_y_near(lanes: Array, point: Vector3) -> float:
	var best := INF
	var y := point.y
	for lane: LanePath in lanes:
		if lane.curve == null:
			continue
		var p := lane.curve.sample_baked(lane.curve.get_closest_offset(point), true)
		var d := Vector2(p.x - point.x, p.z - point.z).length() + absf(p.y - (point.y - SpawnPlacer.LANE_LIFT)) * 3.0
		if d < best:
			best = d
			y = p.y
	return y


## True when the 30 m ahead of a transform are free of the world and the props (the corridor of the spawn placer).
func _corridor_clear(space: PhysicsDirectSpaceState3D, xform: Transform3D) -> bool:
	var box := BoxShape3D.new()
	box.size = SpawnPlacer.CLEAR_BOX
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = SpawnPlacer.CLEAR_MASK
	query.transform = Transform3D(xform.basis,
			xform.origin - xform.basis.z * (SpawnPlacer.CLEAR_AHEAD * 0.5) + Vector3.UP * 0.8)
	return space.intersect_shape(query, 1).is_empty()


## True when the box of a car at a transform touches neither the world nor a prop.
func _box_clear(space: PhysicsDirectSpaceState3D, xform: Transform3D) -> bool:
	var box := BoxShape3D.new()
	box.size = SpawnPlacer.SPOT_BOX
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = SpawnPlacer.CLEAR_MASK
	query.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * SpawnPlacer.SPOT_LIFT)
	return space.intersect_shape(query, 1).is_empty()
