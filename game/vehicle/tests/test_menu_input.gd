extends Node
## The lead note V-INT2: the car must not drive while the game is in the menu (the menu uses the
## same keys for its navigation) and it must not drive while the game is paused.
## Run: tools/godot.sh test res://vehicle/tests/test_menu_input.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")

var _boosts: Array[StringName] = []
var _hops: Array[StringName] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	var events: Node = t.events()
	events.boost_started.connect(func(_v: VehicleBase, k: StringName) -> void: _boosts.append(k))
	events.hop.connect(func(_v: VehicleBase, k: StringName) -> void: _hops.append(k))
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(0.0, 0.15, 0.0), 0.0)
	Game.player = car
	var mode: StringName = Game.mode
	# The menu owns the input.
	Game.mode = &"menu"
	Input.action_press(&"accelerate")
	Input.action_press(&"nitro")
	Input.action_press(&"hop")
	car.boost.n2 = 100.0
	await t.run(2.0)
	t.check("the car stays parked", car.telemetry.speed_kmh < 1.0,
			"= %.2f km/h" % car.telemetry.speed_kmh)
	t.check("the tank is untouched", is_equal_approx(car.boost.n2, 100.0),
			"= %.1f N2" % car.boost.n2)
	t.check("no boost started", _boosts.is_empty(), "= %s" % str(_boosts))
	t.check("no hop", _hops.is_empty(), "= %s" % str(_hops))
	# The game starts: the input works again and no phantom edge fires.
	Game.mode = mode
	await t.run(0.5)
	t.check("the car drives again", car.telemetry.speed_kmh > 5.0,
			"= %.2f km/h" % car.telemetry.speed_kmh)
	t.check("still no boost", _boosts.is_empty(), "= %s" % str(_boosts))
	Input.action_release(&"accelerate")
	Input.action_release(&"nitro")
	Input.action_release(&"hop")
	Game.player = null
	t.finish()
