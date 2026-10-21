extends RefCounted
## The collision of the street furniture. The props are drawn as MultiMeshes, so their shapes
## are added to one StaticBody3D per 512 m tile through the physics server: there is no node
## per prop (the city has more than 30,000 of them).
##
## The bodies are on the prop layer (bit 2), with the mask 0: the cars drive on the mask 0b111,
## so they hit the props, and the props do not hit anything themselves.

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
		for part in _parts_of(type, float(entry.get("height_m", 0.0))):
			_add(parent, xform, part["shape"], part["offset"], part["yaw"])
	# The bodies enter the tree at the end: a body that is in the tree is in the broadphase,
	# and every shape that is added to it costs a broadphase update.
	for key in _bodies.keys():
		parent.add_child(_bodies[key])
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


## Adds one shape to the body of the tile of the prop.
func _add(parent: Node3D, xform: Transform3D, shape: Shape3D, offset: Vector3,
		yaw: float) -> void:
	var body := _body_for(parent, xform.origin)
	var basis := Basis(Vector3.UP, yaw)
	var local := Transform3D(basis, xform.origin + offset - body.position)
	PhysicsServer3D.body_add_shape(body.get_rid(), shape.get_rid(), local)
	_count += 1


## The shapes of a prop kind: a cylinder for a pole, a box for a shelter or a wall, and a box
## for the arm of a traffic-light mast. The shapes are shared: the city has 48,000 props and
## there are only a dozen different shapes.
func _parts_of(type: String, height_m: float) -> Array[Dictionary]:
	var spec: Dictionary = SHAPES[type]
	var out: Array[Dictionary] = []
	if spec.has("size"):
		var size: Vector3 = spec["size"]
		var box := _shared("box_%s" % str(size), func() -> Shape3D:
			var b := BoxShape3D.new()
			b.size = size
			return b)
		out.append({"shape": box, "offset": Vector3(0.0, size.y * 0.5, 0.0), "yaw": 0.0})
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
	out.append({"shape": cylinder, "offset": Vector3(0.0, height * 0.5, 0.0), "yaw": 0.0})
	if type == "traffic_light":
		# The arm of the mast: a box over the road.
		var arm := _shared("mast_arm", func() -> Shape3D:
			var a := BoxShape3D.new()
			a.size = Vector3(0.5, 0.4, 4.5)
			return a)
		out.append({"shape": arm, "offset": Vector3(0.0, height - 0.4, 2.4), "yaw": 0.0})
	return out


## The shape of a key (the shapes are shared between the props).
func _shared(key: String, make: Callable) -> Shape3D:
	if _shared_shapes.has(key):
		return _shared_shapes[key] as Shape3D
	var shape := make.call() as Shape3D
	_shared_shapes[key] = shape
	return shape
