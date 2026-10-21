extends RefCounted
## The read-only view of the menu that the tests and the capture rig ask about.
##
## The menu root keeps the state; this helper answers the questions about it (which screens are
## on the stacks, what is selected, which camera renders the game).

const MenuScreen := preload("res://ui/menu/screens/menu_screen.gd")
const MenuStacks := preload("res://ui/menu/menu_stacks.gd")

var stacks: MenuStacks = null
var tree: SceneTree = null


func _init(menu_stacks: MenuStacks, scene_tree: SceneTree) -> void:
	stacks = menu_stacks
	tree = scene_tree


## The screen of that kind on either stack (the tests).
func screen(kind: String) -> Control:
	for item in stacks.front:
		if _kind_of(item) == kind:
			return item
	for item in stacks.overlay:
		if _kind_of(item) == kind:
			return item
	return null


## True when a screen of that kind is on the overlay stack.
func has(kind: String) -> bool:
	for item in stacks.overlay:
		if _kind_of(item) == kind:
			return true
	return false


## What is on the stacks right now (demo / tests).
func state() -> Dictionary:
	var active := stacks.active() as MenuScreen
	return {
		"front": stacks.names(stacks.front),
		"overlay": stacks.names(stacks.overlay),
		"mode": String(Game.mode),
		"paused": tree != null and tree.paused,
		"selection": active.debug_selection() if active != null else -1,
		"camera": camera_path(),
	}


## The path of the camera that is rendering the game right now.
func camera_path() -> String:
	if tree == null:
		return ""
	var camera := tree.root.get_viewport().get_camera_3d()
	if camera == null:
		return ""
	return String(camera.get_path())


## The kind of a screen ("" when it is not a menu screen).
func _kind_of(item: Control) -> String:
	var base := item as MenuScreen
	return String(base.kind) if base != null else ""
