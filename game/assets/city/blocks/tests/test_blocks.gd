extends Node
## Buildings unit test: the generated city tiles must load, carry geometry inside their
## cell, meet the brief's budgets and agree with the sidecar metadata.
##
##     tools/godot.sh test res://assets/city/blocks/tests/test_blocks.gd
##
## Every check returns a bool and is ANDed into the result, so a broken tile fails.
## It checks the near tiles, the far LOD tiles, the collider coverage (every near-road
## building has a collider that matches its footprint) and that the tiles were built
## from the map that is on disk now.
##
## The tiles are .gltf + .bin with the images in res://assets/city/_tex/.  They are
## written without tangents (a third of the bytes); the import must generate them,
## or the normal maps of the facades would be wrong.

const BLOCKS_DIR := "res://assets/city/blocks"
const CITY_RELATIVE := "res://../data/city/city.json"
const TILE_M := 512.0
const CELL_M := 128.0
const NEAR_TRI_BUDGET := 600000
const FAR_TRI_BUDGET := 40000
const MATERIAL_BUDGET := 40
const MIN_COVERAGE := 0.30
const COLLIDER_TOLERANCE := 0.3
const STYLES := ["shikumen", "midrise", "office_tower", "residential_slab", "heritage",
	"neon_street", "industrial", "park", "plaza"]


func _ready() -> void:
	var dir := DirAccess.open(BLOCKS_DIR)
	if dir == null:
		print("FAIL no blocks directory")
		get_tree().quit(1)
		return
	var tiles: Array[String] = []
	for file_name in dir.get_files():
		if file_name.begins_with("blocks_") and file_name.ends_with(".json"):
			tiles.append(file_name)
	if tiles.is_empty():
		print("FAIL no block sidecars")
		get_tree().quit(1)
		return
	var ok := true
	var buildings := 0
	var near_road := 0
	var colliders := 0
	for tile_name in tiles:
		ok = _check_sidecar(tile_name) and ok
		var data := _read_sidecar(tile_name)
		buildings += data.get("buildings", []).size()
		for rec: Dictionary in data.get("buildings", []):
			if bool(rec.get("near_road", false)):
				near_road += 1
		var near_colliders := _check_tile_mesh(tile_name.get_basename())
		if near_colliders < 0:
			ok = false
		else:
			colliders += near_colliders
		var far_tris := _check_far_mesh(tile_name.get_basename())
		ok = far_tris >= 0 and ok
	ok = _check_city_digest(tiles) and ok
	print(("PASS" if ok else "FAIL") + " %d tiles, %d buildings, %d near-road, %d colliders"
		% [tiles.size(), buildings, near_road, colliders])
	get_tree().quit(0 if ok else 1)


func _read_sidecar(tile_name: String) -> Dictionary:
	var file := FileAccess.open("%s/%s" % [BLOCKS_DIR, tile_name], FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _check_city_digest(tiles: Array[String]) -> bool:
	## The tiles must all come from the map that is on disk now.
	var path := ProjectSettings.globalize_path(CITY_RELATIVE)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("WARN cannot read the city map at %s (the digest is not checked)" % path)
		return true
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(file.get_buffer(file.get_length()))
	var digest := ctx.finish().hex_encode()
	for tile_name in tiles:
		var data := _read_sidecar(tile_name)
		var recorded: String = data.get("city_sha256", "")
		if recorded != digest:
			print("FAIL %s was built from another map (%s != %s)" % [tile_name, recorded, digest])
			return false
	return true


func _check_sidecar(tile_name: String) -> bool:
	var data := _read_sidecar(tile_name)
	if data.is_empty():
		print("FAIL cannot read " + tile_name)
		return false
	var tile: Array = data.get("tile", [])
	if tile.size() != 2:
		print("FAIL " + tile_name + " has no tile index")
		return false
	var ids: Dictionary = {}
	for rec: Dictionary in data.get("buildings", []):
		if not _check_building(rec, tile_name, ids):
			return false
	if not _check_block_coverage(data, tile_name):
		return false
	for occluder: Array in data.get("occluders", []):
		if occluder.size() != 5 or float(occluder[2]) <= 0.0 or float(occluder[3]) <= 0.0:
			print("FAIL " + tile_name + " has a bad occluder " + str(occluder))
			return false
		# the occluders are tile local (city space) and must sit inside the tile + the spill
		if abs(float(occluder[0])) > TILE_M + 150.0 or abs(float(occluder[1])) > TILE_M + 150.0:
			print("FAIL " + tile_name + " has an occluder outside its tile")
			return false
	return true


func _check_block_coverage(data: Dictionary, tile_name: String) -> bool:
	## Every block of the map must carry a building, and be built at least 30 %.
	var ok := true
	for entry: Dictionary in data.get("blocks", []):
		var style: String = entry.get("style", "")
		if style == "park" or style == "plaza":
			continue
		if int(entry.get("buildings", 0)) == 0:
			print("FAIL " + tile_name + " block " + str(entry.get("id", "")) + " has no building")
			ok = false
			continue
		var coverage: float = float(entry.get("coverage", 0.0))
		if coverage < MIN_COVERAGE:
			print("FAIL " + tile_name + " block " + str(entry.get("id", "")) + " is only %.0f %% built"
				% (coverage * 100.0))
			ok = false
	return ok


func _check_building(rec: Dictionary, tile_name: String, ids: Dictionary) -> bool:
	var rec_id: String = rec.get("id", "")
	if rec_id == "" or ids.has(rec_id):
		print("FAIL " + tile_name + " duplicate or empty building id " + rec_id)
		return false
	ids[rec_id] = true
	if not STYLES.has(rec.get("style", "")):
		print("FAIL " + rec_id + " unknown style " + str(rec.get("style", "")))
		return false
	if rec.get("poly", []).size() < 3:
		print("FAIL " + rec_id + " has no footprint")
		return false
	if float(rec.get("height", 0.0)) <= 0.0:
		print("FAIL " + rec_id + " has no height")
		return false
	# the night parameters of the facade shader (lit_ratio, band_ratio, cool_mix)
	for key: String in ["lit_ratio", "band_ratio", "cool_mix"]:
		if not rec.has(key):
			print("FAIL " + rec_id + " has no " + key)
			return false
		var value: float = float(rec[key])
		if value < 0.0 or value > 1.0:
			print("FAIL " + rec_id + " has an out of range " + key)
			return false
	return true


func _check_tile_mesh(tile_base: String) -> int:
	## The number of colliders of the tile, or -1 when the tile is broken.
	var path := "%s/%s.gltf" % [BLOCKS_DIR, tile_base]
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL cannot load " + path)
		return -1
	var root := packed.instantiate()
	# the collider boxes are read in world space, so the tile has to be in the tree
	add_child(root)
	var meshes := 0
	var collider_count := 0
	var bad_collider := 0
	var tris := 0
	var tangents := 0
	var materials: Dictionary = {}
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var bodies: Dictionary = {}
	for node in root.get_children():
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			meshes += 1
			tris += _mesh_tris(mi.mesh)
			tangents += _mesh_tangents(mi.mesh)
			for i in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(i)
				if mat != null:
					materials[mat.resource_name] = true
			var aabb := mi.transform * mi.get_aabb()
			lo = lo.min(aabb.position)
			hi = hi.max(aabb.position + aabb.size)
		var body := node as StaticBody3D
		if body == null:
			continue
		collider_count += 1
		var shape_node := body.get_child(0) as CollisionShape3D
		var convex := shape_node.shape as ConvexPolygonShape3D if shape_node != null else null
		if convex == null or convex.points.size() < 4:
			bad_collider += 1
		else:
			bodies[String(body.name).replace("-convcolonly", "")] = _shape_aabb(body, convex)
	root.free()
	if meshes == 0:
		print("FAIL " + tile_base + " has no meshes")
		return -1
	if bad_collider > 0:
		print("FAIL " + tile_base + " has %d degenerate colliders" % bad_collider)
		return -1
	if materials.size() > MATERIAL_BUDGET:
		print("FAIL " + tile_base + " uses %d materials (budget %d)" % [materials.size(), MATERIAL_BUDGET])
		return -1
	if tris > NEAR_TRI_BUDGET:
		print("FAIL " + tile_base + " has %d triangles (budget %d)" % [tris, NEAR_TRI_BUDGET])
		return -1
	if tangents == 0:
		# the tiles are written without tangents; the import must generate them
		print("FAIL " + tile_base + " has no tangents: set meshes/ensure_tangents=true in its .import")
		return -1
	if not _check_collider_coverage(tile_base, bodies):
		return -1
	# the world AABB of the tile must lie inside its 512 m cell (+ the block spill)
	var tile: Array = _tile_index(tile_base)
	if tile.size() == 2:
		var x0 := float(tile[0]) * TILE_M - 150.0
		var x1 := float(tile[0]) * TILE_M + TILE_M + 150.0
		var z0 := float(tile[1]) * TILE_M - 150.0
		var z1 := float(tile[1]) * TILE_M + TILE_M + 150.0
		if lo.x < x0 or hi.x > x1 or lo.z < z0 or hi.z > z1:
			print("FAIL %s world AABB (%.0f..%.0f, %.0f..%.0f) is outside its cell" %
				[tile_base, lo.x, hi.x, lo.z, hi.z])
			return -1
	print("PASS %s: %d meshes, %d colliders, %d tris, %d materials" %
		[tile_base, meshes, collider_count, tris, materials.size()])
	return collider_count


func _shape_aabb(body: StaticBody3D, convex: ConvexPolygonShape3D) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for point in convex.points:
		lo = lo.min(point)
		hi = hi.max(point)
	var box := AABB(lo, hi - lo)
	return body.global_transform * box


func _check_collider_coverage(tile_base: String, bodies: Dictionary) -> bool:
	## Every near-road building has a collider, and the collider matches the footprint.
	var data := _read_sidecar(tile_base + ".json")
	var ok := true
	for rec: Dictionary in data.get("buildings", []):
		var rec_id: String = rec.get("id", "")
		var near := bool(rec.get("near_road", false))
		if near and not bodies.has(rec_id):
			print("FAIL %s: the near-road building %s has no collider" % [tile_base, rec_id])
			ok = false
		elif not near and bodies.has(rec_id):
			print("FAIL %s: the building %s is not near a road but has a collider" % [tile_base, rec_id])
			ok = false
		if near and bodies.has(rec_id):
			var box: AABB = bodies[rec_id]
			var poly: Array = rec.get("poly", [])
			var xs: Array = []
			var zs: Array = []
			for point in poly:
				xs.append(float(point[0]))
				zs.append(float(point[1]))
			if xs.is_empty():
				continue
			if (absf(box.position.x - float(xs.min())) > COLLIDER_TOLERANCE
					or absf(box.end.x - float(xs.max())) > COLLIDER_TOLERANCE
					or absf(box.position.z - float(zs.min())) > COLLIDER_TOLERANCE
					or absf(box.end.z - float(zs.max())) > COLLIDER_TOLERANCE):
				print("FAIL %s: the collider of %s does not match its footprint" % [tile_base, rec_id])
				ok = false
	return ok


func _check_far_mesh(tile_base: String) -> int:
	## The far LOD tile must exist, stay inside its budget and carry geometry.
	var path := "%s/%s_far.gltf" % [BLOCKS_DIR, tile_base]
	if not ResourceLoader.exists(path):
		return 0
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL cannot load " + path)
		return -1
	var root := packed.instantiate()
	var tris := 0
	var materials: Dictionary = {}
	for node in root.get_children():
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		tris += _mesh_tris(mi.mesh)
		for i in range(mi.mesh.get_surface_count()):
			var mat := mi.get_active_material(i)
			if mat != null:
				materials[mat.resource_name] = true
	root.free()
	if tris > FAR_TRI_BUDGET:
		print("FAIL %s_far has %d triangles (budget %d)" % [tile_base, tris, FAR_TRI_BUDGET])
		return -1
	if materials.size() > MATERIAL_BUDGET:
		print("FAIL %s_far uses %d materials (budget %d)" % [tile_base, materials.size(), MATERIAL_BUDGET])
		return -1
	return tris


func _tile_index(tile_base: String) -> Array:
	var data := _read_sidecar(tile_base + ".json")
	return data.get("tile", [])


func _mesh_tris(mesh: ArrayMesh) -> int:
	var tris := 0
	for i in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		tris += (indices.size() / 3) if indices.size() > 0 else (arrays[Mesh.ARRAY_VERTEX].size() / 3)
	return tris


func _mesh_tangents(mesh: ArrayMesh) -> int:
	## The number of surfaces that carry a tangent array (the normal maps need them).
	var count := 0
	for i in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(i)
		if arrays.is_empty():
			continue
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		if tangents.size() > 0:
			count += 1
	return count
