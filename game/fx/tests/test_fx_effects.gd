extends Node
## The effect tests of the fx unit (tools/godot.sh test res://fx/tests/test_fx_effects.gd).
##
## They cover the rules of the round-2 review: reversing is not braking, the electric arcs stay
## on the bodywork, the emitter budget of 8 holds with a dozen wrecked cars, the rain splashes
## are spread over the road and the sparks of a hit do not fall through a deck.

const TUNE := preload("res://fx/fx_tuning.gd")
const Arcs := preload("res://fx/fx_arcs.gd")
const GROUND := preload("res://fx/fx_ground.gd")
const WRECK := preload("res://fx/fx_wreck_fx.gd")

## Stand-in for the environment unit's weather controller (same group, same API).
class StubWeather extends Node:
	func rain_amount() -> float:
		return 0.6

	func wetness() -> float:
		return 0.85


var _failures: int = 0
var _director: Node
var _car_scene: PackedScene


func _ready() -> void:
	_car_scene = load("res://core/stubs/stub_car.tscn") as PackedScene
	_director = (load("res://fx/fx_director.tscn") as PackedScene).instantiate()
	add_child(_director)
	_add_ground()
	_add_camera()
	var weather := StubWeather.new()
	weather.name = "StubWeather"
	weather.add_to_group("weather")
	add_child(weather)
	# The rain is a quality feature: the test must not depend on the saved user preset.
	Settings.quality = &"high"
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	await _test_reversing()
	await _test_arcs()
	await _test_arc_health()
	await _test_emitter_cap()
	await _test_splash()
	await _test_impact_ground()
	await _test_skid_width()
	await _test_skid_geometry()
	await _test_splash_on_road()

	print("FX EFFECT TESTS %s (%d failures)" % ["FAILED" if _failures > 0 else "OK", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## A flat ground, so the skid ribbon and the ground probe have a surface to work with.
func _add_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "TestGround"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.5, 0.0)
	add_child(body)


## A deck at 10 m: the hit happens on it and the sparks must not fall through it.
func _add_deck() -> void:
	var body := StaticBody3D.new()
	body.name = "TestDeck"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, 9.5, 0.0)
	add_child(body)


## A camera above the ground: the rain probes the road under it.
func _add_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "TestCamera"
	add_child(camera)
	camera.position = Vector3(0.0, 2.6, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		print("FAIL ", label)


func _spawn_car(at: Vector3 = Vector3.ZERO) -> VehicleBase:
	var car := _car_scene.instantiate() as VehicleBase
	car.position = at
	add_child(car)
	return car


## Reversing is not braking: a car that rolls backwards at 40 km/h with the brake on does not
## smoke and does not leave a skid mark.
func _test_reversing() -> void:
	var car := _spawn_car()
	Game.player = car
	await get_tree().process_frame
	car.telemetry.speed_kmh = 40.0
	car.telemetry.forward_speed_kmh = -40.0
	car.telemetry.brake = 1.0
	car.linear_velocity = Vector3(0.0, 0.0, 11.0)
	var pool: Node = _director.call("skid_pool")
	for i in 30:
		car.global_position = Vector3(0.0, 0.6, float(i) * 0.5)
		await get_tree().physics_frame
	var quads := int(pool.call("live_count"))
	_check(quads == 0, "reversing leaves no skid mark (%d quads)" % quads)
	var rig := car.get_node_or_null(^"FxRig")
	var smoking := false
	if rig != null:
		for name: StringName in [&"TyreSmokeL", &"TyreSmokeR"]:
			var smoke := rig.get_node_or_null(NodePath(name)) as GPUParticles3D
			if smoke != null and smoke.emitting:
				smoking = true
	_check(not smoking, "reversing does not smoke")
	car.queue_free()
	Game.player = null
	await get_tree().process_frame


## The electric arcs stay on the bodywork: every bolt is shorter than 0.8 m and no vertex is
## further than 0.15 m from the shell of the car.
func _test_arcs() -> void:
	var arcs := Arcs.new()
	add_child(arcs)
	arcs.setup(Color(0.1, 0.9, 1.0), 6.0, 6)
	var shell := PackedVector3Array()
	for i in 200:
		var a := TAU * float(i) / 200.0
		shell.append(Vector3(cos(a) * 0.9, 0.6 + sin(a * 3.0) * 0.3, sin(a) * 2.0))
	arcs.set_surface_points(shell)
	arcs.play()
	var worst_length := 0.0
	var worst_distance := 0.0
	for i in 100:
		arcs.regenerate()
		for path: PackedVector3Array in arcs.paths():
			worst_length = maxf(worst_length, Arcs.path_length(path))
			for point in path:
				worst_distance = maxf(worst_distance, _distance_to_shell(point, shell))
	_check(worst_length <= TUNE.ARC_MAX_LENGTH + 0.001,
			"every bolt is shorter than %.2f m (%.3f)" % [TUNE.ARC_MAX_LENGTH, worst_length])
	_check(worst_distance <= TUNE.ARC_SURFACE_OFFSET + 0.001,
			"every bolt stays on the shell (%.3f m)" % worst_distance)
	arcs.queue_free()
	await get_tree().process_frame


## The distance of a point to the closest point of the shell.
func _distance_to_shell(point: Vector3, shell: PackedVector3Array) -> float:
	var closest := INF
	for s in shell:
		closest = minf(closest, point.distance_to(s))
	return closest


## The arcs of a wrecked EV only show when the car is nearly dead.
func _test_arc_health() -> void:
	var car := _spawn_car()
	Game.player = car
	await get_tree().process_frame
	car.telemetry.health_norm = 0.5
	Events.vehicle_wrecked.emit(car, null)
	await get_tree().process_frame
	await get_tree().physics_frame
	var rig := car.get_node_or_null(^"FxRig")
	var wreck := rig.get_node_or_null(^"WreckFx") as WRECK
	_check(wreck != null, "a wrecked car gets its wreck effects")
	if wreck != null:
		_check(not wreck.arcs_running(), "a car with 50 % health shows no arcs")
		car.telemetry.health_norm = 0.1
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(wreck.arcs_running(), "a car with 10 % health shows its arcs")
	car.queue_free()
	Game.player = null
	await get_tree().process_frame


## A dozen wrecked cars inside 60 m may not run more than 8 smoke / fire emitters.
func _test_emitter_cap() -> void:
	Game.player = null
	var cars: Array[VehicleBase] = []
	for i in 12:
		cars.append(_spawn_car(Vector3(float(i) * 3.0, 0.0, 20.0)))
	await get_tree().process_frame
	for car in cars:
		Events.vehicle_wrecked.emit(car, null)
	await get_tree().process_frame
	# The emitter budget is handed out every 0.2 s: wait for it.
	for i in 40:
		await get_tree().physics_frame
	var count := int(_director.call("active_emitter_count"))
	_check(count == 8, "12 wrecked cars run 8 smoke / fire emitters (got %d)" % count)
	for car in cars:
		car.queue_free()
	await get_tree().process_frame


## The rain splashes are spread over the road: the point texture holds one point per hit.
func _test_splash() -> void:
	var rain: Node = _director.call("rain")
	var count := int(rain.call("splash_point_count"))
	_check(count > 0, "the rain finds road under the camera (%d points)" % count)
	var material := rain.get_node_or_null(^"RainSplashes") as GPUParticles3D
	_check(material != null, "the rain has a splash system")
	if material != null:
		var mat := material.process_material as ParticleProcessMaterial
		_check(int(mat.emission_point_count) == count,
				"the splash system uses every point (%d of %d)" % [mat.emission_point_count, count])
		_check(mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS,
				"the splashes are directed points")
		var image := mat.emission_point_texture.get_image()
		_check(image != null and image.get_format() == Image.FORMAT_RGBF,
				"the point texture holds positions in metres")


## The sparks of a hit on a deck stay on the deck: they do not fall through it.
func _test_impact_ground() -> void:
	_add_deck()
	var car := _spawn_car(Vector3(0.0, 10.2, 0.0))
	Game.player = car
	await get_tree().process_frame
	var sparks: Node = _director.call("spark_pool")
	sparks.call("clear")
	Events.vehicle_collided.emit(car, null, 26000.0, Vector3(0.0, 10.0, 0.0), Vector3.UP)
	await get_tree().process_frame
	_check(int(sparks.call("live_count")) > 0, "the hit throws sparks")
	for i in 24:
		await get_tree().physics_frame
	var lowest := float(sparks.call("lowest_point"))
	_check(lowest > 9.9, "no spark falls through the deck (lowest %.2f m)" % lowest)
	car.queue_free()
	Game.player = null
	await get_tree().process_frame


## The skid mark is a real strip of 24 cm, not a hairline.
## A drift at 270 km/h leaves a mark, every vertex of the mark is above the road, and the first
## quad of a strip is already 24 cm wide.
func _test_skid_geometry() -> void:
	var car := _spawn_car()
	Game.player = car
	await get_tree().process_frame
	car.telemetry.rear_slip = 1.0
	car.telemetry.drift_state = &"drift"
	car.telemetry.speed_kmh = 270.0
	car.telemetry.forward_speed_kmh = 270.0
	var pool: Node = _director.call("skid_pool")
	# 0.64 m per physics tick: the speed of a real drift at 270 km/h.
	for i in 240:
		car.global_position = Vector3(0.0, 0.6, -float(i) * 0.64)
		await get_tree().physics_frame
	var quads := int(pool.call("live_count"))
	_check(quads > 0, "a drift at 270 km/h leaves a mark (%d quads)" % quads)
	var narrowest := float(pool.call("narrowest_quad_width"))
	_check(narrowest > 0.22 and narrowest < 0.26,
			"the first quad of a strip is 24 cm wide (%.3f m)" % narrowest)
	var verts: PackedVector3Array = pool.call("live_vertices") as PackedVector3Array
	var space := get_viewport().world_3d.direct_space_state
	var lowest := INF
	for v in verts:
		var result := GROUND.probe(space, v)
		if result["hit"]:
			lowest = minf(lowest, v.y - (result["point"] as Vector3).y)
	_check(lowest >= TUNE.SKID_LIFT - 0.001,
			"every vertex of the ribbon is above the road (%.4f m, lift %.4f m)" % [lowest,
			TUNE.SKID_LIFT])
	car.queue_free()
	Game.player = null
	await get_tree().process_frame


## The splash rings land on the place where the ray found the road: the emitter transform times
## the offset of a texel has to be within 3 cm of its hit.
func _test_splash_on_road() -> void:
	var rain: Node = _director.call("rain")
	var positions: Array = rain.call("splash_ring_positions")
	_check(positions.size() > 0, "the rain has splash rings (%d)" % positions.size())
	var space := get_viewport().world_3d.direct_space_state
	var worst := 0.0
	for p: Vector3 in positions:
		var result := GROUND.probe(space, p)
		if result["hit"]:
			worst = maxf(worst, p.distance_to(result["point"] as Vector3))
	_check(worst <= 0.03, "every splash ring is on the road (worst %.3f m)" % worst)


func _test_skid_width() -> void:
	var car := _spawn_car()
	Game.player = car
	await get_tree().process_frame
	car.telemetry.rear_slip = 0.9
	car.telemetry.drift_state = &"drift"
	car.telemetry.speed_kmh = 60.0
	car.telemetry.forward_speed_kmh = 60.0
	var pool: Node = _director.call("skid_pool")
	for i in 120:
		car.global_position = Vector3(0.0, 0.6, -float(i) * 0.5)
		await get_tree().physics_frame
	var width := float(pool.call("quad_width"))
	_check(width > 0.22 and width < 0.26, "the skid mark is 22-26 cm wide (%.3f m)" % width)
	car.queue_free()
	Game.player = null
	await get_tree().process_frame
