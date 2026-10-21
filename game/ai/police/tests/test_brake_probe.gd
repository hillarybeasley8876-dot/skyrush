extends Node
## A temporary probe: how fast does the player brake?

const T := preload("res://ai/police/tests/police_test.gd")


func _ready() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-500.0))
	t.director.spawn_enabled = false
	for kmh in [30.0, 60.0, 90.0, 150.0]:
		t.player.reset_to(t.straight_start(-500.0))
		await t.drive(6.0, 0.0, kmh)
		var before := t.player.get_speed_kmh()
		Input.action_release(&"accelerate")
		Input.action_press(&"brake")
		await t.tree.physics_frame
		await t.tree.physics_frame
		await t.tree.physics_frame
		await t.tree.physics_frame
		var after := t.player.get_speed_kmh()
		print("BRAKEPROBE ", kmh, " km/h -> ", after, " after 4 ticks, decel=",
				(before - after) / 4.0 * 11.111, " m/s2, wheels=",
				t.player.telemetry.grounded_wheels)
		Input.action_release(&"brake")
	t.finish()
