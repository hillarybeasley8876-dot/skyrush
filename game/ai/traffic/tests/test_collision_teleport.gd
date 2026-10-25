extends Node
## REGRESSION TEST (job collision-explosion): a traffic car that is moved to another lane must
## not hit the player at the place where it was.
##
## The cars of the pool used to wait at the world origin, in the middle of the junction the
## player drives through. The engine moves a frozen body one step after its transform is set
## and gives it the velocity of the move (the distance of the move divided by the step): a car
## that is still on its old place with that velocity hits the player with an impulse of millions
## of N*s and launches it at 500 m/s (the bug this test pins).
##
## Setup: the traffic test road (lanes along +X), a traffic car that waits where the player
## drives (it cannot be hit: it is a car of the pool) and the Roadster 14 m before it at
## 18 m/s, driving towards it. The car is put on a lane in the very tick in which the player is
## on it, and the lane it goes to is *behind* the player, so the car leaves in the direction of
## the player (that is the case of the game: the car was placed and shot out of the junction).
## Watched for 2 s:
##   - nothing is launched (the top speed of the player stays under 30 m/s),
##   - nothing teleports (no jump of more than 2 m in one physics tick),
##   - the car does not collide while its body is travelling to the lane,
##   - the car collides again when its body has arrived on the lane,
##   - the player keeps its health.
## Run: python tools/gd.py test res://ai/traffic/tests/test_collision_teleport.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")

## s: the physics step of the engine (the tests wait its ticks)
var DT: float = 1.0 / Engine.physics_ticks_per_second
const PLAYER_KMH := 64.8   ## 18 m/s
const PLACE_AT_X := 3.2    ## the car is put on its lane when the player is here
const MAX_SPEED := 30.0
const MAX_JUMP := 2.0
const MIN_HEALTH := 40.0

var _ctx: DriveContext = DriveContext.new()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := T.new(get_tree())
	await t.build_world()
	_ctx = DriveContext.new()
	_ctx.graph = TrafficTestRoad.build(3)
	_ctx.rng.seed = 77
	var traffic := _make_car()
	# The car waits where the player drives, and it cannot be hit: it is a car of the pool.
	traffic.global_transform = Transform3D(Basis(), Vector3.ZERO)
	traffic.freeze = true
	traffic.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	traffic.collision_layer = 0
	traffic.collision_mask = 0
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(14.0, 0.15, 0.0), PI / 2.0)
	await t.run(0.3)
	t.set_speed(car, PLAYER_KMH)
	var worst_speed := 0.0
	var worst_jump := 0.0
	var placed := false
	var layer_while_moving := -1
	var layer_after := 0
	var prev: Vector3 = car.global_position
	for i in int(2.0 / DT):
		await get_tree().physics_frame
		if not placed and car.global_position.x <= PLACE_AT_X:
			placed = true
			# The car is put on a lane 100 m further down the road: the engine gives the frozen
			# body the velocity of the move and the body is still on its old place for a step.
			traffic.place(1, 100.0)
			layer_while_moving = traffic.collision_layer
		worst_speed = maxf(worst_speed, car.linear_velocity.length())
		worst_jump = maxf(worst_jump, car.global_position.distance_to(prev))
		prev = car.global_position
		if placed:
			layer_after = traffic.collision_layer
	var health: float = float(car.get("health")) if car.get("health") != null else 100.0
	t.check("the car was put on its lane", placed)
	t.check("the car does not collide while its body is travelling", layer_while_moving == 0,
			"= %d" % layer_while_moving)
	t.check("the car collides again when its body has arrived", layer_after == TrafficCar.COLLISION_LAYER,
			"= %d" % layer_after)
	t.check("nothing is launched: top speed of the player <= %.0f m/s" % MAX_SPEED,
			worst_speed <= MAX_SPEED, "= %.1f m/s" % worst_speed)
	t.check("nothing teleports: biggest jump in one tick <= %.1f m" % MAX_JUMP,
			worst_jump <= MAX_JUMP, "= %.2f m" % worst_jump)
	t.check("the player keeps its health (>= %.0f)" % MIN_HEALTH, health >= MIN_HEALTH,
			"= %.0f" % health)
	t.finish()


## A traffic car on the test road (same as ai/traffic/tests/test_wreck.gd).
func _make_car() -> TrafficCar:
	var car := (load("res://ai/traffic/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(car)
	car.build(_ctx, &"sedan_ev", Color.WHITE, _ctx.rng.randi())
	return car
