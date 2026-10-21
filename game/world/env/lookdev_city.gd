extends RefCounted
## The look-dev city: the tower block, the Bund stone with its 2500 K uplights, the shopfront canyon
## with its neon, the river edge and the reflection probes.

const K := preload("res://world/env/lookdev_kit.gd")
const PROPS_TEX := "res://assets/props/textures/"


## The block of towers, the Bund-style stone block with its gold uplights.
## The blocks stand on the WEST side of the street only: the east side is the river (x 17-63) and
## the far bank (x 64+), and a tower standing in the water would block the river views.
static func build_city(p: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var office: Material = K.mat("SH_facade_office")
	for i in 14:
		var h: float = rng.randf_range(30.0, 140.0)
		var w: float = rng.randf_range(16.0, 30.0)
		var pos := Vector3(-(w * 0.5 + 16.0 + rng.randf_range(0, 20)), h * 0.5, -40.0 - i * 22.0)
		var b := K.mesh(p, K.box(Vector3(w, h, w)), office, pos)
		b.set_instance_shader_parameter("building_seed", float(i) + 0.5)
	# A residential slab on the FAR bank, clear of the water.
	var res := K.mesh(p, K.box(Vector3(26.0, 24.0, 14.0)), K.mat("SH_facade_residential"), Vector3(72.0, 12.0, -96.0))
	res.set_instance_shader_parameter("building_seed", 7.5)


## The Bund block: neutral granite with a cornice and pilasters, washed by 2500 K uplights every
## 5 m along the face, 1 m off the wall (DOSSIER 3.4). The gold comes from the lights, never the
## albedo. The uplights are dimmer than the dossier value so the stone does not blow out.
static func build_bund(p: Node) -> void:
	var granite: Material = K.mat("SH_granite_bund")
	var block := K.mesh(p, K.box(Vector3(18, 22, 26)), granite, Vector3(-26, 11, -26))
	block.set_instance_shader_parameter("base_y", 11.0)
	# The cornice and the pilasters catch the wash and break the flat box.
	var cornice := K.mesh(p, K.box(Vector3(19.0, 0.9, 27.0)), granite, Vector3(-26, 22.2, -26))
	cornice.set_instance_shader_parameter("base_y", 22.2)
	for z: float in [-15.0, -21.0, -27.0, -33.0, -39.0]:
		var pilaster := K.mesh(p, K.box(Vector3(0.7, 21.0, 1.4)), granite, Vector3(-16.6, 10.5, z))
		pilaster.set_instance_shader_parameter("base_y", 10.5)
	for z: float in [-15.0, -20.0, -25.0, -30.0, -35.0, -40.0]:
		var up := SpotLight3D.new()
		up.light_color = Color("ff9f46")            # 2500 K Bund daily mode
		up.light_energy = 16.0
		up.spot_range = 30.0
		up.spot_angle = 40.0
		up.position = Vector3(-16.0, 0.3, z)        # 1 m off the wall
		up.rotation_degrees = Vector3(80, -90, 0)
		up.light_volumetric_fog_energy = 0.04       # the uplights must not fog the street out
		p.add_child(up)


## The street-level shopfronts: the dense CJK neon that makes Shanghai readable (Nanjing Road).
## Two continuous facades close the street into a canyon so the wet road has something to mirror.
## Every sign gets its dark back plate, so the colour pops and the sign is a plausible object.
static func build_shopfronts(p: Node) -> void:
	var office: Material = K.mat("SH_facade_office")
	var residential: Material = K.mat("SH_facade_residential")
	# The canyon runs 150 m: the street recedes into the neon instead of ending in a dark void.
	var right := K.mesh(p, K.box(Vector3(0.6, 14.0, 150.0)), office, Vector3(10.8, 7.0, -75.0))
	right.set_instance_shader_parameter("building_seed", 21.5)
	var left := K.mesh(p, K.box(Vector3(0.6, 10.0, 110.0)), residential, Vector3(-10.8, 5.0, -55.0))
	left.set_instance_shader_parameter("building_seed", 33.5)
	var neon: Material = K.mat("SH_neon")
	var plate: Material = K.back_plate()
	# Nanjing Road is red / orange / yellow dominated (dossier 1.5, sh07), with amber and white in
	# the mix and the single cool accent (cyan) on the far kerb.
	var cols: Array[Color] = [
		Color("ff2a8a"), Color("ff3030"), Color("ff6a1a"), Color("ffb000"),
		Color("ff2a8a"), Color("ff3030"), Color("ff6a1a"), Color("ffb000"),
	]
	for i in 14:
		var z: float = -10.0 - i * 7.0
		# The back plate and its brackets, 8 cm behind the tube.
		K.mesh(p, K.box(Vector3(0.08, 4.4, 0.6)), plate, Vector3(10.3, 5.4, z))
		var tube := K.mesh(p, K.cylinder(0.09, 3.8), neon, Vector3(10.1, 5.2 + (i % 3) * 0.9, z))
		tube.set_instance_shader_parameter("neon_color", cols[i % 5])
		tube.set_instance_shader_parameter("neon_seed", float(i) * 2.7)
		tube.set_instance_shader_parameter("neon_energy", 9.0 if i == 0 else 8.0)
		# Horizontal LED channel stroke above it (12 cm, readable from 30 m).
		K.mesh(p, K.box(Vector3(0.08, 0.5, 7.4)), plate, Vector3(10.3, 8.9, z))
		var bar := K.mesh(p, K.box(Vector3(0.22, 0.22, 7.0)), neon, Vector3(10.1, 8.9, z))
		bar.set_instance_shader_parameter("neon_color", cols[(i + 2) % 5])
		bar.set_instance_shader_parameter("neon_seed", 70.0 + i)
		bar.set_instance_shader_parameter("neon_energy", 8.0)
		bar.set_instance_shader_parameter("is_flat_strip", true)
		# A shop window: dark tinted glass (the NPC-car glass material, used on shopfronts too).
		var pane := K.mesh(p, K.quad(Vector2(3.2, 2.6)), K.mat("SH_glass_tinted"), Vector3(10.35, 1.7, z + 1.0))
		pane.rotation_degrees = Vector3(0, -90, 0)
		# A shop light box with real artwork, not a blank cream quad.
		var box_mesh := K.mesh(p, K.quad(Vector2(3.0, 4.0)),
			K.light_box(PROPS_TEX + "billboard_ad.png", Color("ffa24d"), 2.4), Vector3(10.3, 3.2, z + 2.4))
		box_mesh.rotation_degrees = Vector3(0, -90, 0)
	# Horizontal bands along the shopfronts: the saturated area the street views need (a tube is
	# a few pixels wide at 30 m, a band is a metre). They alternate between SIGN ARTWORK and a
	# plain LED band in the sign colour: a 46 m slab in one colour read as a wall, not as a
	# street, but a shopfront with both is what Nanjing Road looks like.
	var band_art: Array[String] = [
		PROPS_TEX + "billboard_ad.png", PROPS_TEX + "bus_ad.png", PROPS_TEX + "roadname_nanjing.png",
	]
	var band_cols: Array[Color] = [Color("ffb000"), Color("ff3030"), Color("19e6ff"), Color("ff6a1a")]
	for i in 4:
		for j in 10:
			var art := band_art[(i + j) % band_art.size()]
			var col := band_cols[(i + j) % band_cols.size()]
			var sign_mat: Material = K.light_box(art, col, 2.4)
			var sign_size := Vector2(7.6, 2.0)
			if (i + j) % 2 == 1:
				# A plain LED band: the same panel, without the artwork mask. It is a strip, not a
				# slab, and its colour is saturated (a white band would raise the P95, not the SAT).
				sign_mat = K.light_box(art, col, 1.2, 0.0)
				sign_size = Vector2(7.6, 1.3)
			var sign := K.mesh(p, K.quad(sign_size), sign_mat,
				Vector3(10.28, 8.4 + i * 2.2, -8.0 - j * 8.0))
			sign.rotation_degrees = Vector3(0, -90, 0)
	# Big vertical blade signs: the Nanjing Road signature, and the saturated area the street views
	# need (a neon tube is only a few pixels wide at 30 m, a blade is a metre).
	for i in 5:
		var zb: float = -14.0 - i * 14.0
		K.mesh(p, K.box(Vector3(0.08, 8.0, 2.8)), plate, Vector3(10.3, 5.6, zb))
		var blade := K.mesh(p, K.quad(Vector2(2.2, 6.4)),
			K.light_box(PROPS_TEX + "neon_blade.png", cols[i % 3], 2.6), Vector3(10.22, 5.6, zb))
		blade.rotation_degrees = Vector3(0, -90, 0)
	# A CJK channel-letter sign (the street name blade) on the first shopfront.
	K.mesh(p, K.box(Vector3(0.08, 1.1, 4.4)), plate, Vector3(10.3, 6.6, -12.0))
	var cjk := K.mesh(p, K.quad(Vector2(4.2, 1.0)),
		K.light_box(PROPS_TEX + "roadname_nanjing.png", Color("19e6ff"), 2.4), Vector3(10.22, 6.6, -12.0))
	cjk.rotation_degrees = Vector3(0, -90, 0)
	# A few signs on the left-hand side so both kerbs carry colour: the palette blue plus two
	# warm signs, so the frame keeps two hue families and not five. The left kerb carries the
	# same density as the right one, so the street reads as a canyon and not as a lit wall.
	var left_cols: Array[Color] = [
		Color("2357f3"), Color("19e6ff"), Color("ff6a1a"), Color("f2f6ff"),
		Color("2357f3"), Color("ffb000"), Color("19e6ff"), Color("ff3030"),
	]
	for i in 10:
		var z2: float = -20.0 - i * 7.0
		K.mesh(p, K.box(Vector3(0.08, 3.8, 0.5)), plate, Vector3(-10.3, 4.6, z2))
		var tube2 := K.mesh(p, K.cylinder(0.08, 3.4), neon, Vector3(-10.1, 4.6, z2))
		tube2.set_instance_shader_parameter("neon_color", left_cols[i % left_cols.size()])
		tube2.set_instance_shader_parameter("neon_seed", 90.0 + i * 1.3)
		tube2.set_instance_shader_parameter("neon_energy", 7.0)
		# A horizontal LED stroke above the tube, so the left kerb has the same vertical rhythm.
		var bar2 := K.mesh(p, K.box(Vector3(0.16, 0.16, 4.4)), neon, Vector3(-10.1, 7.6, z2))
		bar2.set_instance_shader_parameter("neon_color", left_cols[(i + 3) % left_cols.size()])
		bar2.set_instance_shader_parameter("neon_seed", 150.0 + i)
		bar2.set_instance_shader_parameter("neon_energy", 6.0)
		bar2.set_instance_shader_parameter("is_flat_strip", true)
		var box2 := K.mesh(p, K.quad(Vector2(1.6, 2.2)),
			K.light_box(PROPS_TEX + "bus_ad.png", Color("ffe8d0"), 2.2), Vector3(-10.3, 3.0, z2 + 2.0))
		box2.rotation_degrees = Vector3(0, 90, 0)
	for i in 2:
		var z3: float = -14.0 - i * 9.0
		var tube3 := K.mesh(p, K.cylinder(0.10, 4.0), neon, Vector3(-10.1, 5.4, z3))
		tube3.set_instance_shader_parameter("neon_color", Color("ff2a8a") if i == 0 else Color("ff3030"))
		tube3.set_instance_shader_parameter("neon_seed", 120.0 + i)
		tube3.set_instance_shader_parameter("neon_energy", 6.0)
		var bar3 := K.mesh(p, K.box(Vector3(0.18, 0.18, 5.0)), neon, Vector3(-10.1, 8.6, z3))
		bar3.set_instance_shader_parameter("neon_color", Color("ff3030") if i == 0 else Color("ff2a8a"))
		bar3.set_instance_shader_parameter("neon_seed", 130.0 + i)
		bar3.set_instance_shader_parameter("neon_energy", 6.0)
		bar3.set_instance_shader_parameter("is_flat_strip", true)


## The floating hologram and the giant LED wall on a tower.
static func build_signs(p: Node) -> void:
	var holo := K.mesh(p, K.quad(Vector2(8.0, 4.5)), K.mat("SH_hologram"), Vector3(-9.2, 6.0, -30.0))
	holo.rotation_degrees = Vector3(0, 20, 0)
	# A second hologram that carries the REAL ad artwork instead of the library gradient
	# (r1/r2 open item): a copy of SH_hologram with its own emission map.
	var ad_mat := (K.mat("SH_hologram") as ShaderMaterial).duplicate() as ShaderMaterial
	ad_mat.set_shader_parameter("emission_texture", load(PROPS_TEX + "billboard_ad.png"))
	ad_mat.set_shader_parameter("energy", 2.0)
	var holo_ad := K.mesh(p, K.quad(Vector2(6.0, 3.4)), ad_mat, Vector3(-5.6, 10.4, -37.0))
	holo_ad.rotation_degrees = Vector3(0, 20, 0)
	var screen := K.mesh(p, K.quad(Vector2(14.0, 8.0)), K.mat("SH_hologram"), Vector3(-34.0, 20.0, -26.0))
	screen.set_instance_shader_parameter("mode", 0)
	screen.set_instance_shader_parameter("energy", 2.5)
	screen.set_instance_shader_parameter("tint", Color("20e0ff"))
	# The two big screens that close the canyon: the street recedes into light instead of into a
	# dark void (and they are the saturated area the long street view needs).
	var end_art: Array[String] = [PROPS_TEX + "billboard_ad.png", PROPS_TEX + "bus_ad.png"]
	var end_cols: Array[Color] = [Color("ffb000"), Color("ff3030")]
	var end_pos: Array[Vector3] = [Vector3(5.0, 13.0, -132.0), Vector3(-6.0, 9.0, -112.0)]
	for i in 2:
		var end_screen := K.mesh(p, K.quad(Vector2(34.0, 18.0)),
			K.light_box(end_art[i], end_cols[i], 2.0, 0.75), end_pos[i])
		end_screen.rotation_degrees = Vector3(0, 0, 0)   # the quad faces +Z, towards the street


## The Huangpu river edge: the water, the granite promenade parapet, the promenade paving with
## its lamps and the far bank. The lamps are what the water mirrors.
static func build_river(p: Node) -> void:
	K.mesh(p, K.plane(Vector2(46.0, 200.0)), K.mat("SH_water"), Vector3(40.0, -0.6, -80.0))
	# The promenade paving between the pavement (x 12.7) and the parapet (x 16.6): the stone the
	# promenade lamps stand on. It is the same SH_sidewalk as the street, not a grey slab.
	var walk := K.mesh(p, K.box(Vector3(3.9, 0.16, 180.0)), K.mat("SH_sidewalk"), Vector3(14.65, 0.08, -90.0))
	walk.set_instance_shader_parameter("base_y", 0.08)
	walk.set_instance_shader_parameter("splash_override", 0.0)
	for i in 5:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("ffb16e")
		lamp.light_energy = 1.5
		lamp.omni_range = 11.0
		lamp.light_volumetric_fog_energy = 0.0   # 5 promenade lamps: no fog scattering
		lamp.position = Vector3(15.0, 3.2, -16.0 - i * 22.0)
		p.add_child(lamp)
		K.lamp_pole(p, Vector3(15.0, 0.16, -16.0 - i * 22.0), 3.0, Color("ffb16e"))
	K.mesh(p, K.box(Vector3(0.8, 1.1, 200.0)), K.mat("SH_granite_bund"), Vector3(17.0, 0.55, -80.0))
	K.mesh(p, K.box(Vector3(0.8, 1.1, 200.0)), K.mat("SH_concrete_barrier"), Vector3(63.0, 0.55, -80.0))


## The far bank of the Huangpu: the LED towers of Lujiazui (DOSSIER 1.5: dark tower masses, a
## few facades carrying giant LED ads) and the two giant screens. Without them the river is an
## empty black mirror with nothing coloured to reflect.
static func build_far_bank(p: Node) -> void:
	var office: Material = K.mat("SH_facade_office")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var xs: Array[float] = [68.0, 77.0, 86.0, 94.0, 72.5, 82.0]
	for i in xs.size():
		var h: float = 60.0 + rng.randf_range(0.0, 120.0)
		var w: float = rng.randf_range(14.0, 24.0)
		var pos := Vector3(xs[i], h * 0.5, -40.0 - i * 26.0)
		var tower := K.mesh(p, K.box(Vector3(w, h, w)), office, pos)
		tower.set_instance_shader_parameter("building_seed", float(i) + 3.5)
		# The cool LED crown: a frame of edge strips at the top of the tower (#19E6FF / #D9E8FF).
		var crown := Color("19e6ff")
		K.mesh(p, K.box(Vector3(w + 0.8, 0.5, 0.5)), K.emissive(crown, 4.0), Vector3(pos.x, h + 0.25, pos.z - w * 0.5))
		K.mesh(p, K.box(Vector3(w + 0.8, 0.5, 0.5)), K.emissive(crown, 4.0), Vector3(pos.x, h + 0.25, pos.z + w * 0.5))
		K.mesh(p, K.box(Vector3(0.5, 0.5, w + 0.8)), K.emissive(crown, 4.0), Vector3(pos.x - w * 0.5, h + 0.25, pos.z))
		K.mesh(p, K.box(Vector3(0.5, 0.5, w + 0.8)), K.emissive(crown, 4.0), Vector3(pos.x + w * 0.5, h + 0.25, pos.z))
		# A vertical edge strip down the river-facing corner (E2, the halo of a far tower). It is
		# the long vertical line the water mirrors as a streak.
		K.mesh(p, K.box(Vector3(0.4, h * 0.9, 0.4)), K.emissive(Color("d9e8ff"), 3.0),
			Vector3(pos.x - w * 0.5, h * 0.45, pos.z - w * 0.5))
		K.mesh(p, K.box(Vector3(0.4, h * 0.9, 0.4)), K.emissive(Color("19e6ff"), 3.0),
			Vector3(pos.x - w * 0.5, h * 0.45, pos.z + w * 0.5))
	# The lit riverside of the far bank: a row of small lights along the parapet. The water
	# mirrors them as vertical streaks, which is what the river views need.
	for i in 22:
		var z: float = -18.0 - i * 8.0
		var lamp_col := Color("19e6ff") if i % 3 != 0 else Color("d9e8ff")
		K.mesh(p, K.box(Vector3(0.3, 0.3, 0.3)), K.emissive(lamp_col, 4.0), Vector3(63.0, 1.35, z))
	# Two giant LED screens on the far bank (20 x 12 m) with the real ad artwork.
	var art: Array[String] = [PROPS_TEX + "billboard_ad.png", PROPS_TEX + "bus_ad.png"]
	var screen_cols: Array[Color] = [Color("19e6ff"), Color("ff2bd6")]
	for i in 2:
		var screen := K.mesh(p, K.quad(Vector2(20.0, 12.0)),
			K.light_box(art[i], screen_cols[i], 3.2), Vector3(64.5, 13.0 + i * 17.0, -70.0 - i * 46.0))
		screen.rotation_degrees = Vector3(0, -90, 0)


## One static probe per 120-170 m of road: it captures OUR street so puddles reflect our own
## lamps and blue soffit instead of the HDRI (DOSSIER 3.5).
static func make_street_probe() -> ReflectionProbe:
	var rp := ReflectionProbe.new()
	rp.size = Vector3(34, 22, 80)
	rp.position = Vector3(0, 9, -25)
	rp.origin_offset = Vector3(0, -7, 20)
	rp.box_projection = true
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	rp.intensity = 1.0
	rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	rp.blend_distance = 4.0
	return rp


## A second probe over the river: without it the water mirrors the HDRI's golden Bund, the
## "gold foil" the dossier forbids (DOSSIER 1.4 don't #6).
static func make_river_probe() -> ReflectionProbe:
	var rp := ReflectionProbe.new()
	rp.size = Vector3(50, 30, 200)
	rp.position = Vector3(40, 12, -80)
	rp.origin_offset = Vector3(0, -10, 0)   # the capture point is 2 m above the water
	rp.box_projection = true
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	rp.intensity = 1.0
	rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	rp.blend_distance = 4.0
	return rp
