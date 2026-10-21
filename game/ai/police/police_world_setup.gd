class_name PoliceWorldSetup
extends RefCounted
## Puts the dispatcher on the world (CONTRACTS §4: the world is asked for its lanes, its points
## of interest and its spawns).
##
## The module owns the setup of the world of the dispatcher, so the dispatcher itself stays a
## dispatcher: the heat, the units and the rules.

## The dispatcher the setup belongs to.
var director: PoliceDirector = null
## The world of the game.
var world: WorldBase = null
## The player of the moment.
var player: VehicleBase = null


func _init(owner: PoliceDirector) -> void:
	director = owner


## Reads the world and gives the helpers their share of it.
##
## Returns false when the world is not there yet (the city builds over a few seconds).
func refresh() -> bool:
	world = Game.world
	player = Game.player
	if world == null:
		return false
	var lanes := world.get_lane_paths()
	if lanes.is_empty():
		return false
	var graph := LaneGraph.new()
	graph.build(lanes)
	director.events.player = player
	var ctx := _shared_context(graph)
	director.spawner.setup(ctx, world, director)
	director.spawner.contact = director.contact
	director.watch.setup(graph, director.spawner.grid)
	# The spawner keeps the units out of the roadblocks: a unit inside a block is stuck on it.
	director.spawner.blockade = director.blockade
	director.spawner.spots.blockade = director.blockade
	director.blockade.grid = director.spawner.grid
	director.blockade.setup(ctx, world, director)
	director.air.host = director
	director.air.strips = director.strips
	# The strips of the dispatcher are the strips of the blockade (the same list).
	director.blockade.stripper.list = director.strips
	director.spawner.rng.seed = director.random_seed()
	director.blockade.rng.seed = director.random_seed()
	director.pursuit.cache_hiding_spots(world)
	director.offences.on_player_appeared()
	if director.pool.is_built():
		director.pool.set_context(director.spawner.ctx)
	else:
		director.build_pool()
	return true


## The context the helpers share: the lane graph of the world and the player.
func _shared_context(graph: LaneGraph) -> DriveContext:
	var ctx := DriveContext.new()
	ctx.graph = graph
	ctx.world = world
	ctx.player = player
	if ctx.rng == null:
		ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = director.random_seed()
	return ctx
