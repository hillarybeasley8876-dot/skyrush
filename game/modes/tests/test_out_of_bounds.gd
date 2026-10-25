extends Node
## The recovery of a lost player: a car that ends up in the river, under the map or far from
## every lane is put back on the nearest road after a few seconds, and the player is told.
##
## The class is loaded with `ResourceLoader.exists` / `load` (never `preload` and never a static
## type), so the test still runs on the old code: it prints FAIL lines instead of crashing.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const MODE_DIRECTOR := "res://modes/mode_director.tscn"
const OUT_OF_BOUNDS := "res://modes/out_of_bounds.gd"

## The seconds a lost player is put back after (the value of the class).
const LOST_SECONDS := 3.0
## The distance from the nearest lane above which the player counts as lost.
const LOST_DISTANCE := 15.0
## A spot 400 m outside the road loop of the sandbox, on the flat ground. The sandbox has no
## water: a car that ends up in the river is far from every lane, and so is this one.
const LOST_SPOT := Vector3(1000.0, 0.05, 0.0)

var _failures: int = 0
var _modes: ModeDirector = null
var _car: VehicleBase = null
var _toasts: Array[String] = []


func _ready() -> void:
	Events.toast.connect(_on_toast)
	if not await _build():
		_finish()
		return
	_modes.start_mode(&"free", {})
	await _wait(0.5)
	await _test_lost_in_the_water()
	await _test_in_the_water_near_the_bank()
	await _test_on_the_road()
	await _test_timer_restarts()
	await _test_flying_and_grid()
	_finish()


## Builds the world, the player and the mode director. Returns false when a part is missing.
func _build() -> bool:
	var world_scene := load(SANDBOX) as PackedScene
	if world_scene == null:
		_expect(false, "the sandbox loads")
		return false
	add_child(world_scene.instantiate())
	var car_scene := load(PLAYER_CAR) as PackedScene
	if car_scene == null:
		_expect(false, "the player car loads")
		return false
	_car = car_scene.instantiate() as VehicleBase
	add_child(_car)
	Game.player = _car
	var modes_scene := load(MODE_DIRECTOR) as PackedScene
	if modes_scene == null:
		_expect(false, "the mode director loads")
		return false
	_modes = modes_scene.instantiate() as ModeDirector
	if _modes == null:
		_expect(false, "the mode director is a ModeDirector")
		return false
	add_child(_modes)
	await _wait(0.5)
	return true


## A player that is lost is put back on a lane, and the player is told once.
func _test_lost_in_the_water() -> void:
	var before := _road_toasts()
	_place_lost()
	await _wait(LOST_SECONDS - 0.5)
	_expect(_road_toasts() == before, "the lost player is not put back at once")
	await _wait(1.5)
	var road: Transform3D = Game.world.nearest_road_transform(_car.global_position)
	var distance := _car.global_position.distance_to(road.origin)
	_expect(distance < 6.0, "the lost player is put back on a lane",
		"= %.2f m from the lane" % distance)
	_expect(_car.global_position.y > road.origin.y - 1.0, "the player is above the lane",
		"= %.2f m, the lane is at %.2f m" % [_car.global_position.y, road.origin.y])
	_expect(_road_toasts() - before == 1, "one toast tells the player",
		"= %d" % (_road_toasts() - before))


## A player that stands on a lane is left alone.
## A car in the water next to the bank is put back. The water of the city is a solid floor 3 m under the road: a car in the creek
## less than 15 m from the lane of the riverside road was not "lost" (too close to a lane) and could not get out.
func _test_in_the_water_near_the_bank() -> void:
	var water := StaticBody3D.new()
	water.collision_layer = 1
	water.add_to_group(&"water")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 12.0)
	shape.shape = box
	water.add_child(shape)
	add_child(water)
	# the south straight of the sandbox runs at z 196-204: the water is 6-18 m from its outer lane, 3 m under the road
	water.global_position = Vector3(300.0, -3.5, 216.0)
	var before := _road_toasts()
	_car.reset_to(Transform3D(Basis.IDENTITY, Vector3(300.0, -2.6, 216.0)))
	await _wait(LOST_SECONDS + 1.0)
	_expect(_road_toasts() > before, "a car in the water next to the bank is put back",
		"(at %s)" % str(_car.global_position.snapped(Vector3.ONE * 0.1)))
	_expect(_car.global_position.y > -1.0, "it is on the road again", "= y %.2f" % _car.global_position.y)
	water.queue_free()
	await _wait(0.2)


func _test_on_the_road() -> void:
	var before := _road_toasts()
	_place_on_road()
	await _wait(1.0)
	var start := _car.global_position
	await _wait(6.0)
	var moved := _car.global_position.distance_to(start)
	_expect(moved < 1.0, "the player on the road does not move", "= %.2f m" % moved)
	_expect(_road_toasts() == before, "no toast for a player on the road",
		"= %d" % (_road_toasts() - before))


## The timer restarts when the player is found again: two spells of two seconds are not three.
func _test_timer_restarts() -> void:
	var before := _road_toasts()
	_place_lost()
	await _wait(2.0)
	_place_on_road()
	await _wait(1.0)
	_place_lost()
	await _wait(2.0)
	_expect(_road_toasts() == before, "the timer restarts when the player is found again",
		"= %d" % (_road_toasts() - before))
	var road: Transform3D = Game.world.nearest_road_transform(_car.global_position)
	var distance := _car.global_position.distance_to(road.origin)
	_expect(distance > LOST_DISTANCE, "the player is still lost", "= %.2f m from the lane" % distance)


## A player that flies or that waits on the grid is not put back.
func _test_flying_and_grid() -> void:
	var out_of_bounds := _out_of_bounds()
	if out_of_bounds == null:
		_expect(false, "the out of bounds class exists")
		return
	_expect(_member(_modes, "out_of_bounds") != null, "the mode director owns the recovery")
	var flying := _ghost(LOST_SPOT)
	flying.telemetry.flying = true
	_expect(not _run(out_of_bounds, flying, 4.0), "a flying player is not put back")
	var grid := _ghost(LOST_SPOT)
	grid.freeze = true
	_expect(not _run(out_of_bounds, grid, 4.0), "a frozen player is not put back")
	var lost := _ghost(LOST_SPOT)
	_expect(_run(out_of_bounds, lost, LOST_SECONDS + 1.0), "a lost player is put back")


## A new instance of the recovery class (null when it does not exist).
func _out_of_bounds() -> Object:
	if not ResourceLoader.exists(OUT_OF_BOUNDS):
		return null
	var script := load(OUT_OF_BOUNDS) as GDScript
	if script == null:
		return null
	return script.new()


## Runs the recovery for the given seconds. Returns true when the player was put back.
func _run(out_of_bounds: Object, player: VehicleBase, seconds: float) -> bool:
	var steps := int(seconds * 120.0)
	for i in steps:
		if bool(out_of_bounds.call("update", 1.0 / 120.0, player, Game.world)):
			return true
	return false


## A car without a body: it stays where it is put and keeps the telemetry it is given.
func _ghost(pos: Vector3) -> VehicleBase:
	var ghost := VehicleBase.new()
	ghost.gravity_scale = 0.0
	add_child(ghost)
	ghost.reset_to(Transform3D(Basis.IDENTITY, pos))
	return ghost


## The value of a member of an object, or null when it does not have it (no engine error).
func _member(node: Object, member: String) -> Variant:
	if node == null:
		return null
	for property in node.get_property_list():
		if String(property["name"]) == member:
			return node.get(member)
	return null


## Puts the player 400 m outside the road loop, on the ground.
func _place_lost() -> void:
	_car.reset_to(Transform3D(Basis.IDENTITY, LOST_SPOT))


## Puts the player on the nearest lane, facing along it.
func _place_on_road() -> void:
	var spawn: Transform3D = Game.world.get_spawn_transform(&"player", 0)
	var road: Transform3D = Game.world.nearest_road_transform(spawn.origin)
	_car.reset_to(road)


## The number of toasts that told the player that it is back on the road.
func _road_toasts() -> int:
	var count := 0
	for text in _toasts:
		if text.find("BACK ON THE ROAD") >= 0:
			count += 1
	return count


func _on_toast(text: String, _style: StringName) -> void:
	_toasts.append(text)


## Runs the physics for the given seconds.
func _wait(seconds: float) -> void:
	var steps := int(seconds * Engine.physics_ticks_per_second)
	for i in steps:
		await get_tree().physics_frame


## Counts one failed expectation.
func _expect(condition: bool, label: String, detail: String = "") -> void:
	print(("PASS " if condition else "FAIL ") + label + "  " + detail)
	if not condition:
		_failures += 1


## Prints the verdict and quits with the right exit code.
func _finish() -> void:
	if _failures == 0:
		print("OUT OF BOUNDS TESTS OK")
	else:
		print("OUT OF BOUNDS TESTS FAILED (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
