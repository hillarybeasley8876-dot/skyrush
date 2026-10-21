extends RefCounted
## Shared helpers for the look-dev scene builders (street / city / hero).
## Every surface uses a shared SH_* material so the scene doubles as the material proof sheet.

const MAT_DIR := "res://shaders/materials/"


static func mat(name: String) -> Material:
	var path := MAT_DIR + name + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("lookdev: missing material " + path)
		return null
	return load(path) as Material


static func mesh(parent: Node, m: Mesh, material: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cylinder(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	return c


static func plane(size: Vector2) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = size
	return p


static func quad(size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	return q


## A quad in the XZ plane whose UV.x runs in METRES (0..length_m) and whose UV.y runs 0..1
## across the width. The real deck exports u in metres, so the look-dev has to match it or the
## 1.2 m formwork joints appear once instead of every 1.2 m.
static func metre_quad(length_m: float, width_m: float) -> ArrayMesh:
	var hl := length_m * 0.5
	var hw := width_m * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two triangles, wound so the face is visible from ABOVE (the caller turns it down): the
	# soffit is the underside of the deck, so a back-facing quad would show the deck instead.
	_quad_vertex(st, Vector3(-hl, 0.0, -hw), Vector2(0.0, 0.0))
	_quad_vertex(st, Vector3(hl, 0.0, -hw), Vector2(length_m, 0.0))
	_quad_vertex(st, Vector3(hl, 0.0, hw), Vector2(length_m, 1.0))
	_quad_vertex(st, Vector3(-hl, 0.0, -hw), Vector2(0.0, 0.0))
	_quad_vertex(st, Vector3(hl, 0.0, hw), Vector2(length_m, 1.0))
	_quad_vertex(st, Vector3(-hl, 0.0, hw), Vector2(0.0, 1.0))
	return st.commit()


static func _quad_vertex(st: SurfaceTool, pos: Vector3, uv: Vector2) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(uv)
	st.add_vertex(pos)


## A street lamp: a pole and a head. A floating lamp head is not a lamp (ART 8).
static func lamp_pole(parent: Node, pos: Vector3, height: float, color: Color) -> void:
	var pole := mesh(parent, box(Vector3(0.16, height, 0.16)), _pole_material(), pos + Vector3(0, height * 0.5, 0))
	pole.name = "LampPole"
	var head := mesh(parent, box(Vector3(0.7, 0.12, 0.32)), emissive(color, 6.0), pos + Vector3(0, height, 0))
	head.name = "LampHead"


static func _pole_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("2b2d31")
	m.roughness = 0.7
	m.metallic = 0.4
	return m


## A self-lit surface: a lamp head, a light box, a sign face.
static func emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.8)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## A light box with real artwork (a sign PNG). The panel uses the sign_panel shader: the artwork
## masks the panel's own light, so the glyphs glow and the panel is never a flat slab. The panel
## is lit (not unshaded), so the black parts of the artwork are dark grey and not crushed black
## (ART 8: no pure black surfaces). `artwork_mix` = 0 makes it a plain LED band in the sign
## colour (the artwork is then not used at all).
static func light_box(texture_path: String, color: Color, energy: float, artwork_mix: float = 0.92) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sign_panel.gdshader")
	m.set_shader_parameter("artwork", load(texture_path) as Texture2D)
	m.set_shader_parameter("sign_color", color)
	m.set_shader_parameter("sign_energy", energy)
	m.set_shader_parameter("artwork_mix", artwork_mix)
	return m


## The radial falloff of a light pool (DOSSIER 3.7 #1: a 256 px radial gradient). The gradient
## runs from WHITE in the centre to BLACK at the edge: a decal's emission uses the RGB, so a
## gradient that only fades the alpha still glows as a hard-edged square. The falloff is linear
## (six stops), so the luma steps down evenly instead of jumping at the edge.
static func radial_gradient() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.set_offset(0, 0.0)
	grad.set_color(1, Color(0.0, 0.0, 0.0, 1.0))
	grad.set_offset(1, 1.0)
	grad.add_point(0.2, Color(0.8, 0.8, 0.8, 1.0))
	grad.add_point(0.4, Color(0.6, 0.6, 0.6, 1.0))
	grad.add_point(0.6, Color(0.4, 0.4, 0.4, 1.0))
	grad.add_point(0.8, Color(0.2, 0.2, 0.2, 1.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


## The dark back plate behind a neon sign (DOSSIER 4.5: #141416 anodised metal).
static func back_plate() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("141416")
	m.roughness = 0.4
	m.metallic = 0.2
	return m
