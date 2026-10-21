extends RefCounted
## Shared ground probe. One implementation of "where is the road under this point" for the fx
## unit: the skid marks (height + normal), the sparks and debris (bounce height), the rain
## splashes and the charge ground ring all use it.
##
## The raycast uses physics layer 1 (world) and must be called from a physics callback.

const RAY_MASK := 1
const START_HEIGHT := 2.0
const MAX_DROP := 60.0


## Probes the ground under `from`. Returns {hit: bool, point: Vector3, normal: Vector3}.
## The `exclude` list holds the RIDs of the bodies the ray must not hit (the car itself).
static func probe(space: PhysicsDirectSpaceState3D, from: Vector3,
		exclude: Array[RID] = []) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
			from + Vector3.UP * START_HEIGHT, from + Vector3.DOWN * MAX_DROP, RAY_MASK)
	if not exclude.is_empty():
		query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {"hit": false, "point": from, "normal": Vector3.UP}
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	return {"hit": true, "point": point, "normal": normal}


## Convenience: the ground height under `from`, or `fallback` when there is no ground.
static func height(space: PhysicsDirectSpaceState3D, from: Vector3, fallback: float) -> float:
	var result := probe(space, from)
	return (result["point"] as Vector3).y if result["hit"] else fallback


## The wheel contact patches of a car: the point on the road and the surface normal.
## The markers of the real car are used, with a fallback for the cars that have none.
static func wheel_contacts(vehicle: VehicleBase,
		markers: Array[StringName] = [&"Wheel_RL", &"Wheel_RR"]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if vehicle == null:
		return out
	var space := vehicle.get_world_3d().direct_space_state
	# The ray must not hit the car itself: it would report the bodywork as the road.
	var exclude: Array[RID] = [vehicle.get_rid()]
	for i in markers.size():
		var name: StringName = markers[i]
		var marker := vehicle.get_marker(name)
		var wheel := marker.global_position if marker != null else _fallback_wheel(vehicle, i)
		var result := probe(space, wheel, exclude)
		if result["hit"]:
			out.append({"point": result["point"], "normal": result["normal"]})
	return out


## The rear axle of a car that has no wheel markers.
static func _fallback_wheel(vehicle: VehicleBase, index: int) -> Vector3:
	var side := -0.85 if index == 0 else 0.85
	return vehicle.global_position + vehicle.global_transform.basis * Vector3(side, 0.0, 1.35)

