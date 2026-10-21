extends RefCounted
## The reaction of a car to a collision: the impact sparks, the body debris and the impact light.
##
## It lives outside the rig so the rig only drives the tyre effects (smoke, spray, skid marks).
## The severity is measured as delta-v (impulse / mass), the same convention as the vehicle unit.

const TUNE := preload("res://fx/fx_tuning.gd")
const PALETTE := preload("res://fx/fx_palette.gd")
const GROUND := preload("res://fx/fx_ground.gd")

const BIG_SPARKS := 90
const SMALL_SPARKS := 30
const BIG_SPEED := 6.0
const SMALL_SPEED := 4.0
## The glass shards and the plastic bits of a big hit.
const DEBRIS_GLASS := 14
const DEBRIS_PLASTIC := 10
const DEBRIS_SPEED := 8.0
## A hit in slow motion is oversized (the takedown presentation).
const SLOW_MO_SCALE := 2.0
const BIG_HIT_SCALE := 1.5


## The delta-v of a hit: how much the car lost in speed.
static func delta_v(impulse: float, mass: float) -> float:
	return impulse / maxf(mass, 100.0)


## True when the hit is hard enough to throw sparks.
static func is_significant(dv: float) -> bool:
	return dv >= TUNE.DV_SCRAPE


## The scale of the burst: a slow-motion hit is oversized, a big hit is a bit bigger.
static func burst_scale(dv: float) -> float:
	if Engine.time_scale < 0.7:
		return SLOW_MO_SCALE
	return BIG_HIT_SCALE if dv >= TUNE.DV_HIT else 1.0


## Throws the sparks, the debris and the light of an impact.
##
## The ground is probed once, at the point of the hit: every spark and every piece of debris
## bounces on that surface, so a hit on a deck does not throw its sparks through the deck.
static func burst(spark: Node, debris: Node, lights: Node, space: PhysicsDirectSpaceState3D,
		point: Vector3, normal: Vector3, dv: float, car_velocity: Vector3 = Vector3.ZERO) -> void:
	var big := dv >= TUNE.DV_HIT
	var scale := burst_scale(dv)
	var spawn_point := point + normal * TUNE.IMPACT_SURFACE_OFFSET
	var ground := point.y - 5.0
	if space != null:
		ground = GROUND.height(space, point, ground)
	if spark != null and is_instance_valid(spark):
		spark.burst(spawn_point, normal, BIG_SPARKS if big else SMALL_SPARKS,
				BIG_SPEED if big else SMALL_SPEED, scale, ground, car_velocity)
	if big and debris != null and is_instance_valid(debris):
		debris.burst(spawn_point, normal, DEBRIS_GLASS, DEBRIS_PLASTIC, scale, ground,
				car_velocity)
	if big and lights != null and is_instance_valid(lights):
		lights.flash(point, PALETTE.SPARK_HOT, TUNE.IMPACT_LIGHT_ENERGY, TUNE.IMPACT_LIGHT_RANGE,
				TUNE.IMPACT_LIGHT_TIME)
