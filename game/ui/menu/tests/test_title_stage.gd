extends Node
## Test of the title stage: the car is parked off the lanes, so the traffic drives past instead
## of into it (the round 1 review found a burning SUV in the title car), and the spot is only
## derived once the world is built.
##
## Run: tools/godot.sh test res://ui/menu/tests/test_title_stage.gd

const TitleStage := preload("res://ui/menu/widgets/title_stage.gd")
const TitleSpot := preload("res://ui/menu/widgets/title_spot.gd")
const FrontEnd := preload("res://ui/menu/front_end.gd")

## The distance the car keeps from every lane centreline.
const MIN_CLEARANCE := 3.75

## A Bund road with six lanes, 3.35 m apart (the real layout at z −300: the northbound ones
## at x −121.45 / −118.16 / −114.87, the southbound at −124.76 / −128.07 / −131.36) and the
## next street 4.7 m east (x −110.19 / −107.05). The lanes only exist once the world is built.
class FakeWorld extends WorldBase:
	var loading_fraction: float = 0.0
	var _built: bool = false

	func get_lane_paths() -> Array[LanePath]:
		var out: Array[LanePath] = []
		if not _built:
			return out
		var lanes: Array = [
			[-131.36, -400.0, 400.0], [-128.07, -400.0, 400.0], [-124.76, -400.0, 400.0],
			[-121.45, 400.0, -400.0], [-118.16, 400.0, -400.0], [-114.87, 400.0, -400.0],
			[-110.19, 400.0, -400.0], [-107.05, -400.0, 400.0],
		]
		for spec: Array in lanes:
			var lane := LanePath.new()
			lane.road_id = &"bund_zhongshan_e1"
			lane.lane_width = 3.35
			var line := Curve3D.new()
			line.add_point(Vector3(float(spec[0]), 0.0, float(spec[1])))
			line.add_point(Vector3(float(spec[0]), 0.0, float(spec[2])))
			lane.curve = line
			out.append(lane)
		return out

	## The world finishes building: the lanes appear and the progress reaches 100 %.
	func finish_building() -> void:
		_built = true
		loading_fraction = 1.0


## The ground under the title car (the world layer).
class FakeGround extends StaticBody3D:
	func _init() -> void:
		collision_layer = 1
		collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(400.0, 2.0, 400.0)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		add_child(collider)
		position = Vector3(-120.0, -1.0, -300.0)


var _fails: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := FakeWorld.new()
	add_child(world)
	Game.world = world

	var ground := FakeGround.new()
	add_child(ground)

	var stage := TitleStage.new()
	add_child(stage)
	await get_tree().process_frame

	# The world is still building: there are no lanes, so there is no spot to park on.
	stage.prepare()
	_expect(not stage.has_spot(), "no spot is derived before the world is built")
	_expect(stage.parking_spot() == Vector3.ZERO, "the car is not parked before the world is built")

	# The world finishes building ten frames later.
	for i in 10:
		await get_tree().process_frame
	world.finish_building()
	Events.loading_progress.emit(1.0, "就绪")
	await get_tree().process_frame

	stage.prepare()
	_expect(stage.has_spot(), "a spot is derived once the world is built")
	var spot: Vector3 = stage.parking_spot()
	var nearest := INF
	for lane: LanePath in world.get_lane_paths():
		nearest = minf(nearest, _distance_to_lane(spot, lane))
	print("SPOT ", spot, " nearest lane ", nearest)
	_expect(nearest >= MIN_CLEARANCE,
			"the car stands at least 3.75 m from every lane centreline")
	_expect(absf(spot.z + 300.0) <= TitleSpot.SEARCH_RANGE,
			"the car is parked inside the searched stretch of the Bund")
	_expect(spot.x < -125.0, "the car is off the lanes, on the promenade side")

	# The front end parks the car once the world is ready.
	var player := VehicleBase.new()
	add_child(player)
	Game.player = player
	var front := FrontEnd.new()
	front.open(get_tree())
	for i in 5:
		await get_tree().process_frame
	_expect(player.global_position.distance_to(Vector3(spot.x, 0.0, spot.z)) < 1.0,
			"the front end parks the car on the validated spot")
	_expect(player.freeze, "the parked car is frozen")

	print("TITLE STAGE TEST %s (%d failures)" % ["FAIL" if _fails > 0 else "PASS", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## The distance of a point to the centreline of a lane.
func _distance_to_lane(point: Vector3, lane: LanePath) -> float:
	var best := INF
	for p in lane.curve.get_baked_points():
		best = minf(best, Vector2(p.x - point.x, p.z - point.z).length())
	return best


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_fails += 1
		print("FAIL ", label)
