class_name ModeStatus
extends RefCounted
## The status of the running mode for the HUD (the contract of `Events.mode_status`).
##
## Every session owns one of these and pushes its status into it: the bus gets the status when
## the numbers changed and at least every HEARTBEAT seconds, so the HUD always has fresh numbers
## and the bus is not flooded with a status every frame.
##
## The data of a kind is compared as a whole: a changed number is a new status.

const HEARTBEAT := 0.5   ## s: the shortest time between two status pushes of the same kind

## The node that owns the status (the session that pushes it).
var _owner: Node = null
## The data of the last push of every kind.
var _last: Dictionary = {}
## The time since the last push of every kind (s).
var _waited: Dictionary = {}


## The status of a session: the owner is the node that pushes it.
func _init(owner: Node) -> void:
	_owner = owner


## Pushes the status of the mode.
##
## The bus gets it when the data of the kind changed or when the heartbeat is over. The delta is
## the time since the last push of the caller (the frame time of the session).
func push(kind: StringName, data: Dictionary, delta: float) -> void:
	# A session that is on its way out says nothing any more: the mode is over.
	if _owner != null and _owner.is_queued_for_deletion():
		return
	var waited := float(_waited.get(kind, 0.0)) + maxf(0.0, delta)
	if _last.has(kind) and _last[kind] == data and waited < HEARTBEAT:
		_waited[kind] = waited
		return
	_last[kind] = data
	_waited[kind] = 0.0
	Events.mode_status.emit(kind, data)
