extends Node
## Layout test: nothing overlaps and nothing leaves the screen at the three window shapes.
##
## Every screen is built in a stand-in viewport of 1920×1080, 1920×1200 and 2520×1080. The
## global rects of the visible texts and of the logo are collected and checked: no two of them
## may overlap, and none of them may leave the screen.
##
## Run: tools/godot.sh test res://ui/menu/tests/test_layout.gd

const MenuScreens := preload("res://ui/menu/menu_screens.gd")
const Logo := preload("res://ui/menu/widgets/logo.gd")

## The window shapes (1920×1080, 1920×1200 and 2520×1080).
const SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2520, 1080)]
## The screens that carry text.
const SCREENS: Array[StringName] = [&"title", &"main", &"race_setup", &"pursuit_setup",
	&"settings", &"controls", &"pause", &"results", &"loading"]
## Two texts may touch, but they may not overlap.
const OVERLAP_TOLERANCE := 2.0

var _fails: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for size in SIZES:
		for name in SCREENS:
			await _check_screen(name, size)
	print("LAYOUT TEST %s (%d failures)" % ["FAIL" if _fails > 0 else "PASS", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## Builds one screen in a stand-in viewport and checks every text and the logo.
func _check_screen(name: StringName, size: Vector2i) -> void:
	var host := Control.new()
	host.size = Vector2(size)
	add_child(host)
	var screen := MenuScreens.make(name)
	if screen == null:
		_expect(false, "%s builds" % name)
		host.queue_free()
		return
	host.add_child(screen)
	await get_tree().process_frame
	# The screens build their rows in on_enter() (the root calls it when the screen is pushed).
	screen.call("on_enter")
	await get_tree().process_frame
	await get_tree().process_frame

	var rects := _text_rects(screen)
	_expect(rects.size() > 0, "%s at %dx%d: %d texts" % [name, size.x, size.y, rects.size()])
	_expect(_inside(rects, size), "%s at %dx%d: every text is inside the screen" % [
		name, size.x, size.y])
	_expect(not _overlaps(rects), "%s at %dx%d: no two texts overlap" % [name, size.x, size.y])

	host.queue_free()
	await get_tree().process_frame


## The rects of the visible texts and of the logo, with their names.
func _text_rects(node: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if node is Label:
		var label := node as Label
		if label.visible and not label.text.is_empty():
			out.append({"rect": label.get_global_rect(), "name": label.text.substr(0, 16)})
	elif node.get_script() == Logo:
		var logo := node as Control
		if logo.visible:
			out.append({"rect": logo.get_global_rect(), "name": "SKYRUSH logo"})
	for child in node.get_children():
		out.append_array(_text_rects(child))
	return out


## True when every rect is inside the screen.
func _inside(rects: Array[Dictionary], size: Vector2i) -> bool:
	for entry: Dictionary in rects:
		var rect: Rect2 = entry["rect"]
		if rect.position.x < -1.0 or rect.position.y < -1.0:
			return false
		if rect.end.x > float(size.x) + 1.0 or rect.end.y > float(size.y) + 1.0:
			return false
	return true


## True when no two rects overlap.
func _overlaps(rects: Array[Dictionary]) -> bool:
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i]["rect"]
			var b: Rect2 = rects[j]["rect"]
			if a.grow(-OVERLAP_TOLERANCE).intersects(b.grow(-OVERLAP_TOLERANCE)):
				print("  overlap: \"%s\" %s and \"%s\" %s" % [
					rects[i]["name"], a, rects[j]["name"], b])
				return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_fails += 1
		print("FAIL ", label)
