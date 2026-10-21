class_name PoliceRoadblockProps
extends RefCounted
## The dressing of a roadblock: the barriers, the cone taper, the sign board and the invisible
## walls that keep the driver in.
##
## The module owns the props of the block (the props unit), so the block itself only owns the
## cars and the spike strip.

const BARRIER_SCENE := preload("res://assets/props/street/roadblock_barrier.glb")
const CONE_SCENE := preload("res://assets/props/street/cone.glb")
const SIGN_SCENE := preload("res://assets/props/street/police_sign_board.glb")

## The number of barriers on each side of the block.
const BARRIER_COUNT := 6
## The length of one barrier (m).
const BARRIER_LENGTH := 2.5
## A run shorter than this is not dressed with barriers (the car body covers it).
const BARRIER_MIN_RUN := 0.6
## The cone taper in front of the block: four rows of two cones.
const CONE_ROWS := 4
const CONE_FIRST := 4.0     ## m: the distance of the first row before the cars
const CONE_ROW_STEP := 9.0  ## m: the distance between the rows
const CONE_TAPER := 0.15    ## m per m: how fast the cone line opens up
## The distance of the two cones of the closed line (m).
const CONE_SPACING := 1.2
## The sign board in front of the block (m).
const SIGN_AHEAD := 40.0
## The margin of the sign board to the kerb (m).
const SIGN_MARGIN := 1.0
## The smallest margin the sign board keeps to the kerb (m).
const SIGN_MIN_MARGIN := 0.2
## The step the sign board moves inward when its place is not on the road (m).
const SIGN_STEP := 0.5
## The height of the down ray that checks a place on the road (m).
const ROAD_CHECK_HEIGHT := 6.0
## The road height a place has to have (m).
const ROAD_TOLERANCE := 0.3
## Nothing may stand over a place of a prop (m).
const ROAD_CLEAR_HEIGHT := 3.0
## The size of the invisible wall of a barrier run (m).
const WALL_HEIGHT := 0.9
const WALL_DEPTH := 0.95
const WALL_CENTRE_Y := 0.45

## The barriers of the block.
var barriers: Array[Node3D] = []
## The cones of the block.
var cones: Array[Node3D] = []
## The invisible walls of the barrier runs.
var walls: Array[StaticBody3D] = []
## The sign board of the block.
var sign: Node3D = null
## The middle of the gap of the block (the cone taper leads into it).
var gap_centre: float = 0.0


## Builds the props of the block (once: the block is pooled).
func build(host: Node3D) -> void:
	for i in BARRIER_COUNT * 2:
		barriers.append(_add_prop(host, BARRIER_SCENE))
	for i in CONE_ROWS * 2:
		cones.append(_add_prop(host, CONE_SCENE))
	sign = _add_prop(host, SIGN_SCENE)
	for i in 2:
		walls.append(_add_wall(host))


## Places the props in front of a block of a given width.
##
## `span` is the space a broadside car takes across the road (m).
func place(carriageway: float, slots: Array[float], gap: float, span: float) -> void:
	_place_barriers(carriageway, slots, span)
	_place_cones(carriageway, slots, gap, span)
	_place_sign(carriageway)


## The barriers of the props unit: they fill the space between the cars and the kerbs, so the
## only opening of the block is the gap.
##
## A barrier is never stretched: a stretched prop has a stretched texture (ART.md §8). Whole
## barriers are placed, so a run may overhang into the shoulder.
func _place_barriers(carriageway: float, slots: Array[float], span: float) -> void:
	var first := -carriageway * 0.5
	var last := carriageway * 0.5
	if not slots.is_empty():
		first = slots[0] - span * 0.5
		last = slots[slots.size() - 1] + span * 0.5
	var runs := [Vector2(-carriageway * 0.5, first), Vector2(last, carriageway * 0.5)]
	for side in 2:
		var run: Vector2 = runs[side]
		var length := absf(run.y - run.x)
		var count := 0
		if length >= BARRIER_MIN_RUN:
			count = mini(int(ceil(length / BARRIER_LENGTH)), BARRIER_COUNT)
		var total := float(count) * BARRIER_LENGTH
		var start := (run.x + run.y) * 0.5 - total * 0.5
		for i in BARRIER_COUNT:
			var barrier := barriers[side * BARRIER_COUNT + i]
			if i >= count:
				barrier.visible = false
				continue
			barrier.visible = true
			var at := start + (float(i) + 0.5) * BARRIER_LENGTH
			barrier.transform = Transform3D(Basis(Vector3.UP, 0.0), Vector3(at, 0.0, 0.0))
		var wall := walls[side]
		wall.visible = length > 0.05
		var wall_shape := wall.get_child(0) as CollisionShape3D
		if wall_shape != null:
			var box := wall_shape.shape as BoxShape3D
			if box != null:
				box.size = Vector3(maxf(length, 0.05), WALL_HEIGHT, WALL_DEPTH)
			wall_shape.position = Vector3((run.x + run.y) * 0.5, WALL_CENTRE_Y, 0.0)


## The cone taper in front of the block: the driver sees the gap coming.
##
## A block with a gap is marked by a taper that leads into the gap. A CLOSED block has no gap
## to lead into, so it gets a straight line of cones in front of it: the road is closed here.
func _place_cones(carriageway: float, slots: Array[float], gap: float, span: float) -> void:
	if gap <= 0.0:
		_place_closed_cones(carriageway)
		return
	gap_centre = 0.0
	if slots.size() >= 2:
		for i in slots.size():
			if i + 1 < slots.size() and slots[i + 1] - slots[i] > span + 0.5:
				gap_centre = (slots[i] + span * 0.5 + slots[i + 1] - span * 0.5) * 0.5
				break
	for row in CONE_ROWS:
		var along := CONE_FIRST + CONE_ROW_STEP * float(row)
		var offset := gap * 0.5 + CONE_TAPER * (along - CONE_FIRST)
		for side in 2:
			var cone := cones[row * 2 + side]
			cone.visible = true
			var x := gap_centre + (offset if side == 0 else -offset)
			cone.transform = Transform3D(Basis.IDENTITY, Vector3(x, 0.0, along))


## The straight cone line in front of a closed block: the road is closed here.
func _place_closed_cones(carriageway: float) -> void:
	var count := clampi(int(floor(carriageway / CONE_SPACING)), 2, cones.size())
	var total := float(count - 1) * CONE_SPACING
	var start := -total * 0.5
	for i in cones.size():
		var cone := cones[i]
		if i >= count:
			cone.visible = false
			continue
		cone.visible = true
		cone.transform = Transform3D(Basis.IDENTITY,
				Vector3(start + float(i) * CONE_SPACING, 0.0, CONE_FIRST))


## The sign board in front of the block, facing the driver (the face of the model points +Z).
##
## The sign stands at the kerb, but a kerb that is inside a building is no place for a sign:
## the place is checked with a down ray and moved inward when it is not on the road.
func _place_sign(carriageway: float) -> void:
	if sign == null:
		return
	sign.visible = true
	var x := carriageway * 0.5 - SIGN_MARGIN
	var limit := carriageway * 0.5 - SIGN_MIN_MARGIN
	while x > limit and not _road_spot_ok(x, SIGN_AHEAD):
		x -= SIGN_STEP
	sign.transform = Transform3D(Basis.IDENTITY, Vector3(x, 0.0, SIGN_AHEAD))


## True when the place of a prop is on the road: the ground is there and nothing stands over it.
func _road_spot_ok(x: float, z: float) -> bool:
	var world := sign.get_world_3d() if sign != null else null
	if world == null:
		return true
	var space := world.direct_space_state
	if space == null:
		return true
	var from := sign.global_position + Vector3(x, ROAD_CHECK_HEIGHT, z)
	var to := sign.global_position + Vector3(x, -ROAD_CHECK_HEIGHT, z)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		# No ground under the spot: the world does not tell, so the spot is taken.
		return true
	var ground := hit["position"] as Vector3
	if absf(ground.y - sign.global_position.y) > ROAD_TOLERANCE:
		return false
	var up := PhysicsRayQueryParameters3D.create(ground,
			ground + Vector3.UP * ROAD_CLEAR_HEIGHT, 1)
	up.collide_with_areas = false
	return space.intersect_ray(up).is_empty()


## Adds a prop of the props unit to the block.
func _add_prop(host: Node3D, scene: PackedScene) -> Node3D:
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	host.add_child(node)
	MaterialLibrary.apply(node)
	node.transform = Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO)
	return node


## The invisible wall of a barrier run: the barriers of the props unit have no collider, but the
## player must not drive through them.
func _add_wall(host: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "BarrierWall"
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, WALL_HEIGHT, WALL_DEPTH)
	shape.shape = box
	body.add_child(shape)
	host.add_child(body)
	return body
