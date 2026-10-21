extends RefCounted
## Procedural fallback geometry and the shared materials used by the world unit when the
## props / bund / landmark units have not shipped their glb yet. Nothing here is a flat
## untextured surface: every material carries a texture and a normal map.

const CONCRETE_TEX := "res://assets/textures/concrete_wall_008/concrete_wall_008_diff.jpg"
const CONCRETE_NOR := "res://assets/textures/concrete_wall_008/concrete_wall_008_nor_gl.jpg"
const CONCRETE_ROUGH := "res://assets/textures/concrete_wall_008/concrete_wall_008_rough.jpg"
const GRIME_TEX := "res://assets/textures/rough_concrete/rough_concrete_diff.jpg"
const GRANITE_TEX := "res://assets/textures/granite_tile_03/granite_tile_03_diff.jpg"
const GRANITE_NOR := "res://assets/textures/granite_tile_03/granite_tile_03_nor_gl.jpg"
const GRANITE_ROUGH := "res://assets/textures/granite_tile_03/granite_tile_03_rough.jpg"
const FACADE_TEX := "res://assets/textures/Facade009/Facade009_diff.jpg"
const FACADE_NOR := "res://assets/textures/Facade009/Facade009_nor_gl.jpg"
const LEAKING_TEX := "res://assets/textures/Leaking004/Leaking004_diff.jpg"
const PLASTIC_TEX := "res://assets/textures/Plastic006/Plastic006_diff.jpg"
const PLASTIC_NOR := "res://assets/textures/Plastic006/Plastic006_nor_gl.jpg"
const PLASTIC_ROUGH := "res://assets/textures/Plastic006/Plastic006_rough.jpg"
const IMPERFECTION_TEX := "res://assets/textures/SurfaceImperfections001/SurfaceImperfections001_diff.jpg"
const IMPERFECTION_NOR := "res://assets/textures/SurfaceImperfections001/SurfaceImperfections001_nor_gl.jpg"

## The size of one tile of the world space textures, in metres.
const WALL_TILE := 4.0
## The size of one tile of the police station, in metres.
const POLICE_TILE := 0.6
const FACADE_TILE := 3.0
const METAL_TILE := 2.0
const PANEL_TILE := 1.5
const GLASS_TILE := 3.0
const FOLIAGE_TILE := 1.0

static var _materials: Dictionary = {}


## One of the shared world materials. `id`: metal, concrete, foliage, bark, panel, sign_blue,
## sign_green, glow_warm, glow_cool, glow_cyan, glow_red, glow_amber, glow_green, water.
static func material(id: String) -> Material:
	if _materials.has(id):
		return _materials[id] as Material
	var mat := _make_material(id)
	_materials[id] = mat
	return mat


static func _make_material(id: String) -> Material:
	match id:
		"concrete":
			var c := load("res://shaders/materials/SH_concrete_barrier.tres") as Material
			if c != null:
				return c
			return _pbr(Color(0.47, 0.46, 0.44), 0.85, CONCRETE_TEX, CONCRETE_NOR, CONCRETE_ROUGH, 1.0)
		"metal":
			return _pbr(Color(0.168, 0.180, 0.200), 0.42, PLASTIC_TEX, PLASTIC_NOR,
				PLASTIC_ROUGH, 1.0 / METAL_TILE, 1.0, true)
		"foliage":
			return _pbr(Color(0.10, 0.19, 0.10), 0.88, IMPERFECTION_TEX, IMPERFECTION_NOR,
				"", 1.0 / FOLIAGE_TILE, 0.0, true)
		"ground":
			return _pbr(Color(0.135, 0.135, 0.145), 0.94, GRIME_TEX, CONCRETE_NOR, "", 1.0, 0.0, true)
		"bark":
			return _pbr(Color(0.13, 0.10, 0.08), 0.9, GRIME_TEX, CONCRETE_NOR, "", 1.0, 0.0, true)
		"panel":
			return _pbr(Color(0.05, 0.07, 0.11), 0.5, PLASTIC_TEX, PLASTIC_NOR, PLASTIC_ROUGH,
				1.0 / PANEL_TILE, 0.15, true)
		"glass_dark":
			return _pbr(Color(0.043, 0.059, 0.078), 0.05, "", IMPERFECTION_NOR, "", 1.0 / GLASS_TILE,
				0.0, true)
		"tile_white":
			return _pbr(Color(0.72, 0.73, 0.74), 0.55, GRANITE_TEX, GRANITE_NOR, GRANITE_ROUGH,
				1.0 / WALL_TILE, 0.0, true)
		"police_tile":
			# The white tile of the police station: 0.6 x 0.3 m tiles, projected on the world
			# axes so a box of any size carries the same grout.
			return _pbr(Color(0.847, 0.839, 0.816), 0.42, GRANITE_TEX, GRANITE_NOR,
				GRANITE_ROUGH, 1.0 / POLICE_TILE, 0.0, true)
		"police_blue":
			return _pbr(Color(0.118, 0.310, 0.722), 0.38, PLASTIC_TEX, PLASTIC_NOR,
				PLASTIC_ROUGH, 1.0 / PANEL_TILE, 0.1, true)
		"wall":
			return _pbr(Color(0.66, 0.64, 0.60), 0.62, GRANITE_TEX, GRANITE_NOR, GRANITE_ROUGH,
				1.0 / WALL_TILE, 0.0, true)
		"facade":
			return _pbr(Color(0.48, 0.49, 0.50), 0.55, FACADE_TEX, FACADE_NOR, LEAKING_TEX,
				1.0 / FACADE_TILE, 0.0, true)
		"sign_blue":
			return _pbr(Color(0.086, 0.169, 0.435), 0.40, PLASTIC_TEX, PLASTIC_NOR, PLASTIC_ROUGH,
				1.0 / PANEL_TILE, 0.1, true)
		"sign_green":
			return _pbr(Color(0.0, 0.439, 0.290), 0.40, PLASTIC_TEX, PLASTIC_NOR, PLASTIC_ROUGH,
				1.0 / PANEL_TILE, 0.1, true)
		"bay":
			return _pbr(Color(0.910, 0.910, 0.878), 0.72, PLASTIC_TEX, PLASTIC_NOR, PLASTIC_ROUGH,
				1.0 / PANEL_TILE, 0.0, true)
		"water":
			var w := load("res://shaders/materials/SH_water.tres") as Material
			if w != null:
				return w
			return _pbr(Color(0.043, 0.063, 0.086), 0.08, "", "", "", 0.0, 0.9)
		_:
			# A typo must not become a blown out white object: the material is a neutral
			# concrete and the error is loud.
			push_error("[world] unknown material '%s'" % id)
			return _pbr(Color(0.34, 0.34, 0.33), 0.88, CONCRETE_TEX, CONCRETE_NOR,
				CONCRETE_ROUGH, 1.0, 0.0, true)


## Emissive material (unlit sign faces, lamp heads, neon).
static func glow(color: Color, energy: float) -> Material:
	var key := "glow_%s_%.2f" % [color.to_html(false), energy]
	if _materials.has(key):
		return _materials[key] as Material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	_materials[key] = mat
	return mat


## A PBR material. `triplanar` projects the texture on the world axes, so a box of any size
## carries the same grain as the ground next to it (no stretched UVs on the procedural sites).
static func _pbr(albedo: Color, roughness: float, albedo_tex: String, normal_tex: String,
		rough_tex: String, uv_scale: float, metallic: float = 0.0,
		triplanar: bool = false) -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	if triplanar:
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_triplanar_sharpness = 1.0
	if albedo_tex != "" and ResourceLoader.exists(albedo_tex):
		mat.albedo_texture = load(albedo_tex)
	if normal_tex != "" and ResourceLoader.exists(normal_tex):
		mat.normal_enabled = true
		mat.normal_texture = load(normal_tex)
	if rough_tex != "" and ResourceLoader.exists(rough_tex):
		mat.roughness_texture = load(rough_tex)
	return mat


# --- primitive helpers ----------------------------------------------------------------------------

static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## A flat quad in the XY plane with the UVs 0..1 (a BoxMesh has an atlas of UVs, so a sign
## texture would only cover a part of its face).
static func quad(width: float, height: float) -> QuadMesh:
	var m := QuadMesh.new()
	m.size = Vector2(width, height)
	return m


static func cylinder(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 1
	return m


static func sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


## Two crossed quads: a cross that is seen from every direction (the far dot of a lamp).
static func cross_quad(size: float) -> ArrayMesh:
	var h := size * 0.5
	var vertices := PackedVector3Array([
		Vector3(-h, 0.0, -h), Vector3(h, 0.0, -h), Vector3(h, 0.0, h), Vector3(-h, 0.0, h),
		Vector3(-h, 0.0, h), Vector3(h, 0.0, h), Vector3(h, 0.0, -h), Vector3(-h, 0.0, -h),
	])
	var normals := PackedVector3Array([
		Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD,
		Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT,
	])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The material of the far dot of a lamp: a soft, unshaded glow that never shrinks below a
## pixel.
static func dot_material(color: Color) -> Material:
	var key := "dot_%s" % color.to_html(false)
	if _materials.has(key):
		return _materials[key] as Material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = _dot_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	_materials[key] = mat
	return mat


## The soft round sprite of the far dot.
static func _dot_texture() -> Texture2D:
	if _materials.has("_dot_texture"):
		return _materials["_dot_texture"] as Texture2D
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(float(x), float(y)).distance_to(centre) / float(size) * 2.0
			# The core of the dot is solid: the dot must never shrink below one pixel.
			var alpha := clampf((1.0 - distance) * 2.0, 0.0, 1.0)
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	var texture := ImageTexture.create_from_image(image)
	_materials["_dot_texture"] = texture
	return texture


## A part of a prop: mesh + material + local transform.
static func part(mesh: Mesh, mat: Material, xform: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	return {"mesh": mesh, "material": mat, "transform": xform}


static func at(pos: Vector3, yaw_deg: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
