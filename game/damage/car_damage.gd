extends RefCounted
## The damage state of one car: its tier, the damage it took per zone (which decides what
## comes off), the parts that already came off and the takedown credit of the player.

const DentPainter := preload("res://damage/dent_painter.gd")
const DamageFx := preload("res://damage/damage_fx.gd")

enum Tier { CLEAN, LIGHT, HEAVY, WRECKED }

## The zones of a car: the front, the rear, the sides and the roof.
const ZONE_FRONT := &"front"
const ZONE_REAR := &"rear"
const ZONE_SIDE := &"side"
const ZONE_TOP := &"top"

var vehicle: VehicleBase = null
var max_health: float = 100.0
var tier: int = Tier.CLEAN
## True when the car was wrecked: a car that comes out of its pool has to be made whole
## again, even when the pool repaired it before the signal.
var wrecked: bool = false
## The damage per zone (dossier §7.6 uses the front damage for the bumper).
var zone_damage: Dictionary = {}
## The glb node names of the parts that already came off.
var detached: Dictionary = {}
## The meshes of the parts that came off, so they can be put back on the respawn.
var detached_nodes: Dictionary = {}
## The time of the last contact with the player (the takedown credit, dossier §3.5).
var last_player_contact: float = -1000.0
## The speed of the car before the hit that wrecked it (the respawn speed, m/s).
var pre_crash_speed: float = 0.0
## The velocity of the car before the hit that wrecked it (the debris flies with it).
var pre_crash_velocity: Vector3 = Vector3.ZERO
## The horizontal heading of the car before the hit that wrecked it.
var pre_crash_heading: Vector3 = Vector3.FORWARD
## The side of the last hit (-1 = the left of the car, 1 = the right, 0 = the middle).
var last_hit_side: float = 0.0
## The impact ratio of the hit that wrecked the car (the wheels come off above 0.7).
var wreck_impact: float = 0.0
## The point of the hit that wrecked the car (the wheel that comes off is the nearest one).
var wreck_point: Vector3 = Vector3.ZERO
## True when the wreck was a vertical takedown (the player landed on the roof).
var vertical_credit: bool = false
## The dent painter of the car (null when it has no painted body).
var painter: DentPainter = null
## The collision box of the car in its local space: the centre and the half sizes. It is read
## once per car (the shape of a car does not change) and not on every hit.
var body_centre: Vector3 = Vector3.ZERO
var body_half: Vector3 = Vector3.ZERO
var body_known: bool = false
## The tier rig of the car (built when the car is hurt, not when it joins).
var fx: DamageFx = null
## The transforms of the parts that moved (the sprung doors), so the respawn can put them back.
var rest_transforms: Dictionary = {}
## The place of the visual of the car when it was whole: a violent wreck tilts it on the bare
## hub, so a car that comes out of its pool has to get it back.
var rest_visual: Transform3D = Transform3D.IDENTITY
var rest_visual_known: bool = false
## The parts that already sprang open (a door opens once, not on every hit).
var sprung: Dictionary = {}


func setup(car: VehicleBase) -> void:
	vehicle = car
	max_health = maxf(car.max_health, 1.0)
	zone_damage = {ZONE_FRONT: 0.0, ZONE_REAR: 0.0, ZONE_SIDE: 0.0, ZONE_TOP: 0.0}
	var visual := car.get_visual_root()
	if visual != null:
		rest_visual = visual.transform
		rest_visual_known = true


## The tier rig of the car, built the first time the car is hurt.
func ensure_fx() -> DamageFx:
	if fx != null:
		return fx
	if vehicle == null or not is_instance_valid(vehicle):
		return null
	fx = DamageFx.new()
	fx.name = "DamageFx"
	vehicle.add_child(fx)
	fx.setup(vehicle, vehicle.team == VehicleBase.Team.PLAYER)
	return fx


## The tier of a health value (dossier §7.4).
static func tier_of(health: float, max_hp: float) -> int:
	var ratio := health / maxf(max_hp, 1.0)
	if ratio <= 0.0:
		return Tier.WRECKED
	if ratio <= 0.30:
		return Tier.HEAVY
	if ratio <= 0.60:
		return Tier.LIGHT
	return Tier.CLEAN


## Adds the damage of a hit to its zone.
func add_zone_damage(zone: StringName, amount: float) -> void:
	if not zone_damage.has(zone):
		zone_damage[zone] = 0.0
	zone_damage[zone] = float(zone_damage[zone]) + amount


## The damage a zone has taken.
func zone_total(zone: StringName) -> float:
	return float(zone_damage.get(zone, 0.0))


## True when the part already came off.
func is_detached(node_name: StringName) -> bool:
	return detached.has(node_name)


## Marks a part as gone and remembers its meshes, so the respawn can put them back.
## `meshes` are the meshes of the part (the node, its children and its inner shell).
func mark_detached(node_name: StringName, node: MeshInstance3D = null,
		meshes: Array = []) -> void:
	detached[node_name] = true
	var group: Array = []
	for mesh in meshes:
		if mesh is MeshInstance3D:
			group.append(mesh)
	if group.is_empty() and node != null:
		group.append(node)
	if not group.is_empty():
		detached_nodes[node_name] = group


## Remembers where a part was, so the respawn can put it back.
func remember_rest(node_name: StringName, xform: Transform3D) -> void:
	rest_transforms[node_name] = xform


## True when the part already sprang open.
func is_sprung(node_name: StringName) -> bool:
	return sprung.has(node_name)


## Marks a part as sprung open.
func mark_sprung(node_name: StringName) -> void:
	sprung[node_name] = true


## The respawn: the car is whole again.
func reset() -> void:
	zone_damage = {ZONE_FRONT: 0.0, ZONE_REAR: 0.0, ZONE_SIDE: 0.0, ZONE_TOP: 0.0}
	detached.clear()
	for meshes: Array in detached_nodes.values():
		for node: MeshInstance3D in meshes:
			if node != null and is_instance_valid(node):
				node.visible = true
	detached_nodes.clear()
	for node_name: StringName in rest_transforms:
		var mesh := _mesh_of(node_name)
		if mesh != null and is_instance_valid(mesh):
			mesh.transform = rest_transforms[node_name]
	rest_transforms.clear()
	sprung.clear()
	pre_crash_speed = 0.0
	pre_crash_velocity = Vector3.ZERO
	wreck_impact = 0.0
	vertical_credit = false
	wrecked = false
	tier = Tier.CLEAN


## A car that comes out of its pool: it is a whole new car, the visual included (a violent
## wreck tilts it on the bare hub of the wheel that came off).
func recycle() -> void:
	reset()
	if not rest_visual_known or vehicle == null or not is_instance_valid(vehicle):
		return
	var visual := vehicle.get_visual_root()
	if visual != null:
		visual.transform = rest_visual


## The mesh of a part of the car.
func _mesh_of(node_name: StringName) -> MeshInstance3D:
	if vehicle == null or not is_instance_valid(vehicle):
		return null
	var visual := vehicle.get_visual_root()
	if visual == null:
		return null
	return visual.find_child(String(node_name), true, false) as MeshInstance3D
