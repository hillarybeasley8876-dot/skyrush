class_name PoliceFleet
extends RefCounted
## The police fleet of the dossier §3.4 and §7.3, and the factory that builds a unit.
##
## The physics comes from the vehicle unit's CarSpec presets (the same car physics as the
## player, so a ram or a PIT is a real collision). Only the visual path is corrected here: the
## presets point at `patrol.glb` while the npc_cars unit ships `police_patrol.glb`.
##
## This module is the ONE place that instantiates a police car: the dispatcher, the spawner and
## the roadblock all build their units here.

## The role a unit plays. The dispatcher hands one out to every unit.
enum Role { PATROL, PURSUE, RAM, PIT, BOX_FRONT, BOX_SIDE, HEAD_ON }

## The scene of a police unit (preloaded: loading a scene inside the physics tick is a hitch).
const CAR_SCENE := preload("res://ai/police/police_car.tscn")

## The unit kinds and the preset / glb they use.
const KINDS: Dictionary = {
	&"patrol": {
		"spec": "res://vehicle/specs/patrol.tres",
		"glb": "res://assets/cars/npc/police_patrol.glb",
		"label": "巡逻车",
	},
	&"interceptor": {
		"spec": "res://vehicle/specs/interceptor.tres",
		"glb": "res://assets/cars/npc/police_interceptor.glb",
		"label": "拦截车",
	},
	&"heavy_suv": {
		"spec": "res://vehicle/specs/heavy_suv.tres",
		"glb": "res://assets/cars/npc/police_suv.glb",
		"label": "重型SUV",
	},
}

## The radius of the lane search when a unit is placed (m).
const LANE_SEARCH_RADIUS := 30.0
## The catch-up fairness of §6.3: a unit far behind gets a little more power, a unit that is on
## the player a little less.
const CATCHUP_FAR := 1.08
const CATCHUP_NEAR := 0.98
const CATCHUP_FAR_DISTANCE := 150.0
const CATCHUP_NEAR_DISTANCE := 20.0

static var _specs: Dictionary = {}


## The CarSpec of a unit kind. The vehicle preset is the source of truth; only the visual path is
## patched, because the npc_cars unit names the police glbs `police_*`.
static func spec_for(kind: StringName) -> CarSpec:
	if _specs.has(kind):
		return _specs[kind] as CarSpec
	var data := KINDS.get(kind, KINDS[&"patrol"]) as Dictionary
	var spec: CarSpec = null
	var path := String(data["spec"])
	if ResourceLoader.exists(path):
		spec = load(path) as CarSpec
	if spec == null:
		spec = CarSpec.new()
		spec.id = kind
		spec.mass = 1800.0
		spec.max_health = 60.0
		spec.top_speed = 63.889
	spec = spec.duplicate() as CarSpec
	var glb := String(data["glb"])
	if ResourceLoader.exists(glb):
		spec.visual_scene_path = glb
	_specs[kind] = spec
	return spec


## The unit kind a role drives at a heat level.
static func kind_for_role(role: Role, heat: int) -> StringName:
	match role:
		Role.PIT:
			return &"interceptor"
		Role.HEAD_ON:
			return &"heavy_suv"
		Role.BOX_FRONT, Role.BOX_SIDE:
			return &"patrol"
		_:
			# The ordinary chase units: interceptors take over from heat 3 on.
			return &"interceptor" if heat >= 3 else &"patrol"


## The top speed of a unit kind (m/s).
static func top_speed(kind: StringName) -> float:
	return spec_for(kind).top_speed


## The catch-up factor of a unit that is `gap` metres behind the player.
static func catchup_factor(gap: float) -> float:
	if gap > CATCHUP_FAR_DISTANCE:
		return CATCHUP_FAR
	if gap < CATCHUP_NEAR_DISTANCE:
		return CATCHUP_NEAR
	return 1.0


## The display name of a unit kind.
static func label_for(kind: StringName) -> String:
	var data := KINDS.get(kind, KINDS[&"patrol"]) as Dictionary
	return String(data["label"])


## Builds a unit and adds it to `host`. The caller places it and puts it to sleep.
##
## The unit starts its lane state at the place it is put, so a unit that is spawned 300 m away
## stays there instead of being snapped onto the player.
static func build_unit(host: Node, kind: StringName, role: Role, ctx: DriveContext,
		xform: Transform3D, seed_value: int, grid: LaneGrid) -> PoliceCar:
	var car := CAR_SCENE.instantiate() as PoliceCar
	if car == null:
		return null
	car.spec = spec_for(kind)
	car.kind = kind
	host.add_child(car)
	car.team = VehicleBase.Team.POLICE
	car.add_to_group("police")
	car.add_to_group("vehicles")
	place_unit(car, role, ctx, xform, seed_value, grid)
	return car


## Puts a unit on the road: its lane state, its role and the place it stands.
##
## The kind of a unit never changes: the pool builds the cars with their kind, so the visual of
## a pooled car is the one of its kind.
static func place_unit(car: PoliceCar, role: Role, ctx: DriveContext, xform: Transform3D,
		seed_value: int, grid: LaneGrid) -> void:
	if car == null:
		return
	var lane := 0
	var offset := 0.0
	if grid != null and ctx != null and ctx.graph != null and ctx.graph.lane_count() > 0:
		lane = grid.nearest_lane(xform.origin, LANE_SEARCH_RADIUS)
		if lane < 0:
			lane = 0
		offset = ctx.graph.closest_offset(lane, xform.origin)
	car.configure(ctx, car.kind, role, lane, offset, seed_value)
	car.global_transform = xform
