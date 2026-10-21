extends RefCounted
## The layout checks of the props contract test (unit: props).
##
## The toll plaza is the piece the world unit drives through, so its geometry
## is checked against the traffic rules: the island of a lane is on the
## DRIVER'S LEFT, the westbound lane signals stand at the far end of the
## canopy, and no printed board is double sided (a board seen from behind
## would show its text mirrored).

const PropContract = preload("res://assets/props/tests/prop_contract.gd")

## The lanes of the plaza: the south carriageway is eastbound (+X), the north
## one westbound (-X).
const LANE_COUNT := 20
const EASTBOUND_LANES := 10
## The island of a lane stands this far from the lane's centre.
const ISLAND_OFFSET := 2.70
## The westbound signals stand at the far end of the canopy.
const WESTBOUND_SIGNAL_X := 9.5


## The checks of the toll plaza, as [[what, ok], ...].
static func toll_layout(node: Node) -> Array:
	var out: Array = []
	out.append(["the toll plaza brings its islands", _islands(node).size() == LANE_COUNT])
	out.append(["every island is on the driver's left of its lane", _islands_on_the_left(node)])
	out.append(["the westbound lane signals stand at the far end of the canopy",
			_westbound_signals(node)])
	out.append(["no printed board is double sided", _no_double_sided_signs(node)])
	return out


## The AABB centre of every island, by its lane number.
## The islands are the collision proxies of the plaza (the visible kerb is
## joined into the static body), so their bounds come from the shape.
static func _islands(node: Node) -> Dictionary:
	var out := {}
	for child in node.find_children("Island_*", "StaticBody3D", true, false):
		var body := child as StaticBody3D
		if body == null:
			continue
		var name := String(body.name)
		if not name.begins_with("Island_"):
			continue
		out[name.substr(7).to_int()] = PropContract.body_centre(body)
	return out


## The AABB centre of every lane signal (the red face), by its lane number.
static func _signals(node: Node) -> Dictionary:
	var out := {}
	for child in node.find_children("LaneSignal_*_Red", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		var parts := String(mesh.name).split("_")
		if parts.size() < 3:
			continue
		out[parts[1].to_int()] = PropContract.aabb_centre(mesh)
	return out


## Every island has to be on the driver's left: Godot +Z is the right of an
## eastbound driver and the left of a westbound one.
static func _islands_on_the_left(node: Node) -> bool:
	var islands := _islands(node)
	var signals := _signals(node)
	if islands.size() < LANE_COUNT or signals.size() < LANE_COUNT:
		return false
	for n in range(1, LANE_COUNT + 1):
		if not islands.has(n) or not signals.has(n):
			return false
		var island_z: float = islands[n].z
		var lane_z: float = signals[n].z
		if n <= EASTBOUND_LANES:
			# eastbound: the driver's left is -Z
			if island_z >= lane_z:
				return false
		else:
			# westbound: the driver's left is +Z
			if island_z <= lane_z:
				return false
	return true


## The westbound signals have to stand at the +X end of the canopy, where the
## westbound traffic comes from.
static func _westbound_signals(node: Node) -> bool:
	var signals := _signals(node)
	for n in range(EASTBOUND_LANES + 1, LANE_COUNT + 1):
		if not signals.has(n):
			return false
		if signals[n].x < WESTBOUND_SIGNAL_X:
			return false
	return true


## No printed board may be double sided: a board seen from behind would show
## its text mirrored (the review of the toll plaza).
static func _no_double_sided_signs(node: Node) -> bool:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			if not mat.resource_name.begins_with("Prop_Sign"):
				continue
			if mat.cull_mode == BaseMaterial3D.CULL_DISABLED:
				return false
	return true
