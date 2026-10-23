class_name ModeDirector
extends Node3D
## The entry point of the modes unit: it starts a mode and owns the session of the running
## mode (free roam, race or pursuit).
##
## The API for the menu (the menu looks for a node with a `start_mode` method):
##   `start_mode(mode: StringName, options: Dictionary) -> bool`
##
## The options:
##   route       String  the id of the route (race)
##   laps        int     the number of laps (race, default: the laps of the route)
##   difficulty  String  "easy" | "normal" | "hard" (race)
##   player_slot int     the grid slot of the player (race, default: the last one)
##   goal        String  "escape" | "takedowns" (pursuit, default: "escape")
##   count       int     the number of police cars to take down (pursuit, default: 3)
##   time        float   the time limit in seconds (pursuit, default: 180)
##   heat        int     the heat the pursuit starts at (pursuit, default: 3)
##   police      bool    the police take part in a race (race, default: false)
##
## The city builds over several seconds: a mode that is asked for before the world is built is
## kept and started as soon as `Game.world_ready()` fires (see `_start_when_ready`).

## The records of the game (the best times, the best laps, the high score).
var records: GameRecords = GameRecords.new()
## The session of the running mode (null when no mode runs).
var session: Node = null
## The recovery of a lost player (a car in the river, under the map or far from every lane).
var out_of_bounds: OutOfBounds = OutOfBounds.new()
## The results of the last finished mode (a Dictionary for free roam, an Array for a race).
var last_results: Variant = {}
## The mode that is running.
var current_mode: StringName = &"free"
## True while a mode waits for the city to be built.
var loading: bool = false

const MODES: Array[StringName] = [&"free", &"race", &"pursuit"]


func _ready() -> void:
	records = GameRecords.new(Game.option("records", GameRecords.PATH))
	records.load_from_disk()
	var mode := Game.option("mode", "")
	if not mode.is_empty():
		start_mode(StringName(mode), {})
		return
	# Without a mode on the command line the game starts in free roam, so the score of the
	# run is counted even when the menu is skipped.
	if Game.option("skip-menu", "") == "true":
		start_mode(&"free", {})


## Puts a player that is lost back on the road (the river, the kill floor, the edges of the
## city). It runs in every mode: a race and a pursuit are played in the same world.
func _physics_process(delta: float) -> void:
	if Game.player == null or Game.world == null:
		return
	out_of_bounds.update(delta, Game.player, Game.world)


## Starts a mode. Returns false when the mode is unknown or cannot run.
##
## The mode name is checked right away. When the city is still building the request is kept and
## the mode starts as soon as the world is ready: the caller gets true for an accepted request.
func start_mode(mode: StringName, options: Dictionary) -> bool:
	if not MODES.has(mode):
		push_warning("[modes] unknown mode: %s" % mode)
		return false
	if not Game.world_built():
		_start_when_ready(mode, options)
		return true
	return _start_mode_now(mode, options)


## Keeps the request and starts the mode when the city is built.
func _start_when_ready(mode: StringName, options: Dictionary) -> void:
	loading = true
	Events.toast.emit("载入城市… LOADING CITY", &"info")
	await Game.world_ready()
	loading = false
	if not is_inside_tree():
		return
	_start_mode_now(mode, options)


## Starts the mode now (the world is built).
func _start_mode_now(mode: StringName, options: Dictionary) -> bool:
	var route: RaceRoute = null
	if mode == &"race":
		route = _pick_route(options)
		if route == null:
			push_warning("[modes] no route to race on")
			return false
	_stop_session()
	Game.mode = mode
	current_mode = mode
	match mode:
		&"free":
			_start_free(options)
		&"race":
			_start_race(route, options)
		&"pursuit":
			_start_pursuit(options)
	return true


## Free roam: the city, the traffic, the police and the score.
func _start_free(_options: Dictionary) -> void:
	_place_player_at_spawn()
	_set_police_enabled(true)
	var free_session := FreeSession.new()
	free_session.name = "FreeSession"
	add_child(free_session)
	free_session.setup(records)
	free_session.finished.connect(_on_session_finished)
	session = free_session


## A race: the grid, the countdown, the gates, the laps and the results.
func _start_race(route: RaceRoute, options: Dictionary) -> void:
	var laps := int(options.get("laps", route.laps))
	var difficulty := StringName(String(options.get("difficulty", "normal")))
	var race_session := RaceSession.new()
	race_session.name = "RaceSession"
	add_child(race_session)
	race_session.setup(route, laps, difficulty, Game.player, records,
		_rival_director(), options)
	race_session.finished.connect(_on_session_finished)
	session = race_session
	# The police stay out of a race unless the player asks for them.
	_set_police_enabled(bool(options.get("police", false)))


## A pursuit: the police at heat 2-3, the escape or the takedowns.
func _start_pursuit(options: Dictionary) -> void:
	_place_player_at_spawn()
	_set_police_enabled(true)
	var pursuit := PursuitSession.new()
	pursuit.name = "PursuitSession"
	add_child(pursuit)
	pursuit.setup(options)
	pursuit.finished.connect(_on_session_finished)
	session = pursuit


## The route of a race: the one of the options, or the first route of the world.
func _pick_route(options: Dictionary) -> RaceRoute:
	if not Game.world_built():
		push_error("[modes] the routes were asked for before the city was built")
		return null
	var route_id := String(options.get("route", ""))
	if not route_id.is_empty():
		var route := Game.world.get_route(StringName(route_id))
		if route != null:
			return route
		push_warning("[modes] unknown route '%s', the first route of the world is used" % route_id)
	var ids := Game.world.get_route_ids()
	if ids.is_empty():
		return null
	return Game.world.get_route(StringName(ids[0]))


## Puts the player at the spawn of the world (free roam and pursuit).
func _place_player_at_spawn() -> void:
	if not Game.world_built():
		push_error("[modes] the player was placed before the city was built")
		return
	if Game.player == null or Game.world == null:
		return
	Game.player.reset_to(RivalGrid.ground_spot(Game.world.get_spawn_transform(&"player", 0)))


## Ends the running mode and removes the rivals.
func _stop_session() -> void:
	if session != null and is_instance_valid(session):
		if session.has_method("build_results"):
			last_results = session.call("build_results")
		if session is PursuitSession:
			# A pursuit that is left leaves no chase behind.
			_stop_police()
		session.queue_free()
	session = null
	var director := _rival_director()
	if director != null and director.has_method("stop_race"):
		director.call("stop_race")


## The chase of a pursuit is over: the heat goes back to zero, the units leave the road and
## the police can spawn again.
func _stop_police() -> void:
	var police := PoliceLink.director(get_tree())
	PoliceLink.stop_pursuit(police)
	PoliceLink.set_spawn_enabled(police, true)


## The session reported its results.
func _on_session_finished(results: Variant) -> void:
	last_results = results


## The live order of the race: [{name, position, lap, gap}].
##
## The gap is the time gap to the leader (not the distance covered).
func standings() -> Array:
	var out: Array = []
	var race := session as RaceSession
	if race == null:
		return out
	for racer in race.racers:
		out.append({
			"name": racer.name,
			"position": racer.position,
			"lap": racer.lap,
			"gap": race.gap_to_leader(racer),
			"is_player": racer.is_player,
		})
	return out


## The rival director of the rivals unit (null when it is not loaded).
func _rival_director() -> Node:
	return _group_node(&"rival_director")


## Switches the police on or off (the police unit is optional).
func _set_police_enabled(enabled: bool) -> void:
	PoliceLink.set_spawn_enabled(PoliceLink.director(get_tree()), enabled)


## The node of a group (null when the unit is not loaded).
func _group_node(group: StringName) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(group)
