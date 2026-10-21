extends Node3D
## The collision effects of a car rig (brief §4): the impact burst of a crash, the shower of a
## scrape and the ribbon of displaced air of a near miss.
##
## The helper is a child of the rig (and so of the car): it owns the shared pools of the
## director and the timing of the contacts, so fx_car_rig.gd only drives the tyre effects.
##
## A contact that repeats within TUNE.SCRAPE_WINDOW is a scrape (the car grinds along a wall),
## a fresh contact is an impact.

const IMPACT := preload("res://fx/fx_impact_fx.gd")
const GROUND := preload("res://fx/fx_ground.gd")
const TUNE := preload("res://fx/fx_tuning.gd")
const SPARK_POOL := preload("res://fx/fx_spark_pool.gd")
const DEBRIS_POOL := preload("res://fx/fx_debris_pool.gd")
const LIGHT_POOL := preload("res://fx/fx_light_pool.gd")

## A contact that repeats inside this window is a scrape and not a new impact.
const SCRAPE_WINDOW := 0.25

var spark: SPARK_POOL = null
var debris: DEBRIS_POOL = null
var lights: LIGHT_POOL = null
var vehicle: VehicleBase = null
## The velocity of the car, measured from its movement between two physics ticks.
var velocity: Vector3 = Vector3.ZERO

var _last_hit_time: float = -10.0
var _last_spark_time: float = -10.0
var _last_other_id: int = 0


## Hands the helper the car and the shared pools of the director.
func setup(car: VehicleBase, spark_pool: SPARK_POOL, debris_pool: DEBRIS_POOL,
		light_pool: LIGHT_POOL) -> void:
	vehicle = car
	spark = spark_pool
	debris = debris_pool
	lights = light_pool


## Called by the director for every `Events.vehicle_collided` of this car.
func on_collision(impulse: float, point: Vector3, normal: Vector3, other: Node3D) -> void:
	if spark == null or not is_instance_valid(spark):
		return
	var now := _now()
	var other_id := other.get_instance_id() if other != null else 0
	var scraping := other_id != 0 and other_id == _last_other_id \
			and now - _last_hit_time < SCRAPE_WINDOW
	_last_hit_time = now
	_last_other_id = other_id
	if scraping:
		scrape(point, normal, now)
		return
	var mass := maxf(vehicle.mass if vehicle != null else 1800.0, 100.0)
	var dv := IMPACT.delta_v(impulse, mass)
	if not IMPACT.is_significant(dv):
		return
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	IMPACT.burst(spark, debris, lights, space, point, normal, dv, carry_velocity())


## A contact that persists (grinding along a wall) throws a shower that trails behind the car.
func scrape(point: Vector3, normal: Vector3, now: float) -> void:
	if now - _last_spark_time < TUNE.SPARK_SCRAPE_INTERVAL:
		return
	_last_spark_time = now
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var ground := point.y - 5.0
	if space != null:
		ground = GROUND.height(space, point, ground)
	spark.scrape(point, normal, velocity, ground)


## Traffic passed within 1.2 m at speed: a ribbon of displaced air along the passing car.
func near_miss(other: Node3D) -> void:
	if spark == null or not is_instance_valid(spark):
		return
	if vehicle == null or other == null:
		return
	var mid := (vehicle.global_position + other.global_position) * 0.5
	var side := (other.global_position - vehicle.global_position).cross(Vector3.UP)
	if side.length() < 0.05:
		side = -vehicle.get_forward()
	spark.wind_streak(mid + Vector3.UP * TUNE.NEAR_MISS_HEIGHT, side.normalized(),
			relative_speed(other).length())


## The velocity of the car: the body velocity, or the movement of the car for the cars that are
## kinematic (the traffic cars do not move their body).
func carry_velocity() -> Vector3:
	if vehicle == null or not is_instance_valid(vehicle):
		return velocity
	if vehicle.linear_velocity.length() > 1.0:
		return vehicle.linear_velocity
	return velocity


## The speed of the car relative to the other one: the traffic cars do not write a velocity, so
## their speed is measured from their movement.
func relative_speed(other: Node3D) -> Vector3:
	var theirs := Vector3.ZERO
	if other is VehicleBase:
		theirs = (other as VehicleBase).linear_velocity
	return carry_velocity() - theirs


static func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
