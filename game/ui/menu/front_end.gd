extends RefCounted
## What the front end owns while it is open: the camera (the title stage), the parked car, the
## hidden HUD and the menu music.
##
## The menu root calls `open()` and `close()`; everything that belongs to "the front end is up"
## lives here, so the root stays small.
##
## The world is built over several seconds: the car is only parked once the world is ready,
## because the spot is derived from the lanes (CONTRACTS §4: await Game.world_ready() before
## any WorldBase call at start-up).

const Bridge := preload("res://ui/menu/bridge.gd")
const TitleStage := preload("res://ui/menu/widgets/title_stage.gd")

## The HUD script of the hud unit, hidden while a menu screen is up.
const HUD_SCRIPT := "res://ui/hud/hud.gd"

var stage: TitleStage = null
## The car has been parked (the world was ready and the spot was derived).
var _parked: bool = false


## Opens the front end: the menu takes the camera, the car is parked, the HUD is hidden.
func open(tree: SceneTree) -> void:
	Game.mode = &"menu"
	_freeze_car(true)
	_set_hud_visible(tree, false)
	_ensure_stage(tree)
	Bridge.set_music(&"menu")
	# The world is still building: the car is parked when it is ready.
	_park_when_built()


## Closes the front end: the game camera comes back and the HUD returns.
func close(tree: SceneTree) -> void:
	if stage != null:
		stage.deactivate()
	_set_hud_visible(tree, true)
	_freeze_car(false)


## Parks the car again (the player quit to the menu from the middle of a session).
func repark() -> void:
	if stage == null or not is_instance_valid(stage):
		return
	if not stage.has_spot():
		stage.prepare()
	stage.park_the_car()
	_freeze_car(true)


## The stage takes the camera when the front end shows the city (not while the loading screen
## is on top of it).
func set_stage_active(active: bool) -> void:
	if stage == null or not is_instance_valid(stage):
		return
	if active:
		stage.activate()
	else:
		stage.deactivate()


## The title stage owns the menu camera. It is only created when the front end opens, so a run
## with --skip-menu never touches the game camera.
func _ensure_stage(tree: SceneTree) -> TitleStage:
	if stage == null or not is_instance_valid(stage):
		stage = TitleStage.new()
		# The root is busy while the game boots, so the stage is added a frame later.
		tree.root.add_child.call_deferred(stage)
	return stage


## The HUD belongs to the game, not to the front end: it is hidden while a menu screen is up.
## (The HUD unit is asked to do this itself when `Game.mode == "menu"` — see status/menu.md.)
func _set_hud_visible(tree: SceneTree, value: bool) -> void:
	if tree == null or tree.root == null:
		return
	var hud := Bridge.find_by_script(tree.root, HUD_SCRIPT)
	var layer := hud as CanvasLayer
	if layer != null:
		layer.visible = value


## The car is parked while the front end is up.
func _freeze_car(frozen: bool) -> void:
	var player := Game.player
	if player == null:
		return
	player.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	player.freeze = frozen


## Parks the car as soon as the world is built (before that there are no lanes to derive the
## spot from, and the car would stand in the traffic).
func _park_when_built() -> void:
	if _parked:
		return
	_parked = true
	await Game.world_ready()
	if stage == null or not is_instance_valid(stage):
		return
	stage.prepare()
	stage.park_the_car()
	_freeze_car(true)
