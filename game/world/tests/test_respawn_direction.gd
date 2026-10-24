extends Node
## A reset or a respawn puts the car on a lane in the direction of the traffic of that lane, keeps the way the car drove when a lane
## near runs that way, and takes a street lane rather than the turn of a junction. The player reported that the reset "still has an
## axis problem": the respawn took the nearest lane point as it was and turned the car to face the way it had driven, also on a
## one-way lane (into the oncoming traffic), and a connector through a junction put the car across both streets.
##
## From the middle of every 7th street lane the car is reset three times: facing along the lane, against it and across it. The
## car must stand on a lane that runs the way it faces (within 25 degrees), on its road (not on the bed of the river under a lane
## that runs over the water), upright, not on a connector, and on the street it was on or the other carriageway of it.
## Run: python tools/gd.py test res://world/tests/test_respawn_direction.gd -- --timeout=290 --stub=audio,menu,hud,rivals,traffic,police

const MAIN := "res://main.tscn"
## Every n-th lane is tried.
const EVERY := 7
## The car faces its lane within this angle (degrees).
const ALONG_DEG := 25.0
## A lane this close to the car (m, across; the height within LEVEL) is a lane the car stands on.
const ON_LANE := 0.75
const LEVEL := 1.5
## The car keeps the way it drove within this angle (degrees) when its own lane runs that way (the rule: 60 degrees).
const KEEP_DEG := 60.0
## The road under a reset: the car stands this high over the lane (SpawnPlacer.LANE_LIFT), give or take this much (m).
const LANE_LIFT := 0.6
const LIFT_TOLERANCE := 0.4
## A reset this far from where the car was is on another street (m).
const NEAR := 16.0
## Lanes that start over the river (tools/spawn_height_probe.gd: no road under them for 10-15 m), and the way they run.
const RIVER_LANE_STARTS: Array[Vector3] = [Vector3(910.3, 0.0, 1748.0), Vector3(912.0, 0.0, 1746.4)]
const RIVER_LANE_WAY := Vector3(0.72, 0.0, -0.7)

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
	var placer: Object = Game.world.get("_placer")
	var index: Object = placer.get("index")
	var tried := 0
	var wrong_way: Array[String] = []
	var connector: Array[String] = []
	var tilted: Array[String] = []
	var turned: Array[String] = []
	var sunk: Array[String] = []
	var moved: Array[String] = []
	var kept_against := 0
	var against_tries := 0
	for i in range(0, lanes.size(), EVERY):
		var lane := lanes[i] as LanePath
		if lane.curve == null or lane.curve.get_baked_length() < 30.0 or bool(lane.get_meta(&"connector", false)):
			continue
		var offset := lane.curve.get_baked_length() * 0.5
		var point := lane.curve.sample_baked(offset, true)
		var along := _direction(lane, offset)
		var ways: Array[Vector3] = [along, -along, Vector3(-along.z, 0.0, along.x)]
		for w in ways.size():
			var way: Vector3 = ways[w]
			tried += 1
			var xform: Transform3D = Game.world.respawn_transform(point, way)
			var forward := -xform.basis.z
			var label := "(%.0f, %.1f, %.0f) %s" % [point.x, point.y, point.z, ["along", "against", "across"][w]]
			if xform.basis.y.dot(Vector3.UP) < 0.99:
				tilted.append(label)
			var under := _lanes_under(index, lanes, xform.origin, forward)
			if under.is_empty():
				wrong_way.append(label)
			else:
				if not bool(under["street"]):
					connector.append(label)
				if absf(xform.origin.y - LANE_LIFT - float(under["y"])) > LIFT_TOLERANCE:
					sunk.append("%s at y %.2f over a lane at %.2f" % [label, xform.origin.y, float(under["y"])])
			if Vector2(xform.origin.x - point.x, xform.origin.z - point.z).length() > NEAR and w != 1:
				moved.append("%s to (%.0f, %.0f)" % [label, xform.origin.x, xform.origin.z])
			if w == 0 and rad_to_deg(forward.angle_to(along)) > KEEP_DEG:
				turned.append(label)
			if w == 1:
				against_tries += 1
				if rad_to_deg(forward.angle_to(-along)) <= KEEP_DEG:
					kept_against += 1
	# a lane that starts over the river (st_link_25, its first 15 m): the reset there walks along it onto the land
	for place: Vector3 in RIVER_LANE_STARTS:
		tried += 1
		var xform: Transform3D = Game.world.respawn_transform(place, RIVER_LANE_WAY)
		var under := _lanes_under(index, lanes, xform.origin, -xform.basis.z)
		if under.is_empty() or absf(xform.origin.y - LANE_LIFT - float(under["y"])) > LIFT_TOLERANCE:
			sunk.append("(%.0f, %.0f) river lane start, at %s" % [place.x, place.z, str(xform.origin.snapped(Vector3.ONE * 0.1))])
	print("INFO %d resets from %d lanes; facing against the lane, %d of %d kept their way (a lane near runs it)" % [tried,
		tried / 3, kept_against, against_tries])
	_check(tried > 600, "the lanes of the city are tried", "(%d resets)" % tried)
	_check(wrong_way.is_empty(), "every reset stands on a lane that runs the way the car faces",
			"(%d: %s)" % [wrong_way.size(), ", ".join(wrong_way.slice(0, 6))])
	_check(connector.is_empty(), "no reset stands on the turn of a junction when a street lane is near",
			"(%d: %s)" % [connector.size(), ", ".join(connector.slice(0, 6))])
	_check(tilted.is_empty(), "every reset is upright", "(%d: %s)" % [tilted.size(), ", ".join(tilted.slice(0, 6))])
	_check(sunk.is_empty(), "every reset stands on the road of its lane", "(%d: %s)" % [sunk.size(), ", ".join(sunk.slice(0, 6))])
	_check(moved.is_empty(), "a reset facing along or across its street stays on that street",
			"(%d: %s)" % [moved.size(), ", ".join(moved.slice(0, 6))])
	_check(turned.is_empty(), "a car that drove along its lane keeps its way",
			"(%d: %s)" % [turned.size(), ", ".join(turned.slice(0, 6))])
	if _failures == 0:
		print("OK respawn direction: all checks passed")
	else:
		print("FAIL %d checks" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## The horizontal direction of a lane at an offset.
func _direction(lane: LanePath, offset: float) -> Vector3:
	var length := lane.curve.get_baked_length()
	var a := lane.curve.sample_baked(clampf(offset - 2.0, 0.0, length), true)
	var b := lane.curve.sample_baked(clampf(offset + 2.0, 0.0, length), true)
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## The lane under a car at `origin` that runs the way it faces (a street lane before a connector): {"street", "y"}, or empty
## when no lane under the car runs that way. The height is not looked at here (a reset over the river is not a wrong way).
func _lanes_under(index: Object, lanes: Array, origin: Vector3, forward: Vector3) -> Dictionary:
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	var found := {}
	for candidate: int in index.call("candidates", origin, 8.0):
		var lane := lanes[candidate] as LanePath
		if lane.curve == null:
			continue
		var offset := lane.curve.get_closest_offset(origin)
		var p := lane.curve.sample_baked(offset, true)
		if Vector2(p.x - origin.x, p.z - origin.z).length() > ON_LANE or absf(p.y - origin.y) > LEVEL + 3.0:
			continue
		if rad_to_deg(_direction(lane, offset).angle_to(flat)) > ALONG_DEG:
			continue
		if not bool(lane.get_meta(&"connector", false)):
			return {"street": true, "y": p.y}
		found = {"street": false, "y": p.y}
	return found
