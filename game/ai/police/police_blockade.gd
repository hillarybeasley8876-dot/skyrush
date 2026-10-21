class_name PoliceBlockade
extends RefCounted
## The roadblocks of the pursuit (ref/gameplay/DOSSIER.md §6.3).
##
## The block stands on the predicted route of the player, 350-450 m ahead and out of sight: a
## roadblock site of the world when it lies on that route, otherwise the lane itself. The spike
## strips the units drop lie on the road as well: they are placed along the lane graph and
## snapped onto the road surface.
##
## From heat 5 the police close the toll plazas of the route (dossier §3.4).

const ROADBLOCK_INTERVAL := 22.0  ## s: the time between two roadblocks
const ROADBLOCK_MIN := 350.0      ## m: the block is at least this far ahead
const ROADBLOCK_MAX := 450.0      ## m: the block is at most this far ahead
## A roadblock site has to be this close to the route to be used (m).
const SITE_ROUTE_DISTANCE := 20.0
## The height of the down ray that snaps a strip onto the road (m).
const SNAP_HEIGHT := 8.0
## The heat of a closed toll plaza: the carriageway is closed.
const TOLL_HEAT := 5
## The site of the world has to face the player: this much of the direction of the route.
const SITE_FACING := 0.7

## False switches the automatic roadblocks off (the tests build their own blocks).
var auto_spawn: bool = true
## The shared AI context (the lane graph of the world).
var ctx: DriveContext = DriveContext.new()
## The lane grid of the world: the lanes that run beside the lane of the player.
var grid: LaneGrid = null
## The world of the game.
var world: WorldBase = null
## The node the blocks are added to.
var host: Node3D = null
## The shared random source.
var rng := RandomNumberGenerator.new()
## The pool of the police objects (the blocks and the strips come from it).
var pool: PolicePool = null
## The blocks on the road.
var blocks: Array[PoliceRoadblock] = []
## The spike strips on the road (the module of the strips).
var stripper: PoliceStrips = PoliceStrips.new()
## The time until the next block.
var timer: float = 0.0
## The toll plazas of the world (the police close them at heat 5).
var toll: PoliceToll = PoliceToll.new()
## The cars of the blocks on the road (they compete for the omni lights).
var block_cars: Array[PoliceCar] = []


## Prepares the blockade for a world.
func setup(context: DriveContext, world_node: WorldBase, host_node: Node3D) -> void:
	ctx = context
	world = world_node
	host = host_node
	toll.set_world(world_node)
	stripper.host = host_node


## The tick: the blocks age, the units drop strips and the toll plazas close at heat 5.
func update(delta: float, heat: int, player: VehicleBase, lane: int, lane_s: float) -> void:
	for i in range(blocks.size() - 1, -1, -1):
		var block := blocks[i]
		block.tick(delta, player)
		if block.is_expired():
			blocks.remove_at(i)
			_release_block(block)
			_rebuild_block_cars()
	if heat >= 4:
		_update_strips(delta, heat, player, lane, lane_s)
	if heat >= 5:
		_update_toll(delta, player)
	if heat < 2 or not auto_spawn:
		return
	timer -= delta
	if timer > 0.0:
		return
	timer = ROADBLOCK_INTERVAL
	spawn(heat, player, lane, lane_s)


## The units drop spike strips on the road ahead of the player (dossier §6.3).
func _update_strips(delta: float, _heat: int, player: VehicleBase, lane: int,
		lane_s: float) -> void:
	var spot := lane_spot_ahead(player, lane, lane_s, PoliceStrips.STRIP_AHEAD)
	stripper.update(delta, player, lane, lane_s, spot)


## Drops a strip on the route `distance` metres ahead of the player (the drone drops one).
func drop_strip(player: VehicleBase, lane: int, lane_s: float, distance: float) -> bool:
	var spot := lane_spot_ahead(player, lane, lane_s, distance)
	return stripper.drop(player, spot, true)


## True when a block stands near the point: a unit does not spawn inside a block.
func occupied(point: Vector3, radius: float) -> bool:
	for block in blocks:
		if block.global_position.distance_to(point) <= radius:
			return true
	return false


## Takes every block off the road (the tests).
func clear_blocks() -> void:
	for i in range(blocks.size() - 1, -1, -1):
		_release_block(blocks[i])
	blocks.clear()
	_rebuild_block_cars()


## Takes every strip off the road (the tests).
func clear_strips() -> void:
	stripper.clear()


## Rebuilds the list of the cars of the blocks (the omni lights compete with the driving units).
func _rebuild_block_cars() -> void:
	block_cars.clear()
	for block in blocks:
		block_cars.append_array(block.active_cars())


## Puts a block back into the pool.
func _release_block(block: PoliceRoadblock) -> void:
	if pool != null:
		pool.release_block(block)
	else:
		block.queue_free()


## The toll plazas of the route are closed at heat 5 (dossier §3.4).
func _update_toll(delta: float, player: VehicleBase) -> void:
	var plaza := toll.plaza_ahead(player, delta)
	if not bool(plaza["found"]):
		return
	_close_toll(plaza["position"], player)


## Closes a toll plaza: the cars of the block stand across every lane of the plaza.
func _close_toll(pos: Vector3, player: VehicleBase) -> bool:
	if toll.is_closed(pos):
		return false
	for block in blocks:
		if block.global_position.distance_to(pos) < PoliceToll.SAME_PLAZA:
			return false
	var road := toll.world.nearest_road_transform(pos) if toll.world != null \
			else world.nearest_road_transform(pos)
	var across := road.basis.x
	across.y = 0.0
	across = across.normalized()
	var forward := -road.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	# The block faces the player: the driver meets the cone taper first.
	if (player.global_position - road.origin).dot(forward) > 0.0:
		forward = -forward
	var lane := PoliceRoadWidth.lane_at(ctx.graph, road.origin)
	var s := ctx.graph.closest_offset(lane, road.origin)
	var width := PoliceRoadWidth.width_at(ctx.graph, grid, lane, s)
	var block := _take_block()
	if block == null:
		return false
	block.setup(Transform3D(Basis(across, Vector3.UP, -forward), road.origin), across, width,
			TOLL_HEAT, rng.randi())
	blocks.append(block)
	toll.close(pos)
	_rebuild_block_cars()
	PoliceRadio.say(&"roadblock")
	return true


## Sets up a roadblock on the predicted route of the player.
func spawn(heat: int, player: VehicleBase, lane: int, lane_s: float) -> bool:
	if host == null:
		return false
	var spot := _roadblock_spot(player, lane, lane_s)
	if spot.is_empty():
		return false
	# The block may only appear where the player cannot see it.
	if _visible(spot["transform"].origin):
		return false
	var block := _take_block()
	if block == null:
		return false
	block.setup(spot["transform"], spot["across"], float(spot["width"]), heat, rng.randi())
	blocks.append(block)
	_rebuild_block_cars()
	PoliceRadio.say(&"roadblock")
	return true


## Sets up a roadblock at a given distance in front of the player (the demo and the tests).
func spawn_at(heat: int, player: VehicleBase, lane: int, lane_s: float,
		distance: float) -> PoliceRoadblock:
	var spot := lane_spot_ahead(player, lane, lane_s, distance)
	if spot.is_empty():
		return null
	var block := _take_block()
	if block == null:
		return null
	block.setup(spot["transform"], spot["across"],
			PoliceRoadWidth.width_at(ctx.graph, grid, int(spot["lane"]), float(spot["s"])),
			heat, rng.randi())
	blocks.append(block)
	_rebuild_block_cars()
	return block


## Puts a strip on the road at a given distance in front of the player (the demo).
func spawn_strip_at(player: VehicleBase, lane: int, lane_s: float,
		distance: float) -> PoliceSpikeStrip:
	var spot := lane_spot_ahead(player, lane, lane_s, distance)
	if spot.is_empty():
		return null
	return stripper.add(spot["position"], spot["across"], false)


## Takes a block out of the pool.
func _take_block() -> PoliceRoadblock:
	if pool != null:
		return pool.take_block()
	var block := PoliceRoadblock.new()
	host.add_child(block)
	return block


## The place of the roadblock: a roadblock site of the world on the route, or the road itself.
func _roadblock_spot(player: VehicleBase, lane: int, lane_s: float) -> Dictionary:
	var graph := ctx.graph
	if world != null:
		var site := _site_on_route(player, lane, lane_s)
		if bool(site["found"]):
			var xform: Transform3D = site["transform"]
			var direction: Vector3 = site["direction"]
			# The block stands across the road and its front (the cone taper, the sign) faces
			# the driver: its +Z points back along the route, at the player.
			var right := direction.cross(Vector3.UP).normalized()
			var basis := Basis(right, Vector3.UP, -direction)
			# The width of the road at the site itself, not at the lane of the player.
			var site_lane := PoliceRoadWidth.lane_at(graph, xform.origin)
			var site_s := graph.closest_offset(site_lane, xform.origin)
			return {"transform": Transform3D(basis, xform.origin), "across": right,
				"width": PoliceRoadWidth.width_at(graph, grid, site_lane, site_s)}
	var ahead := lane_spot_ahead(player, lane, lane_s, ROADBLOCK_MIN)
	if ahead.is_empty():
		return {}
	ahead["across"] = graph.right_at(int(ahead["lane"]), float(ahead["s"]))
	ahead["width"] = PoliceRoadWidth.width_at(graph, grid, int(ahead["lane"]), float(ahead["s"]))
	return ahead


## The roadblock site of the world that lies on the predicted route of the player.
##
## The site has to face the traffic that comes at it (its -Z points at the driver), so the
## block meets the player the right way round.
##
## Returns {"found": bool, "transform": Transform3D, "direction": Vector3}.
func _site_on_route(player: VehicleBase, lane: int, lane_s: float) -> Dictionary:
	var route := PoliceRoute.route_points(ctx.graph, lane, lane_s, ROADBLOCK_MIN, ROADBLOCK_MAX)
	if route.size() < 2:
		return {"found": false, "transform": Transform3D.IDENTITY, "direction": Vector3.FORWARD}
	var best := Transform3D.IDENTITY
	var best_direction := Vector3.FORWARD
	var found := false
	var best_distance := SITE_ROUTE_DISTANCE
	for site in world.get_roadblock_sites():
		var index := _closest_route_index(route, site.origin)
		if index < 0:
			continue
		var direction := route[index + 1] - route[index]
		direction.y = 0.0
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		# The site has to face the traffic that comes at it.
		if site.basis.z.dot(direction) < SITE_FACING:
			continue
		var distance := site.origin.distance_to(route[index])
		if distance < best_distance:
			best_distance = distance
			best = site
			best_direction = direction
			found = true
	return {"found": found, "transform": best, "direction": best_direction}


## The index of the route point that is the closest to a place (-1 when there is none).
func _closest_route_index(route: Array[Vector3], point: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for i in route.size() - 1:
		var distance := route[i].distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## A spot on the road `distance` metres ahead of the player, snapped onto the road surface.
func lane_spot_ahead(player: VehicleBase, lane: int, lane_s: float, distance: float) -> Dictionary:
	var graph := ctx.graph
	if graph == null or lane < 0 or lane >= graph.lane_count():
		return {}
	var walk := PoliceRoute.walk(graph, lane, lane_s, distance)
	if not bool(walk["found"]):
		return {}
	var target_lane := int(walk["lane"])
	var s := float(walk["s"])
	var across := graph.right_at(target_lane, s)
	var point := graph.position_at(target_lane, s)
	# The block stands in the middle of the carriageway, not on the lane of the player.
	var centre := _road_centre_offset(graph, target_lane)
	return {"position": _snap_to_road(point), "across": across,
		"transform": graph.transform_at(target_lane, s, -centre), "lane": target_lane, "s": s}


## The offset of the middle of the carriageway from the centre of a lane (m).
func _road_centre_offset(graph: LaneGraph, lane: int) -> float:
	if graph == null or lane < 0 or lane >= graph.lane_count():
		return 0.0
	var left := graph.left_gap[lane] if graph.left[lane] >= 0 else 0.0
	var right := graph.right_gap[lane] if graph.right[lane] >= 0 else 0.0
	return (left - right) * 0.5


## Snaps a point onto the road surface with a down ray.
func _snap_to_road(point: Vector3) -> Vector3:
	if host == null:
		return point
	var space := host.get_world_3d().direct_space_state
	if space == null:
		return point
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * SNAP_HEIGHT,
			point - Vector3.UP * SNAP_HEIGHT, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return point
	return hit["position"] as Vector3


## True when the player can see the point: a block never appears in his view.
func _visible(point: Vector3) -> bool:
	if host == null:
		return false
	var camera := host.get_viewport().get_camera_3d()
	return PoliceSight.visible_to_player(camera, point)
