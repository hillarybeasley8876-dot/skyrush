extends Node
## Global game state (autoload "Game"): active world/player, mode, command-line options, slow motion,
## pause and respawn. Core-owned.

const InputSetup := preload("res://core/input_setup.gd")

var world: WorldBase
var player: VehicleBase
## &"free", &"race", &"pursuit", &"menu".
var mode: StringName = &"free"
## Parsed user args after "--": "--key=value" -> {"key": "value"}, bare "--flag" -> {"flag": "true"}.
var options: Dictionary = {}

var _slowmo_until: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	options = _parse_args(OS.get_cmdline_user_args())
	InputSetup.register_actions()
	Events.slowmo_request.connect(_on_slowmo_request)


func _process(_delta: float) -> void:
	if _slowmo_until > 0.0 and _now() >= _slowmo_until:
		Engine.time_scale = 1.0
		_slowmo_until = 0.0


func option(key: String, default_value: String = "") -> String:
	return String(options.get(key, default_value))


func has_option(key: String) -> bool:
	return options.has(key)


## True once the world has its lanes, routes and spawns. The real world builds over several seconds
## (it exposes `loading_fraction` and emits Events.loading_progress(1.0, ...) when done); worlds
## without `loading_fraction` (the sandbox) are complete as soon as they are in the tree.
func world_built() -> bool:
	if world == null:
		return false
	return not ("loading_fraction" in world) or float(world.get("loading_fraction")) >= 1.0


## Await before asking the world for spawns, lanes or routes: `await Game.world_ready()`.
func world_ready() -> void:
	while not world_built():
		await Events.loading_progress


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	Events.game_paused.emit(paused)


func respawn_player() -> void:
	if player == null or world == null:
		return
	player.reset_to(world.nearest_road_transform(player.global_position))
	Events.player_respawned.emit()


func _on_slowmo_request(time_scale: float, duration: float, _focus: Node3D) -> void:
	Engine.time_scale = clampf(time_scale, 0.05, 1.0)
	_slowmo_until = _now() + duration


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func _parse_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = "true"
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out
