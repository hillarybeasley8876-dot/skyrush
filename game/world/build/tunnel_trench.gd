extends RefCounted
## The open ramps of the tunnels. A tunnel lane goes down from the street into its bore; the bore (roads unit, blender/city/roads/
## tunnel.py: a wall of 3.75 m either side of the middle of its carriageway, an arch whose crown is 6.0 m over the road) shows over
## the ground until its crown is under it. The ground of the city is built from the water outlines only, and it lay over both
## ramps of the Yan'an tunnel: from Pudong a car drove over the portal on the flat ground, through the walls of the bores (they
## have no collision over the ground), and a car that came up the Puxi ramp stopped dead at the edge of the ground
## (tools/tunnel_probe.gd).
##
## Built from the lanes of the data (the ground is built before the lane graph):
##   * the cut: the ground is cut out between the walls of a bore where its lanes are TOP to BOTTOM under the ground,
##   * the tube: the walls of the bore from its road to its crown and the roof under the crown, wherever the crown is over the
##     ground: the tube that is drawn is the tube a car meets (from the outside it is a wall, from the inside a tube),
##   * the road surfaces of the tiles that lie over a ramp lose their collision there (clear_roads_over): the plate of the
##     junction at the Pudong portal reaches over the ramp at the street level, and a car that came up the ramp drove its nose
##     into the edge of it and stopped from 145 km/h in one tick,
##   * and they are not drawn there (clear_meshes_over): a car that drove down the ramp disappeared under the plate. Only the
##     surface materials of the roads (ROAD_SURFACES) are cut; the bores are over the ramp on purpose.

const Spline := preload("res://world/api/spline_util.gd")

## m: a tunnel lane this far under the ground is in its open ramp (the ground is cut over it).
const TOP := -0.03
## m: the crown of the bore is under the ground below this (the ground covers the bore).
const BOTTOM := -6.0
## m: the inner face of a wall from the middle of the carriageway (tunnel.py: the half roadway 3.75, the wall 0.35 + 0.3 wide).
const HALF := 3.8
## m: the thickness of a wall and of the roof.
const WALL := 0.3
const ROOF := 0.4
## m: the crown of the bore over its road (tunnel.py bore_crown: the clearance 4.5, the arch of radius 5.5).
const CROWN := 6.0
## m: the length of a piece of the tube, and the step of the walk along the lanes.
const STEP := 4.0
## m: a road surface this far over the road of a ramp is over it, not the ramp (its collision goes).
const CLEAR_ABOVE := 0.3
## The materials of the road surfaces that are cut over a ramp (the start of the name): the asphalt, the markings, the kerbs, the
## pavements. The bores, the gantry and the lamps of the tunnel are not.
const ROAD_SURFACES: Array[String] = ["SH_wet_asphalt", "SH_road_marking", "SH_kerb", "SH_sidewalk", "Road_Tactile", "Road_Planter"]
## m: the road tiles (blender/city/roads/tiles.py TILE) and how far a vertex may be outside its tile.
const ROAD_TILE := 512.0
const ROAD_TILE_MARGIN := 64.0
## The layer of the tube (the world).
const LAYER := 1

## The cut outlines (for the ground builder) and the pieces of the tube: {"centre": Vector3, "basis": Basis, "size": Vector3}.
var cuts: Array[PackedVector2Array] = []
var pieces: Array[Dictionary] = []
## The middle line of the bore of every cut (x, the height of its road, z), for the height of the ramp under a point.
var _lines: Array[PackedVector3Array] = []


## Finds the bores in the lane dictionaries of the data (the lanes of a road whose id says "tunnel", by carriageway).
func build(lane_dicts: Array[Dictionary]) -> void:
	cuts.clear()
	pieces.clear()
	_lines.clear()
	var ways := {}
	for entry in lane_dicts:
		var road := String(entry.get("road", ""))
		if not road.contains("tunnel") or bool(entry.get("connector", false)):
			continue
		var key := "%s/%d" % [road, int(entry.get("dir", 1))]
		if not ways.has(key):
			ways[key] = []
		(ways[key] as Array).append(_points(entry.get("points", [])))
	for key in ways:
		_bore(ways[key] as Array)


## A bore: its middle line is the middle of the lanes of its carriageway (sampled at the same share of their length).
func _bore(lanes: Array) -> void:
	var curves: Array[Curve3D] = []
	for pts: PackedVector3Array in lanes:
		if pts.size() >= 2:
			curves.append(Spline.make_curve(pts, 1.0))
	if curves.is_empty():
		return
	var length := curves[0].get_baked_length()
	var steps := maxi(int(length / STEP), 1)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var line := PackedVector3Array()
	var last_flat := Vector2(1.0, 0.0)
	for i in steps + 1:
		var share := float(i) / float(steps)
		var centre := Vector3.ZERO
		var ahead := Vector3.ZERO
		for curve in curves:
			centre += curve.sample_baked(curve.get_baked_length() * share, true)
			ahead += curve.sample_baked(minf(curve.get_baked_length() * share + 1.0, curve.get_baked_length()), true)
		centre /= float(curves.size())
		ahead /= float(curves.size())
		var flat := Vector2(ahead.x - centre.x, ahead.z - centre.z)
		# at the end of the lanes there is no point ahead: the direction of the step before
		flat = flat.normalized() if flat.length() > 0.01 else last_flat
		last_flat = flat
		var side := Vector2(-flat.y, flat.x)
		var here := Vector2(centre.x, centre.z)
		# the cut: where the lanes are in their open ramp
		if centre.y < TOP and centre.y > BOTTOM:
			left.append(here + side * HALF)
			right.append(here - side * HALF)
			line.append(centre)
		elif left.size() >= 2:
			cuts.append(_strip(left, right))
			_lines.append(line)
			left = PackedVector2Array()
			right = PackedVector2Array()
			line = PackedVector3Array()
		else:
			left.clear()
			right.clear()
			line.clear()
		# the tube: wherever its crown is over the ground
		if centre.y + CROWN > 0.0 and centre.y < 0.5:
			_tube_piece(centre, flat)
	if left.size() >= 2:
		cuts.append(_strip(left, right))
		_lines.append(line)


## Takes the collision of the road surfaces of the tiles away where they lie over a ramp (CLEAR_ABOVE over its road). Only the
## tiles that reach the cuts are read. Returns the number of triangles taken away.
func clear_roads_over(roads: Node) -> int:
	if cuts.is_empty():
		return 0
	var bounds := Rect2(cuts[0][0], Vector2.ZERO)
	for cut in cuts:
		for p in cut:
			bounds = bounds.expand(p)
	var removed := 0
	for node in roads.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		var concave := shape_node.shape as ConcavePolygonShape3D
		var body := shape_node.get_parent()
		if concave == null or body == null or not String(body.name).ends_with("_surface"):
			continue
		if not _tile_reaches(String(body.name), bounds):
			continue
		var xform := shape_node.global_transform
		var faces := concave.get_faces()
		var kept := PackedVector3Array()
		var dropped := 0
		for i in range(0, faces.size() - 2, 3):
			# a triangle goes when its middle or one of its corners is over a ramp (the plate of a junction is a few big
			# triangles: their middles lie outside the cut). Next to the ramp the ground is 2 cm under the plate.
			var a := xform * faces[i]
			var b := xform * faces[i + 1]
			var c := xform * faces[i + 2]
			if _covers_a_ramp(a, b, c, bounds):
				dropped += 1
				continue
			kept.append(faces[i])
			kept.append(faces[i + 1])
			kept.append(faces[i + 2])
		if dropped > 0:
			concave.set_faces(kept)
			removed += dropped
	return removed


## True when the triangle (a, b, c) lies over a part of a ramp, CLEAR_ABOVE or more over its road. The plate of a junction is a
## few big triangles: a triangle can span the whole ramp with its corners and its middle outside of it.
func _covers_a_ramp(a: Vector3, b: Vector3, c: Vector3, bounds: Rect2) -> bool:
	var tri := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
	var box := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
	if not box.intersects(bounds):
		return false
	for i in cuts.size():
		for part in Geometry2D.intersect_polygons(tri, cuts[i]):
			# every corner of the part of the triangle that lies over the ramp: the height of the triangle there (its plane) over
			# the road of the ramp there. The road of the ramp itself lies on the road; a plate of the street over the ramp does not.
			for q in part:
				var y := _plane_y(a, b, c, q)
				if not is_nan(y) and y > _road_y(i, q) + CLEAR_ABOVE:
					return true
	return false


## The height of the plane of a triangle at (x, z), or NAN for a triangle that stands on its edge (a wall).
static func _plane_y(a: Vector3, b: Vector3, c: Vector3, q: Vector2) -> float:
	var v0 := Vector2(b.x - a.x, b.z - a.z)
	var v1 := Vector2(c.x - a.x, c.z - a.z)
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 0.0001:
		return NAN
	var v2 := Vector2(q.x - a.x, q.y - a.z)
	var u := (v2.x * v1.y - v1.x * v2.y) / den
	var v := (v0.x * v2.y - v2.x * v0.y) / den
	return a.y + u * (b.y - a.y) + v * (c.y - a.y)


## The height of the road of the ramp of cut `i` nearest to a point (x, z).
func _road_y(i: int, p: Vector2) -> float:
	var best := INF
	var road_y := 0.0
	for q in _lines[i]:
		var d := Vector2(q.x - p.x, q.z - p.y).length_squared()
		if d < best:
			best = d
			road_y = q.y
	return road_y


## Takes the drawn triangles of the road surfaces away where they lie over a ramp (the same rule as their collision). The meshes of
## the tiles are one surface per material: a surface that loses triangles is built again from its arrays (without its LODs).
## Returns the number of triangles taken away.
func clear_meshes_over(roads: Node) -> int:
	if cuts.is_empty():
		return 0
	var bounds := Rect2(cuts[0][0], Vector2.ZERO)
	for cut in cuts:
		for p in cut:
			bounds = bounds.expand(p)
	var removed := 0
	for node in roads.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mesh == null:
			continue
		var aabb := mi.global_transform * mesh.get_aabb()
		if not Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z).intersects(bounds):
			continue
		var rebuilt := ArrayMesh.new()
		var changed := false
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			var arrays := mesh.surface_get_arrays(surface)
			var kept := _kept_triangles(mi.global_transform, arrays, material, bounds)
			if kept.is_empty() and _is_road_surface(material):
				# every triangle of the surface is over a ramp
				changed = true
				continue
			if not kept.is_empty():
				removed += int(kept[1])
				arrays[Mesh.ARRAY_INDEX] = kept[0]
				changed = changed or int(kept[1]) > 0
			rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			rebuilt.surface_set_material(rebuilt.get_surface_count() - 1, material)
		if changed:
			mi.mesh = rebuilt
	return removed


## The index array of a surface without its triangles over a ramp, and how many went: [indices, removed]. Empty when the surface is
## not a road surface (it is kept as it is) or when nothing is left.
func _kept_triangles(xform: Transform3D, arrays: Array, material: Material, bounds: Rect2) -> Array:
	if not _is_road_surface(material):
		return []
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(verts.size())
		for i in verts.size():
			indices[i] = i
	var kept := PackedInt32Array()
	var removed := 0
	for t in range(0, indices.size() - 2, 3):
		var a := xform * verts[indices[t]]
		var b := xform * verts[indices[t + 1]]
		var c := xform * verts[indices[t + 2]]
		if _covers_a_ramp(a, b, c, bounds):
			removed += 1
			continue
		kept.append(indices[t])
		kept.append(indices[t + 1])
		kept.append(indices[t + 2])
	if kept.is_empty():
		return []
	return [kept, removed]


static func _is_road_surface(material: Material) -> bool:
	if material == null:
		return false
	for prefix in ROAD_SURFACES:
		if material.resource_name.begins_with(prefix):
			return true
	return false


## True when the tile of a body ("roads_<x>_<z>_surface") reaches `bounds` (with the margin of the tiles).
func _tile_reaches(name: String, bounds: Rect2) -> bool:
	var parts := name.split("_")
	if parts.size() < 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return true
	var tile := Rect2(float(int(parts[1])) * ROAD_TILE, float(int(parts[2])) * ROAD_TILE, ROAD_TILE, ROAD_TILE)
	return tile.grow(ROAD_TILE_MARGIN).intersects(bounds)


## The walls and the roof of the bore over one STEP of its middle line.
func _tube_piece(centre: Vector3, flat: Vector2) -> void:
	var forward := Vector3(flat.x, 0.0, flat.y)
	var basis := Basis.looking_at(forward, Vector3.UP)
	var across := basis.x
	# the walls stand from the road to the crown, the roof hangs under the crown (its top is the crown: where the crown meets the
	# ground the roof is flush with it, no step for a car on the street over the tunnel)
	for sign: float in [-1.0, 1.0]:
		pieces.append({"centre": centre + across * sign * (HALF + WALL * 0.5) + Vector3.UP * CROWN * 0.5, "basis": basis,
			"size": Vector3(WALL, CROWN, STEP + 0.2)})
	pieces.append({"centre": centre + Vector3.UP * (CROWN - ROOF * 0.5), "basis": basis,
		"size": Vector3((HALF + WALL) * 2.0, ROOF, STEP + 0.2)})


## Adds the tube as one static body of boxes under `parent`.
func add_tube(parent: Node3D) -> StaticBody3D:
	if pieces.is_empty():
		return null
	var body := StaticBody3D.new()
	body.name = "TunnelTubes"
	body.collision_layer = LAYER
	body.collision_mask = 0
	var shapes: Dictionary = {}
	for piece in pieces:
		var size: Vector3 = piece["size"]
		var key := str(size.snapped(Vector3.ONE * 0.01))
		if not shapes.has(key):
			var box := BoxShape3D.new()
			box.size = size
			shapes[key] = box
		var node := CollisionShape3D.new()
		node.shape = shapes[key]
		node.transform = Transform3D(piece["basis"], piece["centre"])
		body.add_child(node)
	parent.add_child(body)
	return body


## The outline of a strip: the left side forwards, the right side back.
static func _strip(left: PackedVector2Array, right: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(left)
	for i in range(right.size() - 1, -1, -1):
		out.append(right[i])
	return out


static func _points(raw: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if raw is Array:
		for p in raw as Array:
			if p is Array and (p as Array).size() >= 3:
				out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return out
