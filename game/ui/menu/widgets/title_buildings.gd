extends RefCounted
## The buildings of the world as boxes, and the geometry helpers the title spot needs.
##
## The city builds its blocks as meshes (a prism per lot, or the block assets of the city unit)
## and the buildings have no collider: a physics ray passes right through them. So the spot
## search finds them by their size and tests them as boxes.

## A mesh is a building when it is taller than this and wider than this.
const BUILDING_HEIGHT := 4.0
const BUILDING_WIDTH := 8.0
## A mesh that is wider than this covers a whole district (the terrain, a merged mesh).
const MERGED_SIZE := 120.0


## The boxes of the buildings of the world.
##
## A lamp, a tree or a sign is too small to be a building.
static func boxes_of(world: Node) -> Array[AABB]:
	var out: Array[AABB] = []
	if world == null:
		return out
	for node in _descendants(world):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if box.size.y < BUILDING_HEIGHT or maxf(box.size.x, box.size.z) < BUILDING_WIDTH:
			continue
		# The terrain and the merged meshes cover the whole city: they are no building.
		if box.size.x > MERGED_SIZE or box.size.z > MERGED_SIZE:
			continue
		out.append(box)
	return out


## Every node under a node (depth first).
static func _descendants(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


## The distance from a point to the buildings (zero when the point is inside one).
static func distance_to(point: Vector3, boxes: Array[AABB]) -> float:
	var best := INF
	for box: AABB in boxes:
		best = minf(best, distance_to_box(point, box))
	return best


## The distance from a point to a box (zero inside it).
static func distance_to_box(point: Vector3, box: AABB) -> float:
	var delta := Vector3(
		maxf(box.position.x - point.x, 0.0) + maxf(point.x - box.end.x, 0.0),
		maxf(box.position.y - point.y, 0.0) + maxf(point.y - box.end.y, 0.0),
		maxf(box.position.z - point.z, 0.0) + maxf(point.z - box.end.z, 0.0))
	return delta.length()


## True when a point stands inside one of the buildings.
static func inside(point: Vector3, boxes: Array[AABB]) -> bool:
	for box: AABB in boxes:
		if box.has_point(point):
			return true
	return false


## True when the segment from one point to another crosses one of the buildings.
static func crosses(from: Vector3, to: Vector3, boxes: Array[AABB]) -> bool:
	for box: AABB in boxes:
		if segment_hits_box(from, to, box):
			return true
	return false


## True when the segment from one point to another crosses the box (the slab method).
static func segment_hits_box(from: Vector3, to: Vector3, box: AABB) -> bool:
	var start := from - box.position
	var direction := to - from
	var near := 0.0
	var far := 1.0
	for axis in 3:
		var step: float = direction[axis]
		var origin: float = start[axis]
		var size: float = box.size[axis]
		if absf(step) < 0.0001:
			if origin < 0.0 or origin > size:
				return false
			continue
		var first := (0.0 - origin) / step
		var second := (size - origin) / step
		if first > second:
			var swap := first
			first = second
			second = swap
		near = maxf(near, first)
		far = minf(far, second)
		if near > far:
			return false
	return true
