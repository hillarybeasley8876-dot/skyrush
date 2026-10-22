class_name PoliceAftermath
extends RefCounted
## The aftermath of a bust or an escape: the end state stays a few seconds, so the toasts, the
## reward and the pursuit mode can read it. Then the pursuit goes back to "none" and the
## patrols fill the road again.
##
## The module owns the timer only: the dispatcher decides when the pursuit is reset.

## The seconds the aftermath lasts.
const AFTERMATH_SECONDS := 6.0

## The end state the timer is running for ("" = no aftermath).
var state: StringName = &""
## The seconds left before the pursuit goes back to "none".
var timer: float = 0.0


## The tick of the timer. Returns true when the aftermath is over and the pursuit has to go
## back to "none".
##
## A new end state starts the timer again, and every other state (a new chase, a reset, another
## world) clears it: the reset never kills a chase that has just begun.
func update(delta: float, pursuit_state: StringName) -> bool:
	if pursuit_state != &"busted" and pursuit_state != &"escaped":
		# The pursuit runs again (or it is over): there is no aftermath.
		state = &""
		timer = 0.0
		return false
	if pursuit_state != state:
		# A new end state: the aftermath starts again.
		state = pursuit_state
		timer = AFTERMATH_SECONDS
	timer -= delta
	if timer > 0.0:
		return false
	state = &""
	timer = 0.0
	return true
