extends RefCounted
## The look-dev street: the wet road, its GB paint, the kerbs and pavement, the crossing elevated
## deck with the blue soffit, and the light pools on the road.

const K := preload("res://world/env/lookdev_kit.gd")


## The wet road, its paint and the kerbs. GB 5768.3 dimensions (DOSSIER 6.1).
static func build_road(p: Node) -> void:
	K.mesh(p, K.plane(Vector2(16.0, 220.0)), K.mat("SH_wet_asphalt"), Vector3(0, 0, -100))
	var white: Material = K.mat("SH_road_marking_white")
	var yellow: Material = K.mat("SH_road_marking_yellow")
	for z in range(0, 200, 15):                      # 6 m dash / 9 m gap, 15 cm wide
		for x: float in [-1.875, 1.875]:
			K.mesh(p, K.box(Vector3(0.15, 0.01, 6.0)), white, Vector3(x, 0.005, -z - 3.0))
	K.mesh(p, K.box(Vector3(0.2, 0.01, 210.0)), yellow, Vector3(-5.6, 0.005, -95))
	K.mesh(p, K.box(Vector3(0.2, 0.01, 210.0)), white, Vector3(5.6, 0.005, -95))
	# A crosswalk further down the street.
	for i in 9:
		K.mesh(p, K.box(Vector3(0.45, 0.01, 3.0)), white, Vector3(-3.15 + i * 0.8, 0.005, -78.0))


## The kerb and the pavement behind it. The kerb is the Bund granite, darkened (DOSSIER 4.9); the
## pavement is its own material, not a flat slab (ART.md 5, rule 1).
static func build_pavement(p: Node) -> void:
	var kerb: Material = K.mat("SH_kerb")
	var walk: Material = K.mat("SH_sidewalk")
	for x: float in [-6.4, 6.4]:
		var kerb_mesh := K.mesh(p, K.box(Vector3(0.5, 0.18, 220.0)), kerb, Vector3(x, 0.09, -100))
		kerb_mesh.set_instance_shader_parameter("base_y", 0.09)
		var walk_mesh := K.mesh(p, K.box(Vector3(6.0, 0.16, 220.0)), walk, Vector3(x + signf(x) * 3.3, 0.08, -100))
		walk_mesh.set_instance_shader_parameter("base_y", 0.08)
		walk_mesh.set_instance_shader_parameter("splash_override", 0.0)   # a flat pavement has no splash zone
		# The tactile strip (盲道): a 30 cm band along the kerb edge.
		var tactile := K.mesh(p, K.box(Vector3(0.3, 0.02, 220.0)), K.mat("SH_tactile"),
			Vector3(x + signf(x) * 0.75, 0.17, -100))
		tactile.set_instance_shader_parameter("base_y", 0.17)


## The elevated deck that crosses over the street, its piers and the blue soffit under it.
## The piers get their own base_y so the splash zone is the bottom 0.6 m and not half the pier.
static func build_overpass(p: Node) -> void:
	var concrete: Material = K.mat("SH_concrete_pier")
	K.mesh(p, K.box(Vector3(60, 1.4, 16)), concrete, Vector3(0, 10.0, -30))
	for x: float in [-9.0, 9.0]:
		var pier := K.mesh(p, K.cylinder(1.1, 9.3), concrete, Vector3(x, 4.65, -30))
		pier.set_instance_shader_parameter("base_y", 4.65)   # the pier is centred on its own origin
	# Two shadowless blue lights under the deck, so the piers read blue-lit grey (sh05) and not black.
	for x: float in [-4.0, 4.0]:
		var under := OmniLight3D.new()
		under.light_color = Color("2357f3")
		under.light_energy = 0.8
		under.omni_range = 12.0
		under.shadow_enabled = false
		under.light_volumetric_fog_energy = 0.03
		under.position = Vector3(x, 7.4, -30.0)
		p.add_child(under)
	# The soffit: the blue wash + the two LED strips at the deck edges. The quad's u runs in
	# METRES (0..60) like the real deck, so the 1.2 m formwork joints appear every 1.2 m.
	var soffit := K.mesh(p, K.metre_quad(60.0, 15.4), K.mat("SH_soffit_blue"), Vector3(0, 9.29, -30))
	soffit.rotation_degrees = Vector3(180, 0, 0)
	var neon: Material = K.mat("SH_neon")
	for z: float in [-22.2, -37.8]:
		var strip := K.mesh(p, K.box(Vector3(60, 0.06, 0.12)), neon, Vector3(0, 9.26, z))
		strip.set_instance_shader_parameter("neon_color", Color("5a3dff"))
		strip.set_instance_shader_parameter("neon_energy", 4.5)
		strip.set_instance_shader_parameter("is_flat_strip", true)


## The light pool of a lamp that is too far away for a real OmniLight: a Decal on the road
## (DOSSIER 3.7 #1). The old version was a 10 x 10 m QuadMesh with no rotation, so it stood
## VERTICALLY as a translucent tan wall across the street every 30 m - that was the "warm brown
## haze" the lead measured (the horizon band moved #695146 -> #403337 with the quads hidden).
## A Decal is always parallel to the surface it is projected on, so it cannot do that.
static func build_far_light_pools(p: Node) -> void:
	for z: float in [-190.0, -220.0, -250.0, -280.0]:
		var x: float = -5.3 if int(-z / 30.0) % 2 == 0 else 5.3
		var decal := Decal.new()
		decal.texture_emission = K.radial_gradient()
		decal.size = Vector3(10.0, 6.0, 10.0)
		decal.emission_energy = 0.12
		decal.modulate = Color("ffcea6")
		decal.upper_fade = 0.3
		decal.lower_fade = 0.3
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 200.0
		decal.distance_fade_length = 50.0
		decal.position = Vector3(x, 0.05, z)
		p.add_child(decal)
		# Every pool has a lamp above it: a pool without a lamp reads as a stain on the road.
		K.lamp_pole(p, Vector3(x, 0.0, z), 9.0, Color("ffcea6"))
