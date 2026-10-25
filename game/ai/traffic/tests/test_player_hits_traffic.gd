extends Node
## LEAD ACCEPTANCE TEST: the player's Roadster hits a traffic car. A collision must be a collision, not an explosion.
##
## Found by driving the real game: at 65 km/h the player hit a traffic car in the Bund junction and one physics step
## later the car moved at 500 m/s (1800 km/h) with health 0 and was thrown 100 m; the solver reported a contact impulse
## of 3.4 million N s where two cars of 1.9 t and 1.5 t closing at 13 m/s need about 20 thousand.
##
## Setup: the traffic test road (lanes along +X), a traffic car (sedan) in NEAR mode driving 5 m/s, the Roadster 14 m
## behind it at 18 m/s (closing speed 13 m/s). Watched for 3 s after the start:
##   - no body ever moves faster than 30 m/s (nothing is launched),
##   - no body jumps more than 2 m in one physics tick (nothing teleports),
##   - the Roadster is slower after the hit than before it, and does not fly backwards faster than 10 m/s,
##   - the Roadster keeps at least 40 health (a 47 km/h closing hit is a bump, not a death).
## Run: python tools/gd.py test res://ai/traffic/tests/test_player_hits_traffic.gd

const T := preload("res://vehicle/tests/vehicle_test.gd")

## s: the physics step of the engine (the tests wait its ticks)
var DT: float = 1.0 / Engine.physics_ticks_per_second
const PLAYER_KMH := 64.8   ## 18 m/s
const TRAFFIC_SPEED := 5.0
const GAP := 14.0
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
	var traffic := _make_car(1, 80.0)
	traffic.set_mode(TrafficCar.Mode.NEAR)
	traffic.speed = TRAFFIC_SPEED
	await get_tree().physics_frame
	var start: Vector3 = traffic.global_position - Vector3(GAP, 0.0, 0.0)
	var car: ArcadeCar = await t.spawn_car(t.roadster(), Vector3(start.x, 0.15, start.z), -PI / 2.0)
	await t.run(0.4)
	t.set_speed(car, PLAYER_KMH)
	var before: float = car.linear_velocity.length()
	var worst_speed := 0.0
	var worst_jump := 0.0
	var worst_back := 0.0
	var prev_car: Vector3 = car.global_position
	var prev_traffic: Vector3 = traffic.global_position
	var hit_seen := false
	for i in int(3.0 / DT):
		await get_tree().physics_frame
		worst_speed = maxf(worst_speed, maxf(car.linear_velocity.length(), traffic.linear_velocity.length()))
		worst_jump = maxf(worst_jump, maxf(car.global_position.distance_to(prev_car), traffic.global_position.distance_to(prev_traffic)))
		prev_car = car.global_position
		prev_traffic = traffic.global_position
		if traffic.mode == TrafficCar.Mode.WRECK or car.global_position.distance_to(traffic.global_position) < 5.0:
			hit_seen = true
		worst_back = maxf(worst_back, -car.linear_velocity.x)
	var after: float = car.linear_velocity.length()
	var health: float = float(car.get("health")) if car.get("health") != null else 100.0
	t.check("the player car reached the traffic car", hit_seen)
	t.check("nothing is launched: top speed of any body <= %.0f m/s" % MAX_SPEED, worst_speed <= MAX_SPEED, "= %.1f m/s" % worst_speed)
	t.check("nothing teleports: biggest jump in one tick <= %.1f m" % MAX_JUMP, worst_jump <= MAX_JUMP, "= %.2f m" % worst_jump)
	t.check("the player is slower after the hit than before it", after < before, "= %.1f vs %.1f m/s" % [after, before])
	t.check("the player does not fly backwards (<= 10 m/s)", worst_back <= 10.0, "= %.1f m/s" % worst_back)
	t.check("the player survives a 47 km/h closing hit (health >= %.0f)" % MIN_HEALTH, health >= MIN_HEALTH, "= %.0f" % health)
	t.finish()


## A traffic car on the test road (same as ai/traffic/tests/test_wreck.gd).
func _make_car(lane: int, s: float) -> TrafficCar:
	var car := (load("res://ai/traffic/traffic_car.tscn") as PackedScene).instantiate() as TrafficCar
	add_child(car)
	car.build(_ctx, &"sedan_ev", Color.WHITE, _ctx.rng.randi())
	car.place(lane, s)
	car.player_distance = 0.0
	return car
