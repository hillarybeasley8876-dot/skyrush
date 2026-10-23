extends RefCounted
## The sites the HOP prompt watches: the roadblock sites and the toll plazas of the world.
##
## The world builds its network asynchronously, so the HUD reads the sites once the world is ready
## and then works on the cached list (the prompt scans it five times a second).

## The kind of the point of interest of a toll plaza.
const TOLL := &"toll"


## The sites of the world (the roadblock sites and the toll plazas), in world metres.
static func read(world: WorldBase) -> Array[Vector3]:
	var sites: Array[Vector3] = []
	if world == null:
		return sites
	for site in world.get_roadblock_sites():
		sites.append(site.origin)
	for poi in world.get_points_of_interest():
		if StringName(poi.get("kind", &"")) != TOLL:
			continue
		var raw: Variant = poi.get("position", null)
		if raw is Vector3:
			sites.append(raw)
		elif raw is Vector2:
			sites.append(Vector3(raw.x, 0.0, raw.y))
	return sites


## The world is ready when it built its lanes (the real world builds them over several seconds).
static func world_ready(world: WorldBase) -> bool:
	if world == null:
		return false
	if world.has_method(&"is_ready") and not bool(world.call(&"is_ready")):
		return false
	return Game.world_built()
