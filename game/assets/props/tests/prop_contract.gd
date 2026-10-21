extends RefCounted
## The shared checks of the props contract test (unit: props).
##
## The test script (`test_props.gd`) preloads this file: the constants and the
## helpers live here, so the test script itself stays short and the
## duplicated tables cannot drift apart.
##
##   const PropContract = preload("res://assets/props/tests/prop_contract.gd")

## The tileable families: the texture of each covers 2 m, so a correct prop
## samples 512 px/m whatever the size of its parts.
const FAMILY_MATERIALS := ["Prop_Metal", "Prop_Mineral", "Prop_Panel", "Prop_Paint",
		"Prop_Bark", "Prop_Soffit"]
## The sign materials: they carry a printed board, not a tiled family.
const SIGN_MATERIALS := ["Prop_Sign", "Prop_SignLit", "Prop_SignLed",
		"Prop_SignLedCyan"]
## The materials with an alpha cut-out (the markings).
const CUTOUT_MATERIALS := ["Prop_Foliage", "Prop_BayNumbers", "Prop_DeckText",
		"Prop_RoadMarks"]
## The minimum texel density of a surface (px per metre).
const MIN_PX_PER_M := 300.0
## The share of a prop's area that may be below it.
const MAX_BAD_SHARE := 0.05
## The roughness maps are written in the glTF layout: the roughness is in GREEN.
const ROUGHNESS_CHANNEL := 1


## The share of the area of one prop that samples its texture too coarsely.
static func bad_share(node: Node) -> float:
	var total := 0.0
	var bad := 0.0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh == null:
			continue
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null or not FAMILY_MATERIALS.has(mat.resource_name):
				continue
			var tex := mat.albedo_texture
			if tex == null:
				continue
			var px := float(tex.get_width())
			var arrays := mesh.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if uvs.size() != verts.size() or indices.size() < 3:
				continue
			for t in range(0, indices.size() - 2, 3):
				var ia := indices[t]
				var ib := indices[t + 1]
				var ic := indices[t + 2]
				var a3 := _area3(verts[ia], verts[ib], verts[ic])
				if a3 < 1e-9:
					continue
				var a2 := _area2(uvs[ia], uvs[ib], uvs[ic])
				var d: float = sqrt(a2 * px * px / a3)
				total += a3
				if d < MIN_PX_PER_M:
					bad += a3
	if total <= 0.0:
		return 0.0
	return bad / total


static func _area3(a: Vector3, b: Vector3, c: Vector3) -> float:
	var u := b - a
	var v := c - a
	return 0.5 * u.cross(v).length()


static func _area2(a: Vector2, b: Vector2, c: Vector2) -> float:
	return 0.5 * absf((b - a).x * (c - a).y - (b - a).y * (c - a).x)


## The external material of one family, or null.
## `family` is the resource name ("Prop_Metal"); the file is prop_metal.tres.
static func family_material(family: String) -> StandardMaterial3D:
	var stem := family.to_lower()
	if not stem.begins_with("prop_"):
		stem = "prop_" + stem
	var path := "res://assets/props/materials/%s.tres" % stem
	if not ResourceLoader.exists(path):
		return null
	return load(path) as StandardMaterial3D


## The mean and the deviation of one channel of a texture (0 = red, 1 = green).
static func channel_stats(tex: Texture2D, channel: int) -> Vector2:
	var img := tex.get_image()
	if img == null:
		return Vector2.ZERO
	var data := img.get_data()
	var w := img.get_width()
	var h := img.get_height()
	var step := 4 if img.get_format() == Image.FORMAT_RGBA8 else 1
	var total := 0.0
	var total2 := 0.0
	var count := 0.0
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			var i := (y * w + x) * step + channel
			if i >= data.size():
				continue
			var v := float(data[i]) / 255.0
			total += v
			total2 += v * v
			count += 1.0
	if count < 1.0:
		return Vector2.ZERO
	var mean := total / count
	return Vector2(mean, sqrt(max(total2 / count - mean * mean, 0.0)))


## The corners of a collision shape, in the body's local space.
static func shape_points(body: CollisionObject3D) -> PackedVector3Array:
	for child in body.get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		var box := holder.shape as BoxShape3D
		if box != null:
			var h := box.size * 0.5
			return PackedVector3Array([
				Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
				Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
				Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
				Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)])
		var hull := holder.shape as ConvexPolygonShape3D
		if hull != null:
			return hull.points
	return PackedVector3Array()


## The world-space centre of a collision body's bounds.
static func body_centre(body: CollisionObject3D) -> Vector3:
	var points := shape_points(body)
	if points.is_empty():
		return body.global_position
	var lo := points[0]
	var hi := points[0]
	for pt in points:
		lo = lo.min(pt)
		hi = hi.max(pt)
	return body.global_transform * ((lo + hi) * 0.5)


## The world-space centre of a node's bounding box.
static func aabb_centre(node: Node3D) -> Vector3:
	var mesh := node as MeshInstance3D
	if mesh == null:
		return node.global_position
	var box := mesh.mesh.get_aabb()
	return mesh.global_transform * box.get_center()


## The world-space bounds of a node's bounding box.
static func aabb_size(node: Node3D) -> Vector3:
	var mesh := node as MeshInstance3D
	if mesh == null:
		return Vector3.ZERO
	return mesh.mesh.get_aabb().size
