extends Node3D
## Pursuit breaker (ref/gameplay/DOSSIER.md §3.4): a gas-station canopy, a billboard or a
## scaffold whose `Support_*` nodes can be hit. A hit at 60 km/h or more collapses the
## structure in 1.2 s and wrecks the police inside the 25 x 12 m box behind it.

signal collapsed(by: Node3D)

const COLLAPSE_TIME := 1.2
const MIN_SPEED_KMH := 60.0
const ZONE_SIZE := Vector3(12.0, 8.0, 25.0)
const ZONE_OFFSET := Vector3(0.0, 0.0, -12.5)

## The label of the stunt this breaker gives.
var label := "加油站坍塌!"

var _structure: Node3D
var _supports: Array[Node3D] = []
var _zone_centre := Vector3.ZERO
var _zone_yaw := 0.0
var _collapsed := false
var _pending := false


## `structure` is the node that carries the `Support_*` children (the canopy, the billboard...).
func setup(structure: Node3D, zone_offset: Vector3 = ZONE_OFFSET) -> void:
	_structure = structure
	_zone_centre = structure.global_position + zone_offset
	_zone_yaw = structure.global_rotation.y
	for child in structure.find_children("Support_*", "Node3D", true, false):
		_supports.append(child as Node3D)
		_add_sensor(child as Node3D)
	if _supports.is_empty():
		# No named supports: treat the structure itself as the support.
		_supports.append(structure)
		_add_sensor(structure)


func _add_sensor(support: Node3D) -> void:
	var sensor := Area3D.new()
	sensor.name = "SupportHit"
	sensor.collision_layer = 0
	sensor.collision_mask = 1 << 1
	sensor.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 4.0, 1.6)
	shape.shape = box
	shape.position = Vector3(0, 2.0, 0)
	sensor.add_child(shape)
	sensor.body_entered.connect(_on_body_entered)
	support.add_child(sensor)


func _on_body_entered(body: Node3D) -> void:
	if _collapsed or _pending:
		return
	var vehicle := body as VehicleBase
	if vehicle == null or vehicle.get_speed_kmh() < MIN_SPEED_KMH:
		return
	_pending = true
	_trigger(vehicle)


## The structure starts falling at once and is down after COLLAPSE_TIME; the police in the zone
## behind it are wrecked when it lands.
func _trigger(vehicle: VehicleBase) -> void:
	for support in _supports:
		support.set_meta("collapsed", true)
		_disable_collision(support)
	_collapse_visual()
	var timer := get_tree().create_timer(COLLAPSE_TIME, false)
	timer.timeout.connect(_collapse.bind(vehicle))


func _collapse(vehicle: VehicleBase) -> void:
	if _collapsed:
		return
	_collapsed = true
	_wreck_police(vehicle)
	Events.stunt.emit(&"breaker", 500, label)
	collapsed.emit(vehicle)


## Wrecks every police car inside the 25 x 12 m box behind the breaker.
func _wreck_police(vehicle: VehicleBase) -> void:
	var source := vehicle if vehicle.team == VehicleBase.Team.PLAYER else Game.player
	for node in get_tree().get_nodes_in_group(&"police"):
		var police := node as VehicleBase
		if police == null or police.is_wrecked:
			continue
		if _in_zone(police.global_position):
			police.wreck(source)


func _in_zone(position: Vector3) -> bool:
	var local := (position - _zone_centre).rotated(Vector3.UP, -_zone_yaw)
	return absf(local.x) <= ZONE_SIZE.x * 0.5 and absf(local.z) <= ZONE_SIZE.z * 0.5 \
		and absf(local.y) <= ZONE_SIZE.y


func _collapse_visual() -> void:
	if _structure == null:
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_structure, "rotation_degrees:x", 74.0, COLLAPSE_TIME) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_IN)
	tween.tween_property(_structure, "position:y", _structure.position.y - 3.2, COLLAPSE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _disable_collision(node: Node3D) -> void:
	for child in node.find_children("*", "CollisionShape3D", true, false):
		(child as CollisionShape3D).disabled = true
	for child in node.find_children("*", "Area3D", true, false):
		# The monitoring of an area cannot be switched while it is inside a signal.
		(child as Area3D).set_deferred("monitoring", false)
