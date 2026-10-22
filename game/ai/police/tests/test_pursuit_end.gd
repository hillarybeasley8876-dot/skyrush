extends Node
## The aftermath of a bust or an escape (job: police-lifecycle).
##
##   tools/godot.sh test res://ai/police/tests/test_pursuit_end.gd
##
## The pursuit state must stay "busted" / "escaped" for a few seconds (the toasts, the reward
## and the pursuit mode read the end state), then it goes back to "none": the screen is not
## dimmed any more, the pursuit panel is gone, the patrols fill the road again and a second
## chase can start.

const T := preload("res://ai/police/tests/police_test.gd")
const HudScene := preload("res://ui/hud/hud.tscn")
## The seconds the aftermath must still be running (the state is read after them).
const MID_WAIT := 3.0
## The seconds after which the pursuit must be over (the aftermath of the dispatcher is 6 s).
const END_WAIT := 7.0
## The seconds the test gives the patrols to come back.
const PATROL_WAIT := 40.0

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


## The whole suite.
func _run() -> void:
	var t := T.new(get_tree())
	await t.build(t.straight_start(-400.0))
	t.clear_traffic()
	# The player stands still on his lane, so the police can find a place to spawn.
	t.pinned = true
	t.pin_xform = t.straight_start(-400.0)
	var hud := await _make_hud()
	await _check_busted(t, hud)
	await _check_escaped(t, hud)
	await _check_second_chase(t)
	await _check_pursuit_in_aftermath(t)
	_finish(t)


## A bust: the dim and the panel stay, then the pursuit goes back to "none".
func _check_busted(t: T, hud: CanvasLayer) -> void:
	t.start_pursuit(1)
	t.check(t.director.pursuit_state == &"chase", "the pursuit starts in the chase state")
	await t.idle(0.3)
	t.check(_panel(hud).visible, "the pursuit panel is up during the chase")
	t.director._end_pursuit(&"busted")
	await t.idle(0.2)
	t.check(t.director.pursuit_state == &"busted", "the bust ends the pursuit")
	t.check(t.director.heat == 0, "the heat goes back to zero after the bust")
	t.check(_dim(hud).visible, "the screen is dimmed after the bust")
	t.check(_panel(hud).visible, "the pursuit panel is up after the bust")
	t.check(t.director.units.is_empty(), "the units leave the road after the bust")
	await t.idle(MID_WAIT)
	t.check(t.director.pursuit_state == &"busted",
			"the aftermath of the bust is still running after %.0f s" % MID_WAIT)
	t.check(t.director.units.is_empty(), "no unit spawns during the aftermath")
	await t.idle(END_WAIT - MID_WAIT)
	t.check(t.director.pursuit_state == &"none",
			"the pursuit goes back to none after %.0f s" % END_WAIT)
	t.check(not _dim(hud).visible, "the dim goes away with the pursuit")
	t.check(not _panel(hud).visible, "the pursuit panel goes away with the pursuit")
	await _wait_for_patrols(t)


## An escape: the same aftermath, without the dim.
func _check_escaped(t: T, hud: CanvasLayer) -> void:
	t.start_pursuit(1)
	await t.idle(0.3)
	t.director._end_pursuit(&"escaped")
	await t.idle(0.2)
	t.check(t.director.pursuit_state == &"escaped", "the escape ends the pursuit")
	t.check(t.director.heat == 0, "the heat goes back to zero after the escape")
	t.check(_panel(hud).visible, "the pursuit panel is up after the escape")
	await t.idle(MID_WAIT)
	t.check(t.director.pursuit_state == &"escaped",
			"the aftermath of the escape is still running after %.0f s" % MID_WAIT)
	await t.idle(END_WAIT - MID_WAIT)
	t.check(t.director.pursuit_state == &"none",
			"the pursuit goes back to none after %.0f s" % END_WAIT)
	t.check(not _panel(hud).visible, "the pursuit panel goes away after the escape")


## A chase can start again after the reset.
func _check_second_chase(t: T) -> void:
	t.start_pursuit(1)
	t.check(t.director.pursuit_state == &"chase", "a second chase starts after the reset")


## A pursuit that starts inside the aftermath is not killed by the reset.
func _check_pursuit_in_aftermath(t: T) -> void:
	# No unit spawns, so the player cannot be busted while the phase runs.
	t.director.spawn_enabled = false
	t.start_pursuit(1)
	t.director._end_pursuit(&"busted")
	await t.idle(0.2)
	t.check(t.director.pursuit_state == &"busted", "the aftermath starts again")
	t.start_pursuit(1)
	await t.idle(0.2)
	t.check(t.director.pursuit_state == &"chase", "a pursuit starts inside the aftermath")
	await t.idle(END_WAIT)
	t.check(t.director.pursuit_state != &"none",
			"the new pursuit is not reset by the aftermath")
	t.director.spawn_enabled = true


## Waits for the patrols to fill the road again.
func _wait_for_patrols(t: T) -> void:
	var waited := 0.0
	while waited < PATROL_WAIT and t.director.units.is_empty():
		await t.idle(1.0)
		waited += 1.0
	t.check(not t.director.units.is_empty(),
			"the patrols are back on the road (%.0f s)" % waited)


## The dim of the busted screen.
func _dim(hud: CanvasLayer) -> Control:
	return hud.get("busted_dim") as Control


## The pursuit panel.
func _panel(hud: CanvasLayer) -> Control:
	return hud.get("pursuit_panel") as Control


## Builds a HUD with a faked telemetry (the HUD needs a car to draw).
func _make_hud() -> CanvasLayer:
	var hud := HudScene.instantiate() as CanvasLayer
	add_child(hud)
	hud.set("telemetry_override", CarTelemetry.new())
	for i in 4:
		await get_tree().process_frame
	return hud


## Prints the summary and leaves the test.
func _finish(t: T) -> void:
	t.release_all()
	var own: Object = t.get("_own_log")
	if own != null and int(own.get("errors")) > 0:
		_failures += 1
		print("FAIL the suite ran without engine errors (%d in the police code)"
				% int(own.get("errors")))
	_failures += t.failures
	print("PURSUIT END TESTS %s (%d failures)" % ["OK" if _failures == 0 else "FAILED",
			_failures])
	get_tree().quit(1 if _failures > 0 else 0)
