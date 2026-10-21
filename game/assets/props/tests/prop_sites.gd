extends RefCounted
## The site checks of the props contract test (unit: props).
##
## The three gameplay sites carry the nodes the world and gameplay units
## drive: the toll plaza (the lane signals, the barrier arms, the islands),
## the gas station (the breakable canopy supports) and the charging hub (the
## trigger volume, the bay numbers).

const PropContract = preload("res://assets/props/tests/prop_contract.gd")
const PropLayout = preload("res://assets/props/tests/prop_layout.gd")

const LANE_COUNT := 20
const EASTBOUND_LANES := 10
## The barrier arm has to cover its own lane (3.2 m wide) and no island.
const LANE_HALF := 1.6
const LANE_COVER := 2.6
const ISLAND_HALF := 1.1
const ISLAND_TOLERANCE := 0.4


## The checks of the toll plaza, as [[what, ok], ...].
static func toll_checks(node: Node) -> Array:
	var out: Array = []
	var names := _names(node)
	out.append(["the toll plaza has 20 lane signals", _has_prefix(names, "LaneSignal_", 20)])
	out.append(["the toll plaza has 20 barrier arms", _has_prefix(names, "Barrier_", 20)])
	out.append(["the toll plaza has light markers under the canopy",
			_has_prefix(names, "Light_", 10)])
	out.append(["the toll plaza has 20 islands", _has_prefix(names, "Island_", 20)])
	# Godot turns every `-convcolonly` proxy into an anonymous StaticBody3D
	# (CONTRACTS.md §2), so the count is what the world unit gets.
	var bodies := node.find_children("*", "StaticBody3D", true, false)
	out.append(["the toll plaza brings its collision proxies (%d)" % bodies.size(),
			bodies.size() >= 50])
	out.append_array(_barrier_arms(node))
	out.append_array(_lane_signals(node))
	out.append_array(PropLayout.toll_layout(node))
	return out


## Every barrier arm must cover its OWN lane when it is lowered: at least 2.6 m
## of the lane (the lane is 3.2 m wide) and no more than 0.4 m of an island.
static func _barrier_arms(node: Node) -> Array:
	var bad_lane := 0
	var bad_island := 0
	var count := 0
	for child in node.find_children("Barrier_*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		var extras: Dictionary = mesh.get_meta("extras", {})
		if not extras.has("lane_y"):
			continue
		count += 1
		# the arm in its lowered pose: the rotation about X (the raise) is reset
		var xform := mesh.global_transform
		var euler := xform.basis.get_euler()
		euler.x = 0.0
		var flat := Transform3D(xform.basis.from_euler(euler), xform.origin)
		var local: AABB = mesh.mesh.get_aabb()
		var z0 := INF
		var z1 := -INF
		for i in 8:
			var corner := Vector3(local.position.x if (i & 1) == 0 else local.end.x,
					local.position.y if (i & 2) == 0 else local.end.y,
					local.position.z if (i & 4) == 0 else local.end.z)
			var world := flat * corner
			z0 = minf(z0, world.z)
			z1 = maxf(z1, world.z)
		var lane := -float(extras["lane_y"])     # Blender Y is Godot -Z
		var island := -float(extras["island_y"])
		var overlap: float = minf(z1, lane + LANE_HALF) - maxf(z0, lane - LANE_HALF)
		if overlap < LANE_COVER:
			bad_lane += 1
		# the arm must not reach over the island (2.2 m wide, 1.1 m half)
		var reach: float = maxf(absf(z0 - island), absf(z1 - island))
		if reach < ISLAND_HALF - ISLAND_TOLERANCE:
			bad_island += 1
	return [
		["every barrier arm covers its own lane (%d arms, %d bad)" % [count, bad_lane],
			count == LANE_COUNT and bad_lane == 0],
		["no barrier arm lies on an island (%d)" % bad_island, bad_island == 0],
	]


## The south carriageway faces -X (eastbound) and the north one +X (westbound).
static func _lane_signals(node: Node) -> Array:
	var east := 0
	var west := 0
	var bad := 0
	for child in node.find_children("LaneSignal_*_Red", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		var normal := mesh.global_transform.basis.z
		if normal.x < -0.7:
			east += 1
		elif normal.x > 0.7:
			west += 1
		else:
			bad += 1
	return [["the lane signals face the traffic (%d east, %d west, %d sideways)"
			% [east, west, bad], east == EASTBOUND_LANES and west == EASTBOUND_LANES
			and bad == 0]]


## The checks of the gas station.
static func gas_checks(node: Node) -> Array:
	var out: Array = []
	var names := _names(node)
	out.append(["the gas station has Support_1..6", _has_prefix(names, "Support_", 6)])
	out.append(["the gas station has 6 dispensers", _has_prefix(names, "Dispenser_", 6)])
	out.append(["the gas station has a Canopy node", _has(names, "Canopy")])
	out.append(["the gas station has light markers under the canopy",
			_has_prefix(names, "Light_", 18)])
	# the support columns must hang under the canopy: the world unit drops the
	# whole roof when they break (game/world/build/gameplay_sites.gd)
	var hung := 0
	for child in node.find_children("Support_*", "MeshInstance3D", true, false):
		if child.get_parent() != null and child.get_parent().name == "Canopy":
			hung += 1
	out.append(["the six support columns hang under the canopy (%d)" % hung, hung == 6])
	return out


## The checks of the charging hub.
static func charge_checks(node: Node) -> Array:
	var out: Array = []
	var names := _names(node)
	out.append(["the charging hub has a ChargeArea marker", _has(names, "ChargeArea")])
	out.append(["the charging hub has 6 posts", _has_prefix(names, "Post_", 6)])
	out.append(["the charging hub has 6 dispensers", _has_prefix(names, "Dispenser_", 6)])
	out.append(["the charging hub has a Canopy node", _has(names, "Canopy")])
	out.append(["the charging hub has light markers under the canopy",
			_has_prefix(names, "Light_", 14)])
	# the bay paint is part of the joined body, the lit numbers stay separate
	out.append(["the charging hub has the lit bay numbers", _has(names, "BayNumbers")])
	var area := node.find_child("ChargeArea", true, false)
	if area != null:
		# Godot keeps the glTF node extras in the node metadata
		var extras: Dictionary = area.get_meta("extras", {})
		out.append(["ChargeArea carries its centre in the extras",
				extras.has("charge_area_centre")
				and (extras["charge_area_centre"] as Array).size() == 3])
		out.append(["ChargeArea carries its size in the extras",
				extras.has("charge_area_size")
				and (extras["charge_area_size"] as Array).size() == 3])
		out.append(["ChargeArea carries its id in the extras",
				extras.get("charge_area_id", "") == "charge_station"])
	return out


static func _names(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		out.append(String(child.name))
		out.append_array(_names(child))
	return out


static func _has(names: Array[String], wanted: String) -> bool:
	return names.has(wanted)


static func _has_prefix(names: Array[String], prefix: String, count: int) -> bool:
	var found := 0
	for n in names:
		if n.begins_with(prefix):
			found += 1
	return found >= count
