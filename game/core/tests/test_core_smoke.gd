extends Node
## Core smoke test (example of the test convention): boots the sandbox + stub car through Modules
## and checks the contracts respond.
##
## The world builds itself over several frames, so the test waits for it before it asks for the lanes.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Modules.instantiate(&"world")
	add_child(world)
	for i in 900:
		await get_tree().process_frame
		if Game.world != null and Game.world.is_ready():
			break
	var ok: bool = Game.world != null and Game.world.is_ready() and Game.world.get_lane_paths().size() > 0
	print(("PASS" if ok else "FAIL") + " world provides lanes")
	get_tree().quit(0 if ok else 1)
