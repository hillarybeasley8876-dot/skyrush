extends RefCounted
## The occupancy grid of the street furniture: two props may not stand inside each other. A tree
## grew through the roof of a bus shelter in the last review, because the filter only knew
## about the lanes, the junctions and the sites.
##
## The big props are placed first (the bus stops, the masts, the gantry posts, the trees), so
## they get the good places on the kerb; the small ones slide along the road until they find a
## free spot.

## The size of a cell of the grid, in metres. A prop is written into every cell its footprint
## covers, so a prop that is bigger than a cell is still found by the props next to it.
const CELL := 2.0

## The footprint of a prop kind: a radius (in metres) or an oriented box (width, depth).
const FOOTPRINT: Dictionary = {
	"bus_stop": {"size": Vector2(8.4, 2.0)},
	"tree": {"radius": 1.2},
	"lamp": {"radius": 0.5},
	"lamp_heritage": {"radius": 0.5},
	"lamp_magnolia": {"radius": 0.5},
	"lamp_deck_double": {"radius": 0.6},
	"traffic_light": {"radius": 0.6},
	"gantry": {"radius": 0.6},
	"vms": {"radius": 0.6},
	"sign": {"radius": 0.4},
	"billboard": {"radius": 0.6},
	"noise_wall": {"radius": 0.5},
	"neon_blade_frame": {"radius": 0.4},
	"shop_sign": {"radius": 0.4},
	"metro_entrance": {"radius": 1.0},
	"planter": {"radius": 0.6},
	"planter_pot_privet": {"radius": 0.6},
	"planter_pot_bougainvillea": {"radius": 0.6},
	"bin": {"radius": 0.4},
	"bollard": {"radius": 0.4},
	"hydrant": {"radius": 0.4},
	"bike_share": {"size": Vector2(2.0, 1.0)},
	"e_scooter": {"radius": 0.4},
}

## The order the props are placed in: the big ones first.
const ORDER: Array[String] = [
	"bus_stop", "traffic_light", "gantry", "tree", "billboard", "noise_wall",
	"metro_entrance", "planter_pot_bougainvillea", "planter_pot_privet", "planter",
	"lamp_deck_double", "lamp_magnolia", "lamp_heritage", "lamp", "vms",
	"neon_blade_frame", "shop_sign", "sign", "bike_share",
	"e_scooter", "bin", "bollard", "hydrant",
]

## The cells of the grid: the props that stand in them.
var _cells: Dictionary = {}
## The number of props that were placed.
var _placed := 0


## The number of props that were placed.
func placed() -> int:
	return _placed


## The radius of the footprint of a kind (the box of a bus stop uses its half depth).
static func radius_of(kind: String) -> float:
	var spec: Dictionary = FOOTPRINT.get(kind, {"radius": 0.4})
	if spec.has("radius"):
		return float(spec["radius"])
	var size: Vector2 = spec["size"]
	return size.y * 0.5


## The rank of a kind in the placement order (the big props come first).
func rank(kind: String) -> int:
	var index := ORDER.find(kind)
	return index if index >= 0 else ORDER.size()


## True when a prop of this kind may stand at the point.
func is_free(position: Vector3, kind: String) -> bool:
	var spec: Dictionary = FOOTPRINT.get(kind, {"radius": 0.4})
	for other in _near(position, _reach(spec)):
		if _overlaps(position, spec, other, kind):
			return false
	return true


## Puts a prop of this kind at the point. The prop is written into every cell its footprint
## covers: a tree covers the cells around it, so a sign that stands next to it finds it.
func reserve(position: Vector3, kind: String, yaw: float = 0.0) -> void:
	var spec: Dictionary = FOOTPRINT.get(kind, {"radius": 0.4})
	for key in _cell_keys(position, spec, yaw):
		if not _cells.has(key):
			_cells[key] = []
		(_cells[key] as Array).append({
			"position": position, "spec": spec, "kind": kind, "yaw": yaw,
		})
	_placed += 1


## The cells of the grid that the footprint of a prop covers.
func _cell_keys(position: Vector3, spec: Dictionary, yaw: float = 0.0) -> Array:
	var out: Array = []
	if spec.has("radius"):
		var span := int(float(spec["radius"]) / CELL) + 1
		var cx := int(floor(position.x / CELL))
		var cz := int(floor(position.z / CELL))
		for dx in range(-span, span + 1):
			for dz in range(-span, span + 1):
				out.append(_cell_key_int(cx + dx, cz + dz))
		return out
	# The box of a shelter is turned with the road.
	var size: Vector2 = spec["size"]
	var half := size * 0.5
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		var world: Vector2 = corner.rotated(yaw) + Vector2(position.x, position.z)
		min_x = minf(min_x, world.x)
		max_x = maxf(max_x, world.x)
		min_z = minf(min_z, world.y)
		max_z = maxf(max_z, world.y)
	for gx in range(int(floor(min_x / CELL)) - 1, int(floor(max_x / CELL)) + 2):
		for gz in range(int(floor(min_z / CELL)) - 1, int(floor(max_z / CELL)) + 2):
			out.append(_cell_key_int(gx, gz))
	return out


## The place where a prop of this kind stands: the point itself, or the first free point along
## the road. Returns null when there is no room.
func place(position: Vector3, kind: String, tangent: Vector3) -> Variant:
	if is_free(position, kind):
		return position
	var along := tangent
	along.y = 0.0
	if along.length_squared() < 0.0001:
		return null
	along = along.normalized()
	for step in SLIDES:
		var candidate := position + along * step
		if is_free(candidate, kind):
			return candidate
		var other := position - along * step
		if is_free(other, kind):
			return other
	return null


## The slides along the road that are tried when a prop does not fit.
const SLIDES: Array[float] = [1.2, -1.2, 2.4, -2.4, 3.6, -3.6, 5.0, -5.0, 7.0, -7.0,
	9.0, -9.0, 12.0, -12.0, 15.0, -15.0, 19.0, -19.0, 24.0, -24.0]


## The props that stand near a point.
func _near(position: Vector3, reach: float) -> Array:
	var out: Array = []
	var span := int(reach / CELL) + 1
	var cx := int(floor(position.x / CELL))
	var cz := int(floor(position.z / CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := _cell_key_int(cx + dx, cz + dz)
			if not _cells.has(key):
				continue
			for other in _cells[key] as Array:
				out.append(other)
	return out


## How far the footprint of a kind reaches.
func _reach(spec: Dictionary) -> float:
	if spec.has("radius"):
		return float(spec["radius"]) + CELL
	var size: Vector2 = spec["size"]
	return size.length() * 0.5 + CELL


## True when the prop at `position` overlaps the other prop.
func _overlaps(position: Vector3, spec: Dictionary, other: Dictionary, kind: String) -> bool:
	var other_spec: Dictionary = other["spec"]
	var other_position: Vector3 = other["position"]
	var other_yaw := float(other.get("yaw", 0.0))
	if spec.has("radius") and other_spec.has("radius"):
		var distance := Vector2(other_position.x - position.x, other_position.z - position.z).length()
		return distance < float(spec["radius"]) + float(other_spec["radius"])
	if spec.has("radius"):
		return _circle_box(Vector2(position.x, position.z), float(spec["radius"]),
			Vector2(other_position.x, other_position.z), other_spec["size"], other_yaw)
	if other_spec.has("radius"):
		return _circle_box(Vector2(other_position.x, other_position.z),
			float(other_spec["radius"]), Vector2(position.x, position.z), spec["size"], 0.0)
	return _boxes_overlap(Vector2(position.x, position.z), spec["size"], 0.0,
		Vector2(other_position.x, other_position.z), other_spec["size"], other_yaw)


## The overlap of a circle and an oriented box.
func _circle_box(centre: Vector2, radius: float, box: Vector2, size: Vector2,
		yaw: float) -> bool:
	var local := (centre - box).rotated(-yaw)
	var half := size * 0.5
	var clamped := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	return (local - clamped).length() < radius


## The overlap of two oriented boxes (the separating axis theorem).
func _boxes_overlap(a: Vector2, a_size: Vector2, a_yaw: float, b: Vector2, b_size: Vector2,
		b_yaw: float) -> bool:
	for axis in [_axes(a_yaw), _axes(b_yaw)]:
		for direction in axis:
			var ra := _projected(a, a_size, a_yaw, direction)
			var rb := _projected(b, b_size, b_yaw, direction)
			if absf((b - a).dot(direction)) > ra + rb:
				return false
	return true


## The two axes of an oriented box.
func _axes(yaw: float) -> Array:
	var forward := Vector2(cos(yaw), sin(yaw))
	var right := Vector2(-forward.y, forward.x)
	return [forward, right]


## The half width of a box along a direction.
func _projected(centre: Vector2, size: Vector2, yaw: float, direction: Vector2) -> float:
	var forward := Vector2(cos(yaw), sin(yaw))
	var right := Vector2(-forward.y, forward.x)
	return absf(size.x * 0.5 * forward.dot(direction)) + absf(size.y * 0.5 * right.dot(direction))


static func _cell_key(position: Vector3) -> int:
	return _cell_key_int(int(floor(position.x / CELL)), int(floor(position.z / CELL)))


## The key of a cell of the grid (an integer: a string key costs a format per lookup, and the
## city has millions of lookups).
static func _cell_key_int(cx: int, cz: int) -> int:
	return (cx + 32768) * 65536 + (cz + 32768)
