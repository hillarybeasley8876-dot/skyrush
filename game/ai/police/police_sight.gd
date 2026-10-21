class_name PoliceSight
extends RefCounted
## The line of sight of the police (ref/gameplay/DOSSIER.md §3.4).
##
## Every 0.2 s a ray goes from the roof of a unit (1.6 m) to the roof of the player; the ground
## units see 220 m, the drone 350 m. The ray only stops at the world (buildings, decks), so a
## player who hides behind a block is out of sight.

const ROOF_HEIGHT := 1.6   ## m: the height of the eye of a ground unit
const PLAYER_HEIGHT := 1.0 ## m: the height of the roof of the player
const INTERVAL := 0.2       ## s: the time between two sight checks
const GROUND_RANGE := 220.0 ## m: how far a ground unit sees
const DRONE_RANGE := 350.0  ## m: how far the drone sees
## The physics layer of the world (the buildings that block the sight).
const WORLD_LAYER := 1
## How far the player can see a point (m): a spawn further away is out of sight anyway.
const VISIBLE_DISTANCE := 250.0
## The height the sight ray ends at (m): a little above the road, so the road does not block it.
const VISIBLE_HEIGHT := 1.0


## True when the point `from` can see the point `to` within `range` metres.
static func can_see(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		range_m: float, exclude: Array[RID] = []) -> bool:
	if space == null:
		return true
	var delta := to - from
	if delta.length() > range_m:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if not exclude.is_empty():
		query.exclude = exclude
	var hit := space.intersect_ray(query)
	return hit.is_empty()


## True when the point is inside the camera frustum (the one frustum test of the police).
static func in_view(camera: Camera3D, pos: Vector3) -> bool:
	if camera == null:
		return false
	return camera.is_position_in_frustum(pos)


## True when the player can see the point: it is in the frustum of the camera, near enough and
## with a clear line of sight.
##
## A point behind a building is NOT visible: the police never appear in the view of the player
## (dossier §6.3: "never spawn police in the player's view"), and a roadblock behind a block
## of buildings is out of sight as well.
static func visible_to_player(camera: Camera3D, point: Vector3) -> bool:
	if camera == null:
		return false
	if not camera.is_position_in_frustum(point):
		return false
	if camera.global_position.distance_to(point) > VISIBLE_DISTANCE:
		return false
	var space := camera.get_world_3d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
			point + Vector3.UP * VISIBLE_HEIGHT, WORLD_LAYER)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query).is_empty()


## The eye of a ground unit.
static func eye_of(position: Vector3) -> Vector3:
	return position + Vector3.UP * ROOF_HEIGHT


## The roof of the player.
static func roof_of(position: Vector3) -> Vector3:
	return position + Vector3.UP * PLAYER_HEIGHT
