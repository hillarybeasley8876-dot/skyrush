extends RefCounted
## The collision of the street furniture. The props are drawn as MultiMeshes, so their shapes
## are added to one StaticBody3D per 512 m tile through the physics server: there is no node
## per prop (the city has more than 30,000 of them).
##
## The bodies are on the prop layer (bit 2), with the mask 0: the cars drive on the mask 0b111,
## so they hit the props, and the props do not hit anything themselves.
##
## Two things made the props not solid for a long time: the shapes were freed with the (temporary)
## builder, so the bodies had no shape at all (test_prop_collision_orientation.gd checks the
## rays), and the boxes ignored the heading of the prop (a bus shelter or a noise wall that
## runs along the road had a box along the X axis of the world).

const Layers := preload("res://world/api/layers.gd")

## The size of a tile of the city.
const TILE := 512.0

## The shape of every prop kind: a cylinder ({"radius", "height"}) or a box ({"size"}).
const SHAPES: Dictionary = {
	"lamp": {"radius": 0.15, "height": 9.0},
	"lamp_heritage": {"radius": 0.15, "height": 9.0},
	"lamp_magnolia": {"radius": 0.15, "height": 9.0},
	"lamp_deck_double": {"radius": 0.20, "height": 11.0},
	"tree": {"radius": 0.25, "height": 3.0},
	"sign": {"radius": 0.08, "height": 3.0},
	"bollard": {"radius": 0.10, "height": 0.95},
	"bin": {"radius": 0.30, "height": 1.0},
	"hydrant": {"radius": 0.15, "height": 0.8},
	"bike_share": {"size": Vector3(2.0, 1.0, 0.6)},
	"e_scooter": {"radius": 0.30, "height": 1.2},
	"planter": {"size": Vector3(2.4, 0.9, 1.2)},
	"planter_pot_privet": {"size": Vector3(2.4, 0.9, 1.2)},
	"planter_pot_bougainvillea": {"size": Vector3(2.4, 0.9, 1.2)},
	"bus_stop": {"size": Vector3(8.0, 2.6, 1.8)},
	"neon_blade_frame": {"radius": 0.12, "height": 4.0},
	"shop_sign": {"radius": 0.16, "height": 3.4},
	"metro_entrance": {"size": Vector3(3.0, 1.2, 2.0)},
	"noise_wall": {"size": Vector3(30.0, 3.6, 0.35)},
	"billboard": {"size": Vector3(0.6, 9.0, 0.6)},
	"traffic_light": {"radius": 0.20, "height": 6.4},
	"gantry": {"size": Vector3(0.5, 7.0, 0.5)},
	"vms": {"size": Vector3(0.5, 7.0, 0.5)},
}

## The arm of a traffic light mast (the glb: 7.3 m long on -Z, at the top of the pole): its box, and how far under the top of
## the pole the box is.
const MAST_ARM_SIZE := Vector3(0.45, 0.45, 7.0)
const MAST_ARM_DROP := 0.25

## The bodies of the city, one per tile.
var _bodies: Dictionary = {}
## The shapes of the city, shared between the props of a kind.
var _shared_shapes: Dictionary = {}
## The number of shapes that were added.
var _count := 0


## The number of collision shapes that were added.
func count() -> int:
	return _count


## Adds the shape of every prop to the body of its tile.
func build(parent: Node3D, entries: Array[Dictionary]) -> int:
	for entry in entries:
		var type := String(entry.get("type", ""))
		if not SHAPES.has(type):
			continue
		var xform: Transform3D = entry.get("transform", Transform3D.IDENTITY)
		var stretch: Vector3 = entry.get("scale_vector", Vector3.ONE)
		var yaw := yaw_of(xform)
		for part in _parts_of(type, float(entry.get("height_m", 0.0)), stretch):
			_add(parent, xform.origin, yaw, part["shape"], part["offset"])
	# The bodies enter the tree at the end: a body that is in the tree is in the broadphase,
	# and every shape that is added to it costs a broadphase update.
	for key in _bodies.keys():
		var body: StaticBody3D = _bodies[key]
		# The physics server knows a shape by its RID only: the resource has to live as long as the body. The builder is a
		# temporary object and the shared shapes died with it, the server dropped them from the bodies and the 49,000 props of
		# the city had no collision at all (every body had 0 shapes). The bodies keep the shapes now.
		body.set_meta(&"shapes", _shared_shapes.values())
		parent.add_child(body)
	return _count


## The body of the tile of a point.
func _body_for(parent: Node3D, point: Vector3) -> StaticBody3D:
	var tile_x := int(floor(point.x / TILE))
	var tile_z := int(floor(point.z / TILE))
	var key := "%d_%d" % [tile_x, tile_z]
	if _bodies.has(key):
		return _bodies[key]
	var body := StaticBody3D.new()
	body.name = "PropCollision_" + key
	body.collision_layer = Layers.PROP
	body.collision_mask = 0
	body.position = Vector3(float(tile_x) * TILE, 0.0, float(tile_z) * TILE)
	_bodies[key] = body
	return body


## The yaw of a prop (its rotation about the vertical axis): the props stand upright, and the shapes turn with them.
static func yaw_of(xform: Transform3D) -> float:
	return atan2(-xform.basis.x.z, xform.basis.x.x)


## Adds one shape to the body of the tile of the prop. `offset` is in the frame of the prop (it turns with the yaw).
func _add(parent: Node3D, origin: Vector3, yaw: float, shape: Shape3D, offset: Vector3) -> void:
	var body := _body_for(parent, origin)
	var turn := Basis(Vector3.UP, yaw)
	var local := Transform3D(turn, origin + turn * offset - body.position)
	PhysicsServer3D.body_add_shape(body.get_rid(), shape.get_rid(), local)
	_count += 1


## The shapes of a prop kind: a cylinder for a pole, a box for a shelter or a wall, and a box
## for the arm of a traffic-light mast. The shapes are shared: the city has 48,000 props and
## there are only a dozen different shapes. `stretch` is the scale of the prop (a noise wall
## of 24 m is the wall of 30 m scaled by 0.8 on X).
func _parts_of(type: String, height_m: float, stretch: Vector3 = Vector3.ONE) -> Array[Dictionary]:
	var spec: Dictionary = SHAPES[type]
	var out: Array[Dictionary] = []
	if spec.has("size"):
		var size: Vector3 = (spec["size"] as Vector3) * stretch
		var box := _shared("box_%s" % str(size), func() -> Shape3D:
			var b := BoxShape3D.new()
			b.size = size
			return b)
		out.append({"shape": box, "offset": Vector3(0.0, size.y * 0.5, 0.0)})
		return out
	var height := float(spec.get("height", 9.0))
	if height_m > 0.1 and type.begins_with("lamp"):
		height = height_m
	var radius := float(spec.get("radius", 0.15))
	var cylinder := _shared("cyl_%.2f_%.2f" % [radius, height], func() -> Shape3D:
		var c := CylinderShape3D.new()
		c.radius = radius
		c.height = maxf(height, 0.2)
		return c)
	out.append({"shape": cylinder, "offset": Vector3(0.0, height * 0.5, 0.0)})
	if type == "traffic_light":
		# The arm of the mast: a box over the road. The glb has it on -Z of the pole (7.3 m, at the top).
		var arm := _shared("mast_arm", func() -> Shape3D:
			var a := BoxShape3D.new()
			a.size = Vector3(MAST_ARM_SIZE.x, MAST_ARM_SIZE.y, MAST_ARM_SIZE.z)
			return a)
		out.append({"shape": arm, "offset": Vector3(0.0, height - MAST_ARM_DROP, -MAST_ARM_SIZE.z * 0.5)})
	return out


## The shape of a key (the shapes are shared between the props).
func _shared(key: String, make: Callable) -> Shape3D:
	if _shared_shapes.has(key):
		return _shared_shapes[key] as Shape3D
	var shape := make.call() as Shape3D
	_shared_shapes[key] = shape
	return shape
