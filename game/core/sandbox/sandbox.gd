extends WorldBase
## Core test world (fallback for the "world" unit, and the tuning ground for vehicles/AI/FX):
## a 1.2 km x 0.4 km circuit on a flat grid, a launch ramp, an elevated deck with on/off ramps,
## a flight zone with a "gas station" to jump, a flash-charge lane and a row of parked cars.
## Coordinates: X east, Z south, Y up; the circuit runs clockwise seen from above.

const SandboxBuild := preload("res://core/sandbox/sandbox_build.gd")

const LOOP_HALF := Vector2(600.0, 200.0)  # circuit half extents (x, z) along the lane centre
const CORNER_R := 80.0

var _lanes: Array[LanePath] = []
var _route: RaceRoute


func _ready() -> void:
	var build := SandboxBuild.new(self)
	build.ground(2400.0)
	build.road_loop(LOOP_HALF, CORNER_R, 16.0)
	# Stunt features sit in the infield so AI on the loop is never blocked.
	build.ramp(Vector3(-300.0, 0.0, 100.0), 14.0, 4.2, 22.0)
	build.elevated_deck(Vector3(80.0, 0.0, 100.0), 360.0, 9.0, 16.0)
	build.gas_station(Vector3(-60.0, 0.0, -100.0))
	build.sky_lane(Vector3(250.0, 0.0, -30.0), 500.0, 25.0)
	build.charge_lane(Vector3(-420.0, 0.0, -224.0))
	build.parked_row(Vector3(260.0, 0.0, -100.0), 5)
	_lanes = _make_lanes()
	_route = _make_route()
	Game.world = self


func get_spawn_transform(kind: StringName, index: int) -> Transform3D:
	var lane := 4.0 if index % 2 == 0 else -4.0
	if kind == &"police":
		# North straight is driven toward +X: face +X => basis rotated -90° about Y.
		return Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-200.0 + float(index) * 20.0, 0.6, -200.0 + lane))
	# South straight is driven toward -X (clockwise): face -X => basis rotated +90° about Y.
	return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(300.0 + float(index / 2) * 12.0, 0.6, 200.0 + lane))


func nearest_road_transform(pos: Vector3) -> Transform3D:
	var curve := _lanes[0].curve
	var off := curve.get_closest_offset(pos)
	var p := curve.sample_baked(off, true)
	var ahead := curve.sample_baked(fmod(off + 4.0, curve.get_baked_length()), true)
	var xform := Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.6)
	return xform.looking_at(ahead + Vector3.UP * 0.6, Vector3.UP)


func get_lane_paths() -> Array[LanePath]:
	return _lanes


func get_route_ids() -> PackedStringArray:
	return PackedStringArray(["sandbox_loop"])


func get_route(id: StringName) -> RaceRoute:
	return _route if id == &"sandbox_loop" else null


func get_minimap_polylines() -> Array[PackedVector2Array]:
	var line := PackedVector2Array()
	for p in _lanes[0].curve.get_baked_points():
		line.append(Vector2(p.x, p.z))
	return [line]


func get_points_of_interest() -> Array[Dictionary]:
	return [
		{"kind": &"gas", "position": Vector3(-60.0, 0.0, -100.0), "label": "中石华"},
		{"kind": &"charge", "position": Vector3(-420.0, 0.0, -224.0), "label": "申城闪充"},
		{"kind": &"sky_lane", "position": Vector3(250.0, 0.0, -30.0), "label": "飞行航道"},
	]


func get_roadblock_sites() -> Array[Transform3D]:
	return [Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(560.0, 0.0, 0.0))]


## Clockwise rounded-rectangle loop through the lane centres; offset > 0 moves outward.
func _loop_curve(offset: float) -> Curve3D:
	var hx := LOOP_HALF.x + offset
	var hz := LOOP_HALF.y + offset
	var r := CORNER_R + offset
	var curve := Curve3D.new()
	curve.bake_interval = 2.0
	var corners := [Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz), Vector2(-hx, -hz)]
	var centers := [Vector2(hx - r, -hz + r), Vector2(hx - r, hz - r), Vector2(-hx + r, hz - r), Vector2(-hx + r, -hz + r)]
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for i in 4:
		var c: Vector2 = centers[i]
		for s in 9:
			var a: float = start_angles[i] + PI * 0.5 * float(s) / 8.0
			curve.add_point(Vector3(c.x + cos(a) * r, 0.05, c.y + sin(a) * r))
	curve.add_point(curve.get_point_position(0))
	return curve


func _make_lanes() -> Array[LanePath]:
	var lanes: Array[LanePath] = []
	for offset in [-4.0, 4.0]:
		var lane := LanePath.new()
		lane.curve = _loop_curve(offset)
		lane.speed_limit_kmh = 90.0
		lane.road_id = &"sandbox_loop"
		lanes.append(lane)
	return lanes


func _make_route() -> RaceRoute:
	var route := RaceRoute.new()
	route.id = &"sandbox_loop"
	route.title = "测试环线"
	route.laps = 2
	route.racing_line = _lanes[0].curve
	var length := route.racing_line.get_baked_length()
	for i in 8:
		var off := length * float(i) / 8.0
		var p := route.racing_line.sample_baked(off, true)
		var ahead := route.racing_line.sample_baked(fmod(off + 5.0, length), true)
		route.checkpoints.append(Transform3D(Basis.IDENTITY, p).looking_at(ahead, Vector3.UP))
	for i in 6:
		route.grid.append(get_spawn_transform(&"rival", i))
	return route
