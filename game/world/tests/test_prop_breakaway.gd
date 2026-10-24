extends Node
## The street lamps break away (world/build/prop_breaker.gd). A pole of 15 cm used to stop a car of 1.9 t dead, and by the damage
## rules a head-on hit at 108 km/h wrecked it (half of the random drives of tools/fuzz_drive.gd ended on a prop). A car that drives
## into a lamp knocks it down now: the lamp goes from the street (its MultiMesh instances and its light), its pole falls as debris,
## the car keeps 85 % of its speed and loses 3 HP. A car that only creeps into a lamp does not break it. The soft furniture (a
## bollard, a bin) breaks away for less: the car keeps 96-97 % of its speed and loses half an HP (it had no collision at all: the car
## drove through it).
## Run: python tools/gd.py test res://world/tests/test_prop_breakaway.gd -- --timeout=290 --stub=audio,menu,hud,rivals,traffic,police

const MAIN := "res://main.tscn"
const PropBreaker := preload("res://world/build/prop_breaker.gd")
## The speed of the car that drives into the lamp (m/s, 100 km/h) and how far before the lamp it starts (m).
const SPEED := 27.8
const RUN_UP := 8.0
## The speed of the car that drives into a bollard or a bin (m/s, 60 km/h).
const SOFT_SPEED := 16.7
## The world and the props: what the path to a lamp has to be clear of.
const CLEAR_MASK := 1 | 4

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
	var builder: Object = Game.world.get("_builder")
	var breaker := builder.get("prop_breaker") as PropBreaker
	_check(breaker != null, "the world has a breaker of the street lamps")
	if breaker == null:
		_finish()
		return
	_check(breaker.lamp_count() > 1000, "the lamps of the city break away", "(%d lamps)" % breaker.lamp_count())
	var car := Game.player as ArcadeCar
	var pick := _clear_lamp(breaker, car)
	_check(not pick.is_empty(), "a lamp with a clear run-up is found")
	if pick.is_empty():
		_finish()
		return
	var index: int = pick["index"]
	var direction: Vector3 = pick["direction"]
	var base := (breaker.lamp(index)["transform"] as Transform3D).origin
	# the car comes from RUN_UP metres before the lamp, straight at it, at 100 km/h, with nobody at the wheel (the title screen
	# holds the player car frozen when the menu is not stubbed: the test lets it go, as the start of a game does)
	car.freeze = false
	car.reset_to(Transform3D(Basis.looking_at(direction, Vector3.UP), base - direction * RUN_UP + Vector3.UP * 0.4))
	await get_tree().physics_frame
	car.health = car.max_health
	car.linear_velocity = direction * SPEED
	var broken_before := breaker.broken_count
	var debris_before := breaker.debris_count()
	var before := 0.0
	var after := 0.0
	for i in 120:
		var speed := car.linear_velocity.length()
		await get_tree().physics_frame
		if breaker.broken_count > broken_before:
			before = speed
			await get_tree().physics_frame
			after = car.linear_velocity.length()
			break
	_check(breaker.is_broken(index), "the car knocks the lamp down", "(lamps broken: %d)" % (breaker.broken_count - broken_before))
	if not breaker.is_broken(index):
		print("   the car: at %s, %.1f m from the lamp, speed %.1f, frozen %s, visible %s, the player %s, wrecked %s" % [
			str(car.global_position.snapped(Vector3.ONE * 0.1)), Vector2(car.global_position.x - base.x, car.global_position.z - base.z).length(),
			car.linear_velocity.length(), car.freeze, car.is_visible_in_tree(), car == Game.player, car.is_wrecked])
	_check(after >= before * 0.8 and before > SPEED * 0.8, "the car keeps its speed (85 %)",
			"(%.1f -> %.1f m/s)" % [before, after])
	_check(car.max_health - car.health <= 6.0, "the lamp costs a few HP", "(%.1f HP)" % (car.max_health - car.health))
	_check(not car.is_wrecked, "the car is not wrecked")
	# the lamp is gone from the street: every part and far dot of it is an instance of a MultiMesh that the breaker hides (a
	# headless run cannot read a MultiMesh back, the dummy renderer gives every instance as the identity: the picture is checked
	# with a windowed capture), and its light is off
	var multimeshes: Dictionary = breaker.get("_multimeshes")
	var found := 0
	var refs: Array = breaker.lamp(index)["refs"]
	for ref in refs:
		var multimesh := multimeshes.get(ref[0]) as MultiMesh
		if multimesh != null and int(ref[1]) < multimesh.instance_count:
			found += 1
	_check(refs.size() >= 2 and found == refs.size(), "every part of the lamp is an instance the breaker hides",
			"(%d of %d)" % [found, refs.size()])
	var lights: Array = breaker.lamp(index)["lights"]
	var pool: Object = builder.get("lights")
	var sources: Array = pool.get("_sources")
	var off := 0
	for light_index in lights:
		if bool((sources[int(light_index)] as Dictionary).get("off", false)):
			off += 1
	_check(lights.is_empty() or off == lights.size(), "its light is off", "(%d of %d)" % [off, lights.size()])
	_check(breaker.debris_count() > debris_before, "its pole falls")
	# the pole lies, fades and goes (the car is parked meanwhile: rolling on, it knocks more props over, now that the soft
	# furniture breaks away too)
	car.linear_velocity = Vector3.ZERO
	car.freeze = true
	await get_tree().create_timer(PropBreaker.DEBRIS_LIFE + PropBreaker.DEBRIS_FADE + 0.5, true, false, true).timeout
	_check(breaker.debris_count() == debris_before, "the pole fades away", "(%d left)" % breaker.debris_count())
	car.freeze = false
	# a car that creeps into a lamp does not break it
	var slow_pick := _clear_lamp(breaker, car)
	if not slow_pick.is_empty():
		var slow: int = slow_pick["index"]
		var slow_base := (breaker.lamp(slow)["transform"] as Transform3D).origin
		var slow_dir: Vector3 = slow_pick["direction"]
		car.reset_to(Transform3D(Basis.looking_at(slow_dir, Vector3.UP), slow_base - slow_dir * 1.0 + Vector3.UP * 0.4))
		for i in 60:
			car.linear_velocity = slow_dir * 1.0
			await get_tree().physics_frame
		_check(not breaker.is_broken(slow), "a car that creeps into a lamp does not break it")
	# the soft furniture: a bollard or a bin, at 60 km/h
	var soft_pick := _clear_lamp(breaker, car, ["bollard", "bin"])
	_check(not soft_pick.is_empty(), "a bollard or a bin with a clear run-up is found")
	if not soft_pick.is_empty():
		var soft: int = soft_pick["index"]
		var soft_dir: Vector3 = soft_pick["direction"]
		var soft_base := (breaker.lamp(soft)["transform"] as Transform3D).origin
		car.reset_to(Transform3D(Basis.looking_at(soft_dir, Vector3.UP), soft_base - soft_dir * RUN_UP + Vector3.UP * 0.4))
		await get_tree().physics_frame
		car.health = car.max_health
		car.linear_velocity = soft_dir * SOFT_SPEED
		var soft_before := 0.0
		var soft_after := 0.0
		var soft_debris := breaker.debris_count()
		for i in 120:
			var speed := car.linear_velocity.length()
			await get_tree().physics_frame
			if breaker.is_broken(soft):
				soft_before = speed
				await get_tree().physics_frame
				soft_after = car.linear_velocity.length()
				break
		var soft_type := String(breaker.lamp(soft)["type"])
		_check(breaker.is_broken(soft), "the car knocks the %s away" % soft_type)
		_check(soft_after >= soft_before * 0.94 and soft_before > SOFT_SPEED * 0.8, "the car keeps 94 % of its speed or more",
				"(%.1f -> %.1f m/s)" % [soft_before, soft_after])
		_check(car.max_health - car.health <= 1.5, "the %s costs half an HP" % soft_type, "(%.1f HP)" % (car.max_health - car.health))
		_check(breaker.debris_count() > soft_debris, "the %s flies" % soft_type)
	# the cost of the breaker: every car near the camera, every physics tick (the traffic and the police are on in a game)
	var total := 0.0
	var peak := 0.0
	for i in 240:
		await get_tree().physics_frame
		total += breaker.cost_usec
		peak = maxf(peak, breaker.cost_usec)
	var cars := get_tree().get_nodes_in_group(&"vehicles").size()
	_check(total / 240.0 < 150.0, "the breaker costs little", "(%.0f us a tick on average, %.0f at most, %d cars)" % [
		total / 240.0, peak, cars])
	_finish()


func _finish() -> void:
	print("BREAKAWAY TESTS %s (%d failures)" % ["OK" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## A lamp (or a prop of `kinds`) on the ground whose run-up (RUN_UP before it to 4 m after it) is clear of the world and the props,
## and the direction of the run-up: {"index", "direction"}, or empty.
func _clear_lamp(breaker: PropBreaker, car: VehicleBase, kinds: Array = []) -> Dictionary:
	var space := get_viewport().get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.0, 4.6)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = CLEAR_MASK
	query.exclude = [car.get_rid()]
	for index in range(0, breaker.lamp_count(), 7):
		if breaker.is_broken(index):
			continue
		var lamp: Dictionary = breaker.lamp(index)
		var base := (lamp["transform"] as Transform3D).origin
		var type := String(lamp["type"])
		if absf(base.y) > 0.5 or type == "lamp_deck_double":
			continue
		if (kinds.is_empty() and not type.begins_with("lamp")) or (not kinds.is_empty() and not kinds.has(type)):
			continue
		for k in 8:
			var direction := Vector3(sin(float(k) * TAU / 8.0), 0.0, cos(float(k) * TAU / 8.0))
			# the box of the car along the run-up and past the lamp, but not over the lamp itself (a lamp that had a rigid shape
			# would hide every run-up, and the test would not drive into it)
			var clear := true
			for d: float in [-RUN_UP, -6.0, -4.0, -2.5, 2.5, 4.0]:
				query.transform = Transform3D(Basis.looking_at(direction, Vector3.UP), base + direction * d + Vector3.UP * 0.9)
				if not space.intersect_shape(query, 1).is_empty():
					clear = false
					break
			# no other lamp on the way either (it would be knocked down first)
			if clear and breaker.lamps_near(base - direction * (RUN_UP * 0.5), RUN_UP * 0.5 + 1.5).size() == 1:
				return {"index": index, "direction": direction}
	return {}
