extends RefCounted
## The helper for the vehicle tests: it builds the sandbox world, spawns cars, runs the physics
## and reports PASS/FAIL lines.
##
## The test scripts are Nodes (see the project rule: a test host loads them at runtime so the
## autoloads and the class names are available), so the helper gets the SceneTree from the test.


var tree: SceneTree = null
var checks: int = 0
var failures: int = 0
var world: Node3D = null


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree
	# --hz=N: the physics runs at N ticks a second (the project: 120; the reports compare the rates)
	if Game.option("hz", "") != "":
		Engine.physics_ticks_per_second = int(Game.option("hz"))


## Builds the sandbox world and waits for it to settle.
func build_world() -> void:
	var packed: PackedScene = load("res://core/sandbox/sandbox.tscn") as PackedScene
	world = packed.instantiate() as Node3D
	tree.root.add_child(world)
	await step()
	await step()


## Spawns a car of the given spec and returns it.
func spawn_car(spec: CarSpec, pos: Vector3, yaw: float) -> ArcadeCar:
	var packed: PackedScene = load("res://vehicle/player_car.tscn") as PackedScene
	var car: ArcadeCar = packed.instantiate() as ArcadeCar
	car.spec = spec
	car.player_controlled = false
	# --assist=1: the cars of a test have the steering assist of the player (the feel report compares the two)
	car.steering_assist = Game.option("assist", "0") == "1"
	tree.root.add_child(car)
	car.reset_to(Transform3D(Basis(Vector3.UP, yaw), pos))
	await step()
	return car


## The roadster spec.
func roadster() -> CarSpec:
	return load("res://vehicle/specs/roadster.tres") as CarSpec


## A named NPC spec.
func spec(id: String) -> CarSpec:
	return load("res://vehicle/specs/%s.tres" % id) as CarSpec


## Waits for one physics tick.
func step() -> void:
	await tree.physics_frame


## Runs the physics for the given number of seconds.
func run(seconds: float) -> void:
	var steps: int = int(seconds * Engine.physics_ticks_per_second)
	for i in steps:
		await tree.physics_frame


## Runs the physics for the given number of seconds and keeps the car on the ground: the sandbox
## ground is a single 2.4 km box, so a long straight run would drive the car off the edge (and
## the fall would be measured as a speed). The velocity is kept, the position is reset.
func run_steady(car: ArcadeCar, seconds: float) -> void:
	var steps: int = int(seconds * Engine.physics_ticks_per_second)
	for i in steps:
		if i % 60 == 0:
			keep_on_ground(car)
		await tree.physics_frame


## Moves the car back to the start of the straight without touching its height or its velocity,
## so a long run stays on the sandbox ground (a single 2.4 km box).
func keep_on_ground(car: ArcadeCar) -> void:
	car.global_position = Vector3(car.global_position.x, car.global_position.y, 0.0)


## Runs the physics until the predicate is true or the timeout expires. Returns the time used
## in seconds, or -1.0 on timeout.
func run_until(predicate: Callable, timeout: float) -> float:
	var steps: int = int(timeout * Engine.physics_ticks_per_second)
	for i in steps:
		if predicate.call():
			return float(i) / Engine.physics_ticks_per_second
		await tree.physics_frame
	return -1.0


## The Events bus.
func events() -> Node:
	return tree.root.get_node_or_null(^"Events")


## Sets the car's speed along its forward axis.
func set_speed(car: ArcadeCar, kmh: float) -> void:
	car.linear_velocity = -car.global_transform.basis.z * (kmh / 3.6)


## The distance between two world positions (metres, horizontal).
func distance_travelled(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("PASS ", label, "  ", detail)
	else:
		failures += 1
		print("FAIL ", label, "  ", detail)


func check_range(label: String, value: float, lo: float, hi: float) -> void:
	check(label, value >= lo and value <= hi, "= %.3f (want %.3f..%.3f)" % [value, lo, hi])


func check_close(label: String, value: float, want: float, tolerance: float) -> void:
	check(label, absf(value - want) <= tolerance,
			"= %.3f (want %.3f +- %.3f)" % [value, want, tolerance])


## Prints the summary and quits with the right exit code.
func finish() -> void:
	print("RESULT %d checks, %d failures" % [checks, failures])
	tree.quit(1 if failures > 0 else 0)
