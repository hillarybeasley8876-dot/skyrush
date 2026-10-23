extends Node
## Flies every sky lane (飞行航道) of the real city from its launch pad to its end.
##
##   python tools/gd.py test res://world/tests/test_sky_lanes_fly.gd -- --timeout=400
##
## The vehicle tests fly the lane of the sandbox. This one flies the five lanes that city.json describes, on the real
## world: the take-off at the pad, the flight along the curve of the lane (the world's obstacles stand in the tubes), the
## exit and the landing. Per lane it checks that the car took off, that it never jumps (a lane whose curve has a kink or
## whose frame fails would teleport it), that the flight reaches the end of the lane and that the car stands on the ground
## afterwards. The obstacles in the tube are not dodged (the car flies the centre line): their hits are reported, not judged.

const WORLD := "res://world/world.tscn"
const PLAYER_CAR := "res://vehicle/player_car.tscn"
const ENTRY_KMH := 170.0       ## the speed at the pad (the lanes ask 120 km/h)
const APPROACH := 50.0         ## m: the car starts this far before the pad
const APPROACH_SECONDS := 6.0  ## the car has this long to reach the pad and take off
const SECONDS_PER_LANE := 60.0 ## the longest flight we wait for (the longest lane is 1.7 km, cruise 200 km/h)
const LAND_SECONDS := 12.0     ## after the flight the car has this long to stand on its wheels
const END_REACH := 60.0        ## m: the car leaves the lane within this distance of its end (the exit glides on)
const JUMP_FACTOR := 1.6       ## a step of the car may be this many times the distance of its speed
const JUMP_MARGIN := 0.5       ## m

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := (load(WORLD) as PackedScene).instantiate()
	add_child(world)
	var car := (load(PLAYER_CAR) as PackedScene).instantiate() as ArcadeCar
	car.player_controlled = false
	add_child(car)
	Game.player = car
	await Game.world_ready()
	var lanes: Array[SkyLane] = []
	_collect(world, lanes)
	_expect(lanes.size() == 5, "the city has 5 sky lanes (%d)" % lanes.size())
	for lane in lanes:
		await _fly(car, lane)
	print("SKY LANES FLY TESTS %s (%d failures)" % ["OK" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## Every SkyLane under a node.
func _collect(node: Node, out: Array[SkyLane]) -> void:
	if node is SkyLane:
		out.append(node as SkyLane)
	for child in node.get_children():
		_collect(child, out)


## One flight: the car drives up to the launch pad at the entry speed with a full tank, the pad takes it into the lane, the flight runs.
func _fly(car: ArcadeCar, lane: SkyLane) -> void:
	var name := String(lane.name)
	var start := lane.frame_at(0.0)
	var pad := lane.get_node_or_null(^"LaunchPad") as Area3D
	_expect(pad != null, "%s has a launch pad" % name)
	var ahead := -start.basis.z
	var flat := Vector3(ahead.x, 0.0, ahead.z).normalized()
	# The car drives up to the pad like a player: it starts APPROACH metres before it on the road, at the entry speed.
	var from := (pad.global_position if pad != null else start.origin) - flat * APPROACH + Vector3.UP * 1.0
	car.reset_to(Transform3D(Basis.looking_at(flat, Vector3.UP), from))
	await get_tree().physics_frame
	car.boost.n2 = 100.0
	car.health = car.max_health
	car.linear_velocity = flat * (ENTRY_KMH / 3.6)
	var health_before := car.health
	for i in int(APPROACH_SECONDS * 120.0):
		car.set_controls(1.0, 0.0, 0.0, false)
		await get_tree().physics_frame
		if car.telemetry.flying:
			break
	var took_off := car.telemetry.flying
	var flew := took_off
	var max_jump := 0.0
	var worst_ratio := 0.0
	var worst_at := ""
	var previous := car.global_position
	var end_offset := 0.0
	var frames := int(SECONDS_PER_LANE * 120.0)
	var end_point := lane.curve.sample_baked(lane.length(), true)
	var finished := false
	for i in frames:
		car.set_controls(0.0, 0.0, 0.0, false)
		await get_tree().physics_frame
		var here := car.global_position
		var step := here.distance_to(previous)
		var allowed := JUMP_FACTOR * car.linear_velocity.length() / 120.0 + JUMP_MARGIN
		if car.telemetry.flying:
			flew = true
			allowed = JUMP_FACTOR * car.sky.speed / 120.0 + JUMP_MARGIN
			end_offset = car.sky.offset
		max_jump = maxf(max_jump, step)
		if step / allowed > worst_ratio:
			worst_ratio = step / allowed
			worst_at = "tick %d, offset %.0f m, step %.2f m, lane speed %.1f m/s, flying %s, transitioning %s, exiting %s" % [
				i, car.sky.offset, step, car.sky.speed, str(car.telemetry.flying), str(car.sky.transitioning), str(car.sky.exiting)]
		previous = here
		if flew and not car.telemetry.flying:
			finished = true
			break
	var from_end := car.global_position.distance_to(end_point)
	var landed := false
	for i in int(LAND_SECONDS * 120.0):
		await get_tree().physics_frame
		if car.telemetry.grounded_wheels >= 3 and not car.telemetry.airborne:
			landed = true
			break
	print("INFO %s: %.0f m long, left the lane at %.0f m, %.0f m from its end, longest step %.2f m, health %.0f -> %.0f" % [
		name, lane.length(), end_offset, from_end, max_jump, health_before, car.health])
	print("INFO %s: the car is at height %.1f, the end of the lane at %.1f, the altitude over the ground %.1f m, flying %s, exiting %s, gliding %s, vertical %.1f (tube down %.1f)" % [
		name, car.global_position.y, end_point.y, car.telemetry.altitude_m, str(car.telemetry.flying), str(car.sky.exiting),
		str(car.sky.gliding), car.sky.vertical, lane.tube_down])
	_expect(took_off, "%s: the car took off at the pad" % name)
	_expect(finished, "%s: the flight ended inside %.0f s" % [name, SECONDS_PER_LANE])
	_expect(end_offset >= lane.length() - END_REACH, "%s: the flight reached the end of the lane (%.0f of %.0f m)" % [name, end_offset, lane.length()])
	_expect(worst_ratio <= 1.0, "%s: the car never jumps (worst step %.2f of the allowed: %s)" % [name, worst_ratio, worst_at])
	_expect(landed, "%s: the car stands on its wheels after the flight" % name)


func _expect(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		_failures += 1
