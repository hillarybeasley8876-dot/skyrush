class_name WorldBase
extends Node3D
## Contract for the playable world (the city, or the core sandbox). Modes, AI, HUD and the player
## query the world only through these methods. Game.world points at the active instance.

## kind: &"player", &"police", &"traffic", &"rival". index selects among several spawn points.
func get_spawn_transform(_kind: StringName, _index: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))


## Closest safe on-road transform (lane centre, -Z along traffic direction) for respawning.
func nearest_road_transform(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(pos.x, 1.0, pos.z))


## Where the player is put back on the road (a wreck, a reset): a lane near `pos` that runs along `direction` (horizontal), in
## the direction of its traffic, with a clear road ahead. The default is the nearest road transform.
func respawn_transform(pos: Vector3, _direction: Vector3) -> Transform3D:
	return nearest_road_transform(pos)


func get_lane_paths() -> Array[LanePath]:
	return []


func get_route_ids() -> PackedStringArray:
	return PackedStringArray()


func get_route(_id: StringName) -> RaceRoute:
	return null


## Road outlines for the HUD minimap, in world XZ metres (x = X, y = Z).
func get_minimap_polylines() -> Array[PackedVector2Array]:
	return []


## Points of interest: Array of {kind: StringName (&"charge", &"gas", &"toll", &"landmark",
## &"sky_lane", &"police_station"), position: Vector3, label: String}.
func get_points_of_interest() -> Array[Dictionary]:
	return []


## Where police can set up roadblocks (toll plaza lanes etc.); -Z faces oncoming player traffic.
func get_roadblock_sites() -> Array[Transform3D]:
	return []


## Traffic-light state for the approach of `road_id` into `junction_id`: 0 red, 1 amber, 2 green.
## Worlds without signals report green.
func signal_state(_junction_id: StringName, _road_id: StringName) -> int:
	return 2


## Ground height under a point (for flight altitude, FX), or NAN when nothing is below.
func ground_height(pos: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2.0, pos + Vector3.DOWN * 500.0, 1)
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3).y if hit else NAN
