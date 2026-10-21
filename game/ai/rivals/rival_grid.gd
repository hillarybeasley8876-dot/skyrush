class_name RivalGrid
extends RefCounted
## The start grid of a race: the slots, the height the cars are placed at and the offset of
## the slots on the racing line.
##
## The grid is built from the **start gate of the route** (its own transform, -Z = the
## driving direction) and it steps back along the road behind it. The line of a city route
## does not always run through the checkpoint, and a grid that stands 90 m in front of the
## gate is a grid the field drives through before the race starts.
##
## The grid is walked back in two columns: the second column is a little further back, the
## way a real grid is staggered. Every slot is snapped onto the road of the world, so the
## cars stand on the tarmac and not in the air.
##
## The world spawn transforms put a car 0.6 m above the road. A car that lands from that
## height with the throttle open tumbles (the suspension bottoms out and the drive force
## pitches the car over), so every car of a race is placed on the road surface instead: a
## raycast finds the ground and the car is put a few centimetres above it.

const RIDE_HEIGHT := 0.04   ## m: the car origin is this far above the road
const ROW_GAP := 8.0        ## m between two rows of the grid
const COLUMN_BACK := 4.0    ## m the second column stands further back
const COLUMN_OFFSET := 3.0  ## m from the centre of the road (6 m between the columns)
const SLOT_COUNT := 6       ## the player and the five rivals
const ROAD_SNAP := 8.0      ## m: how far a slot may be moved onto the road of the world
const PROJECT_WINDOW := 60.0  ## m: the window of the projection of a slot onto the line


## Puts a transform on the road surface (the height comes from a raycast).
static func ground_spot(xform: Transform3D, world: WorldBase = null) -> Transform3D:
	if not Game.world_built():
		push_error("[rivals] a car was placed before the city was built")
		return xform
	var target := world if world != null else Game.world
	if target == null:
		return xform
	var height := target.ground_height(xform.origin)
	if is_nan(height):
		return xform
	var out := xform
	out.origin.y = height + RIDE_HEIGHT
	return out


## The start gate of the route (the first checkpoint); the identity when it has none.
static func start_gate(route: RaceRoute) -> Transform3D:
	if route == null or route.checkpoints.is_empty():
		return Transform3D.IDENTITY
	return route.checkpoints[0]


## The grid of a route: two columns behind the start gate of the route.
static func slots_of(route: RaceRoute, line: RivalLine, world: WorldBase = null,
		count: int = SLOT_COUNT) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if route == null or line == null:
		return out
	var gate := start_gate(route)
	for i in count:
		out.append(slot_at(i, gate, line, world))
	return out


## The offset on the racing line of the grid slot at `index` (negative: behind the start
## line). The offset is measured from the start gate.
static func offset_of(index: int, anchor: float = 0.0) -> float:
	var row := index / 2
	var column := index % 2
	return anchor - (ROW_GAP * float(row + 1) + COLUMN_BACK * float(column))


## The offsets on the racing line of the grid slots (m).
##
## The slots are projected onto the line near the start gate, so the cars know where they
## stand on it (the local projection of the brain would pick the wrong branch of a line
## that wanders back over the start).
static func offsets_of(route: RaceRoute, line: RivalLine,
		count: int = SLOT_COUNT) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if route == null or line == null:
		return out
	var gate := start_gate(route)
	var anchor := line.curve.get_closest_offset(gate.origin)
	for i in count:
		var slot := slot_at(i, gate, line, null)
		out.append(line.project(anchor, slot.origin, PROJECT_WINDOW))
	return out


## The slot of the grid at `index` (0 = pole).
##
## The slots stand behind the start gate, in two columns across the road. The road is
## followed back: the lane of the world under the slot gives the direction of the car.
static func slot_at(index: int, gate: Transform3D, line: RivalLine,
		world: WorldBase = null) -> Transform3D:
	var row := index / 2
	var column := index % 2
	var distance := ROW_GAP * float(row + 1) + COLUMN_BACK * float(column)
	var xform := _behind(gate, distance, world)
	# Across the road (the local +X of the basis is the right of the car).
	var right := xform.basis.x
	xform.origin += right * (COLUMN_OFFSET if column == 0 else -COLUMN_OFFSET)
	return ground_spot(xform, world)


## The spot `distance` metres behind the gate, on the road of the world.
static func _behind(gate: Transform3D, distance: float, world: WorldBase = null) -> Transform3D:
	var forward := -gate.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var point := gate.origin - forward * distance
	if Game.world_built():
		var target := world if world != null else Game.world
		if target != null:
			var road := target.nearest_road_transform(point)
			if road.origin.distance_to(point) <= ROAD_SNAP:
				point = road.origin
				var dir := -road.basis.z
				dir.y = 0.0
				if dir.length_squared() > 0.0001:
					forward = dir.normalized()
	var basis := Basis.looking_at(forward, Vector3.UP)
	return Transform3D(basis, point)
