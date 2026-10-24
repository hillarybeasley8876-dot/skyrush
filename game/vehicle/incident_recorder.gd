extends Node
## The incident recorder of the player car (debug builds): the last seconds of the car are kept, ten samples a second, and written
## to the log when the car does something no car should do in a normal drive: it hangs in the air without falling, it stays on
## its side or on its roof, or it is thrown up without a hop. A bug that a player meets once in an hour (a car that hung on the
## wall of a building, half transparent) cannot be found by a scripted test; the record says what the car touched and what
## happened before.
##
## The record is printed as "[incident] ..." lines (python tools/gd.py play writes the log to <env>/godot-logs).

## The samples kept: 6 s at 10 a second.
const SAMPLE_TIME := 0.1
const KEEP := 60
## Hanging: no wheel on the ground, the vertical speed under this (m/s), for this long (s), not in a sky lane, not hovering.
const HANG_VY := 1.0
const HANG_TIME := 1.0
## Tipped: the up axis of the car more than this from the vertical (degrees) for this long (s).
const TIP_DEG := 55.0
const TIP_TIME := 1.5
## Thrown: a vertical speed over this (m/s) without a hop.
const THROW_VY := 8.0
## After a record, the next one waits this long (s).
const COOLDOWN := 10.0

var _car: ArcadeCar = null
var _samples: Array[String] = []
var _clock := 0.0
var _next_sample := 0.0
var _hang := 0.0
var _tip := 0.0
var _quiet_until := 0.0
var _events: Array[String] = []


func _ready() -> void:
	_car = get_parent() as ArcadeCar
	Events.vehicle_collided.connect(_on_collided)
	Events.player_respawned.connect(func() -> void: _note("respawned"))
	Events.landed.connect(func(vehicle: VehicleBase, airtime: float, speed: float, _q: StringName) -> void:
		if vehicle == _car:
			_note("landed after %.1f s at %.1f m/s" % [airtime, speed]))


func _note(text: String) -> void:
	_events.append("t=%.1f %s" % [_clock, text])
	if _events.size() > 12:
		_events.remove_at(0)


func _on_collided(vehicle: VehicleBase, other: Node3D, impulse: float, _point: Vector3, normal: Vector3) -> void:
	if vehicle != _car or impulse < 2000.0:
		return
	_note("hit %s impulse %.0f normal (%.2f %.2f %.2f)" % [_name_of(other), impulse, normal.x, normal.y, normal.z])


func _name_of(node: Node) -> String:
	if node == null:
		return "?"
	var chain := String(node.name)
	var parent := node.get_parent()
	if parent != null and parent != get_tree().root:
		chain = String(parent.name) + "/" + chain
	return chain


func _physics_process(delta: float) -> void:
	if _car == null or not is_instance_valid(_car):
		return
	_clock += delta
	var grounded := 0
	for w in _car.wheels:
		if w.contact:
			grounded += 1
	var tilt := rad_to_deg(acos(clampf(_car.global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))
	var vy := _car.linear_velocity.y
	var free := not _car.telemetry.flying and not _car.telemetry.hovering
	_hang = _hang + delta if grounded == 0 and absf(vy) < HANG_VY and free else 0.0
	_tip = _tip + delta if tilt > TIP_DEG and free else 0.0
	if _clock >= _next_sample:
		_next_sample = _clock + SAMPLE_TIME
		_samples.append(_sample(grounded, tilt))
		if _samples.size() > KEEP:
			_samples.remove_at(0)
	if _clock < _quiet_until:
		return
	if _hang >= HANG_TIME:
		_record("hanging in the air (no wheel down, vy %.2f m/s, %.1f s)" % [vy, _hang])
	elif _tip >= TIP_TIME:
		_record("tipped over (%.0f degrees for %.1f s)" % [tilt, _tip])
	elif vy > THROW_VY and free and not _car.air.hop_flight:
		_record("thrown up (vy %.1f m/s without a hop)" % vy)


func _sample(grounded: int, tilt: float) -> String:
	var p := _car.global_position
	var v := _car.linear_velocity
	var normals := ""
	for w in _car.wheels:
		normals += ("%.2f " % w.contact_normal.y) if w.contact else "-- "
	var touching := ""
	var count := _car.get_contact_count()
	if count > 0:
		var names: Array[String] = []
		var state := PhysicsServer3D.body_get_direct_state(_car.get_rid())
		if state != null:
			for i in mini(state.get_contact_count(), 3):
				var collider := state.get_contact_collider_object(i) as Node
				names.append("%s n.y %.2f" % [_name_of(collider), state.get_contact_local_normal(i).y])
		touching = " touching [%s]" % ", ".join(names)
	return "t=%.1f p=(%.1f, %.2f, %.1f) v=(%.1f, %.1f, %.1f) tilt=%.0f wheels=%d [%s] hp=%.0f mask=%d alpha=%.2f%s" % [
		_clock, p.x, p.y, p.z, v.x, v.y, v.z, tilt, grounded, normals.strip_edges(), _car.health, _car.collision_mask,
		_alpha(), touching]


## The transparency of the car (a ghost after a respawn is half transparent).
func _alpha() -> float:
	var visual := _car.get_visual_root()
	if visual == null:
		return 0.0
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		return (child as GeometryInstance3D).transparency
	return 0.0


func _record(kind: String) -> void:
	_quiet_until = _clock + COOLDOWN
	print("[incident] %s at %s, time scale %.2f" % [kind, str(_car.global_position.snapped(Vector3.ONE * 0.1)),
		Engine.time_scale])
	for e in _events:
		print("[incident]   event ", e)
	for s in _samples:
		print("[incident]   ", s)
