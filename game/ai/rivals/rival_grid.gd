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
const GRID_LEAD := 4.0      ## m: the first row stands this far behind the start gate
const COLUMN_BACK := 4.0    ## m the second column stands further back
const COLUMN_OFFSET := 4.5  ## m from the centre of the road (9 m between the columns)
const SLOT_COUNT := 6       ## the player and the five rivals
const ROAD_SNAP := 8.0      ## m: how far a slot may be moved onto the road of the world
const WALK_STEP := 4.0      ## m: the step of the walk back along the road
const PROJECT_WINDOW := 60.0  ## m: the window of the projection of a slot onto the line
const CAR_BOX := Vector3(2.2, 0.6, 4.6)  ## m: the box of a car on the road
const BLOCK_MASK := 1 | 4     ## the world and the props block a spot of the grid
const BLOCK_STEP := 2.0       ## m: the step of the search for a free spot
const BLOCK_REACH := 24.0     ## m: how far a slot may be moved forward


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


## The grid of a route: the slots on the road behind the start gate of the route.
##
## The grid stands on the road of the world: the walk back follows the road, because the
## lead-in of the racing line is a straight line and on the Bund it runs into the
## buildings behind the start gate. The slots stand in the middle of the road, in two
## columns, so they are on the tarmac even when the line of the route runs in the
## footway of a boulevard.
##
## Without a line (a race without the rivals unit) the grid falls back to the slots behind
## the start gate of the route.
static func slots_of(route: RaceRoute, line: RivalLine, world: WorldBase = null,
		road: RivalRoad = null, count: int = SLOT_COUNT) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if route == null:
		return out
	if line == null or line.length < 1.0:
		return _gate_slots(route, world, count)
	var gate := start_gate(route)
	var anchor := line.curve.get_closest_offset(gate.origin)
	for i in count:
		var row := i / 2
		var column := i % 2
		var offset := anchor - (GRID_LEAD + ROW_GAP * float(row + 1)
				+ COLUMN_BACK * float(column))
		var point := line.point_at(offset)
		var forward := line.tangent_at(offset)
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		var xform := Transform3D(Basis.looking_at(forward, Vector3.UP), point)
		# The columns of the grid are counted in the road, and the road is measured at
		# the slot and not at the gate: the road of the world curves away from the line
		# of the route (on the Bund the line runs into the block behind the gate).
		var side := 0.0
		if road != null:
			var frame := road.road_frame(point, line, offset)
			if frame.x > -INF:
				side = frame.z
				side = clampf(side + (COLUMN_OFFSET if column == 0 else -COLUMN_OFFSET),
					frame.x + RivalRoad.ROAD_MARGIN, frame.y - RivalRoad.ROAD_MARGIN)
		if side == 0.0:
			side = (COLUMN_OFFSET if column == 0 else -COLUMN_OFFSET)
		xform.origin += line.right_at(offset) * side
		# A slot that stands in a building is moved forward: the grid stands on free
		# tarmac (the back row of the grid of the Bund stood inside a building and the
		# car in it never left the start line).
		xform = _free_spot(xform, line, offset, world)
		out.append(ground_spot(xform, world))
	return out


## Moves a slot that stands in a building forward, towards the start gate.
static func _free_spot(xform: Transform3D, line: RivalLine, offset: float,
		world: WorldBase) -> Transform3D:
	if not blocked(world, xform):
		return xform
	var forward := line.tangent_at(offset)
	var steps := int(BLOCK_REACH / BLOCK_STEP)
	for i in range(1, steps + 1):
		var moved := xform
		moved.origin += forward * BLOCK_STEP * float(i)
		if not blocked(world, moved):
			return moved
	return xform


## True when a car cannot stand at the spot: a building or a prop stands there.
static func blocked(world: WorldBase, xform: Transform3D) -> bool:
	if world == null or not Game.world_built():
		return false
	var space := world.get_world_3d().direct_space_state
	if space == null:
		return false
	var shape := BoxShape3D.new()
	shape.size = CAR_BOX
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = xform.translated(Vector3.UP * 0.5)
	params.collision_mask = BLOCK_MASK
	params.collide_with_bodies = true
	return not space.intersect_shape(params, 1).is_empty()


## The slots behind the start gate of the route (the fallback without a racing line).
static func _gate_slots(route: RaceRoute, world: WorldBase = null,
		count: int = SLOT_COUNT) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if route == null:
		return out
	var gate := start_gate(route)
	for i in count:
		out.append(slot_at(i, gate, null, world))
	return out


## The offset on the racing line of the grid slot at `index` (negative: behind the start
## line). The offset is measured from the start gate.
static func offset_of(index: int, anchor: float = 0.0) -> float:
	var row := index / 2
	var column := index % 2
	return anchor - (GRID_LEAD + ROW_GAP * float(row + 1) + COLUMN_BACK * float(column))


## The offsets on the racing line of the grid slots (m).
##
## The slots are projected onto the line near the start gate, so the cars know where they
## stand on it (the local projection of the brain would pick the wrong branch of a line
## that wanders back over the start). The slots are the ones the cars are placed on, so
## the offset of a car and the place it stands are the same.
static func offsets_of(route: RaceRoute, line: RivalLine,
		slots: Array[Transform3D]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if route == null or line == null:
		return out
	var gate := start_gate(route)
	var anchor := line.curve.get_closest_offset(gate.origin)
	for slot in slots:
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
	var distance := GRID_LEAD + ROW_GAP * float(row + 1) + COLUMN_BACK * float(column)
	var xform := _behind(gate, distance, world)
	# Across the road (the local +X of the basis is the right of the car).
	var right := xform.basis.x
	xform.origin += right * (COLUMN_OFFSET if column == 0 else -COLUMN_OFFSET)
	return ground_spot(xform, world)


## The spot `distance` metres behind the gate, on the road of the world.
##
## The walk back follows the road: the road of a roundabout curves away from the straight
## line behind the gate, and a slot that is placed on that straight line stands ten metres
## off the tarmac. On the Lujiazui ring two of the rivals stood in the footway that way and
## could not move at all: the throttle was open and the car did not go.
static func _behind(gate: Transform3D, distance: float, world: WorldBase = null) -> Transform3D:
	var forward := -gate.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var point := gate.origin
	var left := distance
	while left > 0.0:
		var step := minf(left, WALK_STEP)
		point -= forward * step
		left -= step
		if not Game.world_built():
			continue
		var target := world if world != null else Game.world
		if target == null:
			continue
		var road := target.nearest_road_transform(point)
		if road.origin.distance_to(point) > ROAD_SNAP:
			continue
		point = road.origin
		var dir := -road.basis.z
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			dir = dir.normalized()
			# The road is two way: the slot faces the way of the race.
			if dir.dot(forward) < 0.0:
				dir = -dir
			forward = dir
	var basis := Basis.looking_at(forward, Vector3.UP)
	return Transform3D(basis, point)
