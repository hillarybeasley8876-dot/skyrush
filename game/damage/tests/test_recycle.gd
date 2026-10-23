extends Node
## A pooled car that comes out of its pool is a whole new car.
##
## The traffic cars and the police cars live in pools: a car that is wrecked sinks, fades out
## and is hidden, then it goes back into its pool and the next spawn takes it out again. The
## recycled car must be whole: it must be visible, it must have its health, its paint, its
## parts and its opacity back, and the wreck of its old life must not touch it any more.
##
##   python tools/gd.py test res://damage/tests/test_recycle.gd

const Kit := preload("res://damage/tests/damage_test_kit.gd")
## The seconds the wreck flow waits before it sinks a wrecked car (wreck_flow.gd).
const SINK_TIME := 6.0
## The seconds the fade of the wreck lasts.
const FADE_TIME := 1.5
## The seconds the test waits for the wreck flow to have hidden the car.
const HIDE_TIME := SINK_TIME + FADE_TIME + 1.0
## The speed of the hit that dents the police car (m/s).
const HIT_SPEED := 26.0

var _failures: int = 0
var _director: Node = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Kit.make_floor(self)
	_director = Kit.make_director(self)
	await _test_traffic()
	await _test_traffic_during_the_fade()
	await _test_police()
	await _test_untouched()
	print("RECYCLE TESTS %s (%d failures)" % ["OK" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- the traffic ---------------------------------------------------------------------------------
## A traffic car that is wrecked, hidden and put back into the pool comes out whole.
func _test_traffic() -> void:
	var pool := _traffic_pool(4242)
	var car := pool.spawn_at(1, 30.0, &"sedan_ev", Color.WHITE)
	await Kit.wait_frames(get_tree(), 3)
	_expect("the traffic car is on the road", car.visible)
	_expect("the traffic car is whole", not car.is_wrecked)
	# The wreck: the car sinks, it fades out and the flow hides it.
	car.apply_damage(car.max_health + 10.0, car.global_position, null)
	await _wait(HIDE_TIME)
	_expect("the traffic car is a wreck", car.is_wrecked)
	_expect("the wreck flow hid the traffic car", not car.visible)
	_expect("the wreck flow made the traffic car invisible", _max_transparency(car) > 0.9)
	# The car goes back into the pool and comes out again.
	pool.release(car)
	var again := pool.spawn_at(1, 90.0, &"sedan_ev", Color.WHITE)
	_expect("the pool gives the same traffic car back", again == car)
	await Kit.wait_frames(get_tree(), 3)
	_expect("the traffic car is on the road again", again.visible)
	_expect("the traffic car is not a wreck any more", not again.is_wrecked)
	_approx("the traffic car has its health back", again.health, again.max_health, 0.01)
	_expect("the traffic car is opaque again", _max_transparency(again) == 0.0)
	# The car can be hurt again.
	again.apply_damage(10.0, again.global_position, null)
	_approx("a hit of 10 costs the traffic car 10 HP", again.max_health - again.health, 10.0, 0.01)
	# The tween of the old wreck must not hide the car again.
	await _wait(3.0)
	_expect("the traffic car is still on the road", again.visible)
	_expect("the traffic car is still opaque", _max_transparency(again) == 0.0)


## A car that comes out of its pool while the wreck of its old life is still fading out must
## stay on the road: the fade and the hide of the old wreck are void.
func _test_traffic_during_the_fade() -> void:
	var pool := _traffic_pool(777)
	var car := pool.spawn_at(2, 30.0, &"hatch_ev", Color.WHITE)
	await Kit.wait_frames(get_tree(), 3)
	car.wreck(null)
	# The sink starts after SINK_TIME: the car is recycled while the old wreck still fades.
	await _wait(SINK_TIME + 0.4)
	pool.release(car)
	var again := pool.spawn_at(2, 90.0, &"hatch_ev", Color.WHITE)
	_expect("the pool gives the same car back", again == car)
	await Kit.wait_frames(get_tree(), 3)
	_expect("the recycled car is on the road", again.visible)
	_expect("the recycled car is opaque", _max_transparency(again) == 0.0)
	# The old wreck must not hide the car a second later.
	await _wait(2.5)
	_expect("the old wreck did not hide the recycled car", again.visible)
	_expect("the recycled car is still opaque", _max_transparency(again) == 0.0)


# --- the police ----------------------------------------------------------------------------------
## A police car that is wrecked, hidden and put back into the pool comes out whole.
func _test_police() -> void:
	var pool := PolicePool.new()
	pool.build(_host(), _context(31337), null)
	var car := _take_patrol(pool)
	if car == null:
		_expect("the police pool has a patrol", false)
		return
	await Kit.wait_frames(get_tree(), 3)
	_expect("the police car is on the road", car.visible)
	car.wreck(null)
	await _wait(HIDE_TIME)
	_expect("the wreck flow hid the police car", not car.visible)
	_expect("the wreck flow made the police car invisible", _max_transparency(car) > 0.9)
	# The car goes back into the pool and comes out again.
	pool.release_unit(car)
	var again := pool.take_unit(&"patrol")
	_expect("the pool gives the same police car back", again == car)
	if again == null:
		return
	await Kit.wait_frames(get_tree(), 3)
	_expect("the police car is on the road again", again.visible)
	_expect("the police car is not a wreck any more", not again.is_wrecked)
	_approx("the police car has its health back", again.health, again.max_health, 0.01)
	_expect("the police car is opaque again", _max_transparency(again) == 0.0)
	_expect("the police car hits the world again", again.collision_mask != 0)
	# The car can be hurt again.
	again.apply_damage(10.0, again.global_position, null)
	_approx("a hit of 10 costs the police car 10 HP", again.max_health - again.health, 10.0, 0.01)
	await _wait(2.0)
	_expect("the police car is still on the road", again.visible)
	await _test_dented(pool, again)


## A car that was dented is whole again after a recycle: no tier, no scrape, the parts back on.
func _test_dented(pool: PolicePool, car: PoliceCar) -> void:
	var wall := _make_wall()
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.4, 0.0))
	await Kit.wait_frames(get_tree(), 2)
	# A hard hit in the front: the bumper comes off and the car is dented.
	await _hit_front(car, wall, HIT_SPEED)
	var state = _director.call("state_of", car)
	_expect("the hit hurt the police car", state.tier != 0)
	_expect("the front bumper came off", not _part_visible(car, "Bumper_F"))
	# The car goes back into the pool and comes out again.
	pool.release_unit(car)
	var again := pool.take_unit(&"patrol")
	_expect("the pool gives the same police car back", again == car)
	if again == null:
		return
	await Kit.wait_frames(get_tree(), 3)
	var state2 = _director.call("state_of", again)
	_expect("the recycled car is clean", state2.tier == 0)
	_expect("the front bumper is back on the car", _part_visible(again, "Bumper_F"))
	_approx("the recycled car has its health back", again.health, again.max_health, 0.01)
	_expect("the recycled car is opaque", _max_transparency(again) == 0.0)


# --- a car that was never hurt --------------------------------------------------------------------
## A car that was never hurt is not touched by the signal: it keeps its health and it does
## not flicker.
func _test_untouched() -> void:
	var pool := _traffic_pool(11)
	var car := pool.spawn_at(0, 20.0, &"taxi", Color.WHITE)
	await Kit.wait_frames(get_tree(), 3)
	var health := car.health
	_expect("the untouched car is on the road", car.visible)
	# The signal of a car that was never hurt must change nothing.
	Events.vehicle_recycled.emit(car)
	await Kit.wait_frames(get_tree(), 2)
	_approx("the untouched car keeps its health", car.health, health, 0.01)
	_expect("the untouched car is not a wreck", not car.is_wrecked)
	_expect("the untouched car stays visible", car.visible)
	_expect("the untouched car stays opaque", _max_transparency(car) == 0.0)


# --- the helpers ---------------------------------------------------------------------------------
## The traffic pool of the test, with its own context.
func _traffic_pool(seed_value: int) -> TrafficPool:
	var pool := TrafficPool.new()
	pool.ctx = _context(seed_value)
	pool.parent = _host()
	return pool


## The context of the test: a straight road with three lanes.
func _context(seed_value: int) -> DriveContext:
	var ctx := DriveContext.new()
	ctx.graph = TrafficTestRoad.build(3)
	ctx.rng.seed = seed_value
	return ctx


## The node the cars of the test hang on.
func _host() -> Node3D:
	var host := Node3D.new()
	host.name = "Host"
	add_child(host)
	return host


## Takes the patrols out of the police pool and parks them, so the unit that is released
## later is the only one the pool gives back.
func _take_patrol(pool: PolicePool) -> PoliceCar:
	var patrols: Array[PoliceCar] = []
	for i in 8:
		var unit := pool.take_unit(&"patrol")
		if unit == null:
			break
		if unit.kind != &"patrol":
			# The pool has no patrol left: it gave another kind of unit.
			pool.release_unit(unit)
			break
		patrols.append(unit)
	if patrols.is_empty():
		return null
	var car: PoliceCar = patrols.back()
	for other in patrols:
		if other != car:
			_hide(other)
	return car


## A car that waits at the side of the test: it is neither seen nor hit.
func _hide(car: PoliceCar) -> void:
	car.visible = false
	car.collision_layer = 0
	car.freeze = true
	car.process_mode = Node.PROCESS_MODE_DISABLED


## The wall the police car runs into. It is far away: the hit of the test is emitted, the
## car never touches it.
func _make_wall() -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 8.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, -60.0))
	return wall


## A head-on hit of the car into the wall in front of it.
func _hit_front(car: VehicleBase, wall: StaticBody3D, speed: float) -> void:
	var forward := Vector3(0.0, 0.0, -1.0)
	car.linear_velocity = forward * speed
	await Kit.wait_frames(get_tree(), 1)
	car.linear_velocity = forward * speed
	await Kit.wait_frames(get_tree(), 1)
	Events.vehicle_collided.emit(car, wall, car.mass * speed,
			car.global_position + Vector3(0.0, 0.6, -2.0), Vector3(0.0, 0.0, 1.0))
	await Kit.wait_frames(get_tree(), 2)


## The highest transparency of the meshes of the car (0 = opaque, 1 = invisible).
func _max_transparency(car: VehicleBase) -> float:
	var visual := car.get_visual_root()
	if visual == null:
		return 0.0
	var value := 0.0
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		value = maxf(value, (child as GeometryInstance3D).transparency)
	return value


## True when the part of the car is on the car.
func _part_visible(car: VehicleBase, part_name: String) -> bool:
	var visual := car.get_visual_root()
	if visual == null:
		return true
	var mesh := visual.find_child(part_name, true, false) as MeshInstance3D
	return mesh == null or mesh.visible


## Waits for a number of seconds on the clock of the scene tree (the clock the wreck flow
## uses) and then for a few physics frames.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	await Kit.wait_frames(get_tree(), 2)


func _expect(label: String, ok: bool) -> void:
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)


func _approx(label: String, got: float, want: float, tolerance: float = 0.05) -> void:
	if absf(got - want) > tolerance:
		_failures += 1
		print("FAIL %s: got %.3f, want %.3f" % [label, got, want])
	else:
		print("PASS %s (%.3f)" % [label, got])
