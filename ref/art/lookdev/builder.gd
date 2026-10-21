## SKYRUSH look-dev: static geometry builders (road deck, markings, crossing deck, towers, Bund block, lamps).
class_name LookdevBuilder
extends RefCounted

const M := preload("res://materials.gd")

static func mesh(parent: Node, m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func cylinder(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	return c

static func build_road(p: Node) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 170.0)
	mesh(p, plane, M.road_wet(), Vector3(0, 0, -75))
	var white := M.road_marking(Color("e9e7df"))
	var yellow := M.road_marking(Color("e8b520"))
	for z in range(0, 160, 15):          # "6-9 line": 6 m dash, 9 m gap, 15 cm wide (GB 5768.3)
		for x in [-1.875, 1.875]:
			mesh(p, box(Vector3(0.15, 0.01, 6.0)), white, Vector3(x, 0.005, -z - 3.0))
	mesh(p, box(Vector3(0.2, 0.01, 160.0)), yellow, Vector3(-5.6, 0.005, -75))  # left edge, one-way deck
	mesh(p, box(Vector3(0.2, 0.01, 160.0)), white, Vector3(5.6, 0.005, -75))
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color("6e6c68")
	concrete.roughness = 0.9
	mesh(p, box(Vector3(60, 1.4, 16)), concrete, Vector3(0, 10.0, -55))         # crossing elevated deck
	for x in [-9.0, 9.0]:
		mesh(p, cylinder(1.1, 9.3), concrete, Vector3(x, 4.65, -55))
	var neon := M.neon()
	for z in [-47.2, -62.8]:                                                      # blue soffit LED lines
		var s := mesh(p, box(Vector3(60, 0.06, 0.12)), neon, Vector3(0, 9.27, z))
		s.set_instance_shader_parameter("neon_color", Color("2357f3"))
		s.set_instance_shader_parameter("neon_energy", 5.0)
	var wash := StandardMaterial3D.new()                                         # soffit wash = baked emissive
	wash.albedo_color = Color("6e6c68")
	wash.emission_enabled = true
	wash.emission = Color("2357f3")
	wash.emission_energy_multiplier = 0.9
	var soffit := PlaneMesh.new()
	soffit.size = Vector2(60, 15.4)
	soffit.flip_faces = true
	mesh(p, soffit, wash, Vector3(0, 9.29, -55))

static func build_city(p: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var h := rng.randf_range(30.0, 140.0)
		var w := rng.randf_range(16.0, 30.0)
		var pos := Vector3(side * (w * 0.5 + 16.0 + rng.randf_range(0, 20)), h * 0.5, -40.0 - i * 22.0)
		var b := mesh(p, box(Vector3(w, h, w)), M.facade(rng.randf_range(3.6, 4.2), rng.randf_range(0.25, 0.5)), pos)
		b.set_instance_shader_parameter("building_seed", float(i) + 0.5)
	mesh(p, box(Vector3(18, 22, 26)), M.granite_bund(), Vector3(-24, 11, -24))   # Bund-style stone block
	for z in [-13.0, -18.0, -23.0, -28.0, -33.0]:
		var up := SpotLight3D.new()                                               # 2500 K uplight = the gold
		up.light_color = Color("ff9f46")   # 2500 K (Bund daily mode); 1800 K = #FF7E00
		up.light_energy = 25.0
		up.spot_range = 30.0
		up.spot_angle = 40.0
		up.position = Vector3(-14.6, 0.3, z)
		up.rotation_degrees = Vector3(80, -90, 0)
		p.add_child(up)
	var neon := M.neon()
	var cols := [Color("ff2a8a"), Color("20e0ff"), Color("ffb000"), Color("ff3030")]
	for i in 6:
		var t := mesh(p, cylinder(0.04, 3.5), neon, Vector3(9.5 + (i % 2) * 0.6, 4.0 + (i % 3), -18.0 - i * 9.0))
		t.set_instance_shader_parameter("neon_color", cols[i % 4])
		t.set_instance_shader_parameter("neon_seed", float(i) * 3.1)
		t.set_instance_shader_parameter("neon_energy", 8.0 if i == 0 else 5.0)
	for k in 2:                                                                   # LED channel-letter bars, 12 cm strokes
		var bar := mesh(p, box(Vector3(0.05, 0.12, 4.0)), neon, Vector3(14.5, 5.0 + k * 0.8, -24.0 - k * 2.0))
		bar.set_instance_shader_parameter("neon_color", cols[k])
		bar.set_instance_shader_parameter("neon_energy", 6.0)
		bar.set_instance_shader_parameter("neon_seed", 40.0 + k)
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color("20e0ff"))
	grad.gradient.set_color(1, Color("ff2a8a"))
	var quad := QuadMesh.new()
	quad.size = Vector2(6.0, 3.4)
	var holo := mesh(p, quad, M.hologram(grad), Vector3(-7.5, 6.5, -30))
	holo.rotation_degrees = Vector3(0, 20, 0)

static func build_lights(p: Node) -> void:
	for i in 6:                                     # LED street lamps every 30 m, alternating sides
		var x := -5.3 if i % 2 == 0 else 5.3
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("ffcea6")          # 4000 K LED (elevated decks)
		lamp.light_energy = 2.5
		lamp.omni_range = 18.0
		lamp.light_volumetric_fog_energy = 0.2
		lamp.position = Vector3(x, 9.0, -10.0 - i * 30.0)
		p.add_child(lamp)
		mesh(p, box(Vector3(0.8, 0.12, 0.35)), M.emissive(Color("ffcea6"), 6.0), lamp.position + Vector3(0, 0.1, 0))
	for x in [-0.75, 0.75]:                         # player headlights
		var hl := SpotLight3D.new()
		hl.light_color = Color("f4f7ff")
		hl.light_energy = 10.0
		hl.spot_range = 70.0
		hl.spot_angle = 22.0
		hl.shadow_enabled = true
		hl.light_volumetric_fog_energy = 1.5
		hl.position = Vector3(x, 0.7, 2.6)
		hl.rotation_degrees = Vector3(-4, 0, 0)
		p.add_child(hl)
