extends RefCounted
## The bumper of a badly hurt car hangs at 25 degrees (dossier §7.4).
##
## It pivots on the lower corner AWAY from the hit and turns about the forward axis of the
## car, with 5 degrees of yaw, so the corner that was hit drops and the bumper does not
## sink into the road.

## The angle the bumper hangs at.
const HANG_ANGLE := 25.0
## The yaw of the hanging bumper.
const HANG_YAW := 5.0

var _hung: bool = false
var _rest: Transform3D = Transform3D.IDENTITY
var _node: MeshInstance3D = null


## Hangs the bumper of the car. `side` is the side of the last hit (-1 = the left of the
## car, 1 = the right, 0 = unknown).
func hang(car: VehicleBase, side: float) -> void:
	if _hung:
		return
	var bumper := car.get_marker(&"Bumper_F") as MeshInstance3D
	if bumper == null or bumper.mesh == null:
		return
	_hung = true
	_node = bumper
	_rest = bumper.transform
	var hit_side := signf(side)
	if absf(hit_side) < 0.01:
		hit_side = 1.0
	# The pivot: the lower corner of the bumper on the side away from the hit.
	var box := bumper.mesh.get_aabb()
	var pivot_local := Vector3(-hit_side * (box.position.x + box.size.x * 0.5), box.position.y,
			box.position.z + box.size.z * 0.5)
	# The axes of the car in the space of the node.
	var to_node := bumper.global_transform.basis.inverse() * car.global_transform.basis
	var forward := (to_node * Vector3.BACK).normalized()
	var up := (to_node * Vector3.UP).normalized()
	# The corner that was hit drops: the rotation about the forward axis is the other way.
	var rotation := Basis(forward, deg_to_rad(-hit_side * HANG_ANGLE)) * Basis(up,
			deg_to_rad(HANG_YAW))
	bumper.transform = _rotate_about(bumper, pivot_local, rotation)


## The bumper goes back where it was.
func reset() -> void:
	if not _hung or _node == null or not is_instance_valid(_node):
		return
	_hung = false
	_node.transform = _rest
	_node = null


## True while the bumper hangs.
func hanging() -> bool:
	return _hung


## Rotates a node about a pivot of its own space.
func _rotate_about(node: Node3D, pivot: Vector3, rotation: Basis) -> Transform3D:
	var moved: Vector3 = rotation * pivot
	return node.transform * Transform3D(rotation, moved - pivot)
