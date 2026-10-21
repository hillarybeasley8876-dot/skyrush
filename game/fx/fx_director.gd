extends Node3D
## FX director (brief §1). Owns the world-space pools (skid ribbons, sparks, debris, lights,
## rain), attaches a rig to every vehicle and reacts to the game events.
##
## The rigs of the cars live in fx_rig_manager.gd, the event handlers in fx_events.gd, the
## world pools below.

const RigManager := preload("res://fx/fx_rig_manager.gd")
const CarRig := preload("res://fx/fx_car_rig.gd")
const EventsFx := preload("res://fx/fx_events.gd")
const GROUND := preload("res://fx/fx_ground.gd")
const SkidRibbon := preload("res://fx/fx_skid_ribbon.gd")
const SparkPool := preload("res://fx/fx_spark_pool.gd")
const DebrisPool := preload("res://fx/fx_debris_pool.gd")
const LightPool := preload("res://fx/fx_light_pool.gd")
const RainFx := preload("res://fx/fx_rain.gd")
const Dev := preload("res://fx/fx_dev.gd")
const TUNE := preload("res://fx/fx_tuning.gd")

const THRUSTER_SCENE := "res://fx/thrusters/thruster_system.tscn"
const LOD_INTERVAL := 0.2
const GROUND_INTERVAL := 0.25
const WET_THRESHOLD := 0.5
## The number of reduced cars in the worst case of the budget.
const WORST_REDUCED_CARS := 20
## The rate of the emitters of a REDUCED car (the tier of fx_car_rig.gd).
const REDUCED_RATIO := 0.3
## The highest particle quality (Settings.feature("particles") at the ultra preset).
const MAX_PARTICLE_QUALITY := 1.3

var _manager: RigManager
var _events: EventsFx
var _skid: SkidRibbon
var _spark: SparkPool
var _debris: DebrisPool
var _lights: LightPool
var _rain: RainFx
var _thrusters: Node = null
var _thruster_player: VehicleBase = null
var _thruster_warned: bool = false
var _lod_timer: float = 0.0
var _ground_timer: float = 0.0
var _ground_y: float = 0.0
var _weather: Node = null
var _rain_amount: float = 0.0
var _wetness: float = 0.85
## The dev switches (--fx-no-*): they switch one family of effects off.
var _dev: Dev


func _ready() -> void:
	name = "FxDirector"
	_dev = Dev.new()
	_skid = SkidRibbon.new()
	_skid.name = "SkidRibbon"
	add_child(_skid)
	_spark = SparkPool.new()
	_spark.name = "SparkPool"
	add_child(_spark)
	_debris = DebrisPool.new()
	_debris.name = "DebrisPool"
	add_child(_debris)
	_lights = LightPool.new()
	_lights.name = "LightPool"
	add_child(_lights)
	_rain = RainFx.new()
	_rain.name = "Rain"
	_rain.dev = _dev
	add_child(_rain)
	_manager = RigManager.new()
	_manager.setup(_skid, _spark, _debris, _lights, _particle_quality(), get_tree())
	_manager.dev = _dev

	_events = EventsFx.new()
	_events.name = "FxEvents"
	add_child(_events)
	_events.setup(_manager, _spark, _debris, _lights, _particle_quality())
	_events.dev = _dev
	_events.connect_events()

	get_tree().node_added.connect(_on_node_added)
	_setup_thrusters()
	for vehicle in _find_vehicles():
		_manager.attach(vehicle)
	_apply_quality()


## ---------------------------------------------------------------------------------------------
## Setup
## ---------------------------------------------------------------------------------------------

func _setup_thrusters() -> void:
	if _dev != null and _dev.no_thrusters:
		return
	if _thrusters != null or not ResourceLoader.exists(THRUSTER_SCENE):
		return
	var packed := load(THRUSTER_SCENE) as PackedScene
	if packed == null:
		push_warning("[fx] thruster scene could not be loaded")
		return
	var node := packed.instantiate() as Node
	if node == null or not node.has_method(&"attach"):
		# The thruster unit may be mid-edit: carry on without it instead of failing the run.
		push_warning("[fx] the thruster system could not be instantiated, continuing without it")
		return
	_thrusters = node
	_thrusters.name = "Thrusters"
	add_child(_thrusters)
	if Game.player != null and is_instance_valid(Game.player):
		_thruster_player = Game.player
	_attach_thruster(Game.player)


## The thruster system is owned by the fx_thrusters unit; call its attach in a way that works
## whether it takes the vehicle as an argument or finds the player itself.
func _attach_thruster(vehicle: Node) -> void:
	if _thrusters == null or vehicle == null:
		return
	for method in _thrusters.get_method_list():
		var name := StringName(method["name"])
		if name == &"attach_player" or name == &"attach_vehicle":
			_thrusters.call(name, vehicle)
			_report_thruster_state()
			return
		if name == &"attach":
			var args: Array = method.get("args", [])
			if args.size() >= 1:
				_thrusters.call(name, vehicle)
			else:
				_thrusters.call(name)
			_report_thruster_state()
			return


## The thruster unit may be mid-edit (its scripts may not compile): warn once instead of
## retrying every frame.
func _report_thruster_state() -> void:
	if _thruster_warned or not _thrusters.has_method(&"attached_count"):
		return
	if int(_thrusters.call(&"attached_count")) > 0:
		return
	_thruster_warned = true
	push_warning("[fx] the thruster system did not take the player (the fx_thrusters unit may be mid-edit)")


func _find_vehicles() -> Array[VehicleBase]:
	var out: Array[VehicleBase] = []
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		if node is VehicleBase:
			out.append(node as VehicleBase)
	for node in get_tree().root.find_children("*", "VehicleBase", true, false):
		if node is VehicleBase and not out.has(node as VehicleBase):
			out.append(node as VehicleBase)
	return out


## ---------------------------------------------------------------------------------------------
## Vehicle rigs
## ---------------------------------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is VehicleBase:
		_manager.attach(node as VehicleBase)


func _particle_quality() -> float:
	return clampf(float(Settings.feature("particles")), 0.2, MAX_PARTICLE_QUALITY)


## Scales the shared pools with the quality preset.
func _apply_quality() -> void:
	var quality := _particle_quality()
	_spark.set_quality(quality)
	_debris.set_quality(quality)


## ---------------------------------------------------------------------------------------------
## Frame loop
## ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	_skid.update(now)
	_spark.update(delta)
	_debris.update(delta)
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = LOD_INTERVAL
		_manager.update_lod()
	_ground_timer -= delta
	if _ground_timer <= 0.0:
		_ground_timer = GROUND_INTERVAL
		_update_ground()
	_update_weather()
	_update_thrusters()


func _update_ground() -> void:
	var world := Game.world
	if world == null:
		_ground_y = 0.0
	else:
		var probe := Game.player.global_position if Game.player != null and is_instance_valid(Game.player) else Vector3.ZERO
		var y := world.ground_height(probe)
		_ground_y = 0.0 if is_nan(y) else y


## Weather comes from the environment unit. Its weather controller lives in the "weather" group
## and publishes the same numbers it writes into the skyrush_rain / skyrush_wetness shader globals
## (rain_amount() / wetness()). We read them from there: RenderingServer.global_shader_parameter_get()
## is an editor-only call and logs an error (and warns about the performance) in a running game.
func _update_weather() -> void:
	if _weather == null or not is_instance_valid(_weather):
		_weather = get_tree().get_first_node_in_group(&"weather")
	if _weather != null:
		if _weather.has_method(&"rain_amount"):
			_rain_amount = float(_weather.call(&"rain_amount"))
		if _weather.has_method(&"wetness"):
			_wetness = float(_weather.call(&"wetness"))
	_rain.set_intensity(_rain_amount, _particle_quality(), bool(Settings.feature("rain")))
	var is_wet := _wetness > WET_THRESHOLD
	var rigs := _manager.rigs()
	for id in rigs:
		var rig: CarRig = rigs[id]
		if rig != null and is_instance_valid(rig):
			rig.set_wet(is_wet)


## The thruster system belongs to the fx_thrusters unit; keep it attached to the player even when
## the player is spawned or respawned after the director came up.
func _update_thrusters() -> void:
	if _thrusters == null:
		return
	var player := Game.player
	if player == null or not is_instance_valid(player) or player == _thruster_player:
		return
	_thruster_player = player
	_attach_thruster(player)


## ---------------------------------------------------------------------------------------------
## Budget helpers (used by the test)
## ---------------------------------------------------------------------------------------------

## The number of particles the fx unit is simulating right now.
func billboard_count() -> int:
	var total: int = _rain.billboard_count()
	total += _spark.live_count()
	total += _debris.live_count()
	for id in _manager.rigs():
		var rig: CarRig = _manager.rigs()[id]
		if rig != null and is_instance_valid(rig):
			total += rig.billboard_count()
	return total


## The worst case: the rain at full strength, every pool full, the player and the three
## nearest cars at full rate, twenty reduced cars and the thruster system of the fx_thrusters
## unit.
func worst_case_count() -> int:
	var total: int = TUNE.RAIN_MAX + TUNE.SPLASH_AMOUNT + TUNE.SPLASH_CROWN_AMOUNT
	total += TUNE.SPARK_MAX + TUNE.DEBRIS_GLASS + TUNE.DEBRIS_PLASTIC
	total += _rig_worst_case(1 + TUNE.NEAR_CARS, 1.0)
	total += _rig_worst_case(WORST_REDUCED_CARS, REDUCED_RATIO)
	total += _thruster_particles()
	return total


## The worst case of a number of rigs at `ratio` of their full rate (a REDUCED car runs its
## emitters at 30 %).
func _rig_worst_case(count: int, ratio: float) -> int:
	var rigs := _manager.rigs()
	var ids: Array = rigs.keys()
	var total := 0
	for i in mini(count, ids.size()):
		var rig: CarRig = rigs[ids[i]]
		if rig != null and is_instance_valid(rig):
			total += rig.worst_case_count(ratio)
	return total


## The particles of the thruster system (the fx_thrusters unit): the sum of the amounts of
## every emitter it owns.
func _thruster_particles() -> int:
	if _thrusters == null or not is_instance_valid(_thrusters):
		return 0
	var total := 0
	for child in _thrusters.find_children("*", "GPUParticles3D", true, false):
		var emitter := child as GPUParticles3D
		if emitter != null:
			total += emitter.amount
	return total


## The number of smoke / fire emitters that are running (gameplay DOSSIER §7.7: ≤ 8).
func active_emitter_count() -> int:
	var count := 0
	for id in _manager.rigs():
		var rig: CarRig = _manager.rigs()[id]
		if rig != null and is_instance_valid(rig):
			count += rig.active_emitter_count()
	return count


## The number of spray emitters that are running (they are counted apart from the budget of 8).
func active_spray_count() -> int:
	var count := 0
	for id in _manager.rigs():
		var rig: CarRig = _manager.rigs()[id]
		if rig != null and is_instance_valid(rig):
			count += rig.active_spray_count()
	return count


## Number of cars that currently have a rig (test hook).
func rig_count() -> int:
	return _manager.count()


## The shared pools (test hooks).
func skid_pool() -> Node3D:
	return _skid


func spark_pool() -> Node3D:
	return _spark


func debris_pool() -> Node3D:
	return _debris


func rain() -> Node3D:
	return _rain
